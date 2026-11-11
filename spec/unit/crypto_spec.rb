# frozen_string_literal: true

RSpec.describe Onetime::Crypto do
  let(:plaintext) { "correct horse battery staple ✓" }

  it "round-trips UTF-8 content" do
    payload = described_class.encrypt(plaintext)
    expect(described_class.decrypt(payload)).to eq(plaintext)
  end

  it "round-trips an empty string" do
    payload = described_class.encrypt("")
    expect(described_class.decrypt(payload)).to eq("")
  end

  it "never stores plaintext in the payload" do
    payload = described_class.encrypt(plaintext)
    expect(payload.values.join).not_to include("horse")
  end

  it "uses a fresh IV and salt per record" do
    a = described_class.encrypt(plaintext)
    b = described_class.encrypt(plaintext)
    expect(a["iv"]).not_to eq(b["iv"])
    expect(a["salt"]).not_to eq(b["salt"])
  end

  it "fails closed under a different SECRET" do
    payload = described_class.encrypt(plaintext)
    expect { described_class.decrypt(payload, secret: "x" * 64) }
      .to raise_error(Onetime::Error)
  end

  it "detects a tampered ciphertext" do
    payload = described_class.encrypt(plaintext)
    bytes = payload["ciphertext"].unpack1("m0")
    bytes.setbyte(0, bytes.getbyte(0) ^ 0xff)
    payload["ciphertext"] = [bytes].pack("m0")
    expect { described_class.decrypt(payload) }.to raise_error(Onetime::Error)
  end
end
