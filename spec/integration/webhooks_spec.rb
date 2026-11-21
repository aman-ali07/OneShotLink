# frozen_string_literal: true

RSpec.describe "Webhook API" do
  REQ_HEADERS = { "CONTENT_TYPE" => "application/json", "HTTP_ORIGIN" => "http://example.org" }.freeze

  def signup(email = "hooks@example.com")
    post "/api/v3/signup", JSON.generate(email: email, password: "correct horse battery hooks"), REQ_HEADERS
    expect(last_response.status).to eq(201)
  end

  def with_env(vars)
    old = vars.keys.to_h { |key| [key, ENV[key]] }
    vars.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    old.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  it "requires a session and creates, lists and deletes an endpoint" do
    with_env("AUTH_MODE" => "simple", "HOST" => "example.org", "SSL" => "false",
             "WEBHOOK_ALLOW_PRIVATE" => "true") do
      post "/api/v3/webhooks", JSON.generate(url: "http://127.0.0.1:9/hook", events: ["secret.created"]), REQ_HEADERS
      expect(last_response.status).to eq(401)

      signup
      post "/api/v3/webhooks", JSON.generate(url: "http://127.0.0.1:9/hook", events: ["secret.created"]), REQ_HEADERS
      expect(last_response.status).to eq(201)
      created = JSON.parse(last_response.body)
      expect(created["signing_secret"].length).to eq(64)

      get "/api/v3/webhooks", nil, REQ_HEADERS
      expect(last_response.status).to eq(200)
      listed = JSON.parse(last_response.body)["webhooks"]
      expect(listed.map { |w| w["id"] }).to include(created["id"])
      expect(listed.first).not_to have_key("signing_secret")

      get "/api/v3/webhooks/#{created['id']}/deliveries", nil, REQ_HEADERS
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)).to have_key("deliveries")

      delete "/api/v3/webhooks/#{created['id']}", nil, REQ_HEADERS
      expect(last_response.status).to eq(200)
      get "/api/v3/webhooks", nil, REQ_HEADERS
      expect(JSON.parse(last_response.body)["webhooks"]).to be_empty
    end
  end

  it "scopes deliveries to the endpoint in the path" do
    with_env("AUTH_MODE" => "simple", "HOST" => "example.org", "SSL" => "false",
             "WEBHOOK_ALLOW_PRIVATE" => "true") do
      signup
      first = JSON.parse(begin
        post "/api/v3/webhooks", JSON.generate(url: "http://127.0.0.1:9/one", events: ["secret.created"]), REQ_HEADERS
        last_response.body
      end)
      second = JSON.parse(begin
        post "/api/v3/webhooks", JSON.generate(url: "http://127.0.0.1:9/two", events: ["secret.created"]), REQ_HEADERS
        last_response.body
      end)

      Onetime::Webhook.emit("secret.created", owner_id: Onetime::Models::Customer.find_by_email("hooks@example.com")[:id],
                            data: { identifier: "first", kind: "text", ttl: 60 })
      # Give the second endpoint its own queue entry so owner-wide filtering
      # would show a delivery that does not belong to the requested id.
      Onetime::Store.redis.zadd(Onetime::Webhook::QUEUE_KEY, Time.now.to_f,
                                JSON.generate("delivery_id" => Onetime::Ids.extid,
                                              "endpoint_id" => second["id"],
                                              "payload" => JSON.generate("event" => "secret.created")))
      Onetime::Store.redis.hset(Onetime::Webhook.delivery_key("second-delivery"), {
        "status" => "queued", "event" => "secret.created", "attempts" => "0",
        "endpoint_id" => second["id"], "created_at" => Time.now.to_i.to_s
      })

      get "/api/v3/webhooks/#{first['id']}/deliveries", nil, REQ_HEADERS
      expect(last_response.status).to eq(200)
      listed = JSON.parse(last_response.body)["deliveries"]
      expect(listed).not_to be_empty
      expect(listed.map { |d| d["id"] }).not_to include("second-delivery")

      get "/api/v3/webhooks/not-an-endpoint/deliveries", nil, REQ_HEADERS
      expect(last_response.status).to eq(404)
    end
  end

  it "rate limits delivery listings, which scan the whole delivery keyspace" do
    with_env("AUTH_MODE" => "simple", "HOST" => "example.org", "SSL" => "false",
             "WEBHOOK_ALLOW_PRIVATE" => "true", "RATE_LIMIT_WEBHOOK_READ" => "1") do
      signup
      created = JSON.parse(begin
        post "/api/v3/webhooks", JSON.generate(url: "http://127.0.0.1:9/scan", events: ["secret.created"]), REQ_HEADERS
        last_response.body
      end)

      get "/api/v3/webhooks/#{created['id']}/deliveries", nil, REQ_HEADERS
      expect(last_response.status).to eq(200)
      get "/api/v3/webhooks/#{created['id']}/deliveries", nil, REQ_HEADERS
      expect(last_response.status).to eq(429)
    end
  end

  it "refuses an unsubscribed or private URL without the local-testing flag" do
    with_env("AUTH_MODE" => "simple", "HOST" => "example.org", "SSL" => "false",
             "WEBHOOK_ALLOW_PRIVATE" => nil) do
      signup
      post "/api/v3/webhooks", JSON.generate(url: "http://127.0.0.1:9/hook", events: ["secret.created"]), REQ_HEADERS
      expect(last_response.status).to eq(422)

      post "/api/v3/webhooks", JSON.generate(url: "https://example.com/hook", events: ["nope"]), REQ_HEADERS
      expect(last_response.status).to eq(422)
    end
  end
end
