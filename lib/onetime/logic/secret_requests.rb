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
        ttl = begin
          Integer(@ttl.nil? ? Config.default_ttl : @ttl)
        rescue ArgumentError, TypeError
          raise ValidationError, "ttl must be an integer number of seconds"
        end
        raise ValidationError, "ttl must be one of: #{Config.ttl_options.join(', ')}" unless Config.ttl_options.include?(ttl)

        ttl
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
        raise ValidationError, "request key is required" if @key.empty? || @key.bytesize > 128
        raise ValidationError, "secret must be a string" unless @secret.is_a?(String)
        raise ValidationError, "secret cannot be empty" if @secret.empty?
        raise PayloadTooLarge if @secret.bytesize > Config.max_secret_bytes

        pair = Models::SecretRequest.fetch(@key)
        raise NotFound unless pair

        record, = pair
        raw = JSON.generate(Crypto.encrypt(@secret))
        written = Models::SecretRequest.submit(@key, raw, ttl: record["ttl"].to_i)
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
        pair = Models::SecretRequest.fetch(@key)
        raise NotFound unless pair

        record, = pair
        raise NotFound unless record["owner_id"] == @owner_id

        raw = Store.redis.get(Models::SecretRequest.submission_key(@key))
        raise NotFound, "No secret has been submitted to this request yet." if raw.nil?

        plaintext = Crypto.decrypt(JSON.parse(raw))
        raise NotFound unless Models::SecretRequest.consume_submission(@key, raw)

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
    end
  end
end
