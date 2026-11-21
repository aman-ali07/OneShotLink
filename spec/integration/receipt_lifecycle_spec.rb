# frozen_string_literal: true

# D-receipt: the payload is destroyed on reveal/burn, but non-sensitive receipt
# metadata is kept for 30 days. Every assertion is on HTTP responses or Redis
# state, never on a mock.
RSpec.describe "Receipt lifecycle and owner burn" do
  HEADERS = { "CONTENT_TYPE" => "application/json", "HTTP_ORIGIN" => "http://example.org" }.freeze
  OTHER_ORIGIN = { "CONTENT_TYPE" => "application/json", "HTTP_ORIGIN" => "http://evil.example" }.freeze
  PASSWORD = "correct horse battery receipt"
  RETENTION = 30 * 86_400

  def with_env(vars)
    old = vars.keys.to_h { |key| [key, ENV[key]] }
    vars.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    old.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def signup(email = "owner@example.org")
    post "/api/v3/signup", JSON.generate(email: email, password: PASSWORD), HEADERS
    expect(last_response.status).to eq(201)
    JSON.parse(last_response.body)
  end

  def conceal_as_owner(secret: "sensitive-payload")
    post "/api/v3/secret/conceal", JSON.generate(secret: secret, ttl: 1800), HEADERS
    expect(last_response.status).to eq(201)
    JSON.parse(last_response.body)["secret_key"]
  end

  def peek(key)
    get "/api/v3/guest/secret/#{key}", nil, HEADERS
  end

  def reveal(key)
    post "/api/v3/guest/secret/#{key}/reveal", JSON.generate({}), HEADERS
  end

  def burn(key, headers: HEADERS)
    delete "/api/v3/secret/#{key}", nil, headers
  end

  def receipt_for(key)
    Onetime::Store.redis.hgetall(Onetime::Models::Secret.receipt_key(key))
  end

  describe "reveal retention" do
    it "keeps a non-sensitive receipt for 30 days and destroys the payload" do
      with_env("AUTH_MODE" => "simple", "HOST" => "example.org") do
        signup
        key = conceal_as_owner(secret: "sensitive-payload")

        reveal(key)
        expect(last_response.status).to eq(200)
        expect(JSON.parse(last_response.body)["secret_value"]).to eq("sensitive-payload")

        expect(Onetime::Store.redis.exists?(Onetime::Models::Secret.object_key(key))).to be(false)
        receipt = receipt_for(key)
        expect(receipt["status"]).to eq("revealed")
        expect(receipt["viewed"]).to eq("1")
        expect(receipt).not_to have_key("secret")
        expect(receipt.values.join).not_to include("sensitive-payload")
        expect(Onetime::Store.redis.ttl(Onetime::Models::Secret.receipt_key(key)))
          .to be_within(5).of(RETENTION)
      end
    end

    it "marks a preview, then a reveal, without downgrading the terminal status" do
      with_env("AUTH_MODE" => "simple", "HOST" => "example.org") do
        signup
        key = conceal_as_owner

        peek(key)
        expect(last_response.status).to eq(200)
        expect(receipt_for(key)["status"]).to eq("previewed")
        expect(Onetime::Store.redis.exists?(Onetime::Models::Secret.object_key(key))).to be(true)

        reveal(key)
        expect(last_response.status).to eq(200)
        expect(receipt_for(key)["status"]).to eq("revealed")

        # A later preview of the burned link cannot reopen the receipt.
        peek(key)
        expect(last_response.status).to eq(404)
        expect(receipt_for(key)["status"]).to eq("revealed")
      end
    end

    it "prunes a retained receipt from the owner index once its TTL elapses" do
      with_env("AUTH_MODE" => "simple", "HOST" => "example.org") do
        signup
        key = conceal_as_owner
        reveal(key)
        expect(last_response.status).to eq(200)

        Onetime::Store.redis.expire(Onetime::Models::Secret.receipt_key(key), 1)
        sleep 1.1

        get "/api/v3/account/receipts", nil, HEADERS
        expect(last_response.status).to eq(200)
        expect(JSON.parse(last_response.body)["receipts"]).to be_empty
      end
    end
  end

  describe "owner burn" do
    it "destroys an unrevealed secret without revealing it and keeps a burned receipt" do
      with_env("AUTH_MODE" => "simple", "HOST" => "example.org") do
        signup
        key = conceal_as_owner(secret: "burn-this-payload")

        burn(key)
        expect(last_response.status).to eq(200)
        expect(last_response.body).not_to include("burn-this-payload")

        expect(Onetime::Store.redis.exists?(Onetime::Models::Secret.object_key(key))).to be(false)
        receipt = receipt_for(key)
        expect(receipt["status"]).to eq("burned")
        expect(receipt.values.join).not_to include("burn-this-payload")
        expect(Onetime::Store.redis.ttl(Onetime::Models::Secret.receipt_key(key)))
          .to be_within(5).of(RETENTION)

        reveal(key)
        expect(last_response.status).to eq(404)
        burn(key)
        expect(last_response.status).to eq(404)
      end
    end

    it "returns 404 to another owner and leaves the secret intact" do
      with_env("AUTH_MODE" => "simple", "HOST" => "example.org") do
        signup("victim@example.org")
        key = conceal_as_owner(secret: "still-live")
        signup("attacker@example.org")

        burn(key)
        expect(last_response.status).to eq(404)
        expect(Onetime::Store.redis.exists?(Onetime::Models::Secret.object_key(key))).to be(true)
        expect(receipt_for(key)["status"]).to eq("new")
      end
    end

    it "rejects a cross-site burn" do
      with_env("AUTH_MODE" => "simple", "HOST" => "example.org") do
        signup
        key = conceal_as_owner(secret: "csrf-burn-target")

        burn(key, headers: OTHER_ORIGIN)
        expect(last_response.status).to eq(403)
        expect(Onetime::Store.redis.exists?(Onetime::Models::Secret.object_key(key))).to be(true)
      end
    end

    it "rate limits burns on their own scope" do
      with_env("AUTH_MODE" => "simple", "HOST" => "example.org", "RATE_LIMIT_BURN" => "1") do
        signup
        first = conceal_as_owner(secret: "burn-one")
        second = conceal_as_owner(secret: "burn-two")

        burn(first)
        expect(last_response.status).to eq(200)
        burn(second)
        expect(last_response.status).to eq(429)
        expect(last_response.headers["Retry-After"]).to match(/\A\d+\z/)
        expect(Onetime::Store.redis.exists?(Onetime::Models::Secret.object_key(second))).to be(true)
      end
    end
  end
end
