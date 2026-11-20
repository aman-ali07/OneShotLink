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

      module_function

      def object_key(key) = "#{OBJECT_PREFIX}#{key}"
      def submission_key(key) = "#{SUBMISSION_PREFIX}#{key}"
      def owner_index(owner_id) = "customer:#{owner_id}#{OWNER_INDEX_SUFFIX}"

      def create(owner_id:, label:, ttl:)
        key = Ids.extid
        record = {
          "v" => 1,
          "owner_id" => owner_id,
          "label" => label,
          "created_at" => Time.now.to_i,
          "ttl" => ttl
        }
        raw = JSON.generate(record)
        Store.redis.multi do |tx|
          tx.set(object_key(key), raw, ex: ttl)
          tx.zadd(owner_index(owner_id), record["created_at"], key)
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
        keys.filter_map do |key|
          pair = fetch(key)
          next unless pair

          record, = pair
          {
            request_key: key,
            label: record["label"],
            created_at: record["created_at"].to_i,
            ttl: record["ttl"].to_i,
            fulfilled: Store.redis.exists?(submission_key(key))
          }
        end
      end

      def submit(key, raw, ttl:)
        Store.redis.set(submission_key(key), raw, nx: true, ex: ttl)
      end

      def fetch_submission(key)
        raw = Store.redis.get(submission_key(key))
        raw && JSON.parse(raw)
      end

      def consume_submission(key, raw)
        Store.consume(submission_key(key), raw)
      end
    end
  end
end
