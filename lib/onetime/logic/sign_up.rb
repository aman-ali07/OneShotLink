# frozen_string_literal: true

module Onetime
  module Logic
    class SignUp
      MIN_PASSWORD_BYTES = 12
      MAX_PASSWORD_BYTES = 256
      MAX_EMAIL_BYTES = 254
      EMAIL_PATTERN = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

      def initialize(email:, password:)
        @email = email
        @password = password
      end

      def call
        email = validate_email
        password = validate_password
        customer = Models::Customer.create(email: email, password_hash: Password.create(password))
        token = Models::Session.create(customer[:id])
        { customer: Models::Customer.public_view(customer), session_token: token }
      end

      private

      def validate_email
        email = Models::Customer.normalize_email(@email)
        raise ValidationError, "email is required" if email.empty?
        raise ValidationError, "email is invalid" if email.bytesize > MAX_EMAIL_BYTES || !email.match?(EMAIL_PATTERN)

        email
      end

      def validate_password
        raise ValidationError, "password must be a string" unless @password.is_a?(String)
        if @password.bytesize < MIN_PASSWORD_BYTES
          raise ValidationError, "password must be at least #{MIN_PASSWORD_BYTES} characters"
        end
        raise ValidationError, "password is too long" if @password.bytesize > MAX_PASSWORD_BYTES

        @password
      end
    end
  end
end
