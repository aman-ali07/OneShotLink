# frozen_string_literal: true

require "digest"

module Onetime
  module Models
    # Opaque, server-side sessions. The cookie carries a random token; Redis
    # stores only its SHA-256 digest, so a Redis dump does not expose live
    # session tokens.
    module Session
      PREFIX = "session:"

      module_function

      def digest(token)
        Digest::SHA256.hexdigest("ots-session/v1:#{token}")
      end

      def key(token)
        "#{PREFIX}#{digest(token)}"
      end

      def create(customer_id)
        token = Ids.session_token
        now = Time.now.to_i
        Store.redis.hset(key(token), {
          "customer_id" => customer_id.to_s,
          "created_at" => now.to_s,
          "last_seen" => now.to_s
        })
        Store.redis.expire(key(token), Config.session_ttl)
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

        Store.redis.del(key(token))
      end
    end
  end
end
