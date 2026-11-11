# frozen_string_literal: true

module Onetime
  module Logic
    # Re-encrypt every stored secret under a new instance secret.
    #
    # Changing SECRET would otherwise orphan every live secret (they can no
    # longer be decrypted). This walks the object keyspace, decrypts each
    # record with the current key, re-encrypts with the new one, and rewrites
    # the record in place with its remaining TTL preserved.
    #
    # Plaintext only ever lives in a local variable; nothing is logged.
    class RotateKey
      BATCH = 200

      def initialize(new_secret:)
        @new_secret = new_secret
      end

      def call
        raise ValidationError, "new secret is too short" if @new_secret.to_s.bytesize < 32

        reencrypted = 0
        skipped = 0

        each_object_key do |key, raw|
          record = parse(raw)
          if record.nil?
            skipped += 1
            next
          end

          begin
            plaintext = Crypto.decrypt(record)
          rescue Onetime::Error
            # A record we cannot decrypt is already unreadable; leave it alone
            # rather than destroying data we do not understand.
            skipped += 1
            next
          end

          reencrypted_payload = reencrypt(plaintext)
          rewritten = record.reject { |k, _| %w[ciphertext iv tag salt cipher].include?(k) }
                            .merge(reencrypted_payload)
          ttl = Store.redis.ttl(key)
          new_raw = JSON.generate(rewritten)
          if ttl.positive?
            Store.redis.set(key, new_raw, keepttl: true)
          else
            Store.redis.set(key, new_raw)
          end
          reencrypted += 1
        end

        { reencrypted: reencrypted, skipped: skipped }
      end

      private

      def each_object_key
        cursor = "0"
        loop do
          cursor, keys = Store.redis.scan(cursor, match: "#{Models::Secret::OBJECT_PREFIX}*", count: BATCH)
          keys.each do |key|
            raw = Store.redis.get(key)
            next if raw.nil?

            yield key, raw
          end
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
