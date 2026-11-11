# frozen_string_literal: true

module Onetime
  # Fixed-window Redis rate limiter.
  #
  # Two keys per limit, as documented in README/DATABASE:
  #   limiter:<id>:<scope>           -> the window's observed count
  #   limiter:<id>:<scope>:counter   -> the raw INCR counter (for observability)
  #
  # The check, the increment, and the header values (count + window TTL) are all
  # returned from one Lua call, so a rate-limited request costs a single
  # round-trip instead of a check plus a peek.
  module Limiter
    SCRIPT = <<~LUA
      local count = redis.call('INCR', KEYS[1])
      if count == 1 then
        redis.call('EXPIRE', KEYS[1], ARGV[1])
        redis.call('SET', KEYS[2], 0, 'EX', ARGV[1])
      end
      redis.call('INCR', KEYS[2])
      local ttl = redis.call('TTL', KEYS[1])
      local allowed = (count <= tonumber(ARGV[2])) and 1 or 0
      return { allowed, count, ttl }
    LUA

    Result = Struct.new(:allowed, :count, :ttl, :limit) do
      def allowed? = allowed == 1
      def remaining = [limit - count, 0].max
      def reset = ttl.negative? ? 0 : ttl
    end

    module_function

    # Returns a Result carrying whether the request is allowed plus the values
    # the HTTP layer needs for X-RateLimit-* headers. Raises RateLimited when
    # the caller is over budget so existing call sites keep working.
    def check!(id, scope:, limit:, window:)
      return Result.new(1, 0, 0, 0) if limit.to_i <= 0

      normalized = id.to_s.gsub(/[^a-zA-Z0-9_.:-]/, "_")[0, 120]
      keys = ["limiter:#{normalized}:#{scope}", "limiter:#{normalized}:#{scope}:counter"]
      allowed, count, ttl = Store.redis.eval(SCRIPT, keys: keys, argv: [window.to_i, limit.to_i])
      result = Result.new(allowed.to_i, count.to_i, ttl.to_i, limit.to_i)
      raise Onetime::RateLimited unless result.allowed?

      result
    end

    # Non-mutating peek, used only to decorate a 429 raised elsewhere.
    def snapshot(id, scope:, limit:, window:)
      return Result.new(1, 0, window.to_i, limit.to_i) if limit.to_i <= 0

      normalized = id.to_s.gsub(/[^a-zA-Z0-9_.:-]/, "_")[0, 120]
      key = "limiter:#{normalized}:#{scope}"
      count = Store.redis.get(key).to_i
      ttl = Store.redis.ttl(key)
      Result.new(1, count, ttl, limit.to_i)
    end
  end
end
