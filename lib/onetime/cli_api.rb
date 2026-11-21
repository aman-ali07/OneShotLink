# frozen_string_literal: true

require "cgi"
require "ipaddr"
require "json"
require "net/http"
require "uri"

module Onetime
  # Stdlib-only HTTP client for the operator CLI. It uses the same public v3
  # endpoints as the examples — never a second Redis write path — so a CLI
  # reveal has exactly the same single-use semantics as the web UI.
  module CliApi
    module_function

    def base_url
      raw = ENV["OTS_URL"]
      if raw.nil? || raw.empty?
        # HOST is usually a bare hostname in production with SSL=true and a
        # TLS terminator in front of the app. Honour that instead of silently
        # sending the secret over plaintext HTTP.
        scheme = Config.ssl? ? "https" : "http"
        raw = "#{scheme}://#{ENV['HOST'] || '127.0.0.1:3000'}"
      else
        raw = "https://#{raw}" unless raw.start_with?("http://", "https://")
      end

      uri = URI.parse(raw)
      raise Error, "OTS_URL must use http or https" unless %w[http https].include?(uri.scheme)

      if uri.scheme == "http" && !loopback?(uri.host) && ENV["OTS_ALLOW_INSECURE"] != "1"
        raise Error, "Refusing to send a secret over plaintext HTTP to #{uri.host}; " \
                     "use https:// or set OTS_ALLOW_INSECURE=1 on an isolated network"
      end
      uri
    end

    def loopback?(host)
      return true if %w[localhost 127.0.0.1 ::1].include?(host.to_s.downcase)

      IPAddr.new(host.to_s).loopback?
    rescue IPAddr::InvalidAddressError
      false
    end

    def conceal(secret:, ttl: 1800, passphrase: nil)
      body = { secret: secret, ttl: ttl }
      body[:passphrase] = passphrase unless passphrase.to_s.empty?
      payload = request(Net::HTTP::Post, "/api/v3/guest/conceal", body)
      key = payload["secret_key"]
      raise Error, "API response has no secret_key" if key.to_s.empty?

      { secret_key: key, link: link_for(key) }
    end

    def reveal(key:, passphrase: nil)
      body = {}
      body[:passphrase] = passphrase unless passphrase.to_s.empty?
      path = "/api/v3/guest/secret/#{CGI.escape(key)}/reveal"
      payload = request(Net::HTTP::Post, path, body)
      payload["secret_value"]
    end

    def link_for(key)
      uri = base_url.dup
      uri.path = "/secret/#{key}"
      uri.query = nil
      uri.to_s
    end

    def request(klass, path, body)
      uri = base_url.dup
      uri.path = path
      message = klass.new(uri)
      message["Content-Type"] = "application/json"
      message.body = JSON.generate(body)
      response = Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 5
      ) { |http| http.request(message) }
      parse(response)
    end

    def parse(response)
      payload = JSON.parse(response.body.to_s)
      unless response.code.to_i.between?(200, 299)
        detail = payload.dig("error", "message") || payload["message"] || "request failed"
        raise Error, "API #{response.code}: #{detail}"
      end
      payload
    rescue JSON::ParserError
      raise Error, "API #{response.code}: invalid JSON response"
    end
  end
end
