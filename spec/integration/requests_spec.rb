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
    it "never writes a raw request key to the audit stream" do
      with_env("AUTH_MODE" => "simple") do
        signup
        key = create_request.fetch("request_key")
        respond(key)
        reveal(key)

        stream = Onetime::Audit.recent(limit: 100).to_json
        expect(stream).to include("request.responded", "request.revealed")
        expect(stream).not_to include(key)
      end
    end

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

    it "rejects a request MAC transplanted from a donor request" do
      with_env("AUTH_MODE" => "simple") do
        signup
        donor_key = create_request(label: "donor")["request_key"]
        target_key = create_request(label: "target")["request_key"]
        respond(target_key, secret: "target-answer")

        donor_object = Onetime::Models::SecretRequest.object_key(donor_key)
        target_object = Onetime::Models::SecretRequest.object_key(target_key)
        donor = JSON.parse(Onetime::Store.redis.get(donor_object))
        target = JSON.parse(Onetime::Store.redis.get(target_object))
        %w[v owner_id label created_at ttl request_key meta_mac].each { |f| target[f] = donor[f] }
        Onetime::Store.redis.set(target_object, JSON.generate(target), ex: 1800)

        reveal(target_key)
        expect(last_response.status).to eq(500)
        expect(last_response.body).not_to include("target-answer")
        expect(Onetime::Store.redis.exists?(Onetime::Models::SecretRequest.submission_key(target_key))).to be(true)
      end
    end

    it "rejects a request whose owner or label was edited in Redis" do
      with_env("AUTH_MODE" => "simple") do
        signup
        key = create_request["request_key"]
        respond(key)
        object_key = Onetime::Models::SecretRequest.object_key(key)
        record = JSON.parse(Onetime::Store.redis.get(object_key))
        record["owner_id"] = "an-attacker-id"
        record["label"] = "tampered"
        Onetime::Store.redis.set(object_key, JSON.generate(record), ex: 600)

        reveal(key)
        expect(last_response.status).to eq(500)
        expect(last_response.body).not_to include("submitted-secret")
        expect(Onetime::Store.redis.exists?(Onetime::Models::SecretRequest.submission_key(key))).to be(true)
      end
    end

    it "does not render tampered request metadata in the public preview" do
      with_env("AUTH_MODE" => "simple") do
        signup
        key = create_request["request_key"]
        object_key = Onetime::Models::SecretRequest.object_key(key)
        record = JSON.parse(Onetime::Store.redis.get(object_key))
        record["label"] = "tampered preview"
        Onetime::Store.redis.set(object_key, JSON.generate(record), ex: 600)

        get "/api/v3/requests/#{key}"
        expect(last_response.status).to eq(500)
        expect(last_response.body).not_to include("tampered preview")
      end
    end

    it "bounds a submission by the request's remaining TTL" do
      with_env("AUTH_MODE" => "simple") do
        signup
        key = create_request(ttl: 1800)["request_key"]
        object_key = Onetime::Models::SecretRequest.object_key(key)
        Onetime::Store.redis.expire(object_key, 5)
        respond(key, secret: "short-window")
        submission_ttl = Onetime::Store.redis.ttl(Onetime::Models::SecretRequest.submission_key(key))
        expect(submission_ttl).to be <= Onetime::Store.redis.ttl(object_key)
      end
    end

    it "removes the fulfilled request from the owner index on reveal" do
      with_env("AUTH_MODE" => "simple") do
        signup
        key = create_request["request_key"]
        respond(key)
        index = Onetime::Models::SecretRequest.owner_index(
          Onetime::Models::Customer.find_by_email("owner@example.com")[:id]
        )
        expect(Onetime::Store.redis.zscore(index, key)).not_to be_nil
        reveal(key)
        expect(last_response.status).to eq(200)
        expect(Onetime::Store.redis.zscore(index, key)).to be_nil
      end
    end

    it "rejects an oversized request key before touching Redis" do
      with_env("AUTH_MODE" => "simple") do
        signup
        post "/api/v3/requests/#{"k" * 200}/reveal", JSON.generate({}), REQ_JSON_HEADERS
        expect(last_response.status).to eq(422)
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

    it "lets a stranger preview and answer a request in the default disabled mode (C2)" do
      key = nil
      with_env("AUTH_MODE" => "simple") do
        signup
        key = create_request["request_key"]
      end

      with_env("AUTH_MODE" => "disabled") do
        clear_cookies
        get "/api/v3/requests/#{key}"
        expect(last_response.status).to eq(200)
        preview = JSON.parse(last_response.body)
        expect(preview).not_to have_key("owner_id")
        expect(preview.dig("metadata", "label")).to eq("Vendor credentials")

        respond(key, secret: "anonymous-answer")
        expect(last_response.status).to eq(201)
      end
    end

    it "rate-limits the public preview so it cannot be polled for free (C2)" do
      key = nil
      with_env("AUTH_MODE" => "simple") do
        signup
        key = create_request["request_key"]
      end

      with_env("AUTH_MODE" => "disabled", "RATE_LIMIT_REVEAL" => "1") do
        clear_cookies
        get "/api/v3/requests/#{key}"
        expect(last_response.status).to eq(200)
        get "/api/v3/requests/#{key}"
        expect(last_response.status).to eq(429)
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

  it "retires the link atomically with the consume (no second-answer window)" do
    with_env("AUTH_MODE" => "simple") do
      signup
      key = create_request["request_key"]
      respond(key)
      expect(last_response.status).to eq(201)

      original = Onetime::Store.method(:consume_request)
      allow(Onetime::Store).to receive(:consume_request) do |submission_key, object_key, raw|
        # At the instant of the consume the submission key must still be
        # occupied, so a concurrent second answer cannot be written. Before
        # the atomic retire this succeeded, orphaning a second secret.
        expect { Onetime::Logic::SubmitToRequest.new(key: key, secret: "injected").call }
          .to raise_error(Onetime::Conflict)
        original.call(submission_key, object_key, raw)
      end

      reveal(key)
      expect(last_response.status).to eq(200)
      expect(Onetime::Store.redis.exists?(Onetime::Models::SecretRequest.object_key(key))).to be(false)
    end
  end

  it "retires the request link after a reveal so it cannot be replayed" do
    with_env("AUTH_MODE" => "simple") do
      signup
      key = create_request["request_key"]

      respond(key)
      expect(last_response.status).to eq(201)
      reveal(key)
      expect(last_response.status).to eq(200)
      expect(Onetime::Store.redis.exists?(Onetime::Models::SecretRequest.object_key(key))).to be(false)

      # The link is a spent capability: no second submission, preview or reveal.
      respond(key, secret: "replayed answer")
      expect(last_response.status).to eq(404)
      get "/api/v3/requests/#{key}"
      expect(last_response.status).to eq(404)
    end
  end

  it "keeps public responses in their own rate-limit bucket" do
    with_env("AUTH_MODE" => "simple", "RATE_LIMIT_CONCEAL" => "1", "RATE_LIMIT_RESPOND" => "100") do
      signup
      first = create_request["request_key"]
      second = create_request["request_key"]

      respond(first)
      expect(last_response.status).to eq(201)
      # Before the dedicated scope this hit :conceal (limit 1) and returned 429,
      # locking public responders out of secret creation from the same IP.
      respond(second)
      expect(last_response.status).to eq(201)
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
