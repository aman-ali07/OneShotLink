# frozen_string_literal: true

require "tmpdir"

RSpec.describe "Audit, backup, and key rotation" do
  describe Onetime::Audit do
    it "records known events as immutable stream entries" do
      described_class.record("customer.signin", actor_id: "cust-1")

      events = described_class.recent(limit: 10)
      expect(events.first["event"]).to eq("customer.signin")
      expect(events.first["actor_id"]).to eq("cust-1")
    end

    it "rejects unknown event names instead of writing arbitrary strings" do
      expect { described_class.record("secret.plaintext_leak") }.to raise_error(ArgumentError)
    end

    it "never stores an email, password, or secret value" do
      described_class.record("customer.signin_failed", actor_id: "cust-9", ip: "203.0.113.9")

      raw = Onetime::Store.redis.xrange(Onetime::Audit::STREAM).to_s
      expect(raw).not_to include("password")
      expect(raw).not_to include("@")
    end
  end

  describe Onetime::Logic::RotateKey do
    it "re-encrypts stored secrets so they decrypt under the new key" do
      objid, = Onetime::Models::Secret.create(plaintext: "rotatable", ttl: 600)
      old_secret = ENV.fetch("SECRET")
      new_secret = "y" * 40

      stats = described_class.new(new_secret: new_secret).call
      expect(stats[:reencrypted]).to be >= 1

      # Old key can no longer read it; new key can.
      raw = Onetime::Store.redis.get(Onetime::Models::Secret.object_key(objid))
      record = JSON.parse(raw)
      expect { Onetime::Crypto.decrypt(record, secret: old_secret) }.to raise_error(Onetime::Error)
      expect(Onetime::Crypto.decrypt(record, secret: new_secret)).to eq("rotatable")
    end

    it "refuses a new secret shorter than 32 bytes" do
      expect { described_class.new(new_secret: "short").call }.to raise_error(Onetime::ValidationError)
    end

    it "preserves the remaining TTL of each record" do
      objid, = Onetime::Models::Secret.create(plaintext: "keep-ttl", ttl: 600)
      described_class.new(new_secret: "z" * 40).call
      remaining = Onetime::Store.redis.ttl(Onetime::Models::Secret.object_key(objid))
      expect(remaining).to be_between(1, 600)
    end

    it "does not resurrect a secret consumed between the read and the rewrite" do
      objid, = Onetime::Models::Secret.create(plaintext: "racy", ttl: 600)
      object_key = Onetime::Models::Secret.object_key(objid)

      allow(Onetime::Crypto).to receive(:encrypt).and_wrap_original do |original, plaintext, **kwargs|
        Onetime::Store.redis.del(object_key) # the reveal wins the race here
        original.call(plaintext, **kwargs)
      end

      stats = described_class.new(new_secret: "w" * 40).call
      expect(stats[:reencrypted]).to eq(0)
      expect(stats[:skipped]).to be >= 1
      expect(Onetime::Store.redis.exists?(object_key)).to be(false)
    end
  end

  describe Onetime::Backup do
    it "exports encrypted records only and restores them faithfully" do
      objid, = Onetime::Models::Secret.create(plaintext: "backup-me", ttl: 600)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "dump.json")
        stats = described_class.export(path)
        expect(stats[:secrets]).to be >= 1

        content = File.read(path)
        expect(content).not_to include("backup-me")

        Onetime::Store.redis.flushdb
        expect(Onetime::Store.redis.get(Onetime::Models::Secret.object_key(objid))).to be_nil

        described_class.restore(path)
        raw = Onetime::Store.redis.get(Onetime::Models::Secret.object_key(objid))
        expect(Onetime::Crypto.decrypt(JSON.parse(raw))).to eq("backup-me")
      end
    end

    it "does not export live session keys" do
      Onetime::Models::Session.create("cust-backup")
      Dir.mktmpdir do |dir|
        path = File.join(dir, "dump.json")
        described_class.export(path)
        expect(File.read(path)).not_to include(Onetime::Models::Session::INDEX_PREFIX)
      end
    end

    it "exports and restores owner receipts with their TTL" do
      objid, = Onetime::Models::Secret.create(plaintext: "owned-backup", ttl: 600, owner_id: "cust-backup")
      receipt_key = Onetime::Models::Secret.receipt_key(objid)
      expect(Onetime::Store.redis.exists?(receipt_key)).to be(true)

      Dir.mktmpdir do |dir|
        path = File.join(dir, "dump.json")
        stats = described_class.export(path)
        expect(stats[:receipts]).to eq(1)

        Onetime::Store.redis.flushdb
        described_class.restore(path)

        expect(Onetime::Store.redis.hgetall(receipt_key)["owner_id"]).to eq("cust-backup")
        expect(Onetime::Store.redis.ttl(receipt_key)).to be_between(1, 600)
      end
    end

    it "restores the customer owner index zset" do
      objid, = Onetime::Models::Secret.create(plaintext: "indexed", ttl: 600, owner_id: "cust-index")
      index_key = Onetime::Models::Secret.owner_index("cust-index")
      expect(Onetime::Store.redis.zscore(index_key, objid)).not_to be_nil

      Dir.mktmpdir do |dir|
        path = File.join(dir, "dump.json")
        described_class.export(path)
        Onetime::Store.redis.flushdb
        described_class.restore(path)
        expect(Onetime::Store.redis.zscore(index_key, objid)).not_to be_nil
      end
    end
  end
end
