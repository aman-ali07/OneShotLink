# frozen_string_literal: true

# The migration substrate must be observable, idempotent and non-destructive:
# it advances a schema marker without rewriting any stored record. Assertions
# are on Redis state, never on mocks.
RSpec.describe Onetime::Migrate do
  SCHEMA_KEY = described_class::SCHEMA_KEY

  describe ".current_version" do
    it "reports 0 when the schema marker has never been written" do
      expect(described_class.current_version).to eq(0)
      expect(Onetime::Store.redis.exists?(SCHEMA_KEY)).to be(false)
    end

    it "refuses a corrupt marker instead of treating it as version 0" do
      Onetime::Store.redis.set(SCHEMA_KEY, "not-a-number")

      expect { described_class.current_version }.to raise_error(Onetime::Error, /schema:version/)
    end
  end

  describe ".dry_run" do
    it "reports the planned step without writing anything to Redis" do
      result = described_class.dry_run

      expect(result[:current]).to eq(0)
      expect(result[:target]).to eq(described_class::TARGET_VERSION)
      expect(result[:planned]).to include("initial-schema")
      expect(result[:applied]).to be_empty
      expect(result[:dry_run]).to be(true)
      expect(Onetime::Store.redis.exists?(SCHEMA_KEY)).to be(false)
    end
  end

  describe ".apply!" do
    it "stamps the schema version once and is idempotent on a second run" do
      first = described_class.apply!

      expect(first[:applied]).to include("initial-schema")
      expect(Onetime::Store.redis.get(SCHEMA_KEY)).to eq("1")

      second = described_class.apply!

      expect(second[:applied]).to be_empty
      expect(Onetime::Store.redis.get(SCHEMA_KEY)).to eq("1")
      expect(second[:current]).to eq(1)
    end

    it "never rewrites a stored secret record" do
      objid, = Onetime::Models::Secret.create(plaintext: "migration-safe", ttl: 600)
      key = Onetime::Models::Secret.object_key(objid)
      before_raw = Onetime::Store.redis.get(key)
      before_ttl = Onetime::Store.redis.ttl(key)

      described_class.apply!

      expect(Onetime::Store.redis.get(key)).to eq(before_raw)
      expect(Onetime::Store.redis.ttl(key)).to eq(before_ttl)
    end

    it "refuses to downgrade a database written by a newer release" do
      Onetime::Store.redis.set(SCHEMA_KEY, "2")

      expect { described_class.apply! }.to raise_error(Onetime::Error, /newer schema version/)
      expect(Onetime::Store.redis.get(SCHEMA_KEY)).to eq("2")
    end
  end
end
