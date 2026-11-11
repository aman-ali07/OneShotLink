# frozen_string_literal: true

RSpec.describe Onetime::Config do
  VALID = {
    "SECRET" => "a" * 64,
    "TTL_OPTIONS" => "60,3600",
    "DEFAULT_TTL" => "60",
    "RATE_LIMIT_CONCEAL" => "10",
    "RATE_LIMIT_REVEAL" => "10",
    "RATE_LIMIT_WINDOW" => "60",
    "SESSION_TTL" => "3600",
    "AUTH_MODE" => "disabled",
    "HOST" => "localhost:3000",
    "TRUST_PROXY" => "false",
    "TRUSTED_PROXIES" => "",
    "REDIS_TIMEOUT" => "5",
    "REDIS_RECONNECT_ATTEMPTS" => "2"
  }.freeze

  def with_env(vars)
    old = vars.keys.to_h { |key| [key, ENV[key]] }
    vars.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    old.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def validate(overrides = {})
    with_env(VALID.merge(overrides)) { described_class.validate! }
  end

  it "accepts a complete, valid environment" do
    expect(validate).to be(true)
  end

  it "rejects a missing or short SECRET" do
    expect { validate("SECRET" => nil) }.to raise_error(described_class::Error, /SECRET must be set/)
    expect { validate("SECRET" => "short") }.to raise_error(described_class::Error, /at least 32 bytes/)
  end

  it "rejects a DEFAULT_TTL outside TTL_OPTIONS" do
    expect { validate("DEFAULT_TTL" => "120") }.to raise_error(described_class::Error, /DEFAULT_TTL/)
  end

  it "rejects empty TTL options and non-positive limits" do
    expect { validate("TTL_OPTIONS" => ",") }.to raise_error(described_class::Error, /TTL_OPTIONS/)
    expect { validate("RATE_LIMIT_CONCEAL" => "0") }.to raise_error(described_class::Error, /RATE_LIMIT_CONCEAL/)
    expect { validate("RATE_LIMIT_WINDOW" => "0") }.to raise_error(described_class::Error, /RATE_LIMIT_WINDOW/)
    expect { validate("MAX_SECRET_BYTES" => (11 * 1024 * 1024).to_s) }.to raise_error(described_class::Error, /10 MiB/)
  end

  it "rejects an invalid auth mode, host, or proxy CIDR" do
    expect { validate("AUTH_MODE" => "maybe") }.to raise_error(described_class::Error, /AUTH_MODE/)
    expect { validate("HOST" => "https://example.com") }.to raise_error(described_class::Error, /scheme/)
    expect { validate("TRUSTED_PROXIES" => "not-a-cidr") }.to raise_error(described_class::Error, /CIDR/)
  end

  it "parses trusted proxy networks and only trusts them when enabled" do
    with_env(VALID.merge("TRUST_PROXY" => "true", "TRUSTED_PROXIES" => "10.0.0.0/8, 2001:db8::/32")) do
      expect(described_class.trust_proxy?).to be(true)
      expect(described_class.trusted_proxies).to eq([IPAddr.new("10.0.0.0/8"), IPAddr.new("2001:db8::/32")])
    end
    with_env(VALID.merge("TRUST_PROXY" => "false", "TRUSTED_PROXIES" => "10.0.0.0/8")) do
      expect(described_class.trust_proxy?).to be(false)
    end
  end

  it "validates the Redis URL scheme and folds in REDIS_PASSWORD" do
    with_env(VALID.merge("REDIS_URL" => "rediss://cache.internal:6380/0", "REDIS_PASSWORD" => "")) do
      expect(described_class.validated_redis_url).to eq("rediss://cache.internal:6380/0")
    end

    with_env(VALID.merge("REDIS_URL" => "redis://redis:6379/0", "REDIS_PASSWORD" => "s3cret")) do
      url = described_class.validated_redis_url
      expect(url).to include("redis://")
      expect(url).to include("s3cret")
      expect(url).to include("redis:6379")
    end
  end

  it "rejects a Redis URL with an unsupported scheme" do
    with_env(VALID.merge("REDIS_URL" => "http://nope:6379/0", "REDIS_PASSWORD" => "")) do
      expect { described_class.validated_redis_url }.to raise_error(described_class::Error, /scheme/)
    end
  end
end
