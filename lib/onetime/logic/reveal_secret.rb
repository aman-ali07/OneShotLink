# frozen_string_literal: true

module Onetime
  module Logic
    # Verify, then decrypt, then consume atomically.
    #
    # A wrong passphrase never reaches the delete, and neither does a record we
    # cannot decrypt: a rotated or wrong SECRET is an operator fault, so the
    # record survives and becomes readable again once the key is right. Both
    # checks are pure, which is why they run before the one irreversible step.
    # Two concurrent reveals both read and decrypt the same record, but only one
    # compare-and-delete wins; the loser gets NotFound (same response as
    # expired/unknown) and never sees plaintext.
    class RevealSecret
      MAX_KEY_BYTES = 128

      def initialize(key:, passphrase: nil)
        @key = key
        @passphrase = passphrase
      end

      def call
        key = validate_key
        pair = Models::Secret.fetch(key)
        raise NotFound unless pair

        record, raw = pair
        verify_passphrase!(record)

        # Decrypt before consuming: if the record cannot be decrypted there is
        # nothing to reveal, and deleting it would destroy a secret the operator
        # could still recover by rotating the key back.
        plaintext = Crypto.decrypt(record)

        raise NotFound unless Models::Secret.consume(key, raw)

        Models::Secret.cleanup(key, owner_id: record["owner_id"])

        {
          secret_value: plaintext,
          metadata: {
            kind: record["kind"],
            filename: record["filename"],
            created_at: record["created_at"],
            ttl: record["ttl"]
          }
        }
      end

      private

      def validate_key
        key = @key.to_s
        raise ValidationError, "secret key is required" if key.empty?
        raise ValidationError, "secret key is invalid" if key.bytesize > MAX_KEY_BYTES

        key
      end

      def verify_passphrase!(record)
        hash = record["passphrase_hash"]
        return unless hash

        if @passphrase.nil? || @passphrase == ""
          raise PassphraseRequired
        end
        raise InvalidPassphrase unless Password.verify(hash, @passphrase)
      end
    end
  end
end
