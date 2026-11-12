# frozen_string_literal: true

module Onetime
  module Web
    # The OpenAPI 3.1 description of this service's HTTP surface.
    #
    # Hand-maintained alongside API.md: it is intentionally explicit rather than
    # generated, because the contract (v1 legacy shape vs v3 native JSON) is the
    # thing worth pinning. `spec/integration/openapi_spec.rb` asserts every
    # documented path/method is actually mounted and that the document parses.
    module OpenApi
      module_function

      def document
        {
          "openapi" => "3.1.0",
          "info" => {
            "title" => "OneShotLink API",
            "version" => VERSION,
            "description" => "Create a single-use secret, share the link, and let it be revealed exactly once."
          },
          "servers" => [{ "url" => "/" }],
          "tags" => [
            { "name" => "meta", "description" => "Health and configuration" },
            { "name" => "guest", "description" => "Anonymous secret lifecycle (v3)" },
            { "name" => "owner", "description" => "Session-scoped secret lifecycle (v3)" },
            { "name" => "account", "description" => "Simple-mode accounts" },
            { "name" => "legacy", "description" => "v1 compatibility surface" }
          ],
          "paths" => paths,
          "components" => components
        }
      end

      def paths
        {
          "/health" => {
            "get" => op(
              "meta",
              "Liveness and Redis health",
              responses: {
                "200" => json_ref("HealthOk"),
                "503" => json_ref("Error")
              }
            )
          },
          "/api/v3/health" => {
            "get" => op(
              "meta",
              "Liveness and Redis health (versioned)",
              responses: { "200" => json_ref("HealthOk"), "503" => json_ref("Error") }
            )
          },
          "/api/v3/config" => {
            "get" => op(
              "meta",
              "Public configuration for the UI",
              responses: { "200" => json_ref("PublicConfig") }
            )
          },
          "/api/v3/guest/conceal" => {
            "post" => op(
              "guest",
              "Create a secret",
              body: "ConcealRequest",
              responses: {
                "201" => json_ref("ConcealResponse"),
                "413" => json_ref("Error"),
                "422" => json_ref("Error"),
                "429" => rate_limited,

                "503" => json_ref("Error")
              }
            )
          },
          "/api/v3/guest/secret/{key}" => {
            "get" => op(
              "guest",
              "Reveal a secret exactly once",
              params: [key_param],
              responses: {
                "200" => json_ref("RevealResponse"),
                "401" => json_ref("Error"),
                "404" => json_ref("Error"),
                "429" => rate_limited,

                "503" => json_ref("Error")
              }
            )
          },
          "/api/v3/guest/secret/{key}/reveal" => {
            "post" => op(
              "guest",
              "Reveal a passphrase-protected secret",
              params: [key_param],
              body: "RevealRequest",
              responses: {
                "200" => json_ref("RevealResponse"),
                "401" => json_ref("Error"),
                "404" => json_ref("Error"),
                "429" => rate_limited,

                "503" => json_ref("Error")
              }
            )
          },
          "/api/v3/secret/conceal" => {
            "post" => op(
              "owner",
              "Create a secret owned by the signed-in customer",
              body: "ConcealRequest",
              security: [{ cookie: [] }],
              responses: {
                "201" => json_ref("ConcealResponse"),
                "401" => json_ref("Error"),
                "403" => json_ref("Error"),
                "429" => rate_limited,

                "503" => json_ref("Error")
              }
            )
          },
          "/api/v3/secret/{key}" => {
            "get" => op(
              "owner",
              "Reveal a secret as the signed-in owner",
              params: [key_param],
              security: [{ cookie: [] }],
              responses: {
                "200" => json_ref("RevealResponse"),
                "401" => json_ref("Error"),
                "404" => json_ref("Error"),

                "503" => json_ref("Error")
              }
            )
          },
          "/api/v3/secret/{key}/reveal" => {
            "post" => op(
              "owner",
              "Reveal a passphrase-protected secret as the signed-in owner",
              params: [key_param],
              body: "RevealRequest",
              security: [{ cookie: [] }],
              responses: {
                "200" => json_ref("RevealResponse"),
                "401" => json_ref("Error"),
                "404" => json_ref("Error"),

                "503" => json_ref("Error")
              }
            )
          },
          "/api/v3/signup" => {
            "post" => op(
              "account",
              "Create an account (simple mode)",
              body: "CredentialsRequest",
              responses: {
                "201" => json_ref("AccountResponse"),
                "403" => json_ref("Error"),
                "409" => json_ref("Error"),
                "422" => json_ref("Error"),
                "429" => rate_limited,
                "501" => json_ref("Error"),

                "503" => json_ref("Error")
              }
            )
          },
          "/api/v3/signin" => {
            "post" => op(
              "account",
              "Sign in (simple mode)",
              body: "CredentialsRequest",
              responses: {
                "200" => json_ref("AccountResponse"),
                "401" => json_ref("Error"),
                "403" => json_ref("Error"),
                "429" => rate_limited,

                "503" => json_ref("Error")
              }
            )
          },
          "/api/v3/signout" => {
            "post" => op(
              "account",
              "Sign out and destroy the session",
              security: [{ cookie: [] }],
              responses: { "200" => json_ref("OkResponse"), "503" => json_ref("Error") }
            )
          },
          "/api/v3/account/me" => {
            "get" => op(
              "account",
              "Current customer",
              security: [{ cookie: [] }],
              responses: { "200" => json_ref("AccountResponse"), "401" => json_ref("Error"), "503" => json_ref("Error") }
            )
          },
          "/api/v3/account/receipts" => {
            "get" => op(
              "account",
              "Owner receipt list",
              security: [{ cookie: [] }],
              responses: { "200" => json_ref("ReceiptsResponse"), "401" => json_ref("Error"), "503" => json_ref("Error") }
            )
          },
          "/api/v3/account/password" => {
            "post" => op(
              "account",
              "Change password; revokes all other sessions",
              body: "PasswordChangeRequest",
              security: [{ cookie: [] }],
              responses: {
                "200" => json_ref("OkResponse"),
                "401" => json_ref("Error"),
                "422" => json_ref("Error"),

                "503" => json_ref("Error")
              }
            )
          },
          "/api/v3/account" => {
            "delete" => op(
              "account",
              "Delete the account, its sessions and its receipts; live secrets expire on their own TTL",
              body: "PasswordConfirmRequest",
              security: [{ cookie: [] }],
              responses: {
                "200" => json_ref("OkResponse"),
                "401" => json_ref("Error"),
                "403" => json_ref("Error"),

                "503" => json_ref("Error")
              }
            )
          },
          "/api/v1/share" => {
            "post" => op(
              "legacy",
              "Create a secret (v1 legacy shape)",
              body: "ConcealRequest",
              responses: { "200" => json_ref("LegacyConcealResponse"), "429" => rate_limited, "503" => json_ref("Error") }
            )
          },
          "/api/v1/secret/{key}" => {
            "get" => op(
              "legacy",
              "Reveal a secret (v1 GET)",
              params: [key_param],
              responses: { "200" => json_ref("LegacyRevealResponse"), "404" => json_ref("LegacyError"), "503" => json_ref("Error") }
            ),
            "post" => op(
              "legacy",
              "Reveal a secret (v1 POST)",
              params: [key_param],
              responses: { "200" => json_ref("LegacyRevealResponse"), "404" => json_ref("LegacyError"), "503" => json_ref("Error") }
            )
          }
        }
      end

      def op(tag, summary, responses:, params: nil, body: nil, security: nil)
        operation = {
          "tags" => [tag],
          "summary" => summary,
          "responses" => responses
        }
        operation["parameters"] = params if params
        operation["security"] = security if security
        if body
          operation["requestBody"] = {
            "required" => true,
            "content" => { "application/json" => { "schema" => { "$ref" => "#/components/schemas/#{body}" } } }
          }
        end
        operation
      end

      def key_param
        {
          "name" => "key",
          "in" => "path",
          "required" => true,
          "schema" => { "type" => "string", "maxLength" => 128 }
        }
      end

      def json_ref(name)
        {
          "description" => name,
          "content" => { "application/json" => { "schema" => { "$ref" => "#/components/schemas/#{name}" } } }
        }
      end

      def rate_limited
        {
          "description" => "Rate limited",
          "headers" => {
            "Retry-After" => { "schema" => { "type" => "integer" } },
            "X-RateLimit-Limit" => { "schema" => { "type" => "integer" } },
            "X-RateLimit-Remaining" => { "schema" => { "type" => "integer" } },
            "X-RateLimit-Reset" => { "schema" => { "type" => "integer" } }
          },
          "content" => { "application/json" => { "schema" => { "$ref" => "#/components/schemas/Error" } } }
        }
      end

      def components
        {
          "securitySchemes" => {
            "cookie" => { "type" => "apiKey", "in" => "cookie", "name" => "ots_session" }
          },
          "schemas" => {
            "Error" => {
              "type" => "object",
              "required" => %w[error],
              "properties" => {
                "error" => {
                  "type" => "object",
                  "required" => %w[code message request_id],
                  "properties" => {
                    "code" => { "type" => "string" },
                    "message" => { "type" => "string" },
                    "request_id" => { "type" => "string" }
                  }
                }
              }
            },
            "LegacyError" => {
              "type" => "object",
              "properties" => { "message" => { "type" => "string" } }
            },
            "HealthOk" => {
              "type" => "object",
              "properties" => {
                "status" => { "type" => "string", "enum" => %w[ok degraded] },
                "redis" => { "type" => "string", "enum" => %w[ok error] },
                "version" => { "type" => "string" }
              }
            },
            "PublicConfig" => {
              "type" => "object",
              "properties" => {
                "ttl_options" => { "type" => "array", "items" => { "type" => "integer" } },
                "default_ttl" => { "type" => "integer" },
                "auth_mode" => { "type" => "string", "enum" => %w[disabled simple full] },
                "ui_enabled" => { "type" => "boolean" },
                "max_secret_bytes" => { "type" => "integer" },
                "version" => { "type" => "string" }
              }
            },
            "ConcealRequest" => {
              "type" => "object",
              "required" => %w[secret],
              "properties" => {
                "secret" => { "type" => "string", "minLength" => 1 },
                "ttl" => { "type" => "integer" },
                "passphrase" => { "type" => "string", "maxLength" => 256 },
                "kind" => { "type" => "string", "enum" => %w[text] }
              }
            },
            "RevealRequest" => {
              "type" => "object",
              "properties" => { "passphrase" => { "type" => "string" } }
            },
            "ConcealResponse" => {
              "type" => "object",
              "properties" => {
                "secret_key" => { "type" => "string" },
                "receipt" => {
                  "type" => "object",
                  "properties" => {
                    "identifier" => { "type" => "string" },
                    "secret_ttl" => { "type" => "integer" },
                    "passphrase_required" => { "type" => "boolean" },
                    "kind" => { "type" => "string" }
                  }
                },
                "links" => {
                  "type" => "object",
                  "properties" => { "secret" => { "type" => "string" } }
                }
              }
            },
            "RevealResponse" => {
              "type" => "object",
              "properties" => {
                "secret_value" => { "type" => "string" },
                "metadata" => {
                  "type" => "object",
                  "properties" => {
                    "kind" => { "type" => "string" },
                    "filename" => { "type" => %w[string null] },
                    "created_at" => { "type" => "integer" },
                    "ttl" => { "type" => "integer" }
                  }
                }
              }
            },
            "CredentialsRequest" => {
              "type" => "object",
              "required" => %w[email password],
              "properties" => {
                "email" => { "type" => "string", "format" => "email" },
                "password" => { "type" => "string", "minLength" => 12, "maxLength" => 256 }
              }
            },
            "PasswordChangeRequest" => {
              "type" => "object",
              "required" => %w[current_password new_password],
              "properties" => {
                "current_password" => { "type" => "string" },
                "new_password" => { "type" => "string", "minLength" => 12, "maxLength" => 256 }
              }
            },
            "PasswordConfirmRequest" => {
              "type" => "object",
              "required" => %w[password],
              "properties" => {
                "password" => { "type" => "string" }
              }
            },
            "AccountResponse" => {
              "type" => "object",
              "properties" => {
                "customer" => {
                  "type" => "object",
                  "properties" => {
                    "id" => { "type" => "string" },
                    "email" => { "type" => "string" },
                    "role" => { "type" => "string" },
                    "created_at" => { "type" => "integer" }
                  }
                }
              }
            },
            "ReceiptsResponse" => {
              "type" => "object",
              "properties" => {
                "receipts" => {
                  "type" => "array",
                  "items" => {
                    "type" => "object",
                    "properties" => {
                      "identifier" => { "type" => "string" },
                      "secret_ttl" => { "type" => "integer" },
                      "created_at" => { "type" => "integer" },
                      "passphrase_required" => { "type" => "boolean" },
                      "kind" => { "type" => "string" },
                      "secret_url" => { "type" => "string" }
                    }
                  }
                }
              }
            },
            "OkResponse" => {
              "type" => "object",
              "properties" => { "ok" => { "type" => "boolean" } }
            },
            "LegacyConcealResponse" => {
              "type" => "object",
              "properties" => {
                "secret_key" => { "type" => "string" },
                "receipt" => { "type" => "object" }
              }
            },
            "LegacyRevealResponse" => {
              "type" => "object",
              "properties" => {
                "secret_value" => { "type" => "string" },
                "metadata" => { "type" => "object" }
              }
            }
          }
        }
      end
    end
  end
end
