# frozen_string_literal: true

require "securerandom"

module Onetime
  module Web
    # Serve HEAD exactly like GET, then discard the body. Roda routes and the
    # static-file plugin only match GET, so relying on Rack::Head alone would
    # turn every HEAD request into a 404.
    class HeadRequests
      def initialize(app)
        @app = app
      end

      def call(env)
        return @app.call(env) unless env["REQUEST_METHOD"] == "HEAD"

        # The frozen v1 GET consumes the secret (SECURITY.md), while this
        # middleware rewrites HEAD to GET and then drops the body. An
        # unfurl/bot HEAD would therefore destroy the secret without ever
        # delivering it. HEAD must stay side-effect-free, so refuse it here.
        if env["PATH_INFO"].to_s.match?(%r{\A/api/v1/secret/.})
          # This middleware sits outside Roda, so its early return must carry
          # the same hardening headers the app would have set on any response.
          return [405, rejection_headers(env), []]
        end

        get_env = env.dup
        get_env["REQUEST_METHOD"] = "GET"
        status, headers, body = @app.call(get_env)
        body.close if body.respond_to?(:close)
        [status, headers, []]
      end

      private

      def rejection_headers(env)
        env["onetime.request_id"] ||= SecureRandom.uuid
        # Reuse the app's single canonical header set. Hand-listing headers here
        # let the 405 silently lag the rest of the app when a header is added
        # (SA-18); merging keeps every future header on this early return too.
        Onetime::Web::App::HARDENING_HEADERS.merge(
          "Allow" => "GET, POST",
          "Content-Type" => "application/json; charset=utf-8",
          "Cache-Control" => "no-store",
          "X-Request-Id" => env["onetime.request_id"]
        )
      end
    end
  end
end
