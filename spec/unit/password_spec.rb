# frozen_string_literal: true

RSpec.describe Onetime::Password do
  let(:password) { "a-long-enough-password" }

  it "creates Argon2id hashes, never the plaintext" do
    hash = described_class.create(password)
    expect(hash).to start_with("$argon2id$")
    expect(hash).not_to include(password)
  end

  it "verifies the correct password and rejects a wrong one" do
    hash = described_class.create(password)
    expect(described_class.verify(hash, password)).to be(true)
    expect(described_class.verify(hash, "nope")).to be(false)
  end

  it "returns false for malformed hashes instead of raising" do
    expect(described_class.verify("not-a-hash", password)).to be(false)
    expect(described_class.verify(nil, password)).to be(false)
  end

  it "verifies legacy bcrypt hashes for migration on login" do
    require "bcrypt"
    legacy = BCrypt::Password.create(password)
    expect(described_class.verify(legacy.to_s, password)).to be(true)
  end
end
