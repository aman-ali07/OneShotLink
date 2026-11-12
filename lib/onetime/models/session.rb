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

        raw = Store.redis.hgetall(key(token))
        return nil if raw.empty?

        Store.redis.expire(key(token), Config.session_ttl)
        Store.redis.hset(key(token), "last_seen", Time.now.to_i.to_s)
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
        Store.redis.srem(index_key(customer_id), doomed) unless doomed.empty?
        doomed.each { |d| Store.redis.del(digest_key(d)) } unless doomed.empty?
        doomed.length
      end
    end
  end
end
