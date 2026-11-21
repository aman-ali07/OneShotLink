# frozen_string_literal: true

# Regression specs for the security-hardening pass. Each example asserts an
# observable behavior at the HTTP/Redis boundary, never an implementation detail.
RSpec.describe "Security hardening" do
  JSON_HEADERS = { "CONTENT_TYPE" => "application/json" }.freeze

  def create(secret:, passphrase: nil, filename: nil)
    body = { secret: secret, ttl: 1800 }
    body[:passphrase] = passphrase if passphrase
    if filename
      body[:kind] = "file"
      body[:filename] = filename
      body[:secret] = Base64.strict_encode64(secret)
    end
    post "/api/v3/guest/conceal", JSON.generate(body), JSON_HEADERS
    JSON.parse(last_response.body)["secret_key"]
  end

  def reveal(key, passphrase: nil)
    body = passphrase.nil? ? {} : { passphrase: passphrase }
    post "/api/v3/guest/secret/#{key}/reveal", JSON.generate(body), JSON_HEADERS
  end

  def tamper(key)
    object_key = Onetime::Models::Secret.object_key(key)
    record = JSON.parse(Onetime::Store.redis.get(object_key))
    yield record
    Onetime::Store.redis.set(object_key, JSON.generate(record), ex: 1800)
  end

  describe "record metadata integrity" do
    it "refuses a record whose passphrase gate was stripped in Redis" do
      key = create(secret: "gate-secret", passphrase: "correct-horse")
      tamper(key) { |record| record.delete("passphrase_hash") }

      reveal(key)
      expect(last_response.status).to eq(500)
      expect(last_response.body).not_to include("gate-secret")
      expect(Onetime::Store.redis.exists?(Onetime::Models::Secret.object_key(key))).to be(true)
    end

    it "refuses a record whose display metadata was edited in Redis" do
      key = create(secret: "meta-secret")
      tamper(key) { |record| record["filename"] = "invoice.xlsx" }

      reveal(key)
      expect(last_response.status).to eq(500)
      expect(last_response.body).not_to include("meta-secret")
      expect(Onetime::Store.redis.exists?(Onetime::Models::Secret.object_key(key))).to be(true)
    end

    it "rejects a metadata MAC transplanted from an unprotected donor record" do
      protected_key = create(secret: "transplant-target", passphrase: "correct-horse")
      donor_key = create(secret: "donor-value")

      target_object = Onetime::Models::Secret.object_key(protected_key)
      donor_object = Onetime::Models::Secret.object_key(donor_key)
      target = JSON.parse(Onetime::Store.redis.get(target_object))
      donor = JSON.parse(Onetime::Store.redis.get(donor_object))

      # Copy every MAC-covered field and the donor MAC, but keep the target's
      # ciphertext. Without ciphertext binding this bypasses the passphrase gate.
      %w[v kind filename owner_id created_at ttl passphrase_hash].each do |field|
        target[field] = donor[field]
      end
      target["meta_mac"] = donor["meta_mac"]
      Onetime::Store.redis.set(target_object, JSON.generate(target), ex: 1800)

      post "/api/v3/guest/secret/#{protected_key}/reveal",
           JSON.generate({}), { "CONTENT_TYPE" => "application/json" }
      expect(last_response.status).to eq(500)
      expect(last_response.body).not_to include("transplant-target")
      expect(Onetime::Store.redis.exists?(target_object)).to be(true)
    end

    it "refuses a downgraded record whose MAC and passphrase gate were stripped" do
      key = create(secret: "downgraded-secret", passphrase: "correct-horse")
      tamper(key) do |record|
        record.delete("meta_mac")
        record.delete("passphrase_hash")
        record["v"] = 1
      end

      reveal(key)
      expect(last_response.status).to eq(500)
      expect(last_response.body).not_to include("downgraded-secret")
      expect(Onetime::Store.redis.exists?(Onetime::Models::Secret.object_key(key))).to be(true)
    end

    it "keeps the metadata MAC valid across key rotation" do
      key = create(secret: "rotate-mac-secret", passphrase: "correct-horse")
      new_secret = "m" * 40
      Onetime::Logic::RotateKey.new(new_secret: new_secret).call

      # The app must be restarted with the new SECRET after rotation; model that
      # by switching the env before the reveal.
      old = ENV["SECRET"]
      ENV["SECRET"] = new_secret
      reveal(key, passphrase: "correct-horse")
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["secret_value"]).to eq("rotate-mac-secret")
    ensure
      ENV["SECRET"] = old
    end
  end

  describe "HEAD rejection headers" do
    def app
      Onetime::Web::HeadRequests.new(Onetime::Web::App)
    end

    it "sends the hardened headers and a request id on the v1 HEAD 405" do
      head "/api/v1/secret/anykey"

      expect(last_response.status).to eq(405)
      expect(last_response.headers["Allow"]).to eq("GET, POST")
      expect(last_response.headers).to include("X-Request-Id", "X-Content-Type-Options", "Content-Security-Policy")
      expect(last_response.headers["Cache-Control"]).to eq("no-store")
      # The early return must carry the *whole* canonical set, not a subset that
      # drifts whenever a header is added to HARDENING_HEADERS.
      expect(last_response.headers).to include(Onetime::Web::App::HARDENING_HEADERS)
    end
  end

  describe "AEAD blob binding" do
    it "refuses a protected ciphertext transplanted onto an ungated record" do
      protected_key = create(secret: "victim-payload", passphrase: "correct-horse")
      ungated_key = create(secret: "cover-payload")

      victim = JSON.parse(Onetime::Store.redis.get(Onetime::Models::Secret.object_key(protected_key)))
      cover = JSON.parse(Onetime::Store.redis.get(Onetime::Models::Secret.object_key(ungated_key)))
      # Keep the cover's meta fields and meta_mac; swap only the AEAD blob.
      %w[cipher ciphertext iv tag salt].each { |field| cover[field] = victim[field] }
      Onetime::Store.redis.set(
        Onetime::Models::Secret.object_key(ungated_key), JSON.generate(cover), ex: 1800
      )

      reveal(ungated_key)

      expect(last_response.status).to eq(500)
      expect(last_response.body).not_to include("victim-payload")
      expect(Onetime::Store.redis.exists?(Onetime::Models::Secret.object_key(ungated_key))).to be(true)
    end
  end

  describe "post-consume housekeeping" do
    it "still delivers the value when receipt cleanup fails after the atomic consume" do
      key = create(secret: "cleanup-failure-secret")
      allow(Onetime::Models::Secret).to receive(:finalize_receipt)
        .and_raise(Redis::CannotConnectError, "connection refused")

      reveal(key)

      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["secret_value"]).to eq("cleanup-failure-secret")
      expect(Onetime::Store.redis.exists?(Onetime::Models::Secret.object_key(key))).to be(false)
    end
  end
end
