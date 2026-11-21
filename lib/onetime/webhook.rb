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
  # Owner-configured HTTP callbacks. Payloads are metadata and opaque identifiers
  # only — never plaintext, ciphertext, passphrases or signing tokens. Request-key
  # events carry an opaque bearer identifier, not the secret itself. Delivery is
  # idempotent: one delivery id per
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
    INFLIGHT_PREFIX = "webhook:inflight:"
    INFLIGHT_TTL = 120
    DELIVERY_PREFIX = "webhook:delivery:"
    OWNER_PREFIX = "webhook:owner:"
    ENDPOINT_PREFIX = "webhook:endpoint:"
    SEEN_DAYS = 7
    # One week is enough for an operator to schedule `webhooks:work` and for
    # three backoff retries, without letting an undelivered queue grow forever.
    QUEUE_TTL = SEEN_DAYS * 86_400
    DELIVERY_TTL = SEEN_DAYS * 86_400

    PRIVATE_NETS = %w[
      0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
      172.16.0.0/12 192.0.0.0/24 192.168.0.0/16 198.18.0.0/15
      ::/128 ::1/128 fc00::/7 fe80::/10
    ].map { |net| IPAddr.new(net) }.freeze

    CLAIM_SCRIPT = <<~LUA
      -- ARGV[3] is the expiry cutoff: anything older than the queue TTL is
      -- dropped in the same atomic operation as the claim.
      redis.call('ZREMRANGEBYSCORE', KEYS[1], '-inf', ARGV[3])
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

      clean_url, pinned_ip = validate_endpoint(url)
      clean_events = validate_events!(events)
      id = Ids.extid
      signing_secret = SecureRandom.hex(32)
      encrypted = JSON.generate(Crypto.encrypt(signing_secret))
      now = Time.now.to_i

      Store.redis.hset(key(id), {
        "id" => id,
        "owner_id" => owner_id,
        "url" => clean_url,
        # Resolved once at creation. Delivery connects to this exact address so
        # a rebinding DNS answer cannot turn a public URL into an internal one.
        "resolved_ip" => pinned_ip.to_s,
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
      ids = Store.redis.zrevrange(owner_index(owner_id), 0, 49)
      return [] if ids.empty?

      # One batch instead of one HGETALL per endpoint (50 sequential RTTs).
      Store.redis.pipelined { |p| ids.each { |id| p.hgetall(key(id)) } }.filter_map do |raw|
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

      # Prune on enqueue as well as on claim: if the operator has not scheduled
      # the worker (K-46), the queue must still not grow without bound. Both
      # reads go in one pipeline: emit is on the conceal/reveal hot path, and
      # the two commands have no data dependency on each other.
      _, endpoint_ids = Store.redis.pipelined do |pipeline|
        pipeline.zremrangebyscore(QUEUE_KEY, "-inf", Time.now.to_f - QUEUE_TTL)
        pipeline.zrange(owner_index(owner_id), 0, -1)
      end

      payload = JSON.generate("event" => event, "created_at" => Time.now.to_i, "data" => data)
      enqueued_at = Time.now.to_f

      # Emit is on the conceal/reveal hot path. Fetching each endpoint and then
      # writing its delivery one command at a time cost 1 + 4N round trips;
      # batch both phases so the count is constant for any number of endpoints.
      endpoints = if endpoint_ids.empty?
                    []
                  else
                    Store.redis.pipelined { |p| endpoint_ids.each { |id| p.hgetall(key(id)) } }
                  end

      targets = endpoint_ids.each_with_index.filter_map do |id, index|
        endpoint = endpoints[index]
        next if endpoint.nil? || endpoint.empty? || endpoint["enabled"] != "true"
        next unless JSON.parse(endpoint["events"]).include?(event)

        [Ids.extid, id]
      end
      return if targets.empty?

      Store.redis.pipelined do |p|
        targets.each do |delivery_id, id|
          p.zadd(QUEUE_KEY, enqueued_at, JSON.generate(
            "delivery_id" => delivery_id, "endpoint_id" => id, "payload" => payload
          ))
          p.hset(delivery_key(delivery_id), {
            "status" => "queued", "event" => event, "attempts" => "0",
            "endpoint_id" => id, "created_at" => enqueued_at.to_i.to_s
          })
          p.expire(delivery_key(delivery_id), DELIVERY_TTL)
        end
      end
    rescue StandardError => e
      # A notification failure must never break the secret/request contract.
      Onetime.logger.warn("webhook.emit_failed class=#{e.class}")
    end

    def claim(limit: 10)
      now = Time.now.to_f
      items = Store.redis.eval(
        CLAIM_SCRIPT, keys: [QUEUE_KEY],
        argv: [now.to_s, limit.to_s, (now - QUEUE_TTL).to_s]
      )
      items.map { |item| JSON.parse(item) }
    end

    # Returns :delivered, :skipped, :retrying or :failed.
    #
    # The seen marker means "successfully delivered" — it must not be claimed
    # before the POST, or a re-queued retry would be skipped before it is ever
    # attempted. A short-lived per-attempt lock still deduplicates concurrent
    # workers pulling the same item, and is released on a retryable failure.
    def deliver(item)
      id = item.fetch("delivery_id")
      return :skipped if Store.redis.exists?("#{SEEN_PREFIX}#{id}")

      endpoint = Store.redis.hgetall(key(item.fetch("endpoint_id")))
      # The endpoint was deleted; its delivery hashes were removed by teardown.
      # Calling mark here would HSET a fresh record with no TTL, resurrecting a
      # permanent key for an endpoint that no longer exists.
      return :skipped if endpoint.empty?

      record = Store.redis.hgetall(delivery_key(id))
      attempts = record.fetch("attempts", "0").to_i + 1
      inflight = "#{INFLIGHT_PREFIX}#{id}:#{attempts}"
      unless Store.redis.set(inflight, "1", nx: true, ex: INFLIGHT_TTL)
        return :skipped
      end

      secret = Crypto.decrypt(JSON.parse(endpoint.fetch("signing_secret")))
      signature = OpenSSL::HMAC.hexdigest("SHA256", secret, item.fetch("payload"))

      uri = URI.parse(endpoint.fetch("url"))
      pinned_ip = pinned_address(endpoint)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["X-OneShotLink-Event"] = record.fetch("event", "unknown")
      request["X-OneShotLink-Delivery"] = id
      request["X-OneShotLink-Signature"] = "sha256=#{signature}"
      request.body = item.fetch("payload")

      code = post(uri, request, pinned_ip)
      if code.between?(200, 299)
        Store.redis.set("#{SEEN_PREFIX}#{id}", "1", ex: SEEN_DAYS * 86_400)
        mark(id, :delivered, nil, attempts: attempts, code: code)
        :delivered
      elsif attempts < MAX_ATTEMPTS
        Store.redis.del(inflight)
        Store.redis.zadd(QUEUE_KEY, Time.now.to_f + (60 * attempts), JSON.generate(item))
        mark(id, :retrying, nil, attempts: attempts, code: code)
        :retrying
      else
        mark(id, :failed, nil, attempts: attempts, code: code)
        :failed
      end
    rescue StandardError => e
      Store.redis.del(inflight) if inflight
      # A malformed item can raise before `id` is known. Marking with nil would
      # HSET a permanent `webhook:delivery:` key with no TTL.
      mark(id, :failed, e.class.to_s, attempts: attempts.to_i, code: nil) if id
      :failed
    end

    def owned?(owner_id, id)
      raw = Store.redis.hgetall(key(id.to_s))
      !raw.empty? && raw["owner_id"] == owner_id
    end

    def deliveries(owner_id, id: nil)
      ids = Store.redis.zrange(owner_index(owner_id), 0, -1)
      # An explicit endpoint id must belong to this owner; a foreign or unknown
      # id returns no deliveries rather than leaking another tenant's events.
      return [] if id && !ids.include?(id)

      # Deliveries are addressed by id; the API exposes only the owner's own
      # endpoint ids, so filter by endpoint ownership here.
      # SCAN instead of KEYS: a tenant listing deliveries must not block Redis
      # for every other request while it walks the whole keyspace.
      Store.redis.scan_each(match: "#{DELIVERY_PREFIX}*", count: 500).filter_map do |k|
        raw = Store.redis.hgetall(k)
        next unless ids.include?(raw["endpoint_id"])
        next if id && raw["endpoint_id"] != id

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

    # Returns [clean_url, pinned_ip]. The address is captured now so delivery
    # never has to trust a second DNS answer for the same hostname.
    def validate_endpoint(url)
      raise ValidationError, "url is too long" if url.bytesize > MAX_URL_BYTES

      uri = URI.parse(url)
      raise ValidationError, "url must use http or https" unless %w[http https].include?(uri.scheme)
      raise ValidationError, "url must have a host" if uri.host.to_s.empty?
      raise ValidationError, "url must not contain credentials" if uri.userinfo

      pinned_ip = nil
      unless ENV["WEBHOOK_ALLOW_PRIVATE"] == "true"
        addresses = resolve_addresses(uri)
        raise ValidationError, "url host is not publicly routable" if addresses.empty?
        addresses.each do |address|
          raise ValidationError, "url host is not publicly routable" if private_address?(address)
        end
        pinned_ip = addresses.first.to_s
      end
      [uri.to_s, pinned_ip]
    rescue URI::InvalidURIError, Resolv::ResolvError
      raise ValidationError, "url is invalid"
    end

    def validate_url!(url)
      validate_endpoint(url).first
    end

    def resolve_addresses(uri)
      uri.host.match?(/\A[0-9.]+\z/) ? [uri.host] : Resolv.getaddresses(uri.host)
    end

    def validate_events!(events)
      raise ValidationError, "events must be an array" unless events.is_a?(Array)

      clean = events.map(&:to_s).uniq
      raise ValidationError, "at least one event is required" if clean.empty?
      unknown = clean - EVENTS
      # Do not echo the submitted token back into an error body: messages are
      # rendered to the caller and may be copied into logs or tickets.
      raise ValidationError, "unknown event" unless unknown.empty?

      clean
    end

    def private_address?(address)
      ip = IPAddr.new(address)
      # ::ffff:127.0.0.1 and ::ffff:169.254.169.254 connect to IPv4 services,
      # so treat the mapped form as the IPv4 address it really is.
      ip = ip.native if ip.ipv4_mapped?
      PRIVATE_NETS.any? { |net| net.include?(ip) }
    rescue IPAddr::InvalidAddressError
      true
    end

    # Endpoints created before IP pinning existed have no resolved_ip. Resolve
    # and validate at delivery for those, then dial exactly that address.
    def pinned_address(endpoint)
      return "" if ENV["WEBHOOK_ALLOW_PRIVATE"] == "true"

      address = endpoint["resolved_ip"].to_s
      if address.empty?
        uri = URI.parse(endpoint.fetch("url"))
        address = resolve_addresses(uri).first.to_s
      end
      raise ValidationError, "url host is not publicly routable" if address.empty? || private_address?(address)

      address
    end

    def post(uri, request, pinned_ip = nil)
      # The IP must be set before #start opens the socket. Only the TCP
      # destination is pinned; Host and TLS SNI stay the original hostname, so
      # virtual hosting and certificate verification still work.
      # Do not let Net::HTTP discover a proxy from http_proxy/HTTP_PROXY: for
      # plain HTTP it connects to the proxy and sends an absolute-form request,
      # so the proxy re-resolves the hostname and defeats the IP pin (SSRF).
      # nil as p_addr means "no proxy" and keeps the pin authoritative.
      http = Net::HTTP.new(uri.host, uri.port, nil)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 5
      http.write_timeout = 5
      http.ipaddr = pinned_ip unless pinned_ip.to_s.empty?
      http.start { |session| session.request(request).code.to_i }
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
