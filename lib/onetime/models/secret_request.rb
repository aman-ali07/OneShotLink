# frozen_string_literal: true

module Onetime
  module Models
    # A public link that lets anyone send one secret to the request's owner.
    #
    # The request itself is a JSON string with a TTL. The submitted secret is a
    # separate encrypted JSON string guarded by SET NX, so exactly one responder
    # can win; the owner consumes it with the same compare-and-delete used by
    # ordinary secrets. No plaintext is ever stored.
    module SecretRequest
      OBJECT_PREFIX = "request:object:"
      SUBMISSION_PREFIX = "request:secret:"
      OWNER_INDEX_SUFFIX = ":requests"

      # Authorization here reads owner_id from this record, so it must be
      # authenticated like a secret record. Reuse Secret's HMAC primitive with
      # a distinct domain separator and field set (no new crypto).
      META_VERSION = 2
      # request_key binds the MAC to this Redis key so a donor record's
      # metadata+MAC cannot be transplanted onto another request.
      META_FIELDS = %w[v owner_id label created_at ttl request_key].freeze
      META_SALT = "ots-request-meta/v1"

      def verify_meta!(record, key: nil)
        Models::Secret.verify_meta!(record, fields: META_FIELDS, salt: META_SALT, version: META_VERSION)
        if key && record["request_key"].to_s != key.to_s
          raise Onetime::Error, "Stored request failed integrity verification"
        end
      end
      module_function :verify_meta!

      module_function

      def object_key(key) = "#{OBJECT_PREFIX}#{key}"
      def submission_key(key) = "#{SUBMISSION_PREFIX}#{key}"
      def owner_index(owner_id) = "customer:#{owner_id}#{OWNER_INDEX_SUFFIX}"

      def create(owner_id:, label:, ttl:)
        key = Ids.extid
        record = {
          "owner_id" => owner_id,
          "label" => label,
          "created_at" => Time.now.to_i,
          "ttl" => ttl,
          "request_key" => key
        }
        Models::Secret.sign_meta!(record, fields: META_FIELDS, salt: META_SALT, version: META_VERSION)
        raw = JSON.generate(record)
        Store.redis.multi do |tx|
          tx.set(object_key(key), raw, ex: ttl)
          index = owner_index(owner_id)
          tx.zadd(index, record["created_at"], key)
          tx.expire(index, Models::Secret.index_ttl(ttl))
        end
        [key, record]
      end

      def fetch(key)
        raw = Store.redis.get(object_key(key))
        return nil unless raw

        [JSON.parse(raw), raw]
      rescue JSON::ParserError
        nil
      end

      def list(owner_id, limit: 50)
        keys = Store.redis.zrevrange(owner_index(owner_id), 0, limit - 1)
        return [] if keys.empty?

        # One batch for all records and one for all submission flags: a
        # per-item GET + EXISTS made a 50-row listing cost 100 Redis RTTs.
        results = Store.redis.pipelined do |p|
          keys.each do |key|
            p.get(object_key(key))
            p.exists?(submission_key(key))
          end
        end
        records = results.each_slice(2).map(&:first)
        flags = results.each_slice(2).map { |pair| pair[1] }

        keys.each_with_index.filter_map do |key, index|
          raw = records[index]
          next unless raw

          record = begin
            JSON.parse(raw)
          rescue JSON::ParserError
            next
          end
          {
            request_key: key,
            label: record["label"],
            created_at: record["created_at"].to_i,
            ttl: record["ttl"].to_i,
            fulfilled: flags[index] == 1 || flags[index] == true
          }
        end
      end

      def submit(key, raw, ttl:)
        Store.redis.set(submission_key(key), raw, nx: true, ex: ttl)
      end

      # Consume the submission and retire the bearer link in ONE atomic step.
      # A separate DEL left a window where the submission slot was free but the
      # request object still accepted a second answer (TOCTOU).
      def consume_and_retire(key, raw)
        Store.consume_request(submission_key(key), object_key(key), raw)
      end

      def cleanup(key, owner_id:)
        Store.redis.zrem(owner_index(owner_id), key)
      end
    end
  end
end
