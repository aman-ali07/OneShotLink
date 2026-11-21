# frozen_string_literal: true

RSpec.describe "OpenAPI document" do
  def doc
    get "/api/v3/openapi.json"
    expect(last_response.status).to eq(200)
    JSON.parse(last_response.body)
  end

  it "is a valid 3.1 document with paths and components" do
    document = doc
    expect(document["openapi"]).to start_with("3.")
    expect(document["info"]["title"]).not_to be_empty
    expect(document["paths"]).not_to be_empty
    expect(document["components"]["schemas"]).to include("Error")
  end

  it "uses bare $refs in schema positions so generated models are not empty" do
    schemas = doc["components"]["schemas"]
    {
      %w[WebhookCreated allOf 0] => "Webhook",
      %w[WebhookList properties webhooks items] => "Webhook",
      %w[WebhookDeliveryList properties deliveries items] => "WebhookDelivery",
      %w[CreateRequestResponse properties metadata] => "RequestMetadata",
      %w[RequestPreview properties metadata] => "RequestMetadata",
      %w[RequestItem allOf 0] => "RequestMetadata",
      %w[RequestList properties requests items] => "RequestItem",
    }.each do |path, expected|
      actual = path.reduce(schemas) do |node, key|
        next nil if node.nil?

        lookup = node.is_a?(Array) ? key.to_i : key
        node.is_a?(Array) ? node[lookup] : node.fetch(lookup, nil)
      end
      expect(actual).to eq({ "$ref" => "#/components/schemas/#{expected}" }), path.join(".")
    end
  end

  it "enumerates every error code the app can emit" do
    enum = doc.dig("components", "schemas", "Error", "properties", "error", "properties", "code", "enum")
    source = File.read(File.expand_path("../../lib/onetime/errors.rb", __dir__))
    emitted = source.scan(/def code(?:\s*=|\s*\n\s*)"([a-z_]+)"/).flatten.uniq
    expect(emitted).not_to be_empty
    expect(emitted - enum).to be_empty
  end

  it "warns that the v1 GET reveal consumes the secret" do
    summary = doc.dig("paths", "/api/v1/secret/{key}", "get", "summary")
    expect(summary).to include("CONSUMES")
    v3 = doc.dig("paths", "/api/v3/guest/secret/{key}", "get", "summary")
    expect(v3).to include("without consuming")
  end

  it "documents every security-critical mounted route" do
    paths = doc["paths"].keys
    %w[
      /health /metrics /api/v3/config /api/v3/openapi.json
      /api/v3/signup /api/v3/signin /api/v3/signout /api/v3/account/me
      /api/v3/account/receipts /api/v3/account/password /api/v3/account
      /api/v3/requests /api/v3/requests/{key} /api/v3/requests/{key}/respond
      /api/v3/requests/{key}/reveal
      /api/v3/webhooks /api/v3/webhooks/{id} /api/v3/webhooks/{id}/deliveries
      /api/v3/secret/conceal /api/v3/secret/{key} /api/v3/secret/{key}/reveal
      /api/v3/guest/conceal /api/v3/guest/secret/{key} /api/v3/guest/secret/{key}/reveal
      /api/v1/share /api/v1/secret/{key}
    ].each { |path| expect(paths).to include(path), path }
  end

  it "references only schemas that exist" do
    document = doc
    defined_schemas = document["components"]["schemas"].keys
    refs = document.to_s.scan(/"\$ref":"#\/components\/schemas\/([^"]+)"/).flatten.uniq
    expect(refs - defined_schemas).to be_empty
  end

  # A documented route must be mounted: a 405 means Roda has no such route, and
  # an API path falling through to the catch-all returns this exact body. Domain
  # 404s carry a different message, so they still pass.
  def assert_mounted(document)
    document["paths"].each do |path, methods|
      methods.each_key do |verb|
        concrete = path.gsub("{key}", "somekey").gsub("{id}", "someid")
        send(verb, concrete)
        expect(last_response.status).not_to eq(405), "#{verb.upcase} #{path} is not mounted"
        # /metrics is deliberately 404 when METRICS_ENABLED is off, so the
        # catch-all-body test applies only to API paths.
        next unless path.start_with?("/api/")

        body = begin
          JSON.parse(last_response.body)
        rescue JSON::ParserError
          {}
        end
        generic = body["error"].is_a?(Hash) &&
                  body["error"]["code"] == "not_found" &&
                  body["error"]["message"] == "Not found."
        expect(generic).to be(false), "#{verb.upcase} #{path} is not mounted (generic catch-all 404)"
      end
    end
  end

  it "documents only paths the app actually mounts" do
    assert_mounted(doc)
  end

  it "catches a documented path that is not mounted (negative control)" do
    bogus = doc
    bogus["paths"]["/api/v3/not-a-real-route"] = { "get" => { "summary" => "bogus" } }

    expect { assert_mounted(bogus) }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /not mounted/)
  end

  it "documents the degraded health body, not the v3 error envelope" do
    document = doc
    %w[/health /api/v3/health].each do |path|
      ref = document.dig("paths", path, "get", "responses", "503", "content", "application/json", "schema", "$ref")
      expect(ref).to eq("#/components/schemas/HealthDegraded"), path
    end
    schema = document.dig("components", "schemas", "HealthDegraded")
    expect(schema["required"]).to include("status", "redis", "version")
  end

  it "names the webhook path parameter id and documents rate limits" do
    document = doc
    expect(document["paths"].keys).to include("/api/v3/webhooks/{id}", "/api/v3/webhooks/{id}/deliveries")
    expect(document["paths"].keys.grep(/webhooks\{key\}/)).to be_empty
    expect(document.dig("paths", "/api/v3/webhooks", "post", "responses").keys).to include("429", "503")
    expect(document.dig("paths", "/api/v3/webhooks/{id}", "delete", "responses").keys).to include("429", "503")
    expect(document.dig("paths", "/api/v3/secret/{key}", "get", "responses").keys).to include("429")
    expect(document["paths"]).to have_key("/api/v3/openapi.json")
  end

  it "documents the Redis-backed failure modes on request and webhook routes" do
    document = doc
    paths = document["paths"]
    expect(paths.dig("/api/v3/webhooks/{id}/deliveries", "get", "responses").keys).to include("404")
    expect(paths.dig("/api/v3/requests", "get", "responses").keys).to include("503")
    expect(paths.dig("/api/v3/requests/{key}", "get", "responses").keys).to include("503")
    expect(paths.dig("/api/v3/requests/{key}/respond", "post", "responses").keys).to include("503")
    expect(paths.dig("/api/v3/requests/{key}/reveal", "post", "responses").keys).to include("503")
    expect(paths.dig("/api/v3/webhooks", "get", "responses").keys).to include("503")
  end

  it "documents 503 on request creation and 429 on the rate-limited health probes" do
    document = doc
    expect(document.dig("paths", "/api/v3/requests", "post", "responses").keys).to include("503")
    expect(document.dig("paths", "/health", "get", "responses").keys).to include("429")
    expect(document.dig("paths", "/api/v3/health", "get", "responses").keys).to include("429")
  end

  it "documents 500 everywhere and full-mode 501 only on API paths" do
    document = doc
    document["paths"].each do |path, methods|
      methods.each do |verb, operation|
        envelope = path.start_with?("/api/v1/") ? "#/components/schemas/LegacyError" : "#/components/schemas/Error"
        expect(operation.dig("responses", "500", "content", "application/json", "schema", "$ref"))
          .to eq(envelope), "#{verb.upcase} #{path} missing 500"
        from_501 = operation.dig("responses", "501")
        if path.start_with?("/api/")
          expect(from_501).not_to be_nil, "#{verb.upcase} #{path}"
          expect(from_501.dig("content", "application/json", "schema", "$ref")).to eq(envelope)
        else
          expect(from_501).to be_nil, "#{verb.upcase} #{path} cannot return 501"
        end
      end
    end
  end

  it "warns that HEAD on the v1 reveal route is refused with 405" do
    summary = doc.dig("paths", "/api/v1/secret/{key}", "get", "summary")
    expect(summary).to include("405", "Allow: GET, POST")
  end

  it "documents 429 on rate-limited reads and 413/422 on owner conceal" do
    document = doc
    {
      ["/api/v3/config", "get"] => %w[429],
      ["/api/v3/openapi.json", "get"] => %w[429],
      ["/api/v3/requests/{key}", "get"] => %w[429],
      ["/api/v3/webhooks/{id}/deliveries", "get"] => %w[429],
      ["/api/v3/secret/conceal", "post"] => %w[413 422 429]
    }.each do |(path, verb), codes|
      responses = document.dig("paths", path, verb, "responses").keys
      expect(codes - responses).to be_empty, "#{verb.upcase} #{path} missing #{codes - responses}"
    end
  end

  it "maps every v1 error response to the legacy message envelope" do
    document = doc
    { "/api/v1/share" => %w[post], "/api/v1/secret/{key}" => %w[get post] }.each do |path, verbs|
      verbs.each do |verb|
        responses = document.dig("paths", path, verb, "responses")
        errors = responses.reject { |status, _| status.start_with?("2") }
        expect(errors).not_to be_empty
        errors.each do |status, response|
          ref = response.dig("content", "application/json", "schema", "$ref")
          expect(ref).to eq("#/components/schemas/LegacyError"), "#{verb.upcase} #{path} #{status}"
        end
      end
    end
  end

  it "documents every status the frozen v1 routes can emit" do
    document = doc
    expect(document.dig("paths", "/api/v1/share", "post", "responses").keys)
      .to include("200", "413", "422", "429", "503")
    %w[get post].each do |verb|
      expect(document.dig("paths", "/api/v1/secret/{key}", verb, "responses").keys)
        .to include("200", "401", "404", "429", "503")
    end
  end

  it "requires the message field in the legacy error schema" do
    expect(doc.dig("components", "schemas", "LegacyError", "required")).to include("message")
  end

  it "documents the v1 form body alongside JSON" do
    content = doc.dig("paths", "/api/v1/share", "post", "requestBody", "content")
    expect(content.keys).to include("application/json", "application/x-www-form-urlencoded")
  end

  it "documents the Prometheus scrape endpoint" do
    metrics = doc.dig("paths", "/metrics", "get")
    expect(metrics).not_to be_nil
    expect(metrics.dig("responses", "200", "content")).to have_key("text/plain")
  end

  it "uses OpenAPI 3.1 null types instead of the 3.0 nullable keyword" do
    expect(doc.to_s).not_to include('"nullable"')
    response_code = doc.dig("components", "schemas", "WebhookDelivery", "properties", "response_code")
    expect(response_code["type"]).to include("null")
  end

  it "documents the owner-only burn route and its response" do
    burn = doc.dig("paths", "/api/v3/secret/{key}", "delete")
    expect(burn["security"]).to eq([{ "cookie" => [] }])
    expect(burn.dig("responses", "200", "content", "application/json", "schema", "$ref"))
      .to eq("#/components/schemas/BurnResponse")
    expect(burn.dig("responses", "429", "content", "application/json", "schema", "$ref"))
      .to eq("#/components/schemas/Error")
  end

  it "requires the cookie security scheme for owner and account routes" do
    document = doc
    %w[/api/v3/account/me /api/v3/secret/conceal].each do |path|
      verb = document["paths"][path].keys.first
      expect(document["paths"][path][verb]["security"]).to eq([{ "cookie" => [] }])
    end
  end
end
