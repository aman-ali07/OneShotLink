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

      def initialize(key:, passphrase: nil)
        @key = key
        @passphrase = passphrase
      end

      def call
        key = validate_key
        # Reject malformed gate input at the boundary, before the guess budget:
        # a non-string passphrase is not a guess, and must never spend one.
        unless @passphrase.nil? || @passphrase.is_a?(String)
          raise ValidationError, "passphrase must be a string"
        end
        # Mirror the create-side ceiling: an over-long guess cannot be a valid
        # passphrase, and must not reach Argon2id or spend a guess slot.
        if @passphrase.is_a?(String) && @passphrase.bytesize > ConcealSecret::MAX_PASSPHRASE_BYTES
          raise ValidationError, "passphrase is too long"
        end
        pair = Models::Secret.fetch(key)
        raise NotFound unless pair

        record, raw = pair
        # Reject a record whose access-control or display metadata was edited
        # after it was written (e.g. a stripped passphrase_hash). This runs
        # before the passphrase gate, the decrypt and the irreversible consume.
        Models::Secret.verify_meta!(record)
        # D-012b: a per-secret budget for actual guesses, using the same Redis
        # Lua limiter as every other scope. Keyed by the opaque secret id, so
        # no IP or other personal data is stored; a wrong guess still never
        # reaches the consume. Requests without a passphrase are not guesses.
        check_passphrase_budget!(record, key)
        verify_passphrase!(record)

        # Decrypt before consuming: if the record cannot be decrypted there is
        # nothing to reveal, and deleting it would destroy a secret the operator
        # could still recover by rotating the key back.
        plaintext = Crypto.decrypt(record)

        raise NotFound unless Models::Secret.consume(key, raw)

        # Receipt/index cleanup is housekeeping: both expire with the record's
        # TTL. A datastore failure here must not turn an already-consumed,
        # successfully-decrypted secret into an error the recipient has to
        # retry (retrying is a 404 — the value is already gone). Log and count
        # it instead. Never log the key: it is a bearer credential.
        begin
          Models::Secret.finalize_receipt(key, status: "revealed", owner_id: record["owner_id"])
        rescue Redis::BaseError => e
          Metrics.best_effort_failure("cleanup")
          Onetime.logger.warn("post_consume_cleanup_failed class=#{e.class}")
        end

        Webhook.emit("secret.revealed", owner_id: record["owner_id"],
                     data: { identifier: key, kind: record["kind"], ttl: record["ttl"].to_i })

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

      def check_passphrase_budget!(record, key)
        # Only a record that actually has a gate can be guessed; an unprotected
        # secret must not have its budget consumed by a stray passphrase field.
        return unless record["passphrase_hash"]
        return if @passphrase.nil? || @passphrase.empty?

        Limiter.check!(
          key,
          scope: :passphrase,
          limit: Config.rate_limit(:passphrase),
          window: Config.passphrase_attempt_window
        )
      rescue Onetime::RateLimited => e
        # The generic error handler derives Retry-After and X-RateLimit-* from
        # the scope. This budget is keyed by secret id and uses a longer window,
        # so carry both so the 429 still honours API.md's header contract.
        e.instance_variable_set(:@scope, :passphrase)
        e.instance_variable_set(:@id, key)
        e.instance_variable_set(:@window, Config.passphrase_attempt_window)
        raise
      end

      def validate_key
        key = @key.to_s
        raise ValidationError, "secret key is required" if key.empty?
        raise ValidationError, "secret key is invalid" if key.bytesize > Ids::MAX_KEY_BYTES

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
