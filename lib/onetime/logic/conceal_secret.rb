# frozen_string_literal: true

require "base64"

module Onetime
  module Logic
    # Create a one-time secret after validating every boundary value.
    class ConcealSecret
      # A one- or two-character passphrase is not an access gate: the per-IP
      # reveal limiter alone would let it fall in a minute of guessing (D-014).
      # Records created before this floor still reveal — the check is on create.
      MIN_PASSPHRASE_BYTES = 8
      MAX_PASSPHRASE_BYTES = 256
      # A file travels as strict base64 inside the JSON body, which is capped at
      # MAX_SECRET_BYTES + 16 KiB. 512 KiB decodes to ~699 KiB of base64, leaving
      # room for the envelope and keeping the existing body ceiling intact.
      MAX_FILE_BYTES = 512 * 1024
      MAX_FILENAME_BYTES = 255
      SAFE_FILENAME = %r{\A[^\x00-\x1F\x7F\\/]{1,255}\z}.freeze
      SUPPORTED_KINDS = %w[text file].freeze

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
        validate_filename
        validate_file_payload if @kind == "file"

        objid, = Models::Secret.create(
          plaintext: content,
          ttl: ttl,
          passphrase: passphrase,
          owner_id: @owner_id,
          kind: @kind,
          filename: @filename
        )

        Webhook.emit("secret.created", owner_id: @owner_id,
                     data: { identifier: objid, kind: @kind, ttl: ttl })

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
        Config.valid_ttl!(@ttl)
      end

      def validate_passphrase
        return nil if @passphrase.nil? || @passphrase == ""
        raise ValidationError, "passphrase must be a string" unless @passphrase.is_a?(String)
        raise ValidationError, "passphrase cannot be empty" if @passphrase.empty?
        if @passphrase.bytesize < MIN_PASSPHRASE_BYTES
          raise ValidationError, "passphrase must be at least #{MIN_PASSPHRASE_BYTES} characters"
        end
        raise ValidationError, "passphrase is too long" if @passphrase.bytesize > MAX_PASSPHRASE_BYTES

        @passphrase
      end

      def validate_kind
        return if SUPPORTED_KINDS.include?(@kind)

        raise ValidationError, "kind must be one of: #{SUPPORTED_KINDS.join(', ')}"
      end

      # Filenames are metadata, not paths. Reject separators, control characters
      # and the relative-path markers so a download can never escape its folder.
      def validate_filename
        return if @kind != "file"

        raise ValidationError, "filename is required for a file" unless @filename.is_a?(String)
        unless @filename.bytesize.between?(1, MAX_FILENAME_BYTES) && SAFE_FILENAME.match?(@filename)
          raise ValidationError, "filename contains unsupported characters"
        end
        return unless [".", ".."].include?(@filename)

        raise ValidationError, "filename contains unsupported characters"
      end

      # The payload stays base64 (ASCII) in the encrypted record: Crypto.decrypt
      # forces UTF-8, which would corrupt arbitrary binary bytes.
      def validate_file_payload
        decoded = begin
          Base64.strict_decode64(@secret)
        rescue ArgumentError
          raise ValidationError, "file payload must be base64"
        end
        raise PayloadTooLarge, "file is too large" if decoded.bytesize > MAX_FILE_BYTES
      end
    end
  end
end
