# frozen_string_literal: true

RSpec.describe Onetime::Web::App do
  def with_env(vars)
    old = vars.keys.to_h { |key| [key, ENV[key]] }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    old.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  it "reports health with Redis up" do
    get "/health"

    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)).to include(
      "status" => "ok", "redis" => "ok", "version" => Onetime::VERSION
    )
  end

  it "reports 503 when Redis is unreachable" do
    allow(Onetime::Store).to receive(:healthy?).and_return(false)
    get "/health"

    expect(last_response.status).to eq(503)
    expect(JSON.parse(last_response.body)).to include("status" => "degraded", "redis" => "error")
  end

  it "sets security headers and a request id" do
    get "/health"

    expect(last_response.headers["X-Content-Type-Options"]).to eq("nosniff")
    expect(last_response.headers["X-Frame-Options"]).to eq("DENY")
    expect(last_response.headers["X-Request-Id"]).to match(/\A[0-9a-f-]{36}\z/)
    expect(last_response.headers["Cache-Control"]).to eq("no-store")
    expect(last_response.headers["Pragma"]).to eq("no-cache")
    expect(last_response.headers["Content-Security-Policy"]).to include("default-src 'self'", "frame-ancestors 'none'")
    expect(last_response.headers["Permissions-Policy"]).to include("camera=()")
    expect(last_response.headers["Cross-Origin-Opener-Policy"]).to eq("same-origin")
    expect(last_response.headers["Strict-Transport-Security"]).to be_nil
  end

  it "sets HSTS only when SSL is enabled" do
    with_env("SSL" => "true") do
      get "/health"
      expect(last_response.headers["Strict-Transport-Security"]).to eq("max-age=31536000; includeSubDomains")
    end
  end

  it "exposes public configuration without secrets" do
    get "/api/v3/config"
    body = JSON.parse(last_response.body)

    expect(last_response.status).to eq(200)
    expect(body["ttl_options"]).to eq(Onetime::Config.ttl_options)
    expect(body["auth_mode"]).to eq("disabled")
    expect(body).not_to have_key("secret")
    expect(last_response.body).not_to include(ENV.fetch("SECRET"))
  end

  it "returns a typed 404 for unknown API routes" do
    get "/api/v3/nope"

    expect(last_response.status).to eq(404)
    expect(JSON.parse(last_response.body).dig("error", "code")).to eq("not_found")
  end

  describe "when the datastore drops out mid-request" do
    before do
      allow(Onetime::Store.redis).to receive(:set).and_raise(Redis::CannotConnectError, "connection refused")
      allow(Onetime::Store.redis).to receive(:multi).and_raise(Redis::CannotConnectError, "connection refused")
      allow(Onetime::Store.redis).to receive(:zadd).and_raise(Redis::CannotConnectError, "connection refused")
    end

    it "answers v3 with 503 and a retry hint instead of a generic 500" do
      post "/api/v3/guest/conceal", JSON.generate(secret: "during an outage", ttl: 1800),
           { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(503)
      expect(JSON.parse(last_response.body).dig("error", "code")).to eq("service_unavailable")
      expect(last_response.headers["Retry-After"]).to match(/\A\d+\z/)
      expect(last_response.body).not_to include("connection refused")
      expect(last_response.body).not_to include("during an outage")
    end

    it "answers v1 in the legacy shape with the same status" do
      post "/api/v1/share", { secret: "during an outage", ttl: 1800 }

      expect(last_response.status).to eq(503)
      expect(JSON.parse(last_response.body)).to have_key("message")
      expect(last_response.headers["Retry-After"]).to match(/\A\d+\z/)
    end
  end

  it "serves the SPA shell for deep links when the build exists" do
    allow(File).to receive(:file?).and_call_original
    allow(File).to receive(:file?).with(Onetime::Web::App::INDEX_PATH).and_return(true)
    allow(File).to receive(:read).with(Onetime::Web::App::INDEX_PATH)
      .and_return("<!doctype html><title>app</title>")

    get "/secret/abc"

    expect(last_response.status).to eq(200)
    expect(last_response.headers["Content-Type"]).to include("text/html")
    expect(last_response.headers["X-Robots-Tag"]).to eq("noindex, nofollow")
  end

  it "serves JSON 404 before the SPA is built" do
    allow(File).to receive(:file?).and_call_original
    allow(File).to receive(:file?).with(Onetime::Web::App::INDEX_PATH).and_return(false)

    get "/somewhere"

    expect(last_response.status).to eq(404)
    expect(last_response.headers["Content-Type"]).to include("application/json")
  end
end

RSpec.describe "HEAD responses" do
  def app
    Onetime::Web::HeadRequests.new(Onetime::Web::App)
  end

  it "answers HEAD like GET with an empty body" do
    head "/health"

    expect(last_response.status).to eq(200)
    expect(last_response.body).to eq("")
    expect(last_response.headers["Content-Type"]).to include("application/json")
  end
end
