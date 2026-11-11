# frozen_string_literal: true

require "ipaddr"
require "uri"

module Onetime
  # Runtime configuration, read from the environment on demand. Keeping this
  # lazy means the CLI and the web app share one source of truth without a
  # global mutable settings object.
  module Config
    class Error < StandardError; end

    DEFAULTS = {
      "HOST" => "localhost:3000",
      "SSL" => "false",
      "AUTH_MODE" => "disabled", # disabled | simple | full
      "UI_ENABLED" => "true",
      "TTL_OPTIONS" => "1800,43200,86400,259200",
      "DEFAULT_TTL" => "86400",
      "SESSION_TTL" => "1209600",
      "RATE_LIMIT_CONCEAL" => "30",
      "RATE_LIMIT_REVEAL" => "60",
      "RATE_LIMIT_SIGNIN" => "10",
      "RATE_LIMIT_WINDOW" => "60",
      "TRUST_PROXY" => "false",
      "TRUSTED_PROXIES" => "",
      "REDIS_TIMEOUT" => "5",
      "REDIS_RECONNECT_ATTEMPTS" => "2"
    }.freeze

    module_function

    def [](key)
      value = ENV.fetch(key) { DEFAULTS[key] }
      value.nil? ? nil : value
    end

    def secret!
      raw = ENV["SECRET"].to_s
      raise Error, "SECRET must be set (generate one with: openssl rand -hex 32)" if raw.empty?
      raise Error, "SECRET must be at least 32 bytes of entropy" if raw.bytesize < 32

      raw
    end

    # Boot-time gate. Fails closed on values that would otherwise be silently
    # coerced into something unsafe or surprising at request time.
    def validate!
      secret!
      raise Error, "HOST must not include a scheme (use SSL=true instead)" if host.to_s.match?(%r{\A[a-z]+://}i)
      raise Error, "HOST must not be empty" if host.to_s.strip.empty?

      options = ttl_options
      raise Error, "TTL_OPTIONS must contain at least one positive integer" if options.empty?
      default = self["DEFAULT_TTL"].to_i
      unless options.include?(default)
        raise Error, "DEFAULT_TTL (#{default}) must be one of TTL_OPTIONS (#{options.join(',')})"
      end

      raise Error, "MAX_SECRET_BYTES must be positive" if max_secret_bytes <= 0
      raise Error, "MAX_SECRET_BYTES must be <= 10 MiB" if max_secret_bytes > (10 * 1024 * 1024)
      raise Error, "RATE_LIMIT_CONCEAL must be positive" if rate_limit(:conceal) <= 0
      raise Error, "RATE_LIMIT_REVEAL must be positive" if rate_limit(:reveal) <= 0
      raise Error, "RATE_LIMIT_SIGNIN must be positive" if rate_limit(:signin) <= 0
      raise Error, "RATE_LIMIT_WINDOW must be positive" if self["RATE_LIMIT_WINDOW"].to_i <= 0
      raise Error, "SESSION_TTL must be at least 60 seconds" if self["SESSION_TTL"].to_i < 60
      raise Error, "AUTH_MODE must be disabled, simple, or full" unless %w[disabled simple full].include?(auth_mode)
      raise Error, "REDIS_TIMEOUT must be positive" if self["REDIS_TIMEOUT"].to_f <= 0
      raise Error, "REDIS_RECONNECT_ATTEMPTS must be >= 0" if redis_reconnect_attempts.negative?
      validated_redis_url

      # Parse now so a typo fails at boot, not on the first proxied request.
      trusted_proxies
      true
    end

    def host
      self["HOST"]
    end

    def ssl?
      %w[true 1 yes on].include?(self["SSL"].to_s.downcase)
    end

    def base_url
      "#{ssl? ? 'https' : 'http'}://#{host}"
    end

    def auth_mode
      mode = self["AUTH_MODE"].to_s.downcase
      mode.empty? ? "disabled" : mode
    end

    def auth_enabled?
      auth_mode != "disabled"
    end

    # "full" mode needs PostgreSQL + RabbitMQ and is intentionally not wired
    # in this build; it fails closed instead of silently downgrading.
    def full_mode?
      auth_mode == "full"
    end

    def ui_enabled?
      %w[true 1 yes on].include?(self["UI_ENABLED"].to_s.downcase)
    end

    def ttl_options
      self["TTL_OPTIONS"].to_s.split(",").map(&:strip).reject(&:empty?).map(&:to_i).select(&:positive?).uniq
    end

    def default_ttl
      ttl = self["DEFAULT_TTL"].to_i
      ttl_options.include?(ttl) ? ttl : (ttl_options.last || 86_400)
    end

    def session_ttl
      self["SESSION_TTL"].to_i.positive? ? self["SESSION_TTL"].to_i : 1_209_600
    end

    def rate_limit(kind)
      key = case kind.to_sym
            when :conceal then "RATE_LIMIT_CONCEAL"
            when :signin then "RATE_LIMIT_SIGNIN"
            else "RATE_LIMIT_REVEAL"
            end
      self[key].to_i
    end

    def rate_limit_window
      self["RATE_LIMIT_WINDOW"].to_i.positive? ? self["RATE_LIMIT_WINDOW"].to_i : 60
    end

    def redis_url
      ENV["REDIS_URL"] || "redis://127.0.0.1:6379/0"
    end

    # Fail closed on a Redis URL that cannot carry auth/TLS correctly. rediss://
    # enables TLS; a password goes in the userinfo (redis://:pw@host/db) or in
    # REDIS_PASSWORD, which is folded into the URL and never logged.
    def validated_redis_url
      raw = redis_url.to_s
      password = ENV["REDIS_PASSWORD"].to_s
      uri = begin
        URI.parse(raw)
      rescue URI::InvalidURIError
        raise Error, "REDIS_URL is not a valid URI"
      end

      unless %w[redis rediss unix].include?(uri.scheme)
        raise Error, "REDIS_URL scheme must be redis://, rediss:// (TLS), or unix:"
      end

      if password.empty?
        raw
      else
        # URI requires the user component before the password. Set it first,
        # and never echo the password into logs or errors.
        uri.user = "default" if uri.user.to_s.empty?
        uri.password = password
        uri.to_s
      end
    end

    def log_level
      (ENV["LOG_LEVEL"] || "info").to_sym
    end

    def max_secret_bytes
      (ENV["MAX_SECRET_BYTES"] || (1 * 1024 * 1024)).to_i
    end

    def trust_proxy?
      %w[true 1 yes on].include?(self["TRUST_PROXY"].to_s.downcase)
    end

    # Only these hops may supply X-Forwarded-For. An empty list means no proxy
    # is trusted, even if TRUST_PROXY=true (fail closed).
    def trusted_proxies
      self["TRUSTED_PROXIES"].to_s.split(",").map(&:strip).reject(&:empty?).map do |cidr|
        IPAddr.new(cidr)
      rescue IPAddr::Error
        raise Error, "TRUSTED_PROXIES contains an invalid CIDR: #{cidr.inspect}"
      end
    end

    def redis_timeout
      value = self["REDIS_TIMEOUT"].to_f
      value.positive? ? value : 5.0
    end

    def redis_reconnect_attempts
      value = self["REDIS_RECONNECT_ATTEMPTS"].to_i
      value.negative? ? 0 : value
    end

  end
end
