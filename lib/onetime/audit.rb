# frozen_string_literal: true

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
      customer.sessions_revoked
      secret.revealed
      secret.passphrase_failed
      admin.role_changed
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
      entry["ip"] = ip.to_s if ip
      entry["detail"] = detail.to_s if detail

      # Approximate trimming keeps memory bounded without blocking writers.
      Store.redis.xadd(STREAM, entry, maxlen: MAXLEN, approximate: true)
      true
    rescue Redis::BaseError => e
      # Auditing must never break a request path; surface the failure in logs.
      Onetime.logger.error("audit_write_failed event=#{event} class=#{e.class}")
      false
    end

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
