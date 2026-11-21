# frozen_string_literal: true

RSpec.describe Onetime::Store do
  let(:key) { "spec:#{SecureRandom.hex(6)}" }

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

  it "rewrites a value while it is still unchanged, keeping its TTL" do
    described_class.redis.set(key, "before", ex: 30)

    expect(described_class.rewrite_if_unchanged(key, "before", "after")).to be(true)
    expect(described_class.redis.get(key)).to eq("after")
    expect(described_class.redis.ttl(key)).to be_between(1, 30)
  end

  it "refuses to rewrite a value that changed meanwhile" do
    described_class.redis.set(key, "current")

    expect(described_class.rewrite_if_unchanged(key, "stale", "after")).to be(false)
    expect(described_class.redis.get(key)).to eq("current")
  end

  it "refuses to rewrite a key that is gone" do
    expect(described_class.rewrite_if_unchanged(key, "before", "after")).to be(false)
    expect(described_class.redis.exists?(key)).to be(false)
  end

  it "rewrites a hash field only while it is still unchanged" do
    described_class.redis.hset(key, "signing_secret", "before")

    expect(described_class.rewrite_hash_field_if_unchanged(key, "signing_secret", "before", "after")).to be(true)
    expect(described_class.redis.hget(key, "signing_secret")).to eq("after")
    expect(described_class.rewrite_hash_field_if_unchanged(key, "signing_secret", "before", "again")).to be(false)
    expect(described_class.redis.hget(key, "signing_secret")).to eq("after")
  end
end
