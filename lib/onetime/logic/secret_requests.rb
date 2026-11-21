# frozen_string_literal: true

module Onetime
  module Logic
    # Owner creates a public link that accepts exactly one secret.
    class CreateSecretRequest
      MAX_LABEL_BYTES = 120
      DEFAULT_LABEL = "A secret for you"

      def initialize(owner_id:, label: nil, ttl: nil)
        @owner_id = owner_id
        @label = label
        @ttl = ttl
      end

      def call
        raise ValidationError, "sign in to create a request" if @owner_id.to_s.empty?

        label = validate_label
        ttl = validate_ttl
        key, record = Models::SecretRequest.create(owner_id: @owner_id, label: label, ttl: ttl)
        Webhook.emit("request.created", owner_id: @owner_id,
                     data: { request_key: key, label: label, ttl: ttl })
        { request_key: key, metadata: { label: record["label"], created_at: record["created_at"], ttl: ttl } }
      end

      private

      def validate_label
        return DEFAULT_LABEL if @label.nil? || @label == ""

        raise ValidationError, "label must be a string" unless @label.is_a?(String)

        label = @label.strip
        raise ValidationError, "label is too long" if label.bytesize > MAX_LABEL_BYTES
        raise ValidationError, "label contains unsupported characters" if label.match?(/[\u0000-\u001F\u007F]/)

        label
      end

      def validate_ttl
        Config.valid_ttl!(@ttl)
      end
    end

    # A responder submits one secret. SET NX makes the "only one answer" rule
    # atomic even when two people open the link at the same time.
    class SubmitToRequest
      def initialize(key:, secret:)
        @key = key.to_s
        @secret = secret
      end

      def call
        raise ValidationError, "request key is required" if @key.empty? || @key.bytesize > Ids::MAX_KEY_BYTES
        raise ValidationError, "secret must be a string" unless @secret.is_a?(String)
        raise ValidationError, "secret cannot be empty" if @secret.empty?
        raise PayloadTooLarge if @secret.bytesize > Config.max_secret_bytes

        pair = Models::SecretRequest.fetch(@key)
        raise NotFound unless pair

        record, = pair
        Models::SecretRequest.verify_meta!(record, key: @key)

        # An answer must never outlive the request it answers. Use the remaining
        # TTL of the request object, not its original full lifetime.
        remaining = Store.redis.ttl(Models::SecretRequest.object_key(@key))
        raise NotFound if remaining == -2
        # Redis reports 0 in the final sub-second of a key's life; accepting an
        # answer then would need the full-TTL fallback below and would leave an
        # orphan after the request expired. The fallback now only covers -1 (a
        # TTL-less key, e.g. from a legacy restore).
        raise NotFound if remaining.zero?

        raw = JSON.generate(Crypto.encrypt(@secret))
        ttl = remaining == -1 ? record["ttl"].to_i : remaining
        written = Models::SecretRequest.submit(@key, raw, ttl: ttl)
        raise Conflict, "This request has already been answered." unless written

        Webhook.emit("request.responded", owner_id: record["owner_id"],
                     data: { request_key: @key, label: record["label"].to_s })
        { ok: true, label: record["label"].to_s }
      end
    end

    # The owner reveals the submitted secret once. Decryption runs before the
    # compare-and-delete so a rotated SECRET cannot destroy the submission.
    class RevealRequestSubmission
      def initialize(key:, owner_id:)
        @key = key.to_s
        @owner_id = owner_id.to_s
      end

      def call
        raise ValidationError, "request key is invalid" if @key.empty? || @key.bytesize > Ids::MAX_KEY_BYTES

        pair = Models::SecretRequest.fetch(@key)
        raise NotFound unless pair

        record, = pair
        # Authenticate the record before trusting owner_id for authorization.
        Models::SecretRequest.verify_meta!(record, key: @key)
        raise NotFound unless record["owner_id"] == @owner_id

        raw = Store.redis.get(Models::SecretRequest.submission_key(@key))
        raise NotFound, "No secret has been submitted to this request yet." if raw.nil?

        plaintext = Crypto.decrypt(JSON.parse(raw))
        # One atomic step: delete the submission AND retire the bearer object.
        # Doing them separately left a window for a second answer to be written
        # to the now-free submission key while the link was still live.
        raise NotFound unless Models::SecretRequest.consume_and_retire(@key, raw)

        cleanup_owner_index(record["owner_id"])
        Webhook.emit("request.revealed", owner_id: @owner_id,
                     data: { request_key: @key, label: record["label"].to_s })
        {
          secret_value: plaintext,
          metadata: {
            kind: "text",
            filename: nil,
            label: record["label"],
            created_at: record["created_at"].to_i,
            ttl: record["ttl"].to_i
          }
        }
      end

      private

      # Housekeeping after the irreversible consume: a failure must not turn an
      # already-delivered secret into an error. Count and log the class only —
      # the key is a bearer credential and must never be logged (AGENTS rule 7).
      def cleanup_owner_index(owner_id)
        Models::SecretRequest.cleanup(@key, owner_id: owner_id)
      rescue Redis::BaseError => e
        Onetime.logger.warn("request_cleanup_failed class=#{e.class}")
        Metrics.best_effort_failure("cleanup")
      end
    end
  end
end
