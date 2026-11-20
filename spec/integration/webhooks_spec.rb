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
