# frozen_string_literal: true

RSpec.describe Onetime::Web::RequestLogger do
  def log_for(path)
    messages = []
    logger = Object.new
    logger.define_singleton_method(:info) { |message| messages << message }
    app = ->(_env) { [200, { "X-Request-Id" => "req-1" }, []] }
    described_class.new(app, logger: logger).call(
      "REQUEST_METHOD" => "GET", "PATH_INFO" => path
    )
    messages.fetch(0)
  end

  it "logs method, path, status, duration, and request id" do
    line = log_for("/health")
    expect(line).to include("method=GET", "path=/health", "status=200", "request_id=req-1")
  end

  it "redacts secret keys in API and UI paths" do
    expect(log_for("/api/v3/guest/secret/abcdef123456")).to include("path=/api/v3/guest/secret/<redacted>")
    expect(log_for("/api/v1/secret/abcdef123456")).to include("path=/api/v1/secret/<redacted>")
    expect(log_for("/api/v3/guest/secret/abcdef123456/reveal")).to include("/secret/<redacted>/reveal")
    expect(log_for("/secret/abcdef123456")).to include("path=/secret/<redacted>")
    expect(log_for("/api/v3/guest/secret/abcdef123456")).not_to include("abcdef123456")
  end

  it "skips asset noise but still logs API errors" do
    messages = []
    logger = Object.new
    logger.define_singleton_method(:info) { |message| messages << message }
    app = ->(_env) { [200, {}, []] }
    middleware = described_class.new(app, logger: logger)
    middleware.call("REQUEST_METHOD" => "GET", "PATH_INFO" => "/assets/app.js")
    middleware.call("REQUEST_METHOD" => "GET", "PATH_INFO" => "/api/v3/config")
    expect(messages.length).to eq(1)
    expect(messages.first).to include("path=/api/v3/config")
  end
end
