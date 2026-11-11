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

  it "references only schemas that exist" do
    document = doc
    defined_schemas = document["components"]["schemas"].keys
    refs = document.to_s.scan(/"\$ref":"#\/components\/schemas\/([^"]+)"/).flatten.uniq
    expect(refs - defined_schemas).to be_empty
  end

  it "documents only paths the app actually mounts" do
    document = doc
    document["paths"].each do |path, methods|
      methods.each_key do |verb|
        # Substitute the path parameter with a plausible value.
        concrete = path.gsub("{key}", "somekey")
        send(verb, concrete)
        # A documented route must not be the generic catch-all 404.
        expect(last_response.status).not_to eq(405), "#{verb.upcase} #{path} is not mounted"
      end
    end
  end

  it "requires the cookie security scheme for owner and account routes" do
    document = doc
    %w[/api/v3/account/me /api/v3/secret/conceal].each do |path|
      verb = document["paths"][path].keys.first
      expect(document["paths"][path][verb]["security"]).to eq([{ "cookie" => [] }])
    end
  end
end
