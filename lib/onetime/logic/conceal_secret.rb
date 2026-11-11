# frozen_string_literal: true

module Onetime
  module Logic
    # Create a one-time secret after validating every boundary value.
    class ConcealSecret
      MAX_PASSPHRASE_BYTES = 256
      SUPPORTED_KINDS = %w[text].freeze

      def initialize(secret:, ttl: nil, passphrase: nil, owner_id: nil, kind: "text", filename: nil)
        @secret = secret
        @ttl = ttl
        @passphrase = passphrase
        @owner_id = owner_id
        @kind = kind || "text"
        @filename = filename
      end

      def call
        content = validate_secret
        ttl = validate_ttl
        passphrase = validate_passphrase
        validate_kind

        objid, = Models::Secret.create(
          plaintext: content,
          ttl: ttl,
          passphrase: passphrase,
          owner_id: @owner_id,
          kind: @kind,
          filename: @filename
        )

        {
          secret_key: objid,
          receipt: {
            identifier: objid,
            secret_ttl: ttl,
            passphrase_required: !passphrase.nil?,
            kind: @kind
          },
          links: { secret: "/secret/#{objid}" }
        }
      end

      private

      def validate_secret
        raise ValidationError, "secret must be a string" unless @secret.is_a?(String)
        raise ValidationError, "secret cannot be empty" if @secret.empty?
        raise PayloadTooLarge if @secret.bytesize > Config.max_secret_bytes

        @secret
      end

      def validate_ttl
        ttl = begin
          Integer(@ttl.nil? ? Config.default_ttl : @ttl)
        rescue ArgumentError, TypeError
          raise ValidationError, "ttl must be an integer number of seconds"
        end

        unless Config.ttl_options.include?(ttl)
          raise ValidationError, "ttl must be one of: #{Config.ttl_options.join(', ')}"
        end

        ttl
      end

      def validate_passphrase
        return nil if @passphrase.nil? || @passphrase == ""
        raise ValidationError, "passphrase must be a string" unless @passphrase.is_a?(String)
        raise ValidationError, "passphrase cannot be empty" if @passphrase.empty?
        raise ValidationError, "passphrase is too long" if @passphrase.bytesize > MAX_PASSPHRASE_BYTES

        @passphrase
      end

      def validate_kind
        return if SUPPORTED_KINDS.include?(@kind)

        raise ValidationError, "kind must be one of: #{SUPPORTED_KINDS.join(', ')}"
      end
    end
  end
end
