# frozen_string_literal: true

require "json"
require "redis"

module Onetime
  # Thin Redis access layer. Everything that mutates more than one key goes
  # through a Lua script so a reveal can never half-succeed.
  module Store
    class << self
      attr_writer :redis

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
      CONSUME_SCRIPT = <<~LUA
        local current = redis.call('GET', KEYS[1])
        if not current then return 0 end
        if ARGV[1] ~= '' and current ~= ARGV[1] then return 0 end
        redis.call('DEL', KEYS[1])
        return 1
      LUA

      # expected_value is required: deleting without proving which value we
      # verified would turn any caller bug into silent data loss.
      def consume(key, expected_value)
        raise ArgumentError, "expected_value is required" if expected_value.nil? || expected_value.empty?

        redis.eval(CONSUME_SCRIPT, keys: [key], argv: [expected_value.to_s]).to_i == 1
      end

      def get_json(key)
        raw = redis.get(key)
        raw && JSON.parse(raw)
      end

      def set_json(key, value, ttl: nil)
        if ttl
          redis.set(key, JSON.generate(value), ex: ttl.to_i)
        else
          redis.set(key, JSON.generate(value))
        end
      end

      def flush_test_db!
        redis.flushdb
      end
    end
  end
end
