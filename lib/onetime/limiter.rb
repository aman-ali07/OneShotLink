# frozen_string_literal: true

module Onetime
  # Fixed-window Redis rate limiter.
  #
  # Two keys per limit, as documented in the README:
  #   limiter:<id>:<scope>           -> the window's observed count
  #   limiter:<id>:<scope>:counter   -> the raw INCR counter (for observability)
  #
  # The check and the increment happen in one Lua script so parallel requests
  # cannot slip past the ceiling.
  module Limiter
    SCRIPT = <<~LUA
      local count = redis.call('INCR', KEYS[1])
      if count == 1 then
        redis.call('EXPIRE', KEYS[1], ARGV[1])
        redis.call('SET', KEYS[2], 0, 'EX', ARGV[1])
      end
      redis.call('INCR', KEYS[2])
      if count > tonumber(ARGV[2]) then
        return 0
      end
      return 1
    LUA

    module_function

    # Raises Onetime::RateLimited when the caller is over budget.
    def check!(id, scope:, limit:, window:)
      return true if limit.to_i <= 0

      normalized = id.to_s.gsub(/[^a-zA-Z0-9_.:-]/, "_")[0, 120]
      keys = ["limiter:#{normalized}:#{scope}", "limiter:#{normalized}:#{scope}:counter"]
      allowed = Store.redis.eval(SCRIPT, keys: keys, argv: [window.to_i, limit.to_i]).to_i
      raise Onetime::RateLimited unless allowed == 1

      true
    end
  end
end
