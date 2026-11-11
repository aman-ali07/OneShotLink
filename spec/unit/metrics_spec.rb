# frozen_string_literal: true

RSpec.describe Onetime::Metrics do
  before { described_class.reset! }

  it "counts requests by route family and status class" do
    described_class.record(family: "api_v3", status: 201, duration: 0.01)
    described_class.record(family: "api_v3", status: 404, duration: 0.02)

    snapshot = described_class.snapshot
    expect(snapshot[:requests][%w[api_v3 2xx]]).to eq(1)
    expect(snapshot[:requests][%w[api_v3 4xx]]).to eq(1)
    expect(snapshot[:errors]).to eq(0)
  end

  it "counts only 5xx responses as errors" do
    described_class.record(family: "web", status: 200, duration: 0.01)
    described_class.record(family: "web", status: 503, duration: 0.01)

    expect(described_class.snapshot[:errors]).to eq(1)
  end

  it "collapses an unknown family to other so labels stay bounded" do
    described_class.record(family: "/secret/super-secret-key", status: 200, duration: 0.01)

    expect(described_class.snapshot[:requests].keys.map(&:first)).to eq(["other"])
  end

  it "accumulates duration sum and count per family" do
    described_class.record(family: "health", status: 200, duration: 0.1)
    described_class.record(family: "health", status: 200, duration: 0.2)

    snapshot = described_class.snapshot
    expect(snapshot[:durations_count]["health"]).to eq(2)
    expect(snapshot[:durations_sum]["health"]).to be_within(1e-9).of(0.3)
  end

  it "renders valid Prometheus exposition text" do
    described_class.record(family: "api_v3_guest", status: 201, duration: 0.05)

    body = described_class.render(redis_memory: { used: 800, max: 1000 }, redis_up: true)

    expect(body).to include("onetime_up 1")
    expect(body).to include("onetime_redis_up 1")
    expect(body).to include(%(onetime_requests_total{family="api_v3_guest",status="2xx"} 1))
    expect(body).to include("onetime_errors_total 0")
    expect(body).to include("onetime_redis_memory_used_bytes 800")
    expect(body).to include("onetime_redis_memory_max_bytes 1000")
    expect(body).to include("onetime_redis_memory_used_ratio 0.800000")
    expect(body).to include(%(onetime_version_info{version="#{Onetime::VERSION}"} 1))
    # Every non-comment line must be `name{labels} value`.
    body.lines.reject { |line| line.start_with?("#") || line.strip.empty? }.each do |line|
      expect(line).to match(/\A[a-z_]+\{?.*\}? -?[\d.]+\n\z/)
    end
  end

  it "omits the ratio when maxmemory is unlimited" do
    body = described_class.render(redis_memory: { used: 800, max: 0 }, redis_up: true)

    expect(body).to include("onetime_redis_memory_used_bytes 800")
    expect(body).not_to include("onetime_redis_memory_used_ratio")
  end

  it "reports redis down without failing to render" do
    body = described_class.render(redis_memory: nil, redis_up: false)

    expect(body).to include("onetime_redis_up 0")
    expect(body).to include("onetime_up 1")
  end
end
