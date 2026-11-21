# frozen_string_literal: true

RSpec.describe Onetime::Models::Session do
  let(:customer_id) { "cust-#{SecureRandom.hex(4)}" }

  it "stores only a digest of the token in Redis" do
    token = described_class.create(customer_id)

    expect(Onetime::Store.redis.exists?("session:#{described_class.digest(token)}")).to be(true)
    # The raw token must never be a key (or a field value) anywhere.
    expect(Onetime::Store.redis.keys("*").join).not_to include(token)
  end

  it "returns the owning customer on fetch and refreshes the TTL" do
    token = described_class.create(customer_id)
    Onetime::Store.redis.expire("session:#{described_class.digest(token)}", 5)

    session = described_class.fetch(token)
    expect(session[:customer_id]).to eq(customer_id)
    expect(Onetime::Store.redis.ttl("session:#{described_class.digest(token)}")).to be > 5
  end

  it "keeps revocation working after the customer index has lapsed" do
    keep = described_class.create(customer_id)
    stolen = described_class.create(customer_id)
    index_key = described_class.index_key(customer_id)

    # Simulate one SESSION_TTL elapsing while the session key is kept alive by
    # activity: the index is gone, but the cookie still resolves.
    Onetime::Store.redis.del(index_key)
    expect(described_class.fetch(stolen)[:customer_id]).to eq(customer_id)
    expect(Onetime::Store.redis.smembers(index_key)).to include(described_class.digest(stolen))

    removed = described_class.revoke_all(customer_id, except_token: keep)
    expect(removed).to eq(1)
    expect(described_class.fetch(stolen)).to be_nil
    expect(described_class.fetch(keep)).not_to be_nil
  end

  it "slides the revocation index TTL when a session is touched" do
    token = described_class.create(customer_id)
    index = described_class.index_key(customer_id)
    Onetime::Store.redis.expire(index, 2)

    expect(described_class.fetch(token)[:customer_id]).to eq(customer_id)
    expect(Onetime::Store.redis.ttl(index)).to be > 2
  end

  it "does not recreate a destroyed session hash on a stale touch" do
    token = described_class.create(customer_id)
    key = described_class.key(token)
    Onetime::Store.redis.del(key)

    expect(described_class.fetch(token)).to be_nil
    expect(Onetime::Store.redis.exists?(key)).to be(false)
  end

  it "destroys a session and removes it from the customer index" do
    token = described_class.create(customer_id)
    described_class.destroy(token)

    expect(described_class.fetch(token)).to be_nil
    expect(Onetime::Store.redis.smembers(described_class.index_key(customer_id))).to be_empty
  end

  it "revokes every session except the one that must survive" do
    keep = described_class.create(customer_id)
    drop1 = described_class.create(customer_id)
    drop2 = described_class.create(customer_id)

    removed = described_class.revoke_all(customer_id, except_token: keep)

    expect(removed).to eq(2)
    expect(described_class.fetch(keep)).not_to be_nil
    expect(described_class.fetch(drop1)).to be_nil
    expect(described_class.fetch(drop2)).to be_nil
  end

  it "revokes all sessions when no exception is given" do
    token = described_class.create(customer_id)
    expect(described_class.revoke_all(customer_id)).to eq(1)
    expect(described_class.fetch(token)).to be_nil
  end

  it "does not let one customer's revocation touch another's sessions" do
    mine = described_class.create(customer_id)
    other = described_class.create("someone-else")

    described_class.revoke_all(customer_id)

    expect(described_class.fetch(mine)).to be_nil
    expect(described_class.fetch(other)).not_to be_nil
  end
end
