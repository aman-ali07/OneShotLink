# frozen_string_literal: true

require "base64"
require "ipaddr"
require "json"
require "net/http"
require "openssl"
require "resolv"
require "securerandom"
require "time"
require "uri"

module Onetime
  # Owner-configured HTTP callbacks. Events are metadata only — never plaintext,
  # ciphertext, passphrases or tokens. Delivery is idempotent: one delivery id per
  # event, claimed with SET NX, and a stable X-OneShotLink-Delivery header so the
  # receiver can deduplicate too.
  module Webhook
    EVENTS = %w[
      secret.created
      secret.revealed
      request.created
      request.responded
      request.revealed
    ].freeze
    MAX_URL_BYTES = 2048
    MAX_ATTEMPTS = 3
    QUEUE_KEY = "webhook:queue"
    SEEN_PREFIX = "webhook:seen:"
    DELIVERY_PREFIX = "webhook:delivery:"
    OWNER_PREFIX = "webhook:owner:"
    ENDPOINT_PREFIX = "webhook:endpoint:"
    SEEN_DAYS = 7

    PRIVATE_NETS = %w[
      0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
      172.16.0.0/12 192.0.0.0/24 192.168.0.0/16 198.18.0.0/15
      ::/128 ::1/128 fc00::/7 fe80::/10
    ].map { |net| IPAddr.new(net) }.freeze

    CLAIM_SCRIPT = <<~LUA
      local items = redis.call('ZRANGEBYSCORE', KEYS[1], '-inf', ARGV[1], 'LIMIT', 0, ARGV[2])
      for _, item in ipairs(items) do redis.call('ZREM', KEYS[1], item) end
      return items
    LUA

    module_function

    def key(id) = "#{ENDPOINT_PREFIX}#{id}"
    def owner_index(owner_id) = "#{OWNER_PREFIX}#{owner_id}"
    def delivery_key(id) = "#{DELIVERY_PREFIX}#{id}"

    def create(owner_id:, url:, events:)
      raise ValidationError, "owner is required" if owner_id.to_s.empty?
      raise ValidationError, "url must be a string" unless url.is_a?(String)

      clean_url = validate_url!(url)
      clean_events = validate_events!(events)
      id = Ids.extid
      signing_secret = SecureRandom.hex(32)
      encrypted = JSON.generate(Crypto.encrypt(signing_secret))
      now = Time.now.to_i

      Store.redis.hset(key(id), {
        "id" => id,
        "owner_id" => owner_id,
        "url" => clean_url,
        "events" => JSON.generate(clean_events),
        # The signing secret is encrypted at rest like every other stored value.
        "signing_secret" => encrypted,
        "created_at" => now.to_s,
        "enabled" => "true"
      })
      Store.redis.zadd(owner_index(owner_id), now, id)
      {
        id: id, url: clean_url, events: clean_events, signing_secret: signing_secret,
        enabled: true, created_at: now
      }
    end

    def list(owner_id)
      Store.redis.zrevrange(owner_index(owner_id), 0, 49).filter_map do |id|
        raw = Store.redis.hgetall(key(id))
        next if raw.empty?

        {
          id: raw["id"],
          url: raw["url"],
          events: JSON.parse(raw["events"]),
          enabled: raw["enabled"] == "true",
          created_at: raw["created_at"].to_i
        }
      end
    end

    def delete(owner_id:, id:)
      raw = Store.redis.hgetall(key(id))
      raise NotFound unless raw["owner_id"] == owner_id

      Store.redis.multi do |tx|
        tx.del(key(id))
        tx.zrem(owner_index(owner_id), id)
      end
      { ok: true }
    end

    # Enqueue metadata-only events for every endpoint subscribed to that event.
    def emit(event, owner_id:, data:)
      return if owner_id.to_s.empty? || !EVENTS.include?(event)

      payload = JSON.generate("event" => event, "created_at" => Time.now.to_i, "data" => data)
      Store.redis.zrange(owner_index(owner_id), 0, -1).each do |id|
        endpoint = Store.redis.hgetall(key(id))
        next if endpoint.empty? || endpoint["enabled"] != "true"
        next unless JSON.parse(endpoint["events"]).include?(event)

        delivery_id = Ids.extid
        Store.redis.zadd(QUEUE_KEY, Time.now.to_f, JSON.generate(
          "delivery_id" => delivery_id, "endpoint_id" => id, "payload" => payload
        ))
        Store.redis.hset(delivery_key(delivery_id), {
          "status" => "queued", "event" => event, "attempts" => "0",
          "endpoint_id" => id, "created_at" => Time.now.to_i.to_s
        })
      end
    rescue StandardError => e
      # A notification failure must never break the secret/request contract.
      Onetime.logger.warn("webhook.emit_failed class=#{e.class}")
    end

    def claim(limit: 10)
      items = Store.redis.eval(CLAIM_SCRIPT, keys: [QUEUE_KEY], argv: [Time.now.to_f.to_s, limit.to_s])
      items.map { |item| JSON.parse(item) }
    end

    # Returns :delivered, :skipped, :retrying or :failed.
    def deliver(item)
      id = item.fetch("delivery_id")
      claimed = Store.redis.set("#{SEEN_PREFIX}#{id}", "1", nx: true, ex: SEEN_DAYS * 86_400)
      return :skipped unless claimed

      endpoint = Store.redis.hgetall(key(item.fetch("endpoint_id")))
      return mark(id, :skipped, "endpoint removed") if endpoint.empty?

      record = Store.redis.hgetall(delivery_key(id))
      attempts = record.fetch("attempts", "0").to_i + 1
      secret = Crypto.decrypt(JSON.parse(endpoint.fetch("signing_secret")))
      signature = OpenSSL::HMAC.hexdigest("SHA256", secret, item.fetch("payload"))

      uri = URI.parse(endpoint.fetch("url"))
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["X-OneShotLink-Event"] = record.fetch("event", "unknown")
      request["X-OneShotLink-Delivery"] = id
      request["X-OneShotLink-Signature"] = "sha256=#{signature}"
      request.body = item.fetch("payload")

      code = post(uri, request)
      if code.between?(200, 299)
        mark(id, :delivered, nil, attempts: attempts, code: code)
        :delivered
      elsif attempts < MAX_ATTEMPTS
        Store.redis.zadd(QUEUE_KEY, Time.now.to_f + (60 * attempts), JSON.generate(item))
        mark(id, :retrying, nil, attempts: attempts, code: code)
        :retrying
      else
        mark(id, :failed, nil, attempts: attempts, code: code)
        :failed
      end
    rescue StandardError => e
      mark(id, :failed, e.class.to_s, attempts: attempts.to_i, code: nil)
      :failed
    end

    def deliveries(owner_id)
      ids = Store.redis.zrange(owner_index(owner_id), 0, -1)
      # Deliveries are addressed by id; the API exposes only the owner's own
      # endpoint ids, so filter by endpoint ownership here.
      Store.redis.keys("#{DELIVERY_PREFIX}*").filter_map do |k|
        raw = Store.redis.hgetall(k)
        next unless ids.include?(raw["endpoint_id"])

        {
          id: k.delete_prefix(DELIVERY_PREFIX),
          event: raw["event"],
          status: raw["status"],
          attempts: raw["attempts"].to_i,
          response_code: raw["response_code"]&.to_i,
          created_at: raw["created_at"].to_i
        }
      end
    end

    def validate_url!(url)
      raise ValidationError, "url is too long" if url.bytesize > MAX_URL_BYTES

      uri = URI.parse(url)
      raise ValidationError, "url must use http or https" unless %w[http https].include?(uri.scheme)
      raise ValidationError, "url must have a host" if uri.host.to_s.empty?
      raise ValidationError, "url must not contain credentials" if uri.userinfo
      allowed = ENV["WEBHOOK_ALLOW_PRIVATE"] == "true"
      unless allowed
        addresses = uri.host.match?(/\A[0-9.]+\z/) ? [uri.host] : Resolv.getaddresses(uri.host)
        raise ValidationError, "url host is not publicly routable" if addresses.empty?
        addresses.each do |address|
          raise ValidationError, "url host is not publicly routable" if private_address?(address)
        end
      end
      uri.to_s
    rescue URI::InvalidURIError, Resolv::ResolvError
      raise ValidationError, "url is invalid"
    end

    def validate_events!(events)
      raise ValidationError, "events must be an array" unless events.is_a?(Array)

      clean = events.map(&:to_s).uniq
      raise ValidationError, "at least one event is required" if clean.empty?
      unknown = clean - EVENTS
      raise ValidationError, "unknown event: #{unknown.first}" unless unknown.empty?

      clean
    end

    def private_address?(address)
      ip = IPAddr.new(address)
      PRIVATE_NETS.any? { |net| net.include?(ip) }
    rescue IPAddr::InvalidAddressError
      true
    end

    def post(uri, request)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                      open_timeout: 5, read_timeout: 5, write_timeout: 5) do |http|
        http.request(request).code.to_i
      end
    end

    def mark(id, status, error, attempts: nil, code: nil)
      fields = { "status" => status.to_s, "updated_at" => Time.now.to_i.to_s }
      fields["attempts"] = attempts.to_s if attempts
      fields["response_code"] = code.to_s if code
      fields["last_error"] = error.to_s if error
      Store.redis.hset(delivery_key(id), fields)
      status
    end
  end
end
