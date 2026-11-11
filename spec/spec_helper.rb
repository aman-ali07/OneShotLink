# frozen_string_literal: true

# Test configuration must be set before the library reads it (Config is lazy).
ENV["SECRET"] ||= "test-only-secret-not-a-real-deployment-key"
ENV["REDIS_URL"] ||= "redis://127.0.0.1:6399/15"
ENV["RACK_ENV"] = "test"
ENV["AUTH_MODE"] ||= "disabled"
ENV["LOG_LEVEL"] = "error"

require "rack/test"
require_relative "../lib/onetime"
require_relative "../lib/onetime/web/app"

module AppHelper
  include Rack::Test::Methods

  def app
    Onetime::Web::App
  end
end

RSpec.configure do |config|
  config.include AppHelper
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.before(:suite) do
    unless ENV.fetch("REDIS_URL").end_with?("/15")
      raise "refusing to flush a non-test Redis database: #{ENV['REDIS_URL']}"
    end
    Onetime::Store.redis.flushdb
  end

  config.before do
    Onetime::Store.redis.flushdb
  end
end
