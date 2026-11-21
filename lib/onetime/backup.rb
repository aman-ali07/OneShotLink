# frozen_string_literal: true

require "json"
require "time"
require_relative "migrate"

module Onetime
  # Point-in-time export of the Redis state that matters for restore.
  #
  # Every secret record is exported exactly as stored: still encrypted under
  # the instance SECRET. A backup file therefore leaks no plaintext, and it is
  # only restorable by an instance holding the same SECRET (or after a key
  # rotation, the rotated one).
  #
  # Format 2 adds inbound requests and webhook state. Format 1 files remain
  # restorable. Ephemeral dedup state (webhook:seen:*, webhook:inflight:*), the
  # audit stream and live session digests (customer:sessions:*) are deliberately
  # excluded: replaying them would be wrong.
  module Backup
    FORMAT_VERSION = 2
    SUPPORTED_FORMATS = [1, 2].freeze
    # A backup is a point-in-time view of a schema, not just of keys. Without
    # this marker a restore onto an empty instance leaves schema:version at 0
    # while the restored data is already at version 1's shape, so the next
    # migration would re-run against migrated records.
    SCHEMA_FIELD = "schema_version"

    # Literal prefixes: this file is required before the model constants exist.
    SECTIONS = {
      "secret" => "secret:object:",
      "receipt" => "secret:receipt:",
      "customer" => "customer:",
      "request_object" => "request:object:",
      "request_secret" => "request:secret:",
      "webhook_endpoint" => "webhook:endpoint:",
      "webhook_owner" => "webhook:owner:",
      "webhook_queue" => "webhook:queue",
      "webhook_delivery" => "webhook:delivery:"
    }.freeze
    DENIED_PREFIXES = %w[customer:sessions: webhook:seen: webhook:inflight: limiter: audit:].freeze

    module_function

    def export(path)
      payload = {
        "format" => FORMAT_VERSION,
        "exported_at" => Time.now.utc.iso8601,
        SCHEMA_FIELD => Migrate.current_version
      }
      SECTIONS.each do |name, prefix|
        payload[name] = name == "secret" ? collect_secrets : collect_typed(prefix)
      end

      tmp = "#{path}.tmp"
      # The export contains Argon2id password hashes and customer emails. Create
      # it owner-only from the first byte rather than inheriting the process umask.
      File.unlink(tmp) if File.exist?(tmp)
      File.open(tmp, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(JSON.pretty_generate(payload))
      end
      File.rename(tmp, path)
      {
        secrets: payload["secret"].length,
        receipts: payload["receipt"].length,
        customers: payload["customer"].length,
        requests: payload["request_object"].length + payload["request_secret"].length,
        webhooks: payload["webhook_endpoint"].length + payload["webhook_owner"].length +
                  payload["webhook_queue"].length + payload["webhook_delivery"].length
      }
    end

    # Restores export() output into the current Redis. Returns counts.
    #
    # A restore is destructive: without `force` it refuses to overwrite keys
    # that already exist, so an old backup cannot silently resurrect consumed
    # secrets or replace live customer records.
    def restore(path, force: false)
      data = JSON.parse(File.read(path))
      unless SUPPORTED_FORMATS.include?(data["format"])
        raise Error, "Unsupported backup format: #{data['format'].inspect}"
      end

      keys = backup_keys(data)
      validate_keys!(keys)
      validate_entries!(data)
      # Pre-flight: refuse a corrupt/future marker before writing any key.
      schema_version = validate_schema_version!(data)

      unless force
        existing = keys.count { |key| Store.redis.exists?(key) }
        raise Error, "Refusing to overwrite #{existing} live key(s); pass --force to restore anyway" if existing.positive?
      end

      counts = {}
      SECTIONS.each_key do |section|
        counts[section.to_sym] = restore_section(section, data[section] || {})
      end
      Store.redis.set(Migrate::SCHEMA_KEY, schema_version.to_s) if schema_version
      {
        secrets: counts[:secret],
        receipts: counts[:receipt],
        customers: counts[:customer],
        requests: counts[:request_object] + counts[:request_secret],
        webhooks: counts[:webhook_endpoint] + counts[:webhook_owner] +
                  counts[:webhook_queue] + counts[:webhook_delivery]
      }
    end

    # A backup only ever contains these namespaces. Deny ephemeral/credential
    # keys even when they share a permitted prefix (customer:sessions:*), so a
    # substituted file cannot plant live sessions on restore (D-016).
    def restorable_prefixes
      SECTIONS.values
    end
    private_class_method :restorable_prefixes

    def backup_keys(data)
      keys = SECTIONS.keys.flat_map { |section| (data[section] || {}).keys }
      # The marker is real state: include it in the overwrite check so a
      # non-forced restore cannot silently replace a live schema version.
      keys << Migrate::SCHEMA_KEY if data.key?(SCHEMA_FIELD)
      keys
    end
    private_class_method :backup_keys

    # Pre-flight entry validation: a bad `type` used to be discovered halfway
    # through the restore, after earlier sections had overwritten live keys.
    def validate_entries!(data)
      SECTIONS.each_key do |section|
        entries = data[section] || {}
        raise Error, "Backup section #{section} must be an object" unless entries.is_a?(Hash)

        entries.each do |key, entry|
          raise Error, "Backup entry #{key} must be an object" unless entry.is_a?(Hash)

          kind = entry["type"] || (entry.key?("raw") ? "raw" : (entry["value"].is_a?(Hash) ? "hash" : "string"))
          expected = { "raw" => String, "string" => String, "hash" => Hash, "zset" => Array, "set" => Array }
          unless expected.key?(kind)
            raise Error, "Backup entry #{key} has unsupported type: #{kind.inspect}"
          end
          payload = kind == "raw" ? entry["raw"] : entry["value"]
          unless payload.is_a?(expected.fetch(kind))
            raise Error, "Backup entry #{key} has a malformed #{kind} payload"
          end

          # Encrypted payloads and submitted answers must expire: a bare SET on
          # restore resurrects a TTL-less record as an immortal secret. Match on
          # the key's namespace, not just its section, so a substituted backup
          # cannot dodge the guard by filing a secret key elsewhere. A missing
          # ttl fails here too (`nil.to_i` used to become a bare SET downstream).
          # Receipts carry customer emails; deliveries carry endpoint metadata.
          # Both are supposed to expire (30 d / 7 d), so a tampered backup must
          # not be able to plant permanent copies of either.
          expires_must_be_positive =
            kind == "raw" ||
            key.start_with?("secret:object:", "secret:receipt:", "request:object:",
                            "request:secret:", "webhook:delivery:")
          if expires_must_be_positive
            ttl = Integer(entry["ttl"], exception: false)
            raise Error, "Backup entry #{key} is a secret without a TTL" unless ttl&.positive?
          end
        end
      end
    end
    private_class_method :validate_entries!

    def validate_keys!(keys)
      bad = keys.reject do |key|
        (key == Migrate::SCHEMA_KEY || restorable_prefixes.any? { |prefix| key.start_with?(prefix) }) &&
          DENIED_PREFIXES.none? { |prefix| key.start_with?(prefix) }
      end
      raise Error, "Backup contains #{bad.length} key(s) outside the restorable namespaces" unless bad.empty?
    end
    private_class_method :validate_keys!

    # Parse and bound the marker during pre-flight so a corrupt or future
    # schema version is refused before a single key is written.
    def validate_schema_version!(data)
      return nil unless data.key?(SCHEMA_FIELD)

      version = begin
        Integer(data[SCHEMA_FIELD])
      rescue ArgumentError, TypeError
        raise Error, "Backup #{SCHEMA_FIELD} is not an integer"
      end
      unless version.between?(0, Migrate::TARGET_VERSION)
        raise Error, "Backup schema version #{version} is outside 0..#{Migrate::TARGET_VERSION}"
      end

      # A forced restore must never move a migrated instance backwards. Once
      # schema:version exists, `Migrate.apply!` uses SET NX, so stamping a lower
      # value would leave the marker permanently stuck below the real shape.
      current = Migrate.current_version
      if version < current
        raise Error, "Backup schema version #{version} is older than live #{current}"
      end

      version
    end
    private_class_method :validate_schema_version!

    def ttl_of(key)
      value = Store.redis.ttl(key)
      value.positive? ? value : 0
    end
    private_class_method :ttl_of

    # Generic collector for hashes, strings, zsets and sets. The secret namespace
    # keeps its raw+ttl shape so CAS-compatible bytes survive the round trip.
    def collect_typed(prefix)
      out = {}
      scan_keys("#{prefix}*").each do |key|
        # Session digests and other denied namespaces are live/transient state,
        # not portable backups (same rule as validate_keys! in pre-flight).
        next if DENIED_PREFIXES.any? { |prefix| key.start_with?(prefix) }

        entry = case Store.redis.type(key)
                when "string" then { "type" => "string", "value" => Store.redis.get(key) }
                when "hash" then { "type" => "hash", "value" => Store.redis.hgetall(key) }
                when "zset"
                  pairs = Store.redis.zrange(key, 0, -1, with_scores: true)
                  { "type" => "zset", "value" => pairs.map { |member, score| [member, score] } }
                when "set" then { "type" => "set", "value" => Store.redis.smembers(key) }
                end
        next unless entry

        entry["ttl"] = ttl_of(key)
        out[key] = entry
      end
      out
    end
    private_class_method :collect_typed

    def restore_section(section, entries)
      count = 0
      entries.each do |key, entry|
        ttl = entry["ttl"].to_i
        kind = entry["type"] || (entry.key?("raw") ? "raw" : (entry["value"].is_a?(Hash) ? "hash" : "string"))
        case kind
        when "raw"
          ttl.positive? ? Store.redis.set(key, entry["raw"], ex: ttl) : Store.redis.set(key, entry["raw"])
        when "string"
          ttl.positive? ? Store.redis.set(key, entry["value"], ex: ttl) : Store.redis.set(key, entry["value"])
        when "hash"
          Store.redis.hset(key, entry["value"])
          Store.redis.expire(key, ttl) if ttl.positive?
        when "zset"
          pairs = entry["value"].map { |member, score| [score, member] }
          Store.redis.zadd(key, pairs) unless pairs.empty?
          Store.redis.expire(key, ttl) if ttl.positive?
        when "set"
          Store.redis.sadd(key, entry["value"]) unless entry["value"].empty?
          Store.redis.expire(key, ttl) if ttl.positive?
        else
          raise Error, "Unsupported backup entry type: #{kind.inspect}"
        end
        count += 1
      end
      count
    end
    private_class_method :restore_section

    def collect_secrets
      out = {}
      scan_keys("#{Models::Secret::OBJECT_PREFIX}*").each do |key|
        raw = Store.redis.get(key)
        next unless raw

        out[key] = { "raw" => raw, "ttl" => ttl_of(key) }
      end
      out
    end
    private_class_method :collect_secrets

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
