# frozen_string_literal: true

require "tmpdir"

# Regressions found by the parallel QA audit (2026-11-21). Each example asserts
# observable HTTP/Redis behaviour, never a mock created in the same example.
RSpec.describe "QA defect regressions" do
  QA_DEFECT_HEADERS = {
    "CONTENT_TYPE" => "application/json",
    "HTTP_ORIGIN" => "http://example.org",
    # Be explicit: rack-test can retain a Sec-Fetch-Site header from an earlier
    # spec, which would turn an otherwise same-origin signup into a 403.
    "HTTP_SEC_FETCH_SITE" => "same-origin",
  }.freeze

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
    post "/api/v3/guest/conceal", JSON.generate(body), QA_DEFECT_HEADERS
    JSON.parse(last_response.body)
  end

  def reveal(key, passphrase: nil)
    post "/api/v3/guest/secret/#{key}/reveal",
         JSON.generate(passphrase ? { passphrase: passphrase } : {}), QA_DEFECT_HEADERS
  end

  def signup(email = "owner@example.com")
    post "/api/v3/signup", JSON.generate(email: email, password: "correct horse battery qa"), QA_DEFECT_HEADERS
    expect(last_response.status).to eq(201)
  end

  def create_request(ttl: 1800)
    post "/api/v3/requests", JSON.generate(label: "QA", ttl: ttl), QA_DEFECT_HEADERS
    JSON.parse(last_response.body)
  end

  it "refuses a submission when the request's remaining TTL rounds down to zero" do
    with_env("AUTH_MODE" => "simple", "HOST" => "example.org", "SSL" => "false", "RATE_LIMIT_SIGNUP" => "1000", "RATE_LIMIT_REQUEST" => "1000", "RATE_LIMIT_CONCEAL" => "1000", "RATE_LIMIT_REVEAL" => "1000") do
      signup
      expect(last_response.status).to eq(201), last_response.body
      key = create_request.fetch("request_key")
      object_key = Onetime::Models::SecretRequest.object_key(key)
      submission_key = Onetime::Models::SecretRequest.submission_key(key)

      # Redis reports 0 for a key with less than one second left. The old code
      # treated that as "no TTL information" and gave the answer the full TTL.
      allow(Onetime::Store.redis).to receive(:ttl).and_call_original
      allow(Onetime::Store.redis).to receive(:ttl).with(object_key).and_return(0)

      post "/api/v3/requests/#{key}/respond", JSON.generate(secret: "short-window"), QA_DEFECT_HEADERS
      expect(last_response.status).to eq(404)
      expect(Onetime::Store.redis.exists?(submission_key)).to be false
    end
  end

  it "rejects a non-string passphrase without spending the per-secret guess budget" do
    with_env("RATE_LIMIT_PASSPHRASE" => "2") do
      key = conceal(secret: "qa-typed-passphrase", passphrase: "correct horse").fetch("secret_key")

      reveal(key, passphrase: { "guess" => 1 })
      expect(last_response.status).to eq(422)
      expect(JSON.parse(last_response.body).dig("error", "code")).to eq("validation_error")

      reveal(key, passphrase: [1])
      expect(last_response.status).to eq(422)

      reveal(key, passphrase: "correct horse")
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["secret_value"]).to eq("qa-typed-passphrase")
    end
  end

  it "refuses an oversized reveal passphrase before hashing or spending a guess" do
    with_env("RATE_LIMIT_PASSPHRASE" => "1") do
      key = conceal(secret: "qa-long-passphrase", passphrase: "correct horse").fetch("secret_key")

      reveal(key, passphrase: "A" * 1000)
      expect(last_response.status).to eq(422)
      expect(JSON.parse(last_response.body).dig("error", "code")).to eq("validation_error")

      # One guess is allowed in this window: the rejected oversized value must
      # not have spent it, or the legitimate passphrase would be throttled.
      reveal(key, passphrase: "correct horse")
      expect(last_response.status).to eq(200)
    end
  end

  it "keeps the v1 passphrase gate intact across API versions" do
    key = conceal(secret: "qa-v1-gated", passphrase: "correct horse").fetch("secret_key")

    post "/api/v1/secret/#{key}"
    expect(last_response.status).to eq(401)
    expect(JSON.parse(last_response.body)).to have_key("message")
    expect(last_response.body).not_to include("qa-v1-gated")
    expect(Onetime::Store.redis.exists?("secret:object:#{key}")).to be true

    reveal(key, passphrase: "correct horse")
    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)["secret_value"]).to eq("qa-v1-gated")
  end

  it "does not render tampered secret preview metadata" do
    key = conceal(secret: "qa-preview").fetch("secret_key")
    object_key = "secret:object:#{key}"
    original = Onetime::Store.redis.get(object_key)
    record = JSON.parse(original)
    record["filename"] = "evil.exe"
    Onetime::Store.redis.set(object_key, JSON.generate(record), ex: 1800)

    get "/api/v3/guest/secret/#{key}"
    expect(last_response.status).to eq(500)
    expect(last_response.body).not_to include("evil.exe")
    expect(Onetime::Store.redis.exists?(object_key)).to be true

    Onetime::Store.redis.set(object_key, original, ex: 1800)
    get "/api/v3/guest/secret/#{key}"
    expect(last_response.status).to eq(200)
  end

  it "refuses to restore a backup entry that would make a secret immortal" do
    key = conceal(secret: "qa-immortal").fetch("secret_key")
    object_key = "secret:object:#{key}"
    raw = Onetime::Store.redis.get(object_key)
    # A TTL-less legacy/imported record must not round-trip into a permanent one.
    Onetime::Store.redis.set(object_key, raw)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "backup.json")
      Onetime::Backup.export(path)
      expect(File.read(path)).to include(key)

      Onetime::Store.redis.flushdb
      expect { Onetime::Backup.restore(path) }.to raise_error(Onetime::Error, /without a TTL/)
      expect(Onetime::Store.redis.exists?(object_key)).to be false
    end
  end

  it "refuses a backup whose secret entry omits ttl entirely" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "no-ttl-secret.json")
      key = "secret:object:qa-omitted-ttl"
      File.write(path, JSON.generate(
        "format" => 2,
        "secret" => { key => { "type" => "raw", "raw" => "opaque-ciphertext" } }
      ))

      expect { Onetime::Backup.restore(path) }.to raise_error(Onetime::Error, /without a TTL/)
      expect(Onetime::Store.redis.exists?(key)).to be false
    end
  end

  it "refuses a ttl-less submission even when filed under a non-secret section" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "no-ttl-submission.json")
      key = "request:secret:qa-omitted-ttl"
      File.write(path, JSON.generate(
        "format" => 2,
        "customer" => { key => { "type" => "string", "value" => "opaque-answer" } }
      ))

      expect { Onetime::Backup.restore(path) }.to raise_error(Onetime::Error, /without a TTL/)
      expect(Onetime::Store.redis.exists?(key)).to be false
    end
  end

  it "refuses a backup with TTL-less receipt or delivery entries before writing anything" do
    entry = { "type" => "hash", "value" => { "status" => "revealed" }, "ttl" => 0 }
    payload = {
      "format" => 2,
      "secret" => {},
      "receipt" => { "secret:receipt:qa-key" => entry },
      "customer" => {},
      "request_object" => {},
      "request_secret" => {},
      "webhook_endpoint" => {},
      "webhook_owner" => {},
      "webhook_queue" => {},
      "webhook_delivery" => { "webhook:delivery:qa-id" => entry },
    }

    Dir.mktmpdir do |dir|
      path = File.join(dir, "backup.json")
      File.write(path, JSON.generate(payload))
      expect { Onetime::Backup.restore(path) }.to raise_error(Onetime::Error, /without a TTL/)
      expect(Onetime::Store.redis.exists?("secret:receipt:qa-key")).to be false
      expect(Onetime::Store.redis.exists?("webhook:delivery:qa-id")).to be false
    end
  end

  it "refuses a backup whose request object omits ttl" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "no-ttl-request-object.json")
      key = "request:object:qa-omitted-ttl"
      File.write(path, JSON.generate(
        "format" => 2,
        "request_object" => { key => { "type" => "string", "value" => "{}" } }
      ))

      expect { Onetime::Backup.restore(path) }.to raise_error(Onetime::Error, /without a TTL/)
      expect(Onetime::Store.redis.exists?(key)).to be false
    end
  end

  it "requires a session for the owner reveal alias when accounts are enabled" do
    with_env("AUTH_MODE" => "simple", "HOST" => "example.org", "SSL" => "false", "RATE_LIMIT_SIGNUP" => "1000", "RATE_LIMIT_REQUEST" => "1000", "RATE_LIMIT_CONCEAL" => "1000", "RATE_LIMIT_REVEAL" => "1000") do
      signup
      post "/api/v3/secret/conceal", JSON.generate(secret: "qa-owner-alias", ttl: 1800), QA_DEFECT_HEADERS
      expect(last_response.status).to eq(201), last_response.body
      key = JSON.parse(last_response.body).fetch("secret_key")
      clear_cookies

      post "/api/v3/secret/#{key}/reveal", JSON.generate({}), QA_DEFECT_HEADERS
      expect(last_response.status).to eq(401)
      expect(Onetime::Store.redis.exists?("secret:object:#{key}")).to be true

      get "/api/v3/secret/#{key}"
      expect(last_response.status).to eq(401)
    end
  end
end
