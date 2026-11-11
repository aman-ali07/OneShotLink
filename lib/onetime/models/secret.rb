# frozen_string_literal: true

module Onetime
  module Models
    # Redis persistence for one-time secrets.
    #
    # The encrypted payload is a JSON *string* (`secret:object:<id>`) so that
    # `Store.consume` can compare-and-delete a single value atomically. Metadata
    # lives in a separate receipt hash with the same TTL. See DATABASE.md.
    module Secret
      OBJECT_PREFIX = "secret:object:"
      RECEIPT_PREFIX = "secret:receipt:"
      OWNER_INDEX_SUFFIX = ":secrets"

      module_function

      def object_key(objid)
        "#{OBJECT_PREFIX}#{objid}"
      end

      def receipt_key(objid)
        "#{RECEIPT_PREFIX}#{objid}"
      end

      def owner_index(owner_id)
        "customer:#{owner_id}#{OWNER_INDEX_SUFFIX}"
      end

      # Returns [objid, record]. Encryption happens here, in one place, so no
      # caller can accidentally persist plaintext.
      def create(plaintext:, ttl:, passphrase: nil, owner_id: nil, kind: "text", filename: nil)
        objid = Ids.extid
        now = Time.now.to_i

        record = {
          "v" => 1,
          "kind" => kind,
          "filename" => filename,
          "owner_id" => owner_id,
          "org_id" => nil,
          "created_at" => now,
          "ttl" => ttl
        }.merge(Crypto.encrypt(plaintext))
        record["passphrase_hash"] = Password.create(passphrase) if passphrase && !passphrase.empty?

        raw = JSON.generate(record)
        write(objid, raw, record, now)
        [objid, record]
      end

      def fetch(objid)
        raw = Store.redis.get(object_key(objid))
        return nil unless raw

        [JSON.parse(raw), raw]
      rescue JSON::ParserError
        nil
      end

      # Returns true for exactly one caller when the record is unchanged.
      def consume(objid, raw)
        Store.consume(object_key(objid), raw)
      end

      def cleanup(objid, owner_id: nil)
        Store.redis.del(receipt_key(objid))
        Store.redis.zrem(owner_index(owner_id), objid) if owner_id && !owner_id.to_s.empty?
      end

      def write(objid, raw, record, now)
        Store.redis.multi do |tx|
          tx.set(object_key(objid), raw, ex: record["ttl"])
          tx.hset(receipt_key(objid), {
            "identifier" => objid,
            "owner_id" => record["owner_id"].to_s,
            "created_at" => now.to_s,
            "ttl" => record["ttl"].to_s,
            "kind" => record["kind"],
            "passphrase" => record["passphrase_hash"] ? "1" : "0",
            "viewed" => "0"
          })
          tx.expire(receipt_key(objid), record["ttl"])
          tx.zadd(owner_index(record["owner_id"]), now, objid) if record["owner_id"]
        end
      end
      private_class_method :write
    end
  end
end
