# frozen_string_literal: true

module Onetime
  module Logic
    class SignIn
      def initialize(email:, password:)
        @email = email
        @password = password
      end

      def call
        raise InvalidCredentials unless @password.is_a?(String)

        customer = Models::Customer.authenticate(@email, @password)
        raise InvalidCredentials unless customer

        token = Models::Session.create(customer[:id])
        { customer: Models::Customer.public_view(customer), session_token: token }
      end
    end
  end
end
