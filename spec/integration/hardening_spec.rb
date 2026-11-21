# frozen_string_literal: true

RSpec.describe "Web hardening" do
  WEB_HARDENING_HEADERS = { "CONTENT_TYPE" => "application/json", "HTTP_ORIGIN" => "http://example.org" }.freeze

  def with_env(vars)
    old = vars.keys.to_h { |key| [key, ENV[key]] }
    vars.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    old.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  before { clear_cookies }

  def simple(&block)
    with_env("AUTH_MODE" => "simple", "HOST" => "example.org", "SSL" => "false", &block)
  end

  def signup(email = "scope-#{SecureRandom.hex(4)}@example.com")
    post "/api/v3/signup", JSON.generate(email: email, password: "correct horse battery"), WEB_HARDENING_HEADERS
    expect(last_response.status).to eq(201)
  end

  it "sends the hardening headers on static assets, not just API responses" do
    asset = Dir["public/app/assets/index-*.js"].first
    expect(asset).not_to be_nil

    get "/assets/#{File.basename(asset)}"
    expect(last_response.status).to eq(200)
    expect(last_response.headers["Content-Security-Policy"]).to include("default-src 'self'")
    expect(last_response.headers["X-Content-Type-Options"]).to eq("nosniff")
    expect(last_response.headers["X-Frame-Options"]).to eq("DENY")
  end

  it "rejects a lookalike JSON media type" do
    post "/api/v3/guest/conceal", '{"secret":"x"}', "CONTENT_TYPE" => "application/jsonp"
    expect(last_response.status).to eq(422)
  end

  it "limits webhook creation on its own scope" do
    simple do
      with_env("RATE_LIMIT_WEBHOOK" => "1", "RATE_LIMIT_SIGNUP" => "100") do
        signup
        body = JSON.generate(url: "http://93.184.216.34/hook", events: ["secret.created"])
        post "/api/v3/webhooks", body, WEB_HARDENING_HEADERS
        expect(last_response.status).to eq(201)
        post "/api/v3/webhooks", body, WEB_HARDENING_HEADERS
        expect(last_response.status).to eq(429)
      end
    end
  end

  it "limits password changes, signout and account deletion independently" do
    simple do
      with_env("RATE_LIMIT_PASSWORD" => "1", "RATE_LIMIT_SIGNOUT" => "1", "RATE_LIMIT_DELETE" => "1",
               "RATE_LIMIT_SIGNUP" => "100") do
        signup
        post "/api/v3/account/password", JSON.generate(current_password: "correct horse battery",
                                                        new_password: "a brand new passphrase"), WEB_HARDENING_HEADERS
        expect(last_response.status).to eq(200)
        post "/api/v3/account/password", JSON.generate(current_password: "a brand new passphrase",
                                                        new_password: "another passphrase entirely"), WEB_HARDENING_HEADERS
        expect(last_response.status).to eq(429)
      end
    end

    simple do
      with_env("RATE_LIMIT_SIGNOUT" => "1", "RATE_LIMIT_SIGNUP" => "100") do
        signup
        post "/api/v3/signout", "{}", WEB_HARDENING_HEADERS
        expect(last_response.status).to eq(200)
        post "/api/v3/signout", "{}", WEB_HARDENING_HEADERS
        expect(last_response.status).to eq(429)
      end
    end

    simple do
      with_env("RATE_LIMIT_DELETE" => "1", "RATE_LIMIT_SIGNUP" => "100") do
        signup
        delete "/api/v3/account", JSON.generate(password: "correct horse battery"), WEB_HARDENING_HEADERS
        expect(last_response.status).to eq(200)
        delete "/api/v3/account", JSON.generate(password: "correct horse battery"), WEB_HARDENING_HEADERS
        expect(last_response.status).to eq(429)
      end
    end
  end
end
