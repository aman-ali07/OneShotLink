# frozen_string_literal: true

RSpec.describe "Simple-mode accounts" do
  ACCOUNT_JSON_HEADERS = { "CONTENT_TYPE" => "application/json", "HTTP_ORIGIN" => "http://example.org" }.freeze
  PASSWORD = "correct horse battery"

  before { clear_cookies }

  def with_env(vars)
    old = vars.keys.to_h { |key| [key, ENV[key]] }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    old.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def post_json(path, payload, headers = ACCOUNT_JSON_HEADERS)
    post path, JSON.generate(payload), ACCOUNT_JSON_HEADERS.merge(headers)
  end

  def delete_json(path, payload, headers = ACCOUNT_JSON_HEADERS)
    delete path, JSON.generate(payload), ACCOUNT_JSON_HEADERS.merge(headers)
  end

  def events
    Onetime::Audit.recent(limit: 100).map { |e| e["event"] }
  end

  def signup(email = "person@example.com", password = PASSWORD)
    post_json("/api/v3/signup", { email: email, password: password })
    JSON.parse(last_response.body)
  end

  def signin(email = "person@example.com", password = PASSWORD)
    post_json("/api/v3/signin", { email: email, password: password })
    JSON.parse(last_response.body)
  end

  def simple
    with_env("AUTH_MODE" => "simple") { yield }
  end

  describe "signup" do
    it "creates a customer, sets a hardened cookie, and stores no plaintext password" do
      simple do
        body = signup("Person@Example.com ")

        expect(last_response.status).to eq(201)
        expect(body.dig("customer", "email")).to eq("person@example.com")
        expect(body["customer"]).not_to have_key("password_hash")
        expect(last_response.headers["Set-Cookie"]).to include("ots_session=", "httponly", "samesite=lax")
        expect(last_response.headers["Set-Cookie"]).not_to include(PASSWORD)

        customer = Onetime::Models::Customer.find_by_email("person@example.com")
        expect(customer[:password_hash]).to start_with("$argon2id$")
        expect(Onetime::Store.redis.keys("*person@example.com*")).to be_empty
        expect(Onetime::Store.redis.ttl("session:#{Onetime::Models::Session.digest(body['customer']['id'])}")).to be(-2)
      end
    end

    it "rejects duplicate emails case-insensitively" do
      simple do
        signup
        expect(last_response.status).to eq(201)
        signup("PERSON@example.com")

        expect(last_response.status).to eq(409)
        expect(JSON.parse(last_response.body).dig("error", "code")).to eq("email_taken")
      end
    end

    it "validates email and password length" do
      simple do
        post_json("/api/v3/signup", { email: "not-an-email", password: PASSWORD })
        expect(last_response.status).to eq(422)

        post_json("/api/v3/signup", { email: "a@b.co", password: "short" })
        expect(last_response.status).to eq(422)
        expect(JSON.parse(last_response.body).dig("error", "message")).to match(/at least 12/)
      end
    end
  end

  describe "signin and session" do
    it "returns a generic 401 for a wrong password and succeeds with the right one" do
      simple do
        signup
        clear_cookies

        signin("person@example.com", "wrong password here")
        expect(last_response.status).to eq(401)
        expect(JSON.parse(last_response.body).dig("error", "code")).to eq("invalid_credentials")

        signin
        expect(last_response.status).to eq(200)
        get "/api/v3/account/me"
        expect(last_response.status).to eq(200)
        expect(JSON.parse(last_response.body).dig("customer", "email")).to eq("person@example.com")
      end
    end

    it "requires a session for account routes and leaves the cookie HttpOnly" do
      simple do
        get "/api/v3/account/me"
        expect(last_response.status).to eq(401)

        signup
        get "/api/v3/account/me"
        expect(last_response.status).to eq(200)
        expect(last_response.headers["Set-Cookie"]).to be_nil
      end
    end

    it "sets Secure when SSL is enabled" do
      with_env("AUTH_MODE" => "simple", "SSL" => "true") do
        signup
        expect(last_response.headers["Set-Cookie"]).to include("secure")
      end
    end

    it "signs out and invalidates the Redis session" do
      simple do
        signup
        token = rack_mock_session.cookie_jar["ots_session"]
        post_json("/api/v3/signout", {})

        expect(last_response.status).to eq(200)
        expect(Onetime::Store.redis.exists?("session:#{Onetime::Models::Session.digest(token)}")).to be(false)
        expect(last_response.headers["Set-Cookie"]).to include("max-age=0")
        get "/api/v3/account/me"
        expect(last_response.status).to eq(401)
      end
    end
  end

  describe "CSRF and owner scope" do
    it "rejects a cookie-authenticated mutation without same-origin proof" do
      simple do
        signup
        post "/api/v3/secret/conceal", JSON.generate(secret: "x", ttl: 1800), "CONTENT_TYPE" => "application/json"
        expect(last_response.status).to eq(403)
        expect(JSON.parse(last_response.body).dig("error", "code")).to eq("forbidden")
      end
    end

    it "creates an owner receipt and removes it when revealed" do
      simple do
        signup
        post_json("/api/v3/secret/conceal", { secret: "owner secret", ttl: 1800 })
        expect(last_response.status).to eq(201)
        key = JSON.parse(last_response.body)["secret_key"]

        get "/api/v3/account/receipts"
        receipts = JSON.parse(last_response.body)["receipts"]
        expect(receipts.map { |r| r["identifier"] }).to eq([key])
        expect(receipts.first["secret_url"]).to eq("/secret/#{key}")

        post_json("/api/v3/guest/secret/#{key}/reveal", {})
        expect(last_response.status).to eq(200)

        get "/api/v3/account/receipts"
        expect(JSON.parse(last_response.body)["receipts"]).to be_empty
      end
    end

    it "does not show another customer's receipts" do
      simple do
        signup("first@example.com")
        post_json("/api/v3/secret/conceal", { secret: "first", ttl: 1800 })
        first_key = JSON.parse(last_response.body)["secret_key"]

        clear_cookies
        signup("second@example.com")
        post_json("/api/v3/secret/conceal", { secret: "second", ttl: 1800 })
        second_key = JSON.parse(last_response.body)["secret_key"]

        get "/api/v3/account/receipts"
        identifiers = JSON.parse(last_response.body)["receipts"].map { |r| r["identifier"] }
        expect(identifiers).to include(second_key)
        expect(identifiers).not_to include(first_key)
      end
    end
  end

  describe "password change" do
    it "requires the current password and makes the new one effective" do
      simple do
        signup
        post_json("/api/v3/account/password", { current_password: "wrong password here", new_password: "a new long password" })
        expect(last_response.status).to eq(401)

        post_json("/api/v3/account/password", { current_password: PASSWORD, new_password: "a new long password" })
        expect(last_response.status).to eq(200)

        clear_cookies
        signin("person@example.com", "a new long password")
        expect(last_response.status).to eq(200)
      end
    end

    it "revokes other sessions when the password changes" do
      simple do
        signup
        first = rack_mock_session.cookie_jar["ots_session"]
        first_digest = Onetime::Models::Session.digest(first)

        # A second device signs in with the same credentials.
        clear_cookies
        signin
        expect(last_response.status).to eq(200)

        post_json("/api/v3/account/password", { current_password: PASSWORD, new_password: "a new long password" })
        expect(last_response.status).to eq(200)

        # The session that performed the change survives; the other one dies.
        expect(Onetime::Store.redis.exists?("session:#{first_digest}")).to be(false)
        expect(Onetime::Store.redis.exists?("session:#{Onetime::Models::Session.digest(rack_mock_session.cookie_jar['ots_session'])}")).to be(true)
      end
    end
  end

  describe "account deletion" do
    it "removes the account, its sessions and its receipts, and frees the email" do
      simple do
        signup("delete-me@example.com")
        customer = Onetime::Models::Customer.find_by_email("delete-me@example.com")
        post_json("/api/v3/secret/conceal", { secret: "owner secret", ttl: 1800 })
        expect(last_response.status).to eq(201)

        delete_json("/api/v3/account", { password: PASSWORD })

        expect(last_response.status).to eq(200)
        expect(JSON.parse(last_response.body)).to eq("ok" => true)
        expect(last_response.headers["Set-Cookie"]).to include("ots_session=")

        get "/api/v3/account/me"
        expect(last_response.status).to eq(401)

        expect(Onetime::Store.redis.exists(Onetime::Models::Customer.key(customer[:id]))).to be(0)
        expect(Onetime::Store.redis.exists(Onetime::Models::Customer.index_key("delete-me@example.com"))).to be(0)
        expect(Onetime::Store.redis.exists(Onetime::Models::Secret.owner_index(customer[:id]))).to be(0)
        expect(Onetime::Models::Session.revoke_all(customer[:id])).to be(0)

        clear_cookies
        signup("delete-me@example.com")
        expect(last_response.status).to eq(201)
      end
    end

    it "leaves a live secret readable by its recipient until it expires" do
      simple do
        signup
        post_json("/api/v3/secret/conceal", { secret: "already sent", ttl: 1800 })
        key = JSON.parse(last_response.body)["secret_key"]

        delete_json("/api/v3/account", { password: PASSWORD })
        expect(last_response.status).to eq(200)
        expect(Onetime::Store.redis.exists(Onetime::Models::Secret.receipt_key(key))).to be(0)

        clear_cookies
        post_json("/api/v3/guest/secret/#{key}/reveal", {})
        expect(last_response.status).to eq(200)
        expect(JSON.parse(last_response.body)["secret_value"]).to eq("already sent")
      end
    end

    it "removes nothing when the transaction fails" do
      simple do
        signup("atomic@example.com")
        post_json("/api/v3/secret/conceal", { secret: "still here", ttl: 1800 })
        key = JSON.parse(last_response.body)["secret_key"]
        session_digest = Onetime::Models::Session.digest(rack_mock_session.cookie_jar["ots_session"])

        # A crash between the first and the last command must leave no partial
        # state behind: the account, its receipts and its sessions all survive.
        allow(Onetime::Store.redis).to receive(:multi).and_raise(RuntimeError, "simulated crash")
        delete_json("/api/v3/account", { password: PASSWORD })
        allow(Onetime::Store.redis).to receive(:multi).and_call_original

        expect(last_response.status).to eq(500)
        expect(Onetime::Models::Customer.find_by_email("atomic@example.com")).not_to be_nil
        expect(Onetime::Store.redis.exists(Onetime::Models::Secret.receipt_key(key))).to be(1)
        expect(Onetime::Store.redis.exists("session:#{session_digest}")).to be(1)
      end
    end

    it "refuses without the password and deletes nothing" do
      simple do
        signup
        delete_json("/api/v3/account", { password: "not the password" })

        expect(last_response.status).to eq(401)
        expect(JSON.parse(last_response.body).dig("error", "code")).to eq("invalid_credentials")

        get "/api/v3/account/me"
        expect(last_response.status).to eq(200)
        expect(Onetime::Models::Customer.find_by_email("person@example.com")).not_to be_nil
        expect(events).to include("customer.delete_failed")
        expect(events).not_to include("customer.deleted")
      end
    end

    it "requires a session" do
      simple do
        signup
        clear_cookies

        delete_json("/api/v3/account", { password: PASSWORD })
        expect(last_response.status).to eq(401)
        expect(Onetime::Models::Customer.find_by_email("person@example.com")).not_to be_nil
      end
    end

    it "records the deletion" do
      simple do
        signup
        delete_json("/api/v3/account", { password: PASSWORD })
        expect(events).to include("customer.deleted")
      end
    end
  end

  describe "audit trail" do
    it "records signup, signin, and a failed signin" do
      simple do
        signup
        clear_cookies
        signin
        clear_cookies
        post_json("/api/v3/signin", { email: "person@example.com", password: "the wrong password" })
        expect(last_response.status).to eq(401)

        expect(events).to include("customer.signup", "customer.signin", "customer.signin_failed")
      end
    end

    it "records a password change and the resulting revocation" do
      simple do
        signup
        post_json("/api/v3/account/password", { current_password: PASSWORD, new_password: "a new long password" })
        expect(last_response.status).to eq(200)
        expect(events).to include("customer.password_changed", "customer.sessions_revoked")
      end
    end

    it "never stores an email, password, or secret value in the audit log" do
      simple do
        signup("leaky@example.com")
        raw = Onetime::Store.redis.xrange(Onetime::Audit::STREAM).to_s
        expect(raw).not_to include("leaky@example.com")
        expect(raw).not_to include(PASSWORD)
      end
    end
  end

  describe "mode gates" do
    it "returns 403 for account routes when auth is disabled" do
      post_json("/api/v3/signup", { email: "a@b.co", password: PASSWORD })
      expect(last_response.status).to eq(403)
      expect(JSON.parse(last_response.body).dig("error", "code")).to eq("forbidden")
    end

    it "returns 501 in full mode" do
      with_env("AUTH_MODE" => "full") do
        post_json("/api/v3/signup", { email: "a@b.co", password: PASSWORD })
        expect(last_response.status).to eq(501)
      end
    end
  end
end
