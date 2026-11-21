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

      # D-receipt: the payload is destroyed on reveal/burn, but non-sensitive
      # metadata stays for 30 days, then Redis expires it. No secret content,
      # passphrase or key is ever written to the receipt.
      RECEIPT_RETAIN_SECONDS = 30 * 86_400
      STATUSES = %w[new previewed revealed burned].freeze
      TERMINAL_STATUSES = %w[revealed burned].freeze

      # Conditional status write. A preview cannot downgrade a terminal receipt;
      # a terminal transition is applied at most once. Both the receipt and its
      # owner index get the retention TTL on a terminal transition so dormant
      # accounts do not accumulate stale members (KEYS[2] is unused without an
      # owner). See DATABASE.md §4.
      MARK_STATUS_LUA = <<~LUA
        if redis.call('EXISTS', KEYS[1]) == 0 then return 0 end
        local current = redis.call('HGET', KEYS[1], 'status') or 'new'
        local target = ARGV[1]
        if target == 'previewed' and current ~= 'new' then return 0 end
        if (target == 'revealed' or target == 'burned') and
           (current == 'revealed' or current == 'burned') then return 0 end
        redis.call('HSET', KEYS[1], 'status', target, 'viewed', ARGV[2], ARGV[3], ARGV[4])
        if ARGV[5] == '1' then
          redis.call('EXPIRE', KEYS[1], ARGV[6])
          if ARGV[7] == '1' then redis.call('EXPIRE', KEYS[2], ARGV[6]) end
        end
        return 1
      LUA

      # The ciphertext is AEAD-protected, but the passphrase hash and display
      # metadata are siblings in the JSON string. Without a MAC over those
      # fields, anyone who can write Redis could delete `passphrase_hash` and
      # turn the app into a no-passphrase decryption oracle. Records carry an
      # HMAC over exactly the fields reveal trusts.
      # v3 binds the MAC to this record's ciphertext. Without that binding a
      # Redis writer could copy an unprotected record's metadata+MAC onto a
      # protected record and bypass the passphrase gate. v2 records are no
      # longer accepted; no public data exists, and rotation re-signs them.
      META_VERSION = 3
      META_FIELDS = %w[v kind filename owner_id created_at ttl passphrase_hash ciphertext].freeze
      META_SALT = "ots-record-meta/v1"

      module_function

      # Owner indexes are convenience lists, not durable state. Without a TTL a
      # dormant account accumulates stale members forever; the longest allowed
      # secret TTL keeps every still-live member visible.
      def index_ttl(ttl)
        [ttl.to_i, Config.ttl_options.max.to_i, 86_400].max
      end

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
          "v" => META_VERSION,
          "kind" => kind,
          "filename" => filename,
          "owner_id" => owner_id,
          "org_id" => nil,
          "created_at" => now,
          "ttl" => ttl
        }.merge(Crypto.encrypt(plaintext))
        record["passphrase_hash"] = Password.create(passphrase) if passphrase && !passphrase.empty?
        sign_meta!(record)

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

      # MAC the fields that control access and presentation but are not inside
      # the AEAD ciphertext. Callers must run verify_meta! before trusting them.
      # Field list, salt and version are parameters so request records can be
      # signed with the same primitive under a distinct domain. Defaults keep
      # every existing secret-record MAC byte-identical.
      def sign_meta!(record, secret: Config.secret!, fields: META_FIELDS, salt: META_SALT, version: META_VERSION)
        record["v"] = version
        record["meta_mac"] = meta_mac(record, secret: secret, fields: fields, salt: salt)
        record
      end

      def verify_meta!(record, fields: META_FIELDS, salt: META_SALT, version: META_VERSION)
        # There is no released data to stay compatible with, so the legacy
        # window is closed: a downgraded or unsigned record is an attack, not a
        # migration case. Accepting it would let a Redis writer strip the
        # passphrase gate from a protected secret.
        # Do not call #to_i on an attacker-supplied object/array: that raises a
        # raw NoMethodError (an untyped 500) instead of the integrity error the
        # rest of this guard promises. A Redis writer controls these bytes.
        valid_version = record["v"].is_a?(Integer) && record["v"] == version
        unless valid_version && record["meta_mac"].is_a?(String) && !record["meta_mac"].empty?
          raise Onetime::Error, "Stored secret failed integrity verification"
        end

        expected = record["meta_mac"].to_s
        actual = meta_mac(record, secret: Config.secret!, fields: fields, salt: salt)
        return if Crypto.secure_compare(expected, actual)

        raise Onetime::Error, "Stored secret failed integrity verification"
      end

      def meta_mac(record, secret:, fields: META_FIELDS, salt: META_SALT)
        material = JSON.generate(fields.to_h { |field| [field, record[field]] })
        OpenSSL::HMAC.hexdigest("SHA256", Crypto.derive(secret, salt), material)
      end
      private_class_method :meta_mac

      # Returns true for exactly one caller when the record is unchanged.
      def consume(objid, raw)
        Store.consume(object_key(objid), raw)
      end

      # Records a lifecycle transition. Only status and timestamps change; the
      # receipt never receives the payload, passphrase or encryption key.
      def mark_status(objid, status, owner_id: nil)
        raise Error, "unknown receipt status: #{status.inspect}" unless STATUSES.include?(status)

        terminal = TERMINAL_STATUSES.include?(status)
        stamp_field = status == "revealed" ? "revealed_at" : (status == "burned" ? "burned_at" : "previewed_at")
        owner = owner_id && !owner_id.to_s.empty?
        index_key = owner ? owner_index(owner_id) : receipt_key(objid)

        Store.redis.eval(
          MARK_STATUS_LUA,
          keys: [receipt_key(objid), index_key],
          argv: [status, terminal ? "1" : "0", stamp_field, Time.now.to_i.to_s,
                 terminal ? "1" : "0", RECEIPT_RETAIN_SECONDS.to_s, owner ? "1" : "0"]
        ).to_i == 1
      end

      # Best-effort finalisation after an irreversible consume. The caller
      # decides how to report a failure so a spent secret is never a 5xx (SA-06).
      def finalize_receipt(objid, status:, owner_id: nil)
        mark_status(objid, status, owner_id: owner_id)
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
            "status" => "new",
            "viewed" => "0"
          })
          tx.expire(receipt_key(objid), record["ttl"])
          if record["owner_id"]
            index = owner_index(record["owner_id"])
            tx.zadd(index, now, objid)
            tx.expire(index, index_ttl(record["ttl"]))
          end
        end
      end
      private_class_method :write
    end
  end
end
