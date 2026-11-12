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

    # `flushdb` is the point of no return. If a live server or a second suite is
    # attached to DB 15, flushing it corrupts their state and can make this run
    # report fewer examples than it should, without failing. One client (this
    # process) is expected; more than one means the database is shared.
    attached = Onetime::Store.redis.client(:list).count { |client| client["db"].to_s == "15" }
    if attached > 1
      raise "refusing to run: #{attached} clients are attached to Redis DB 15 " \
            "(another server or suite is using it). Stop it, or point REDIS_URL at a free DB."
    end

    Onetime::Store.redis.flushdb
  end

  config.before do
    Onetime::Store.redis.flushdb
  end
end
