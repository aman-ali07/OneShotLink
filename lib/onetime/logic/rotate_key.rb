# frozen_string_literal: true

module Onetime
  module Logic
    # Re-encrypt every SECRET-encrypted value under a new instance secret.
    #
    # Changing SECRET would otherwise orphan every live record (they can no
    # longer be decrypted). Three shapes carry Crypto.encrypt output:
    #   - secret:object:<id>     — the JSON record itself
    #   - request:secret:<key>   — a submitted one-time answer
    #   - webhook:endpoint:<id>  — the signing_secret hash field
    # All are rewritten in place with a compare-and-swap so a consume during
    # rotation can never be undone by a stale write. Plaintext only ever lives
    # in a local variable; nothing is logged.
    class RotateKey
      BATCH = 200
      STRING_PREFIXES = [
        Models::Secret::OBJECT_PREFIX,
        Models::SecretRequest::SUBMISSION_PREFIX
      ].freeze
      ENDPOINT_PREFIX = Webhook::ENDPOINT_PREFIX
      REQUEST_OBJECT_PREFIX = Models::SecretRequest::OBJECT_PREFIX
      SIGNING_FIELD = "signing_secret"

      def initialize(new_secret:)
        @new_secret = new_secret
      end

      def call
        raise ValidationError, "new secret is too short" if @new_secret.to_s.bytesize < 32

        reencrypted = 0
        skipped = 0

        STRING_PREFIXES.each do |prefix|
          each_string_record(prefix) do |key, raw|
            if rewrite_string(key, raw)
              reencrypted += 1
            else
              skipped += 1
            end
          end
        end

        each_hash_record(ENDPOINT_PREFIX) do |key, endpoint|
          if rewrite_endpoint(key, endpoint)
            reencrypted += 1
          else
            skipped += 1
          end
        end

        # Request objects carry an HMAC keyed by SECRET over their authorization
        # fields. It must be renewed too, or every request link fails integrity
        # after the operator switches keys.
        each_string_record(REQUEST_OBJECT_PREFIX) do |key, raw|
          if rewrite_request_meta(key, raw)
            reencrypted += 1
          else
            skipped += 1
          end
        end

        { reencrypted: reencrypted, skipped: skipped }
      end

      private

      def rewrite_string(key, raw)
        record = parse(raw)
        return false if record.nil?

        if key.start_with?(Models::Secret::OBJECT_PREFIX)
          # Never launder tampered metadata: a Redis writer could strip the
          # passphrase gate, and re-signing under the new key would make the
          # protected secret revealable without it. verify_meta! uses the
          # still-active old key, which is correct during rotation.
          Models::Secret.verify_meta!(record)
        end

        plaintext = Crypto.decrypt(record)
        payload = record.reject { |k, _| %w[ciphertext iv tag salt cipher].include?(k) }
                        .merge(reencrypt(plaintext))
        # The metadata MAC is keyed by SECRET too, so it must be renewed in the
        # same write or every rotated secret would fail verify_meta! on reveal.
        Models::Secret.sign_meta!(payload, secret: @new_secret) if key.start_with?(Models::Secret::OBJECT_PREFIX)
        # A reveal may have consumed this record since we read it. Rewriting
        # unconditionally would bring a burned secret back; the CAS keeps the
        # original one-time invariant intact during rotation.
        Store.rewrite_if_unchanged(key, raw, JSON.generate(payload))
      rescue Onetime::Error
        # A record we cannot decrypt is already unreadable; leave it alone
        # rather than destroying data we do not understand.
        false
      end

      def rewrite_request_meta(key, raw)
        record = parse(raw)
        return false if record.nil?

        # Same laundering defence for request objects: verify the old MAC
        # before signing the attacker-controlled fields with the new key.
        # verify_meta! binds the MAC to the bare request id, not the prefixed
        # Redis key. Passing the full key would make every renewal fail closed.
        bare_key = key.delete_prefix(Models::SecretRequest::OBJECT_PREFIX)
        Models::SecretRequest.verify_meta!(record, key: bare_key)

        updated = record.dup
        Models::Secret.sign_meta!(
          updated,
          fields: Models::SecretRequest::META_FIELDS,
          salt: Models::SecretRequest::META_SALT,
          version: Models::SecretRequest::META_VERSION,
          secret: @new_secret
        )
        Store.rewrite_if_unchanged(key, raw, JSON.generate(updated))
      rescue Onetime::Error
        # A record that fails its old MAC is left under the old key, fail closed.
        false
      end

      def rewrite_endpoint(key, endpoint)
        old = endpoint[SIGNING_FIELD]
        return false if old.to_s.empty?

        plaintext = Crypto.decrypt(JSON.parse(old))
        replacement = JSON.generate(Crypto.encrypt(plaintext, secret: @new_secret))
        Store.rewrite_hash_field_if_unchanged(key, SIGNING_FIELD, old, replacement)
      rescue JSON::ParserError, Onetime::Error
        false
      end

      def each_string_record(prefix)
        each_key(prefix) do |key|
          raw = Store.redis.get(key)
          next if raw.nil?

          yield key, raw
        end
      end

      def each_hash_record(prefix)
        each_key(prefix) do |key|
          value = Store.redis.hgetall(key)
          next if value.empty?

          yield key, value
        end
      end

      def each_key(prefix)
        cursor = "0"
        loop do
          cursor, keys = Store.redis.scan(cursor, match: "#{prefix}*", count: BATCH)
          keys.each { |key| yield key }
          break if cursor == "0"
        end
      end

      def parse(raw)
        parsed = JSON.parse(raw)
        parsed.is_a?(Hash) ? parsed : nil
      rescue JSON::ParserError
        nil
      end

      def reencrypt(plaintext)
        Crypto.encrypt(plaintext, secret: @new_secret)
      end
    end
  end
end
