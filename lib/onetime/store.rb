# frozen_string_literal: true

require "json"
require "redis"

module Onetime
  # Thin Redis access layer. Every compare-and-swap / consume uses a Lua script
  # so a reveal can never half-succeed; other multi-key writes use MULTI.
  module Store
    class << self
      def redis
        @redis ||= Redis.new(
          url: Config.validated_redis_url,
          timeout: Config.redis_timeout,
          connect_timeout: Config.redis_timeout,
          read_timeout: Config.redis_timeout,
          write_timeout: Config.redis_timeout,
          reconnect_attempts: Config.redis_reconnect_attempts
        )
      end

      def reset!
        @redis = nil
      end

      def healthy?
        redis.ping == "PONG"
      rescue StandardError
        false
      end

      # used_memory / maxmemory for the metrics endpoint. Returns nil when Redis
      # is unreachable so /metrics can still render application counters.
      def memory_stats
        info = redis.info("memory")
        { used: info["used_memory"].to_i, max: info["maxmemory"].to_i }
      rescue StandardError
        nil
      end

      # Atomically consume a record: delete the key only if its packed value is
      # still exactly the one we read and verified. Two concurrent reveals race
      # here and exactly one wins; the loser gets nil and a 404.
      # The comparison is unconditional: an empty expected value can never turn
      # this into an unverified delete, even if a future caller forgets the Ruby
      # guard below. Only an exact match may destroy a record.
      CONSUME_SCRIPT = <<~LUA
        local current = redis.call('GET', KEYS[1])
        if not current then return 0 end
        if current ~= ARGV[1] then return 0 end
        redis.call('DEL', KEYS[1])
        return 1
      LUA

      # expected_value is required: deleting without proving which value we
      # verified would turn any caller bug into silent data loss.
      def consume(key, expected_value)
        raise ArgumentError, "expected_value is required" if expected_value.nil? || expected_value.empty?

        redis.eval(CONSUME_SCRIPT, keys: [key], argv: [expected_value.to_s]).to_i == 1
      end

      # A request reveal must retire the bearer link in the SAME atomic step as
      # the submission consume. Two separate round trips would leave a window
      # where the submission slot is free but the request object still accepts a
      # second answer (TOCTOU). One winner, one reveal, one retired link.
      CONSUME_REQUEST_SCRIPT = <<~LUA
        local current = redis.call('GET', KEYS[1])
        if not current or current ~= ARGV[1] then return 0 end
        redis.call('DEL', KEYS[1], KEYS[2])
        return 1
      LUA

      def consume_request(submission_key, object_key, expected_value)
        raise ArgumentError, "expected_value is required" if expected_value.nil? || expected_value.empty?

        redis.eval(CONSUME_REQUEST_SCRIPT, keys: [submission_key, object_key], argv: [expected_value.to_s]).to_i == 1
      end

      # Rewriting a record (key rotation) must not resurrect a secret that was
      # consumed between the read and the write. KEEPTTL preserves the remaining
      # lifetime without a second round trip; a vanished or changed key is left
      # alone and reported to the caller as a skip.
      REWRITE_SCRIPT = <<~LUA
        local current = redis.call('GET', KEYS[1])
        if not current or current ~= ARGV[1] then return 0 end
        redis.call('SET', KEYS[1], ARGV[2], 'KEEPTTL')
        return 1
      LUA

      def rewrite_if_unchanged(key, expected_value, new_value)
        raise ArgumentError, "expected_value is required" if expected_value.nil? || expected_value.empty?

        redis.eval(REWRITE_SCRIPT, keys: [key], argv: [expected_value.to_s, new_value.to_s]).to_i == 1
      end

      # Hash fields (webhook signing secrets) need the same compare-and-swap as
      # string records. HSET does not disturb an existing TTL.
      REWRITE_HASH_FIELD_SCRIPT = <<~LUA
        local current = redis.call('HGET', KEYS[1], ARGV[1])
        if not current or current ~= ARGV[2] then return 0 end
        redis.call('HSET', KEYS[1], ARGV[1], ARGV[3])
        return 1
      LUA

      def rewrite_hash_field_if_unchanged(key, field, expected_value, new_value)
        raise ArgumentError, "expected_value is required" if expected_value.nil? || expected_value.empty?

        redis.eval(REWRITE_HASH_FIELD_SCRIPT, keys: [key], argv: [field, expected_value.to_s, new_value.to_s]).to_i == 1
      end

    end
  end
end
