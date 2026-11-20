# frozen_string_literal: true

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
          return [405, { "Allow" => "GET, POST" }, []]
        end

        get_env = env.dup
        get_env["REQUEST_METHOD"] = "GET"
        status, headers, body = @app.call(get_env)
        body.close if body.respond_to?(:close)
        [status, headers, []]
      end
    end
  end
end
