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

  it "round-trips arbitrary binary bytes without losing data" do
    binary = ["00ff801f7f41"].pack("H*")
    payload = described_class.encrypt(binary)
    expect(described_class.decrypt(payload).b).to eq(binary.b)
  end

  it "fails when a record's salt is swapped with another record's" do
    a = described_class.encrypt("first record")
    b = described_class.encrypt("second record")
    # The salt is authenticated as AEAD associated data; transplanting one must
    # fail the tag check rather than silently decrypting with the wrong key.
    swapped = a.merge("salt" => b["salt"])
    expect { described_class.decrypt(swapped) }
      .to raise_error(Onetime::Error, /integrity verification/)
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

  it "rejects an unauthenticated algorithm override in a stored record" do
    payload = described_class.encrypt(plaintext)
    # Another algorithm's key/tag sizes fail closed on OpenSSL, but an unknown
    # name used to raise a raw RuntimeError (a 500). Both are attacker-controlled
    # bytes, so both must become the same typed integrity error.
    %w[aes-128-gcm garbage].each do |name|
      expect { described_class.decrypt(payload.merge("cipher" => name)) }
        .to raise_error(Onetime::Error, /integrity verification/)
    end
  end

  it "rejects a non-integer record version as a typed integrity error" do
    record = Onetime::Crypto.encrypt("version-tamper").merge(
      "v" => { "downgrade" => true }, "meta_mac" => "a" * 64
    )
    expect { Onetime::Models::Secret.verify_meta!(record) }
      .to raise_error(Onetime::Error, /integrity verification/)
  end

  it "compares opaque tokens in constant time and rejects non-strings" do
    expect(described_class.secure_compare("abc", "abc")).to be(true)
    expect(described_class.secure_compare("abc", "abd")).to be(false)
    expect(described_class.secure_compare("abc", "abcd")).to be(false)
    expect(described_class.secure_compare(nil, "abc")).to be(false)
  end
end
