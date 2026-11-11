# frozen_string_literal: true

RSpec.describe Onetime::Store do
  let(:key) { "spec:#{SecureRandom.hex(6)}" }

  it "writes and reads JSON with a TTL" do
    described_class.set_json(key, { "a" => 1 }, ttl: 30)
    expect(described_class.get_json(key)).to eq("a" => 1)
    expect(described_class.redis.ttl(key)).to be_between(1, 30)
  end

  it "consumes a record exactly once when the value matches" do
    value = JSON.generate("secret" => "ciphertext")
    described_class.redis.set(key, value)

    expect(described_class.consume(key, value)).to be(true)
    expect(described_class.redis.exists?(key)).to be(false)
    expect(described_class.consume(key, value)).to be(false)
  end

  it "does not delete when the stored value changed" do
    described_class.redis.set(key, "current")
    expect(described_class.consume(key, "stale")).to be(false)
    expect(described_class.redis.get(key)).to eq("current")
  end

  it "refuses to consume without an expected value" do
    described_class.redis.set(key, "current")
    expect { described_class.consume(key, "") }.to raise_error(ArgumentError)
  end
end
