# frozen_string_literal: true

# Unit-level edge coverage added by the QA acceptance pass.
RSpec.describe "QA acceptance — pure-logic edges" do
  describe Onetime::Store do
    let(:submission) { "qa:#{SecureRandom.hex(6)}:sub" }
    let(:object) { "qa:#{SecureRandom.hex(6)}:obj" }

    it "atomically consumes a submission and retires its request object" do
      Onetime::Store.redis.set(submission, "ciphertext")
      Onetime::Store.redis.set(object, "request-object")

      expect(described_class.consume_request(submission, object, "ciphertext")).to be(true)
      expect(Onetime::Store.redis.exists?(submission)).to be(false)
      expect(Onetime::Store.redis.exists?(object)).to be(false)
      expect(described_class.consume_request(submission, object, "ciphertext")).to be(false)
    end

    it "refuses a two-key consume without an expected value" do
      expect { described_class.consume_request(submission, object, "") }.to raise_error(ArgumentError)
    end
  end

  describe Onetime::Crypto do
    it "rejects a non-string plaintext at the boundary" do
      expect { described_class.encrypt(123) }.to raise_error(ArgumentError, /must be a String/)
    end

    it "maps a missing field to a typed malformed-record error" do
      expect { described_class.decrypt({}) }.to raise_error(Onetime::Error, /malformed/)
    end

    it "detects a tampered authentication tag" do
      payload = described_class.encrypt("qa-tamper")
      bytes = payload["tag"].unpack1("m0")
      bytes.setbyte(0, bytes.getbyte(0) ^ 0xff)
      payload["tag"] = [bytes].pack("m0")

      expect { described_class.decrypt(payload) }.to raise_error(Onetime::Error)
    end

    it "returns false when either side of a secure compare is nil" do
      expect(described_class.secure_compare("abc", nil)).to be(false)
      expect(described_class.secure_compare(nil, nil)).to be(false)
    end
  end

  describe Onetime::Limiter do
    it "exposes correct result helpers" do
      denied = described_class::Result.new(0, 5, 10, 3)
      expect(denied.allowed?).to be(false)
      expect(denied.remaining).to eq(0)
      expect(denied.reset).to eq(10)
      expect(described_class::Result.new(1, 0, -1, 3).reset).to eq(0)
    end

    it "allows everything when the limit is disabled and writes no keys" do
      id = "qa-disabled-#{SecureRandom.hex(4)}"
      expect(described_class.check!(id, scope: :conceal, limit: 0, window: 60).allowed?).to be(true)
      expect(Onetime::Store.redis.exists?("limiter:#{id}:conceal")).to be(false)
    end
  end

  describe Onetime::Ids do
    it "generates unique 256-bit session tokens and normalises opaque indexes" do
      expect(described_class.session_token).to match(/\A[0-9a-f]{64}\z/)
      expect(described_class.session_token).not_to eq(described_class.session_token)
      expect(described_class.opaque_index(" a@Example.com ")).to eq(described_class.opaque_index("a@example.com"))
    end
  end

  describe Onetime::Metrics do
    it "buckets out-of-range statuses as other" do
      expect(described_class.status_bucket(99)).to eq("other")
      expect(described_class.status_bucket(600)).to eq("other")
    end
  end
end
