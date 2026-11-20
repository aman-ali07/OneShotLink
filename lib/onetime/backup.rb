# frozen_string_literal: true

require "json"
require "time"

module Onetime
  # Point-in-time export of the Redis state that matters for restore.
  #
  # Every secret record is exported exactly as stored: still encrypted under
  # the instance SECRET. A backup file therefore leaks no plaintext, and it is
  # only restorable by an instance holding the same SECRET (or after a key
  # rotation, the rotated one).
  module Backup
    FORMAT_VERSION = 1

    module_function

    def export(path)
      payload = {
        "format" => FORMAT_VERSION,
        "exported_at" => Time.now.utc.iso8601,
        "secret" => collect_secrets,
        "receipt" => collect_receipts,
        "customer" => collect_customers
      }

      tmp = "#{path}.tmp"
      File.write(tmp, JSON.pretty_generate(payload))
      File.rename(tmp, path)
      {
        secrets: payload["secret"].length,
        receipts: payload["receipt"].length,
        customers: payload["customer"].length
      }
    end

    # Restores export() output into the current Redis. Returns counts.
    def restore(path)
      data = JSON.parse(File.read(path))
      raise Error, "Unknown backup format" unless data["format"] == FORMAT_VERSION

      secrets = 0
      (data["secret"] || {}).each do |key, entry|
        ttl = entry["ttl"].to_i
        raw = entry["raw"]
        if ttl.positive?
          Store.redis.set(key, raw, ex: ttl)
        else
          Store.redis.set(key, raw)
        end
        secrets += 1
      end

      receipts = 0
      (data["receipt"] || {}).each do |key, entry|
        Store.redis.hset(key, entry["value"])
        ttl = entry["ttl"].to_i
        Store.redis.expire(key, ttl) if ttl.positive?
        receipts += 1
      end

      customers = 0
      (data["customer"] || {}).each do |key, entry|
        case entry["type"]
        when "hash"
          Store.redis.hset(key, entry["value"])
        when "string"
          Store.redis.set(key, entry["value"])
        when "zset"
          pairs = entry["value"].map { |member, score| [score, member] }
          Store.redis.zadd(key, pairs) unless pairs.empty?
        when "set"
          Store.redis.sadd(key, entry["value"]) unless entry["value"].empty?
        end
        customers += 1
      end

      { secrets: secrets, receipts: receipts, customers: customers }
    end

    def collect_secrets
      out = {}
      scan_keys("#{Models::Secret::OBJECT_PREFIX}*").each do |key|
        raw = Store.redis.get(key)
        next unless raw

        ttl = Store.redis.ttl(key)
        out[key] = { "raw" => raw, "ttl" => ttl.positive? ? ttl : 0 }
      end
      out
    end
    private_class_method :collect_secrets

    # Owner receipts are metadata, not plaintext, but the dashboard needs them
    # after a restore. They are hashes with the same TTL as their secret.
    def collect_receipts
      out = {}
      scan_keys("#{Models::Secret::RECEIPT_PREFIX}*").each do |key|
        value = Store.redis.hgetall(key)
        next if value.empty?

        ttl = Store.redis.ttl(key)
        out[key] = { "value" => value, "ttl" => ttl.positive? ? ttl : 0 }
      end
      out
    end
    private_class_method :collect_receipts

    # Customer records and their indexes; never session keys (those are
    # ephemeral credentials and should not be resurrected by a restore).
    def collect_customers
      out = {}
      scan_keys("customer:*").each do |key|
        next if key.start_with?(Models::Session::INDEX_PREFIX)

        type = Store.redis.type(key)
        case type
        when "hash"
          out[key] = { "type" => "hash", "value" => Store.redis.hgetall(key) }
        when "string"
          out[key] = { "type" => "string", "value" => Store.redis.get(key) }
        when "zset"
          entries = Store.redis.zrange(key, 0, -1, with_scores: true)
          out[key] = { "type" => "zset", "value" => entries.map { |m, s| [m, s] } }
        when "set"
          out[key] = { "type" => "set", "value" => Store.redis.smembers(key) }
        end
      end
      out
    end
    private_class_method :collect_customers

    def scan_keys(pattern)
      cursor = "0"
      keys = []
      loop do
        cursor, batch = Store.redis.scan(cursor, match: pattern, count: 500)
        keys.concat(batch)
        break if cursor == "0"
      end
      keys
    end
    private_class_method :scan_keys
  end
end
