# frozen_string_literal: true

module Onetime
  # In-process request metrics in Prometheus text exposition format.
  #
  # Deliberately tiny: counters and a latency sum/count, guarded by a mutex.
  # No new dependency and no background thread. Counters are per-process, so
  # scrape every worker (or scrape a load-balanced endpoint) to see totals.
  module Metrics
    # Bounded label set — never interpolate a secret key or raw path into a
    # label, or cardinality grows without limit.
    FAMILIES = %w[health metrics web api_v1 api_v3 api_v3_guest other].freeze

    class << self
      def record(family:, status:, duration:)
        bucket = status_bucket(status)
        key = [normalize_family(family), bucket]

        lock.synchronize do
          requests[key] += 1
          durations_sum[key[0]] += duration.to_f
          durations_count[key[0]] += 1
          # Assign the ivar directly: `errors += 1` would create a local
          # variable rather than call the reader/writer pair.
          @errors = (@errors || 0) + 1 if bucket == "5xx"
        end
      rescue StandardError
        # Metrics must never break a request.
        nil
      end

      # Snapshot for tests and rendering.
      def snapshot
        lock.synchronize do
          {
            requests: requests.dup,
            durations_sum: durations_sum.dup,
            durations_count: durations_count.dup,
            errors: errors
          }
        end
      end

      def reset!
        lock.synchronize do
          @requests = Hash.new(0)
          @durations_sum = Hash.new(0.0)
          @durations_count = Hash.new(0)
          @errors = 0
        end
      end

      # Basic sanity on the family label so a caller typo cannot explode labels.
      def normalize_family(family)
        value = family.to_s
        FAMILIES.include?(value) ? value : "other"
      end

      def status_bucket(status)
        code = status.to_i
        return "other" if code < 100 || code > 599

        "#{code / 100}xx"
      end

      def render(redis_memory: nil, redis_up: true)
        snap = snapshot
        lines = []

        lines << "# HELP onetime_up 1 when the application is serving requests."
        lines << "# TYPE onetime_up gauge"
        lines << "onetime_up 1"

        lines << "# HELP onetime_redis_up 1 when Redis answered PING."
        lines << "# TYPE onetime_redis_up gauge"
        lines << "onetime_redis_up #{redis_up ? 1 : 0}"

        lines << "# HELP onetime_version_info Build version, always 1."
        lines << "# TYPE onetime_version_info gauge"
        lines << %(onetime_version_info{version="#{VERSION}"} 1)

        lines << "# HELP onetime_requests_total HTTP requests by route family and status class."
        lines << "# TYPE onetime_requests_total counter"
        snap[:requests].sort.each do |(family, bucket), count|
          lines << %(onetime_requests_total{family="#{family}",status="#{bucket}"} #{count})
        end

        lines << "# HELP onetime_errors_total 5xx responses."
        lines << "# TYPE onetime_errors_total counter"
        lines << "onetime_errors_total #{snap[:errors]}"

        lines << "# HELP onetime_request_duration_seconds_sum Total request time by route family."
        lines << "# TYPE onetime_request_duration_seconds_sum counter"
        snap[:durations_sum].sort.each do |family, sum|
          lines << %(onetime_request_duration_seconds_sum{family="#{family}"} #{format("%.6f", sum)})
        end

        lines << "# HELP onetime_request_duration_seconds_count Request count by route family."
        lines << "# TYPE onetime_request_duration_seconds_count counter"
        snap[:durations_count].sort.each do |family, count|
          lines << %(onetime_request_duration_seconds_count{family="#{family}"} #{count})
        end

        append_redis_memory(lines, redis_memory)

        lines.join("\n") + "\n"
      end

      private

      def append_redis_memory(lines, memory)
        return unless memory

        used = memory[:used].to_i
        max = memory[:max].to_i

        lines << "# HELP onetime_redis_memory_used_bytes Redis used_memory in bytes."
        lines << "# TYPE onetime_redis_memory_used_bytes gauge"
        lines << "onetime_redis_memory_used_bytes #{used}"

        lines << "# HELP onetime_redis_memory_max_bytes Redis maxmemory in bytes (0 = unlimited)."
        lines << "# TYPE onetime_redis_memory_max_bytes gauge"
        lines << "onetime_redis_memory_max_bytes #{max}"

        # The alerting threshold is a ratio: alert at >= 0.8.
        return if max <= 0

        lines << "# HELP onetime_redis_memory_used_ratio used_memory / maxmemory."
        lines << "# TYPE onetime_redis_memory_used_ratio gauge"
        lines << format("onetime_redis_memory_used_ratio %.6f", used.to_f / max)
      end

      def lock
        @lock ||= Mutex.new
      end

      def requests
        @requests ||= Hash.new(0)
      end

      def durations_sum
        @durations_sum ||= Hash.new(0.0)
      end

      def durations_count
        @durations_count ||= Hash.new(0)
      end

      def errors
        @errors ||= 0
      end
    end
  end
end
