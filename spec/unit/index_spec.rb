# frozen_string_literal: true

RSpec.describe "Owner index TTLs" do
  let(:owner_id) { "cust-index-ttl-#{SecureRandom.hex(4)}" }

  it "expires the secret owner index and refreshes it on a new secret" do
    Onetime::Models::Secret.create(plaintext: "indexed", ttl: 600, owner_id: owner_id)
    key = Onetime::Models::Secret.owner_index(owner_id)
    expect(Onetime::Store.redis.ttl(key)).to be > 0

    Onetime::Store.redis.expire(key, 5)
    Onetime::Models::Secret.create(plaintext: "second", ttl: 600, owner_id: owner_id)
    expect(Onetime::Store.redis.ttl(key)).to be > 5
  end

  it "expires the incoming-request owner index" do
    Onetime::Models::SecretRequest.create(owner_id: owner_id, label: "label", ttl: 600)
    key = Onetime::Models::SecretRequest.owner_index(owner_id)
    expect(Onetime::Store.redis.ttl(key)).to be > 0
  end
end
