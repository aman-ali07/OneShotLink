# frozen_string_literal: true

require "oj"
require "roda"
require "securerandom"

require_relative "head_requests"
require_relative "request_logger"
require_relative "openapi"

module Onetime
  module Web
    # Roda app: health/config, API v1 (legacy) and API v3 (guest + owner).
    # Routes validate at the boundary; domain rules live in lib/onetime/logic.
    class App < Roda
      PUBLIC_ROOT = File.expand_path("../../../public/app", __dir__)
      INDEX_PATH = File.join(PUBLIC_ROOT, "index.html")
      SESSION_COOKIE = "ots_session"

      plugin :error_handler
      plugin :halt
      plugin :public, root: PUBLIC_ROOT,
                     headers: { "Cache-Control" => "public, max-age=31536000, immutable" }

      CONTENT_SECURITY_POLICY = [
        "default-src 'self'",
        "base-uri 'self'",
        "object-src 'none'",
        "frame-ancestors 'none'",
        "form-action 'self'",
        "img-src 'self' data:",
        "style-src 'self'",
        "script-src 'self'",
        "connect-src 'self'",
        "font-src 'self'",
        "manifest-src 'self'",
        "worker-src 'self'"
      ].join("; ").freeze

      plugin :default_headers,
             "Content-Type" => "application/json; charset=utf-8",
             "Content-Security-Policy" => CONTENT_SECURITY_POLICY,
             "X-Content-Type-Options" => "nosniff",
             "X-Frame-Options" => "DENY",
             "Referrer-Policy" => "no-referrer",
             "Permissions-Policy" => "camera=(), microphone=(), geolocation=(), payment=(), usb=()",
             "Cross-Origin-Opener-Policy" => "same-origin",
             "Cross-Origin-Resource-Policy" => "same-origin",
             "X-Permitted-Cross-Domain-Policies" => "none"

      def json(payload, status: nil)
        response.status = status if status
        Oj.dump(payload, mode: :compat)
      end

      def request_id
        env["onetime.request_id"] ||= SecureRandom.uuid
      end

      def logger
        Onetime.logger
      end

      def error_body(code, message, extra = {})
        { error: { code: code, message: message, request_id: request_id }.merge(extra) }
      end

      def api_version
        env["onetime.api_version"] || "v3"
      end

      def health_response
        redis_ok = Store.healthy?
        status = redis_ok ? 200 : 503
        body = {
          status: redis_ok ? "ok" : "degraded",
          redis: redis_ok ? "ok" : "error",
          version: VERSION
        }
        [status, body]
      end

      def public_config
        {
          ttl_options: Config.ttl_options,
          default_ttl: Config.default_ttl,
          auth_mode: Config.auth_mode,
          ui_enabled: Config.ui_enabled?,
          max_secret_bytes: Config.max_secret_bytes,
          version: VERSION
        }
      end

      def index_path
        INDEX_PATH
      end

      def serve_index
        unless Config.ui_enabled? && File.file?(index_path)
          return v3_not_found
        end

        response["Content-Type"] = "text/html; charset=utf-8"
        response["Cache-Control"] = "no-cache"
        response["X-Robots-Tag"] = "noindex, nofollow"
        File.read(index_path)
      end

      # Do not use Rack's request.ip here: it trusts X-Forwarded-For from any
      # client. Only an explicitly configured proxy hop may supply the header.
      def client_id
        remote = parse_ip(env["REMOTE_ADDR"])
        return env["REMOTE_ADDR"].to_s if remote.nil? || !Config.trust_proxy?
        return remote.to_s unless trusted_proxy?(remote)

        forwarded = env["HTTP_X_FORWARDED_FOR"].to_s.split(",").map { |part| parse_ip(part) }.compact
        client = remote
        forwarded.reverse_each do |ip|
          next if trusted_proxy?(ip)

          client = ip
          break
        end
        client.to_s
      end

      def parse_ip(raw)
        value = raw.to_s.strip
        return nil if value.empty?

        value = value[/\A\[(.+)\](?::\d+)?\z/, 1] || value
        value = value.sub(/:\d+\z/, "") if value.count(":") == 1 && value.include?(".")
        IPAddr.new(value)
      rescue IPAddr::Error
        nil
      end

      def trusted_proxy?(ip)
        Config.trusted_proxies.any? { |network| network.include?(ip) }
      rescue Config::Error
        false
      end

      # Never passes secret material: only identifiers, request id, and IP.
      def audit(event, actor_id: nil, detail: nil)
        Audit.record(event, actor_id: actor_id, request_id: request_id, ip: client_id, detail: detail)
      end

      def enforce_rate_limit!(scope)
        result = Limiter.check!(
          client_id,
          scope: scope,
          limit: Config.rate_limit(scope),
          window: Config.rate_limit_window
        )
        set_rate_limit_headers(result)
      rescue Onetime::RateLimited => e
        # Remember which scope tripped so the error handler can emit headers.
        e.instance_variable_set(:@scope, scope)
        raise
      end

      def set_rate_limit_headers(result)
        return if result.nil? || result.limit.to_i <= 0

        response["X-RateLimit-Limit"] = result.limit.to_s
        response["X-RateLimit-Remaining"] = result.remaining.to_s
        response["X-RateLimit-Reset"] = result.reset.to_s
      end

      # Recompute headers for the 429 path: enforce_rate_limit! raises before
      # it can set them, so the error handler asks the limiter what is left.
      def set_rate_limit_headers_for(scope)
        set_rate_limit_headers(
          Limiter.snapshot(
            client_id,
            scope: scope,
            limit: Config.rate_limit(scope),
            window: Config.rate_limit_window
          )
        )
      rescue StandardError
        nil
      end

      def parse_json_body
        unless request.content_type.to_s.include?("application/json")
          raise ValidationError, "Content-Type must be application/json"
        end

        limit = Config.max_secret_bytes + 16_384
        raise PayloadTooLarge if env["CONTENT_LENGTH"].to_i > limit

        # CONTENT_LENGTH is advisory for chunked requests; cap the actual read
        # so a client cannot make the process allocate an unbounded body.
        raw = request.body.read(limit + 1)
        request.body.rewind
        raise PayloadTooLarge if raw.bytesize > limit
        parsed = JSON.parse(raw)
        raise ValidationError, "Body must be a JSON object" unless parsed.is_a?(Hash)

        parsed
      rescue JSON::ParserError
        raise ValidationError, "Malformed JSON body"
      end

      def reveal_payload(key, passphrase: nil)
        result = Logic::RevealSecret.new(key: key, passphrase: passphrase).call
        audit("secret.revealed", detail: result[:metadata][:kind])
        json(result)
      rescue InvalidPassphrase => e
        audit("secret.passphrase_failed")
        raise e
      end

      def cookies
        @cookies ||= Rack::Utils.parse_cookies(env)
      end

      def session_token
        cookies[SESSION_COOKIE]
      end

      def current_session
        return @current_session if defined?(@current_session)

        @current_session = session_token && Models::Session.fetch(session_token)
      end

      def current_customer
        return @current_customer if defined?(@current_customer)

        @current_customer = current_session && Models::Customer.find(current_session[:customer_id])
      end

      def set_session_cookie(token)
        Rack::Utils.set_cookie_header!(response.headers, SESSION_COOKIE, {
          value: token,
          path: "/",
          max_age: Config.session_ttl,
          secure: Config.ssl?,
          httponly: true,
          same_site: :lax
        })
      end

      def clear_session_cookie
        Rack::Utils.set_cookie_header!(response.headers, SESSION_COOKIE, {
          value: "",
          path: "/",
          max_age: 0,
          expires: Time.at(0),
          secure: Config.ssl?,
          httponly: true,
          same_site: :lax
        })
      end

      # Account routes exist only in simple mode; full mode fails closed and
      # disabled mode hides/disables them rather than pretending they work.
      def require_accounts!
        raise NotConfigured if Config.full_mode?
        return if Config.auth_mode == "simple"

        raise Forbidden, "Accounts are disabled on this instance."
      end

      # Cookie-authenticated mutations must come from our own origin. Browsers
      # send Sec-Fetch-Site/Origin; non-browser clients with a session cookie
      # must send Origin too. No cookie means no CSRF authority to abuse.
      def verify_csrf!
        return unless session_token

        return if env["HTTP_SEC_FETCH_SITE"] == "same-origin"

        origin = env["HTTP_ORIGIN"].to_s
        raise Forbidden, "Cross-site request rejected." if origin.empty?

        uri = URI.parse(origin)
        raise Forbidden, "Cross-site request rejected." unless uri.host == request.host
      rescue URI::InvalidURIError
        raise Forbidden, "Cross-site request rejected."
      end

      def require_session!
        raise NotConfigured if Config.full_mode?
        return nil if Config.auth_mode == "disabled"

        current_customer || raise(Unauthorized, "Sign in is required.")
      end

      def account_payload
        { customer: Models::Customer.public_view(current_customer) }
      end

      def receipts_payload(customer)
        ids = Store.redis.zrevrange(Models::Secret.owner_index(customer[:id]), 0, 49)
        receipts = ids.filter_map do |objid|
          receipt = Store.redis.hgetall(Models::Secret.receipt_key(objid))
          if receipt.empty?
            Store.redis.zrem(Models::Secret.owner_index(customer[:id]), objid)
            next
          end

          {
            identifier: objid,
            secret_ttl: receipt["ttl"].to_i,
            created_at: receipt["created_at"].to_i,
            passphrase_required: receipt["passphrase"] == "1",
            kind: receipt["kind"],
            secret_url: "/secret/#{objid}"
          }
        end
        { receipts: receipts }
      end

      def legacy_not_found
        response.status = 404
        json({ message: "Not found." })
      end

      def v3_not_found
        response.status = 404
        json(error_body("not_found", "Not found."))
      end

      def create_v3(owner_id: nil)
        enforce_rate_limit!(:conceal)
        body = parse_json_body
        result = Logic::ConcealSecret.new(
          secret: body["secret"],
          ttl: body["ttl"],
          passphrase: body["passphrase"],
          owner_id: owner_id,
          kind: body["kind"]
        ).call
        json(result, status: 201)
      end

      def create_v1(r)
        env["onetime.api_version"] = "v1"
        raise PayloadTooLarge if env["CONTENT_LENGTH"].to_i > (Config.max_secret_bytes + 16_384)

        enforce_rate_limit!(:conceal)

        params = if request.content_type.to_s.include?("application/json")
                   parse_json_body
                 else
                   r.params
                 end

        result = Logic::ConcealSecret.new(
          secret: params["secret"],
          ttl: params["ttl"],
          passphrase: params["passphrase"]
        ).call

        json({
          secret_key: result[:secret_key],
          receipt: result[:receipt].slice(:identifier, :secret_ttl, :passphrase_required)
        })
      end

      def reveal_v1(key)
        env["onetime.api_version"] = "v1"
        enforce_rate_limit!(:reveal)
        result = Logic::RevealSecret.new(key: key).call
        json({ secret_value: result[:secret_value], metadata: result[:metadata] })
      end

      route do |r|
        response["X-Request-Id"] = request_id
        response["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains" if Config.ssl?
        if r.path.start_with?("/api", "/health")
          response["Cache-Control"] = "no-store"
          response["Pragma"] = "no-cache"
        end

        # The shell must revalidate; hashed assets are immutable (public plugin).
        r.get true do
          serve_index
        end

        r.get "index.html" do
          serve_index
        end

        # Hashed Vite assets and other public files. Deep links fall through to
        # the SPA fallback below.
        r.public

        r.get "health" do
          status, body = health_response
          response.status = status
          json(body)
        end

        r.on "api" do
          r.on "v1" do
            env["onetime.api_version"] = "v1"

            r.post "share" do
              create_v1(r)
            end

            r.on "secret", String do |key|
              r.get true do
                reveal_v1(key)
              end

              r.post true do
                reveal_v1(key)
              end

              r.get(/.*/) { legacy_not_found }
              r.post(/.*/) { legacy_not_found }
            end

            legacy_not_found
          end

          r.on "v3" do
            r.get "health" do
              status, body = health_response
              response.status = status
              json(body)
            end

            r.get "config" do
              json(public_config)
            end

            r.get "openapi.json" do
              response["Content-Type"] = "application/json; charset=utf-8"
              json(OpenApi.document)
            end

            r.post "signup" do
              require_accounts!
              enforce_rate_limit!(:signin)
              body = parse_json_body
              result = Logic::SignUp.new(email: body["email"], password: body["password"]).call
              set_session_cookie(result[:session_token])
              audit("customer.signup", actor_id: result[:customer][:id])
              json({ customer: result[:customer] }, status: 201)
            end

            r.post "signin" do
              require_accounts!
              enforce_rate_limit!(:signin)
              body = parse_json_body
              result = Logic::SignIn.new(email: body["email"], password: body["password"]).call
              set_session_cookie(result[:session_token])
              audit("customer.signin", actor_id: result[:customer][:id])
              json({ customer: result[:customer] })
            rescue InvalidCredentials => e
              audit("customer.signin_failed")
              raise e
            end

            r.post "signout" do
              require_accounts!
              verify_csrf!
              actor = current_customer
              Models::Session.destroy(session_token)
              clear_session_cookie
              audit("customer.signout", actor_id: actor && actor[:id])
              json({ ok: true })
            end

            r.on "account" do
              r.get "me" do
                require_accounts!
                require_session!
                json(account_payload)
              end

              r.get "receipts" do
                require_accounts!
                customer = require_session!
                json(receipts_payload(customer))
              end

              r.post "password" do
                require_accounts!
                verify_csrf!
                customer = require_session!
                body = parse_json_body
                current = body["current_password"]
                replacement = body["new_password"]
                unless Models::Customer.authenticate(customer[:email], current)
                  raise InvalidCredentials
                end
                unless replacement.is_a?(String) && replacement.bytesize.between?(12, 256)
                  raise ValidationError, "new_password must be 12 to 256 characters"
                end

                Models::Customer.update_password(customer[:id], replacement)
                # A password change is a credential reset: every other live
                # session must stop working. Keep the caller signed in.
                revoked = Models::Session.revoke_all(customer[:id], except_token: session_token)
                audit("customer.password_changed", actor_id: customer[:id])
                audit("customer.sessions_revoked", actor_id: customer[:id], detail: revoked.to_s)
                json({ ok: true })
              end

              r.get(/.*/) { v3_not_found }
              r.post(/.*/) { v3_not_found }
            end

            r.on "guest" do
              r.post "conceal" do
                owner = current_customer
                verify_csrf! if owner
                create_v3(owner_id: owner && owner[:id])
              end

              r.on "secret", String do |key|
                r.post "reveal" do
                  enforce_rate_limit!(:reveal)
                  body = parse_json_body
                  reveal_payload(key, passphrase: body["passphrase"])
                end

                r.get true do
                  enforce_rate_limit!(:reveal)
                  reveal_payload(key)
                end

                r.get(/.*/) { v3_not_found }
                r.post(/.*/) { v3_not_found }
              end

              r.get(/.*/) { v3_not_found }
              r.post(/.*/) { v3_not_found }
            end

            # Owner-scoped aliases. Auth disabled => anonymous allowed.
            r.on "secret" do
              r.post "conceal" do
                owner = require_session!
                verify_csrf!
                create_v3(owner_id: owner && owner[:id])
              end

              r.on String do |key|
                r.post "reveal" do
                  require_session!
                  verify_csrf!
                  enforce_rate_limit!(:reveal)
                  body = parse_json_body
                  reveal_payload(key, passphrase: body["passphrase"])
                end

                r.get true do
                  require_session!
                  enforce_rate_limit!(:reveal)
                  reveal_payload(key)
                end

                r.get(/.*/) { v3_not_found }
                r.post(/.*/) { v3_not_found }
              end

              r.get(/.*/) { v3_not_found }
              r.post(/.*/) { v3_not_found }
            end

            r.get(/.*/) { v3_not_found }
            r.post(/.*/) { v3_not_found }
          end

          response.status = 404
          json(error_body("not_found", "Not found."))
        end

        # SPA fallback once the Vite build exists. Until then, a clear JSON 404.
        r.get(/.*/) do
          serve_index
        end

        response.status = 404
        json(error_body("not_found", "Not found."))
      end

      error do |error|
        if api_version == "v1"
          response.status = error.respond_to?(:status) ? error.status : 500
          if error.is_a?(Onetime::RateLimited)
            response["Retry-After"] = Config.rate_limit_window.to_s
            scope = error.instance_variable_get(:@scope)
            set_rate_limit_headers_for(scope) if scope
          end
          message = error.is_a?(Onetime::Error) ? error.message : "An internal error occurred."
          json({ message: message })
        else
          case error
          when Onetime::RateLimited
            response.status = 429
            response["Retry-After"] = Config.rate_limit_window.to_s
            scope = error.instance_variable_get(:@scope)
            set_rate_limit_headers_for(scope) if scope
            json(error_body(error.code, error.message))
          when Onetime::Error
            response.status = error.status
            json(error_body(error.code, error.message))
          else
            # Never include exception messages that could carry request data.
            logger.error("unhandled_error class=#{error.class} request_id=#{request_id}")
            response.status = 500
            json(error_body("internal_error", "An internal error occurred."))
          end
        end
      end
    end
  end
end
