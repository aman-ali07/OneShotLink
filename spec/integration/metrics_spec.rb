# frozen_string_literal: true

RSpec.describe "Metrics endpoint" do
  before do
    Onetime::Metrics.reset!
    @prev = ENV["METRICS_ENABLED"]
  end

  after do
    Onetime::Metrics.reset!
    ENV["METRICS_ENABLED"] = @prev
  end

  it "returns 404 when METRICS_ENABLED is off" do
    ENV["METRICS_ENABLED"] = "false"
    get "/metrics"

    expect(last_response.status).to eq(404)
  end

  it "serves Prometheus text when enabled" do
    ENV["METRICS_ENABLED"] = "true"
    get "/health" # seed one recorded sample
    get "/metrics"

    expect(last_response.status).to eq(200)
    expect(last_response.content_type).to include("text/plain")
    expect(last_response.body).to include("onetime_up 1")
    expect(last_response.body).to include(%(onetime_requests_total{family="health",status="2xx"} 1))
    expect(last_response.body).to include("onetime_redis_memory_used_bytes")
    expect(last_response.headers).not_to include("Set-Cookie")
  end

  it "records 4xx and 5xx status classes separately" do
    ENV["METRICS_ENABLED"] = "true"
    get "/api/v3/guest/secret/does-not-exist" # 404
    get "/metrics"

    expect(last_response.status).to eq(200)
    expect(last_response.body).to include(%(family="api_v3_guest",status="4xx"} 1))
  end
end
