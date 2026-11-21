# frozen_string_literal: true

require "openssl"
require "securerandom"

module Onetime
  # Append-only audit log for security-relevant account events.
  #
  # Backed by a Redis stream so entries are immutable and ordered. Records
  # carry identifiers and outcomes only: never passwords, passphrases, tokens,
  # or secret plaintext.
  module Audit
    STREAM = "audit:events"
    MAXLEN = 100_000

    # Closed vocabulary so dashboards/alerts can rely on stable event names.
    EVENTS = %w[
      customer.signup
      customer.signin
      customer.signin_failed
      customer.signout
      customer.password_changed
      customer.deleted
      customer.delete_failed
      customer.sessions_revoked
      secret.revealed
      secret.burned
      secret.passphrase_failed
      request.created
      request.responded
      request.revealed
      webhook.created
      webhook.deleted
      admin.role_changed
      admin.migrated
      admin.backup_exported
      admin.restored
      admin.key_rotated
      webhook.worker_run
    ].freeze

    module_function

    def record(event, actor_id: nil, request_id: nil, ip: nil, detail: nil)
      raise ArgumentError, "unknown audit event: #{event}" unless EVENTS.include?(event)

      entry = {
        "event" => event,
        "at" => Time.now.to_i.to_s
      }
      entry["actor_id"] = actor_id.to_s if actor_id
      entry["request_id"] = request_id.to_s if request_id
      # D-retention: raw IPs are personal data. Store a truncated HMAC with a
      # key that rotates daily, so events from the same source can still be
      # correlated within a day without building a long-term identifier.
      reference = ip_reference(ip)
      entry["ip_day"] = reference if reference
      entry["detail"] = detail.to_s if detail

      # Approximate trimming keeps memory bounded without blocking writers.
      Store.redis.xadd(STREAM, entry, maxlen: MAXLEN, approximate: true)
      true
    rescue Redis::BaseError => e
      # Auditing must never break a request path. Keep the correlation fields
      # so an operator can find the affected request, and count the drop so it
      # can be alerted on rather than disappearing into a log line.
      Metrics.best_effort_failure("audit")
      Onetime.logger.error(
        "audit_write_failed event=#{event} class=#{e.class} " \
        "request_id=#{request_id} actor_id=#{actor_id}"
      )
      false
    end

    # Privacy-conscious, short-lived IP correlation. The daily salt means the
    # same IP produces a different reference tomorrow; short-lived Redis
    # limiter keys remain the actual abuse-prevention control.
    def ip_reference(ip)
      return nil if ip.to_s.empty?

      day = Time.now.to_i / 86_400
      key = Crypto.derive(Config.secret!, "ots-audit-ip/v1:#{day}")
      OpenSSL::HMAC.hexdigest("SHA256", key, ip.to_s)[0, 12]
    end
    private_class_method :ip_reference

    # Newest-first slice for an operator-facing listing.
    def recent(limit: 50)
      safe_limit = limit.to_i.clamp(1, 1000)
      entries = Store.redis.xrevrange(STREAM, "+", "-", count: safe_limit)
      entries.map do |id, fields|
        { id: id }.merge(fields)
      end
    end
  end
end
