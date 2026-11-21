# frozen_string_literal: true

RSpec.describe Onetime::CliApi do
  let(:http) { instance_double(Net::HTTP) }
  let(:payload) { { "secret_key" => "key-123", "links" => { "secret" => "/secret/key-123" } } }
  let(:response) { instance_double(Net::HTTPResponse, code: "201", body: JSON.generate(payload)) }
  let(:captured) { [] }

  before do
    allow(Net::HTTP).to receive(:start).and_yield(http).and_return(response)
    allow(http).to receive(:request) { |request| captured << request; response }
  end

  around do |example|
    # SSL must be restored too: leaving SSL=true made later origin proofs
    # expect https while their Origin header was http (order-dependent 403s).
    old = ENV.to_h.slice("OTS_URL", "HOST", "OTS_SECRET", "OTS_PASSPHRASE", "SSL")
    ENV["OTS_URL"] = "http://127.0.0.1:3100"
    example.run
  ensure
    %w[OTS_URL HOST OTS_SECRET OTS_PASSPHRASE SSL].each { |key| ENV.delete(key) }
    old.each { |key, value| ENV[key] = value }
  end

  it "creates a secret through the public v3 API and returns only the key and link" do
    result = described_class.conceal(secret: "cli-secret", ttl: 1800)
    expect(result[:secret_key]).to eq("key-123")
    expect(result[:link]).to eq("http://127.0.0.1:3100/secret/key-123")

    request = captured.fetch(0)
    expect(request.path).to eq("/api/v3/guest/conceal")
    expect(JSON.parse(request.body)).to include("secret" => "cli-secret", "ttl" => 1800)
  end

  it "reveals once through the consuming POST route with an optional passphrase" do
    allow(response).to receive(:code).and_return("200")
    allow(response).to receive(:body).and_return(JSON.generate("secret_value" => "revealed-value"))

    value = described_class.reveal(key: "key-123", passphrase: "correct-horse")
    expect(value).to eq("revealed-value")
    expect(captured.fetch(0).path).to eq("/api/v3/guest/secret/key-123/reveal")
    expect(JSON.parse(captured.fetch(0).body)).to eq("passphrase" => "correct-horse")
  end

  it "raises a typed error with the server message on a non-2xx response" do
    allow(response).to receive(:code).and_return("404")
    allow(response).to receive(:body).and_return(
      JSON.generate("error" => { "code" => "not_found", "message" => "Not found." })
    )

    expect { described_class.reveal(key: "missing") }.to raise_error(Onetime::Error, /Not found/)
  end

  it "derives https from SSL=true with a bare production HOST" do
    ENV.delete("OTS_URL")
    ENV["SSL"] = "true"
    ENV["HOST"] = "secrets.example.com"

    described_class.conceal(secret: "tls-check")
    expect(Net::HTTP).to have_received(:start).with(
      "secrets.example.com", 443, hash_including(use_ssl: true)
    )
  end

  it "refuses plaintext HTTP to a non-loopback host without an explicit opt-in" do
    ENV["OTS_URL"] = "http://secrets.example.com"
    expect { described_class.conceal(secret: "no-cleartext") }
      .to raise_error(Onetime::Error, /plaintext HTTP/)
    expect(Net::HTTP).not_to have_received(:start)
  end

  it "never puts the secret in the URL" do
    described_class.conceal(secret: "url-safe-check")
    expect(captured.fetch(0).path).not_to include("url-safe-check")
  end
end
