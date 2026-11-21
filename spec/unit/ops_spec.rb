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

    it "stores a daily rotating IP reference instead of the raw address (D-retention)" do
      described_class.record("customer.signin_failed", actor_id: "cust-9", ip: "203.0.113.9")
      entry = described_class.recent(limit: 1).fetch(0)
      expect(entry).not_to have_key("ip")
      expect(entry["ip_day"]).to match(/\A[0-9a-f]{12}\z/)
      expect(Onetime::Store.redis.xrange(Onetime::Audit::STREAM).to_s).not_to include("203.0.113.9")

      today = entry["ip_day"]
      allow(Time).to receive(:now).and_return(Time.now + 86_400)
      described_class.record("customer.signin_failed", actor_id: "cust-9", ip: "203.0.113.9")
      expect(described_class.recent(limit: 1).fetch(0)["ip_day"]).not_to eq(today)
    end

    it "correlates and counts a dropped audit write without breaking the caller" do
      allow(Onetime::Store.redis).to receive(:xadd).and_raise(Redis::CannotConnectError, "connection refused")
      Onetime::Metrics.reset!
      expect(Onetime.logger).to receive(:error).with(
        a_string_including("audit_write_failed")
          .and(a_string_including("request_id=req-42"))
          .and(a_string_including("actor_id=cust-7"))
      )

      expect(described_class.record("customer.signin", actor_id: "cust-7", request_id: "req-42")).to be(false)
      expect(Onetime::Metrics.snapshot[:best_effort_failures]["audit"]).to eq(1)
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

    it "re-encrypts in-flight secret request submissions under the new key" do
      key, = Onetime::Models::SecretRequest.create(owner_id: "cust-rot", label: "label", ttl: 600)
      Onetime::Logic::SubmitToRequest.new(key: key, secret: "rotate-submission").call
      submission_key = Onetime::Models::SecretRequest.submission_key(key)
      new_secret = "r" * 40

      described_class.new(new_secret: new_secret).call

      payload = JSON.parse(Onetime::Store.redis.get(submission_key))
      expect { Onetime::Crypto.decrypt(payload, secret: ENV.fetch("SECRET")) }.to raise_error(Onetime::Error)
      expect(Onetime::Crypto.decrypt(payload, secret: new_secret)).to eq("rotate-submission")
    end

    it "re-encrypts webhook signing secrets under the new key" do
      endpoint = Onetime::Webhook.create(
        owner_id: "cust-hook", url: "http://93.184.216.34/hook", events: ["secret.created"]
      )
      new_secret = "h" * 40

      described_class.new(new_secret: new_secret).call

      raw = Onetime::Store.redis.hget(Onetime::Webhook.key(endpoint[:id]), "signing_secret")
      expect(Onetime::Crypto.decrypt(JSON.parse(raw), secret: new_secret)).to eq(endpoint[:signing_secret])
    end

    it "skips a tampered protected record during rotation instead of re-signing it" do
      key, = Onetime::Models::Secret.create(plaintext: "launder-target", ttl: 600, passphrase: "correct-horse")
      object_key = Onetime::Models::Secret.object_key(key)
      record = JSON.parse(Onetime::Store.redis.get(object_key))
      mac_before = record["meta_mac"]
      record.delete("passphrase_hash")
      Onetime::Store.redis.set(object_key, JSON.generate(record), ex: 600)

      new_secret = "n" * 40
      stats = described_class.new(new_secret: new_secret).call
      expect(stats[:skipped]).to be >= 1
      expect(JSON.parse(Onetime::Store.redis.get(object_key))["meta_mac"]).to eq(mac_before)

      old = ENV["SECRET"]
      begin
        ENV["SECRET"] = new_secret
        post "/api/v3/guest/secret/#{key}/reveal", JSON.generate({}),
             { "CONTENT_TYPE" => "application/json" }
        expect(last_response.status).to eq(500)
        expect(last_response.body).not_to include("launder-target")
      ensure
        ENV["SECRET"] = old
      end
    end

    it "renews request-object MACs so answered links survive rotation" do
      key, = Onetime::Models::SecretRequest.create(owner_id: "cust-rot-req", label: "L", ttl: 600)
      Onetime::Logic::SubmitToRequest.new(key: key, secret: "still-readable").call
      new_secret = "q" * 40
      described_class.new(new_secret: new_secret).call

      old = ENV["SECRET"]
      begin
        ENV["SECRET"] = new_secret
        result = Onetime::Logic::RevealRequestSubmission.new(key: key, owner_id: "cust-rot-req").call
        expect(result[:secret_value]).to eq("still-readable")
      ensure
        ENV["SECRET"] = old
      end
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

    it "carries the schema version through a backup and restore" do
      Onetime::Migrate.apply!
      expect(Onetime::Migrate.current_version).to eq(1)

      Dir.mktmpdir do |dir|
        path = File.join(dir, "dump.json")
        described_class.export(path)
        expect(JSON.parse(File.read(path))["schema_version"]).to eq(1)

        Onetime::Store.redis.flushdb
        expect(Onetime::Migrate.current_version).to eq(0)
        described_class.restore(path)
        expect(Onetime::Migrate.current_version).to eq(1)
        expect(Onetime::Migrate.dry_run[:planned]).to be_empty
      end
    end

    it "refuses to stamp an older schema marker over a migrated instance" do
      Onetime::Migrate.apply!
      objid, = Onetime::Models::Secret.create(plaintext: "keep-me", ttl: 600)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "old.json")
        described_class.export(path)
        data = JSON.parse(File.read(path))
        data["schema_version"] = 0
        File.write(path, JSON.generate(data))

        expect { described_class.restore(path, force: true) }
          .to raise_error(Onetime::Error, /older than live/)
        expect(Onetime::Migrate.current_version).to eq(1)
        expect(Onetime::Store.redis.exists?(Onetime::Models::Secret.object_key(objid))).to be(true)
      end
    end

    it "refuses a corrupt schema marker before writing any key" do
      objid, = Onetime::Models::Secret.create(plaintext: "untouched-by-bad-restore", ttl: 600)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "dump.json")
        described_class.export(path)
        data = JSON.parse(File.read(path))
        data["schema_version"] = 99
        File.write(path, JSON.generate(data))

        Onetime::Store.redis.flushdb
        expect { described_class.restore(path) }.to raise_error(Onetime::Error, /outside 0/)
        expect(Onetime::Store.redis.exists?(Onetime::Models::Secret.object_key(objid))).to be(false)
      end
    end

    it "writes the backup file with owner-only permissions" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "dump.json")
        described_class.export(path)
        expect(File.stat(path).mode & 0o777).to eq(0o600)
      end
    end

    it "refuses to overwrite live keys unless forced" do
      objid, = Onetime::Models::Secret.create(plaintext: "do-not-clobber", ttl: 600)
      object_key = Onetime::Models::Secret.object_key(objid)
      before = Onetime::Store.redis.get(object_key)

      Dir.mktmpdir do |dir|
        path = File.join(dir, "dump.json")
        described_class.export(path)
        expect { described_class.restore(path) }.to raise_error(Onetime::Error, /Refusing to overwrite/)
        expect(Onetime::Store.redis.get(object_key)).to eq(before)

        stats = described_class.restore(path, force: true)
        expect(stats[:secrets]).to be >= 1
      end
    end

    it "rejects a malformed entry before overwriting any live key" do
      objid, = Onetime::Models::Secret.create(plaintext: "keep-live", ttl: 600)
      object_key = Onetime::Models::Secret.object_key(objid)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "malformed.json")
        described_class.export(path)
        data = JSON.parse(File.read(path))
        data["customer"]["customer:malformed"] = { "type" => "weird", "value" => {} }
        File.write(path, JSON.generate(data))

        expect { described_class.restore(path, force: true) }
          .to raise_error(Onetime::Error, /unsupported type/)
        expect(Onetime::Store.redis.exists?(object_key)).to be(true)
        expect(Onetime::Crypto.decrypt(JSON.parse(Onetime::Store.redis.get(object_key)))).to eq("keep-live")
      end
    end

    it "rejects a backup that contains keys outside the restorable namespaces" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "evil.json")
        File.write(path, JSON.generate("format" => 1, "secret" => { "limiter:1:signin" => { "raw" => "x" } }))
        expect { described_class.restore(path) }.to raise_error(Onetime::Error, /outside the restorable/)
      end
    end

    it "exports and restores request and webhook state with TTLs" do
      request_key, = Onetime::Models::SecretRequest.create(owner_id: "cust-bk", label: "backup request", ttl: 600)
      Onetime::Logic::SubmitToRequest.new(key: request_key, secret: "backup answer").call
      endpoint = Onetime::Webhook.create(
        owner_id: "cust-bk", url: "https://example.com/hook", events: ["secret.created"]
      )
      Onetime::Webhook.emit("secret.created", owner_id: "cust-bk",
                            data: { identifier: "x", kind: "text", ttl: 60 })

      object_key = Onetime::Models::SecretRequest.object_key(request_key)
      submission_key = Onetime::Models::SecretRequest.submission_key(request_key)
      request_index = Onetime::Models::SecretRequest.owner_index("cust-bk")
      endpoint_key = Onetime::Webhook.key(endpoint[:id])
      owner_index = Onetime::Webhook.owner_index("cust-bk")

      Dir.mktmpdir do |dir|
        path = File.join(dir, "dump.json")
        described_class.export(path)
        content = File.read(path)
        expect(content).to include("request:secret:", "webhook:endpoint:", "webhook:delivery:")
        expect(content).not_to include("backup answer")

        Onetime::Store.redis.flushdb
        stats = described_class.restore(path)
        expect(stats[:requests]).to eq(2)
        expect(stats[:webhooks]).to be >= 3
        expect(Onetime::Store.redis.exists?(object_key)).to be(true)
        expect(Onetime::Store.redis.exists?(submission_key)).to be(true)
        expect(Onetime::Store.redis.ttl(submission_key)).to be_between(1, 600)
        expect(Onetime::Store.redis.ttl(object_key)).to be_between(1, 600)
        expect(Onetime::Store.redis.hget(endpoint_key, "owner_id")).to eq("cust-bk")
        expect(Onetime::Store.redis.zscore(request_index, request_key)).not_to be_nil
        expect(Onetime::Store.redis.zscore(owner_index, endpoint[:id])).not_to be_nil
      end
    end

    it "rejects a backup that plants a session index under the customer prefix" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "evil.json")
        payload = {
          "format" => 1,
          "customer" => { "customer:sessions:victim" => { "type" => "set", "value" => ["digest"] } }
        }
        File.write(path, JSON.generate(payload))
        expect { described_class.restore(path) }.to raise_error(Onetime::Error, /outside the restorable/)
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
