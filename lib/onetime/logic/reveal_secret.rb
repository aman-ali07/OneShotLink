# frozen_string_literal: true

module Onetime
  module Logic
    # Verify first, consume atomically second, decrypt last.
    #
    # A wrong passphrase never reaches the delete. Two concurrent reveals both
    # read the same record, but only one compare-and-delete wins; the loser gets
    # NotFound (same response as expired/unknown).
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

        raise NotFound unless Models::Secret.consume(key, raw)

        plaintext = Crypto.decrypt(record)
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
