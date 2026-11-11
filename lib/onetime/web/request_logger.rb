# frozen_string_literal: true

module Onetime
  module Web
    # One line per request, with no query string, body, cookies, or IP. That
    # keeps tokens and passphrases out of logs while still giving operators
    # latency/status visibility.
    class RequestLogger
      ASSET_PATH = %r{\A/assets/}
      SAFE_PATH = %r{[^[:print:]]}
      SECRET_PATH = %r{(/api/v[13]/(?:guest/)?secret/)[^/]+}
      UI_SECRET_PATH = %r{(\A/secret/)[^/]+}

      def initialize(app, logger: Onetime.logger)
        @app = app
        @logger = logger
      end

      def call(env)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        status, headers, body = @app.call(env)
        log(env, status, headers, started)
        [status, headers, body]
      rescue StandardError => e
        log(env, 500, {}, started, error: e.class)
        raise
      end

      private

      def log(env, status, headers, started, error: nil)
        path = env["PATH_INFO"].to_s.gsub(SAFE_PATH, "")
        return if path.match?(ASSET_PATH)

        # Secret keys are bearer credentials. Keep them out of logs even though
        # the rest of the path is useful for routing/status diagnostics.
        path = path.gsub(SECRET_PATH, '\\1<redacted>').gsub(UI_SECRET_PATH, '\\1<redacted>')

        duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2)
        request_id = headers["X-Request-Id"] || env["onetime.request_id"] || "-"
        fields = [
          "method=#{env['REQUEST_METHOD']}",
          "path=#{path[0, 200]}",
          "status=#{status}",
          "duration_ms=#{duration}",
          "request_id=#{request_id}",
          ("error=#{error}" if error)
        ].compact
        @logger.info("request #{fields.join(' ')}")
      end
    end
  end
end
