# frozen_string_literal: true

module Onetime
  # Errors carry both a machine code (stable API contract) and a human message
  # that never contains plaintext secret material.
  class Error < StandardError
    def status
      500
    end

    def code
      "internal_error"
    end
  end

  class ValidationError < Error
    def status = 422
    def code = "validation_error"
  end

  class NotFound < Error
    def status = 404
    def code = "not_found"
    def message = "The secret is gone, expired, or was already viewed."
  end

  class Unauthorized < Error
    def status = 401
    def code = "unauthorized"
  end

  class Forbidden < Error
    def status = 403
    def code = "forbidden"
  end

  class Conflict < Error
    def status = 409
    def code = "conflict"
  end

  class EmailTaken < Conflict
    def code = "email_taken"
    def message = "An account with that email already exists."
  end

  class InvalidCredentials < Unauthorized
    def code = "invalid_credentials"
    def message = "Email or password is incorrect."
  end

  class RateLimited < Error
    def status = 429
    def code = "rate_limited"
    def message = "Too many requests. Slow down and try again shortly."
  end

  class PassphraseRequired < Error
    def status = 401
    def code = "passphrase_required"
    def message = "This secret is protected by a passphrase."
  end

  class InvalidPassphrase < Error
    def status = 401
    def code = "invalid_passphrase"
    def message = "That passphrase is not correct. The secret has not been viewed."
  end

  class PayloadTooLarge < Error
    def status = 413
    def code = "payload_too_large"
    def message = "The secret exceeds the maximum allowed size."
  end

  class NotConfigured < Error
    def status = 501
    def code = "not_configured"
    def message = "This feature is not configured in this deployment."
  end
end
