# frozen_string_literal: true

RSpec.describe "Incoming secret requests" do
  REQ_JSON_HEADERS = {
    "CONTENT_TYPE" => "application/json",
    "HTTP_ORIGIN" => "http://example.org",
  }.freeze
  PASSWORD = "correct horse battery request"

  def signup(email = "owner@example.com")
    post "/api/v3/signup", JSON.generate(email: email, password: PASSWORD), REQ_JSON_HEADERS
    expect(last_response.status).to eq(201)
  end

  def create_request(label: "Vendor credentials", ttl: 1800)
    post "/api/v3/requests", JSON.generate(label: label, ttl: ttl), REQ_JSON_HEADERS
    JSON.parse(last_response.body)
  end

  def respond(key, secret: "submitted-secret", passphrase: nil)
    body = { secret: secret }
    body[:passphrase] = passphrase if passphrase
    post "/api/v3/requests/#{key}/respond", JSON.generate(body), REQ_JSON_HEADERS
  end

  def reveal(key)
    post "/api/v3/requests/#{key}/reveal", JSON.generate({}), REQ_JSON_HEADERS
  end

  describe "owner and responder flow" do
    it "creates, lists, previews, accepts one response and reveals it once" do
      with_env("AUTH_MODE" => "simple") do
        signup
        created = create_request
        expect(last_response.status).to eq(201)
        key = created["request_key"]
        expect(created.dig("links", "request")).to eq("/request/#{key}")

        get "/api/v3/requests", nil, REQ_JSON_HEADERS
        expect(last_response.status).to eq(200)
        expect(JSON.parse(last_response.body)["requests"].map { |r| r["request_key"] }).to include(key)

        get "/api/v3/requests/#{key}"
        expect(last_response.status).to eq(200)
        expect(JSON.parse(last_response.body).dig("metadata", "label")).to eq("Vendor credentials")

        respond(key)
        expect(last_response.status).to eq(201)
        respond(key, secret: "a second answer")
        expect(last_response.status).to eq(409)

        reveal(key)
        expect(last_response.status).to eq(200)
        expect(JSON.parse(last_response.body)["secret_value"]).to eq("submitted-secret")

        reveal(key)
        expect(last_response.status).to eq(404)
      end
    end

    it "never stores the submitted plaintext in Redis" do
      with_env("AUTH_MODE" => "simple") do
        signup
        key = create_request["request_key"]
        respond(key, secret: "plaintext-marker")
        raw = Onetime::Store.redis.get("request:secret:#{key}")
        expect(raw).not_to be_nil
        expect(raw).not_to include("plaintext-marker")
      end
    end

    it "requires a session for owner routes and hides requests from other owners" do
      with_env("AUTH_MODE" => "simple") do
        signup("first@example.com")
        key = create_request["request_key"]
        clear_cookies
        post "/api/v3/requests", JSON.generate(label: "x", ttl: 1800), REQ_JSON_HEADERS
        expect(last_response.status).to eq(401)
        reveal(key)
        expect(last_response.status).to eq(401)

        signup("second@example.com")
        reveal(key)
        expect(last_response.status).to eq(404)
      end
    end

    it "validates the label and the submitted secret" do
      with_env("AUTH_MODE" => "simple") do
        signup
        create_request(label: "x" * 121)
        expect(last_response.status).to eq(422)

        key = create_request["request_key"]
        respond(key, secret: "")
        expect(last_response.status).to eq(422)
      end
    end
  end

  def with_env(vars)
    old = vars.keys.to_h { |key| [key, ENV[key]] }
    vars["HOST"] = "example.org"
    vars["SSL"] = "false"
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    old.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
