# frozen_string_literal: true

RSpec.describe "Secret lifecycle API" do
  JSON_HEADERS = { "CONTENT_TYPE" => "application/json" }.freeze

  def create_v3(secret:, ttl: 1800, passphrase: nil)
    body = { secret: secret, ttl: ttl }
    body[:passphrase] = passphrase if passphrase
    post "/api/v3/guest/conceal", JSON.generate(body), JSON_HEADERS
    JSON.parse(last_response.body)
  end

  def reveal_v3(key, passphrase: nil)
    if passphrase.nil?
      get "/api/v3/guest/secret/#{key}"
    else
      post "/api/v3/guest/secret/#{key}/reveal",
           JSON.generate(passphrase: passphrase), JSON_HEADERS
    end
  end

  def with_env(vars)
    old = vars.keys.to_h { |key| [key, ENV[key]] }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    old.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  describe "v3 guest conceal/reveal" do
    it "creates a secret and reveals it exactly once" do
      created = create_v3(secret: "s3cr3t-value")
      key = created["secret_key"]

      expect(last_response.status).to eq(201)
      expect(key.length).to be >= 22
      expect(created.dig("receipt", "secret_ttl")).to eq(1800)
      expect(created.dig("receipt", "passphrase_required")).to be(false)
      expect(created.dig("links", "secret")).to eq("/secret/#{key}")

      reveal_v3(key)
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["secret_value"]).to eq("s3cr3t-value")
      expect(body.dig("metadata", "kind")).to eq("text")

      reveal_v3(key)
      expect(last_response.status).to eq(404)
      expect(JSON.parse(last_response.body).dig("error", "code")).to eq("not_found")

      expect(Onetime::Store.redis.exists?("secret:object:#{key}")).to be(false)
      expect(Onetime::Store.redis.exists?("secret:receipt:#{key}")).to be(false)
    end

    it "stores only ciphertext at rest with a TTL" do
      created = create_v3(secret: "plaintext-marker-12345")
      key = created["secret_key"]
      raw = Onetime::Store.redis.get("secret:object:#{key}")
      record = JSON.parse(raw)

      expect(raw).not_to include("plaintext-marker")
      expect(record).to include("ciphertext", "iv", "tag", "salt")
      expect(Onetime::Store.redis.ttl("secret:object:#{key}")).to be_between(1, 1800)

      receipt = Onetime::Store.redis.hgetall("secret:receipt:#{key}")
      expect(receipt["identifier"]).to eq(key)
      expect(receipt["passphrase"]).to eq("0")
      expect(receipt["viewed"]).to eq("0")
    end

    it "requires the passphrase and never burns on a wrong attempt" do
      created = create_v3(secret: "guarded", passphrase: "open sesame")
      key = created["secret_key"]

      reveal_v3(key)
      expect(last_response.status).to eq(401)
      expect(JSON.parse(last_response.body).dig("error", "code")).to eq("passphrase_required")

      reveal_v3(key, passphrase: "wrong")
      expect(last_response.status).to eq(401)
      expect(JSON.parse(last_response.body).dig("error", "code")).to eq("invalid_passphrase")
      expect(Onetime::Store.redis.exists?("secret:object:#{key}")).to be(true)

      reveal_v3(key, passphrase: "open sesame")
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["secret_value"]).to eq("guarded")

      reveal_v3(key, passphrase: "open sesame")
      expect(last_response.status).to eq(404)
    end

    it "lets exactly one concurrent reveal win" do
      key = create_v3(secret: "race")["secret_key"]

      statuses = 8.times.map do
        Thread.new do
          Rack::MockRequest.new(Onetime::Web::App)
                         .post("/api/v3/guest/secret/#{key}/reveal", input: "{}",
                               "CONTENT_TYPE" => "application/json").status
        end
      end.map(&:value)

      expect(statuses.count(200)).to eq(1)
      expect(statuses.count(404)).to eq(7)
    end

    it "expires after the TTL and then returns the same 404" do
      with_env("TTL_OPTIONS" => "1,1800", "DEFAULT_TTL" => "1") do
        key = create_v3(secret: "short-lived", ttl: 1)["secret_key"]
        sleep 1.1

        reveal_v3(key)
        expect(last_response.status).to eq(404)
        expect(JSON.parse(last_response.body).dig("error", "code")).to eq("not_found")
      end
    end

    it "does not destroy the secret when it cannot be decrypted" do
      # A rotated or wrong SECRET makes decryption impossible. That is an
      # operator fault, not a reveal: the record must survive so the operator
      # can rotate back and the reader can still get the secret.
      key = create_v3(secret: "unreadable-under-this-key")["secret_key"]

      allow(Onetime::Crypto).to receive(:decrypt).and_raise(Onetime::Error, "Stored secret could not be decrypted")
      reveal_v3(key)
      expect(last_response.status).to eq(500)
      expect(last_response.body).not_to include("unreadable-under-this-key")

      allow(Onetime::Crypto).to receive(:decrypt).and_call_original
      reveal_v3(key)
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["secret_value"]).to eq("unreadable-under-this-key")
    end
  end

  describe "v1 compatibility" do
    it "creates via form and reveals with the legacy shape" do
      post "/api/v1/share", secret: "legacy-secret", ttl: 1800
      expect(last_response.status).to eq(200)
      key = JSON.parse(last_response.body)["secret_key"]
      expect(key).not_to be_nil

      post "/api/v1/secret/#{key}"
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["secret_value"]).to eq("legacy-secret")

      post "/api/v1/secret/#{key}"
      expect(last_response.status).to eq(404)
      expect(JSON.parse(last_response.body)).to include("message")
    end

    it "accepts a JSON body for legacy clients" do
      post "/api/v1/share", JSON.generate(secret: "legacy-json", ttl: 1800), JSON_HEADERS
      expect(last_response.status).to eq(200)
      key = JSON.parse(last_response.body)["secret_key"]

      post "/api/v1/secret/#{key}"
      expect(JSON.parse(last_response.body)["secret_value"]).to eq("legacy-json")
    end
  end

  describe "validation and abuse controls" do
    it "rejects an unlisted TTL, an empty secret, and non-JSON bodies" do
      post "/api/v3/guest/conceal", JSON.generate(secret: "x", ttl: 999), JSON_HEADERS
      expect(last_response.status).to eq(422)
      expect(JSON.parse(last_response.body).dig("error", "code")).to eq("validation_error")

      post "/api/v3/guest/conceal", JSON.generate(secret: "", ttl: 1800), JSON_HEADERS
      expect(last_response.status).to eq(422)

      post "/api/v3/guest/conceal", JSON.generate(secret: "x", ttl: 1800)
      expect(last_response.status).to eq(422)
    end

    it "rejects an oversized secret without writing anything" do
      with_env("MAX_SECRET_BYTES" => "5") do
        post "/api/v3/guest/conceal", JSON.generate(secret: "123456", ttl: 1800), JSON_HEADERS
        expect(last_response.status).to eq(413)
        expect(JSON.parse(last_response.body).dig("error", "code")).to eq("payload_too_large")
        expect(Onetime::Store.redis.keys("secret:*")).to be_empty
      end
    end

    it "accepts exactly MAX_SECRET_BYTES and rejects one byte more" do
      with_env("MAX_SECRET_BYTES" => "16") do
        exact = "a" * 16
        create_v3(secret: exact)
        expect(last_response.status).to eq(201)

        create_v3(secret: "a" * 17)
        expect(last_response.status).to eq(413)
      end
    end

    it "treats empty and one-character passphrases as absent or valid" do
      # Empty string means "no passphrase": no passphrase required on reveal.
      post "/api/v3/guest/conceal", JSON.generate(secret: "p0", ttl: 1800, passphrase: ""), JSON_HEADERS
      expect(last_response.status).to eq(201)
      key = JSON.parse(last_response.body)["secret_key"]
      get "/api/v3/guest/secret/#{key}"
      expect(last_response.status).to eq(200)

      # A single character is a real passphrase and must be enforced.
      post "/api/v3/guest/conceal", JSON.generate(secret: "p1", ttl: 1800, passphrase: "x"), JSON_HEADERS
      expect(last_response.status).to eq(201)
      key = JSON.parse(last_response.body)["secret_key"]
      post "/api/v3/guest/secret/#{key}/reveal", JSON.generate(passphrase: "y"), JSON_HEADERS
      expect(last_response.status).to eq(401)
      post "/api/v3/guest/secret/#{key}/reveal", JSON.generate(passphrase: "x"), JSON_HEADERS
      expect(last_response.status).to eq(200)
    end

    it "rate limits conceal with Retry-After" do
      with_env("RATE_LIMIT_CONCEAL" => "1", "RATE_LIMIT_WINDOW" => "60") do
        create_v3(secret: "one")
        expect(last_response.status).to eq(201)
        expect(last_response.headers["X-RateLimit-Limit"]).to eq("1")
        expect(last_response.headers["X-RateLimit-Remaining"]).to eq("0")

        create_v3(secret: "two")
        expect(last_response.status).to eq(429)
        expect(last_response.headers["Retry-After"]).to eq("60")
        expect(last_response.headers["X-RateLimit-Limit"]).to eq("1")
        expect(last_response.headers["X-RateLimit-Remaining"]).to eq("0")
        expect(last_response.headers["X-RateLimit-Reset"].to_i).to be_between(1, 60)
        expect(JSON.parse(last_response.body).dig("error", "code")).to eq("rate_limited")
      end
    end

    it "rate limits v1 with Retry-After too" do
      with_env("RATE_LIMIT_CONCEAL" => "1", "RATE_LIMIT_WINDOW" => "60") do
        post "/api/v1/share", secret: "one", ttl: 1800
        expect(last_response.status).to eq(200)

        post "/api/v1/share", secret: "two", ttl: 1800
        expect(last_response.status).to eq(429)
        expect(last_response.headers["Retry-After"]).to eq("60")
      end
    end

    it "ignores X-Forwarded-For when no proxy is trusted" do
      with_env("RATE_LIMIT_CONCEAL" => "1", "TRUST_PROXY" => "false") do
        env = JSON_HEADERS.merge("REMOTE_ADDR" => "203.0.113.9", "HTTP_X_FORWARDED_FOR" => "198.51.100.1")
        post "/api/v3/guest/conceal", JSON.generate(secret: "one", ttl: 1800), env
        expect(last_response.status).to eq(201)

        env = JSON_HEADERS.merge("REMOTE_ADDR" => "203.0.113.9", "HTTP_X_FORWARDED_FOR" => "198.51.100.2")
        post "/api/v3/guest/conceal", JSON.generate(secret: "two", ttl: 1800), env
        expect(last_response.status).to eq(429)
      end
    end

    it "uses X-Forwarded-For only from a configured trusted proxy" do
      with_env("RATE_LIMIT_CONCEAL" => "1", "TRUST_PROXY" => "true", "TRUSTED_PROXIES" => "10.0.0.0/8") do
        first = JSON_HEADERS.merge("REMOTE_ADDR" => "10.0.0.2", "HTTP_X_FORWARDED_FOR" => "198.51.100.1")
        second = JSON_HEADERS.merge("REMOTE_ADDR" => "10.0.0.2", "HTTP_X_FORWARDED_FOR" => "198.51.100.2")
        post "/api/v3/guest/conceal", JSON.generate(secret: "one", ttl: 1800), first
        expect(last_response.status).to eq(201)
        post "/api/v3/guest/conceal", JSON.generate(secret: "two", ttl: 1800), second
        expect(last_response.status).to eq(201)

        post "/api/v3/guest/conceal", JSON.generate(secret: "three", ttl: 1800), first
        expect(last_response.status).to eq(429)
      end
    end

    it "fails closed on owner routes when auth is enabled but sessions do not exist yet" do
      with_env("AUTH_MODE" => "simple") do
        post "/api/v3/secret/conceal", JSON.generate(secret: "x", ttl: 1800), JSON_HEADERS
        expect(last_response.status).to eq(401)
        expect(JSON.parse(last_response.body).dig("error", "code")).to eq("unauthorized")
      end
    end

    it "returns 501 for full auth mode instead of degrading" do
      with_env("AUTH_MODE" => "full") do
        post "/api/v3/secret/conceal", JSON.generate(secret: "x", ttl: 1800), JSON_HEADERS
        expect(last_response.status).to eq(501)
        expect(JSON.parse(last_response.body).dig("error", "code")).to eq("not_configured")
      end
    end

    it "returns not_found for an unknown key" do
      get "/api/v3/guest/secret/does-not-exist"
      expect(last_response.status).to eq(404)
      expect(JSON.parse(last_response.body).dig("error", "code")).to eq("not_found")
    end
  end
end
