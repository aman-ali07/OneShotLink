# frozen_string_literal: true

RSpec.describe "HTTP edge hardening" do
  EDGE_HEADERS = { "CONTENT_TYPE" => "application/json", "HTTP_ORIGIN" => "http://example.org" }.freeze

  def with_env(vars)
    old = vars.keys.to_h { |key| [key, ENV[key]] }
    vars.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    old.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def simple(vars = {})
    with_env({ "AUTH_MODE" => "simple", "HOST" => "example.org" }.merge(vars)) { yield }
  end

  def signup(email = "edge-#{SecureRandom.hex(4)}@example.com")
    post "/api/v3/signup", JSON.generate(email: email, password: "correct horse battery"), EDGE_HEADERS
    expect(last_response.status).to eq(201)
  end

  it "keeps the hardening headers on statically served assets" do
    asset = Dir.glob("public/app/assets/*.js").first
    skip "no built assets" unless asset

    get "/assets/#{File.basename(asset)}"
    expect(last_response.status).to eq(200)
    h = last_response.headers
    expect(h["content-security-policy"]).to include("script-src 'self'")
    expect(h["x-content-type-options"]).to eq("nosniff")
    expect(h["referrer-policy"]).to eq("no-referrer")
    expect(h["cache-control"]).to include("immutable")
  end

  it "rejects a loose JSON media type" do
    post "/api/v3/guest/conceal", JSON.generate(secret: "x", ttl: 1800), EDGE_HEADERS.merge("CONTENT_TYPE" => "application/jsonp")
    expect(last_response.status).to eq(422)
    expect(JSON.parse(last_response.body).dig("error", "code")).to eq("validation_error")
  end

  it "rate limits webhook creation on its own scope" do
    simple("RATE_LIMIT_WEBHOOK" => "2") do
      signup
      2.times do
        post "/api/v3/webhooks", JSON.generate(url: "http://93.184.216.34/hook", events: ["secret.created"]), EDGE_HEADERS
        expect(last_response.status).to eq(201)
      end
      post "/api/v3/webhooks", JSON.generate(url: "http://93.184.216.34/hook", events: ["secret.created"]), EDGE_HEADERS
      expect(last_response.status).to eq(429)
      expect(last_response.headers["Retry-After"]).not_to be_nil
    end
  end

  it "rate limits password change, account deletion and signout" do
    simple("RATE_LIMIT_PASSWORD" => "2", "RATE_LIMIT_DELETE" => "2", "RATE_LIMIT_SIGNOUT" => "2") do
      signup
      2.times do
        post "/api/v3/account/password", JSON.generate(current_password: "wrong", new_password: "new password value"), EDGE_HEADERS
        expect(last_response.status).to eq(401)
      end
      post "/api/v3/account/password", JSON.generate(current_password: "wrong", new_password: "new password value"), EDGE_HEADERS
      expect(last_response.status).to eq(429)

      clear_cookies
      signup
      delete "/api/v3/account", JSON.generate(password: "wrong"), EDGE_HEADERS
      expect(last_response.status).to eq(401)
      delete "/api/v3/account", JSON.generate(password: "wrong"), EDGE_HEADERS
      expect(last_response.status).to eq(401)
      delete "/api/v3/account", JSON.generate(password: "wrong"), EDGE_HEADERS
      expect(last_response.status).to eq(429)

      clear_cookies
      signup
      2.times { post "/api/v3/signout", nil, EDGE_HEADERS }
      post "/api/v3/signout", nil, EDGE_HEADERS
      expect(last_response.status).to eq(429)
    end
  end

  it "keeps signup and signin on separate limiter buckets" do
    simple("RATE_LIMIT_SIGNIN" => "2") do
      2.times do
        post "/api/v3/signin", JSON.generate(email: "nobody@example.com", password: "wrong"), EDGE_HEADERS
        expect(last_response.status).to eq(401)
      end
      # A signin burst must not consume the signup budget.
      post "/api/v3/signup", JSON.generate(email: "fresh@example.com", password: "correct horse battery"), EDGE_HEADERS
      expect(last_response.status).to eq(201)
    end
  end
end
