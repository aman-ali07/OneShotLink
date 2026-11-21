# frozen_string_literal: true

RSpec.describe "Metrics endpoint" do
  TOKEN = "scrape-token-for-specs-only-0123456789abcdef"

  before do
    Onetime::Metrics.reset!
    @prev = { "METRICS_ENABLED" => ENV["METRICS_ENABLED"], "METRICS_TOKEN" => ENV["METRICS_TOKEN"] }
    ENV["METRICS_TOKEN"] = TOKEN
  end

  after do
    Onetime::Metrics.reset!
    @prev.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def scrape(headers = {})
    get "/metrics", nil, { "HTTP_AUTHORIZATION" => "Bearer #{TOKEN}" }.merge(headers)
  end

  it "returns 404 when METRICS_ENABLED is off" do
    ENV["METRICS_ENABLED"] = "false"
    scrape

    expect(last_response.status).to eq(404)
  end

  it "stays closed when enabled without a token (fail closed)" do
    ENV["METRICS_ENABLED"] = "true"
    ENV["METRICS_TOKEN"] = ""
    get "/metrics", nil, { "HTTP_AUTHORIZATION" => "Bearer anything" }

    expect(last_response.status).to eq(404)
  end

  it "rejects a wrong or missing token with the same 404" do
    ENV["METRICS_ENABLED"] = "true"
    get "/metrics", nil, { "HTTP_AUTHORIZATION" => "Bearer wrong" }
    expect(last_response.status).to eq(404)

    get "/metrics"
    expect(last_response.status).to eq(404)
  end

  it "throttles repeated failed token guesses" do
    ENV["METRICS_ENABLED"] = "true"
    6.times { get "/metrics", nil, { "HTTP_AUTHORIZATION" => "Bearer wrong-token" } }

    expect(last_response.status).to eq(429)
    expect(last_response.headers["Retry-After"]).to match(/\A\d+\z/)
  end

  it "serves Prometheus text to an authorized scraper" do
    ENV["METRICS_ENABLED"] = "true"
    get "/health" # seed one recorded sample
    scrape

    expect(last_response.status).to eq(200)
    expect(last_response.content_type).to include("text/plain")
    expect(last_response.body).to include("onetime_up 1")
    expect(last_response.body).to include(%(onetime_requests_total{family="health",status="2xx"} 1))
    expect(last_response.body).to include("onetime_redis_memory_used_bytes")
    expect(last_response.headers).not_to include("Set-Cookie")
  end

  it "does not publish the exact build version" do
    ENV["METRICS_ENABLED"] = "true"
    scrape

    expect(last_response.status).to eq(200)
    expect(last_response.body).not_to include("onetime_version_info")
  end

  it "records 4xx and 5xx status classes separately" do
    ENV["METRICS_ENABLED"] = "true"
    get "/api/v3/guest/secret/does-not-exist" # 404
    scrape

    expect(last_response.status).to eq(200)
    expect(last_response.body).to include(%(family="api_v3_guest",status="4xx"} 1))
  end

  it "rate limits authorized scrapes on their own scope" do
    ENV["METRICS_ENABLED"] = "true"
    ENV["RATE_LIMIT_METRICS"] = "1"
    2.times { scrape }

    expect(last_response.status).to eq(429)
    expect(last_response.headers["Retry-After"]).to match(/\A\d+\z/)
  ensure
    ENV["RATE_LIMIT_METRICS"] = nil
  end
end
