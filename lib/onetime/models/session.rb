# frozen_string_literal: true

require "digest"

module Onetime
  module Models
    # Opaque, server-side sessions. The cookie carries a random token; Redis
    # stores only its SHA-256 digest, so a Redis dump does not expose live
    # session tokens.
    #
    # Each session is also recorded in a per-customer set so an account-wide
    # revocation (password change, sign-out everywhere) can find and delete
    # every live session without scanning the keyspace.
    module Session
      PREFIX = "session:"
      INDEX_PREFIX = "customer:sessions:"

      # Sliding a session and its revocation index must be one atomic step. The
      # index can lapse before the session (the cookie keeps the session alive),
      # so re-add the digest on every touch. The EXISTS guard stops a concurrent
      # destroy from recreating a TTL-less ghost hash between HGETALL and write.
      TOUCH_SCRIPT = <<~LUA
        if redis.call('EXISTS', KEYS[1]) == 0 then return 0 end
        redis.call('HSET', KEYS[1], 'last_seen', ARGV[1])
        redis.call('EXPIRE', KEYS[1], ARGV[2])
        if ARGV[3] ~= '' then
          redis.call('SADD', KEYS[2], ARGV[4])
          redis.call('EXPIRE', KEYS[2], ARGV[2])
        end
        return 1
      LUA

      module_function

      def digest(token)
        Digest::SHA256.hexdigest("ots-session/v1:#{token}")
      end

      def key(token)
        digest_key(digest(token))
      end

      # The hash record is keyed by the digest, so revocation paths that already
      # hold digests (the customer's session index) can address it directly.
      def digest_key(digest)
        "#{PREFIX}#{digest}"
      end

      def index_key(customer_id)
        "#{INDEX_PREFIX}#{customer_id}"
      end

      def create(customer_id)
        token = Ids.session_token
        now = Time.now.to_i
        Store.redis.multi do |tx|
          tx.hset(key(token), {
            "customer_id" => customer_id.to_s,
            "created_at" => now.to_s,
            "last_seen" => now.to_s
          })
          tx.expire(key(token), Config.session_ttl)
          tx.sadd(index_key(customer_id), digest(token))
          tx.expire(index_key(customer_id), Config.session_ttl)
        end
        token
      end

      def fetch(token)
        return nil if token.to_s.empty?

        session_key = key(token)
        raw = Store.redis.hgetall(session_key)
        return nil if raw.empty?

        customer_id = raw["customer_id"].to_s
        still_live = Store.redis.eval(
          TOUCH_SCRIPT,
          keys: [session_key, index_key(customer_id)],
          argv: [Time.now.to_i.to_s, Config.session_ttl, customer_id, digest(token)]
        ).to_i == 1
        return nil unless still_live

        { customer_id: raw["customer_id"], created_at: raw["created_at"].to_i }
      end

      def destroy(token)
        return if token.to_s.empty?

        customer_id = Store.redis.hget(key(token), "customer_id")
        Store.redis.multi do |tx|
          tx.del(key(token))
          tx.srem(index_key(customer_id), digest(token)) if customer_id
        end
      end

      # Delete every session for a customer except the one that must survive
      # (e.g. the session that just changed the password).
      def revoke_all(customer_id, except_token: nil)
        keep = except_token.to_s.empty? ? nil : digest(except_token)
        digests = Store.redis.smembers(index_key(customer_id))
        doomed = digests.reject { |d| d == keep }
        return 0 if doomed.empty?

        Store.redis.multi do |tx|
          tx.srem(index_key(customer_id), doomed)
          doomed.each { |d| tx.del(digest_key(d)) }
        end
        doomed.length
      end
    end
  end
end
