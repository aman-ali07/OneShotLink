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

        get_env = env.dup
        get_env["REQUEST_METHOD"] = "GET"
        status, headers, body = @app.call(get_env)
        body.close if body.respond_to?(:close)
        [status, headers, []]
      end
    end
  end
end
