# frozen_string_literal: true

module Onetime
  module Logic
    # Permanently destroys an unrevealed secret on its owner's instruction,
    # without decrypting or returning it. The atomic compare-and-delete is the
    # same primitive reveal uses, so a reveal racing a burn leaves exactly one
    # winner and no plaintext. The receipt becomes `burned` with D-receipt's
    # 30-day metadata retention; no secret content is ever written to it.
    class BurnSecret

      def initialize(key:, owner_id:)
        @key = key.to_s
        @owner_id = owner_id.to_s
      end

      def call
        key = validate_key
        raise NotFound if @owner_id.empty?

        pair = Models::Secret.fetch(key)
        raise NotFound unless pair

        record, raw = pair
        # Authenticate the record before trusting owner_id for authorization.
        Models::Secret.verify_meta!(record)
        raise NotFound unless record["owner_id"] == @owner_id

        raise NotFound unless Models::Secret.consume(key, raw)

        begin
          Models::Secret.finalize_receipt(key, status: "burned", owner_id: @owner_id)
        rescue Redis::BaseError => e
          # Housekeeping after the irreversible delete must not turn a successful
          # burn into an error. Never log the key: it is a bearer credential.
          Metrics.best_effort_failure("cleanup")
          Onetime.logger.warn("post_consume_cleanup_failed class=#{e.class}")
        end

        { ok: true, metadata: { identifier: key, status: "burned" } }
      end

      private

      def validate_key
        raise ValidationError, "secret key is required" if @key.empty?
        raise ValidationError, "secret key is invalid" if @key.bytesize > Ids::MAX_KEY_BYTES

        @key
      end
    end
  end
end
