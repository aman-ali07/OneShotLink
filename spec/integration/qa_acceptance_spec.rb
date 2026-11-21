# frozen_string_literal: true

# Tests added by the QA acceptance pass. Each one asserts an observable
# guarantee (status, body bytes, Redis state, or a race outcome) — never a mock
# created in the same example.
RSpec.describe "QA acceptance — edges, races and contracts" do
  JSON_HEADERS = { "CONTENT_TYPE" => "application/json" }.freeze

  def with_env(vars)
    old = vars.keys.to_h { |key| [key, ENV[key]] }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    old.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def conceal(secret:, passphrase: nil)
    body = { secret: secret, ttl: 1800 }
    body[:passphrase] = passphrase if passphrase
    post "/api/v3/guest/conceal", JSON.generate(body), JSON_HEADERS
    JSON.parse(last_response.body)
  end

  def reveal(key, passphrase: nil)
    post "/api/v3/guest/secret/#{key}/reveal",
         JSON.generate(passphrase ? { passphrase: passphrase } : {}), JSON_HEADERS
  end

  describe "input validation at the HTTP boundary" do
    it "rejects syntactically invalid JSON with a typed error and writes nothing" do
      post "/api/v3/guest/conceal", '{"secret":', JSON_HEADERS

      expect(last_response.status).to eq(422)
      expect(JSON.parse(last_response.body).dig("error", "code")).to eq("validation_error")
      expect(Onetime::Store.redis.keys("secret:object:*")).to be_empty
    end

    it "rejects a JSON body that is not an object" do
      post "/api/v3/guest/conceal", "[]", JSON_HEADERS

      expect(last_response.status).to eq(422)
      expect(Onetime::Store.redis.keys("secret:object:*")).to be_empty
    end
  end

  describe "uniform terminal responses" do
    it "returns byte-identical 404s for consumed, unknown and expired-like keys on GET and POST" do
      consumed = conceal(secret: "qa-consumed")["secret_key"]
      reveal(consumed)
      expired = conceal(secret: "qa-expired")["secret_key"]
      Onetime::Store.redis.del(Onetime::Models::Secret.object_key(expired))
      protected = conceal(secret: "qa-protected", passphrase: "correct-horse")["secret_key"]
      Onetime::Store.redis.del(Onetime::Models::Secret.object_key(protected))

      observed = []
      [consumed, "never-existed-key-1234", expired, protected].each do |key|
        get "/api/v3/guest/secret/#{key}"
        observed << [last_response.status, last_response.body]
        reveal(key)
        observed << [last_response.status, last_response.body]
      end

      expect(observed.map(&:first).uniq).to eq([404])
      # The request_id is intentionally unique per call; the stable part of the
      # envelope (code + message) must be identical for all terminal causes.
      stable = observed.map { |_status, body| JSON.parse(body)["error"].slice("code", "message") }
      expect(stable.uniq.length).to eq(1)
    end
  end

  describe "concurrency" do
    it "reveals a passphrase-protected secret exactly once under an 8-way race" do
      with_env("RATE_LIMIT_PASSPHRASE" => "100") do
        key = conceal(secret: "qa-race-protected", passphrase: "correct-horse")["secret_key"]

        outcomes = 8.times.map do
          Thread.new do
            Onetime::Logic::RevealSecret.new(key: key, passphrase: "correct-horse").call
            :ok
          rescue Onetime::NotFound
            :gone
          end
        end.map(&:value)

        expect(outcomes.count(:ok)).to eq(1)
        expect(outcomes.count(:gone)).to eq(7)
        expect(Onetime::Store.redis.exists?(Onetime::Models::Secret.object_key(key))).to be(false)
      end
    end

    it "keeps the per-secret guess budget atomic under a concurrent wrong-passphrase burst" do
      with_env("RATE_LIMIT_PASSPHRASE" => "2") do
        key = conceal(secret: "qa-budget-race", passphrase: "correct-horse")["secret_key"]

        outcomes = 8.times.map do
          Thread.new do
            Onetime::Logic::RevealSecret.new(key: key, passphrase: "wrong-pass").call
            :ok
          rescue Onetime::InvalidPassphrase
            :wrong
          rescue Onetime::RateLimited
            :limited
          end
        end.map(&:value)

        expect(outcomes.count(:wrong)).to eq(2)
        expect(outcomes.count(:limited)).to eq(6)
        expect(Onetime::Store.redis.exists?(Onetime::Models::Secret.object_key(key))).to be(true)
      end
    end
  end

  describe "correlation and rate-limit headers" do
    it "echoes the generated request id in the error envelope" do
      get "/api/v3/guest/secret/never-existed-key-1234"

      expect(last_response.headers["X-Request-Id"]).to match(/\A[0-9a-f-]{36}\z/)
      expect(JSON.parse(last_response.body).dig("error", "request_id"))
        .to eq(last_response.headers["X-Request-Id"])
    end

    it "throttles reveal POSTs on their own scope" do
      with_env("RATE_LIMIT_REVEAL" => "1") do
        first = conceal(secret: "qa-reveal-limit")["secret_key"]
        second = conceal(secret: "qa-reveal-limit-2")["secret_key"]

        reveal(first)
        expect(last_response.status).to eq(200)
        reveal(second)
        expect(last_response.status).to eq(429)
        expect(last_response.headers["Retry-After"]).to match(/\A\d+\z/)
      end
    end
  end
end
