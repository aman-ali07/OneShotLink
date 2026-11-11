# frozen_string_literal: true

require "argon2"

module Onetime
  # Password / passphrase hashing.
  #
  # New hashes are Argon2id. Legacy bcrypt hashes ($2a$/$2b$/$2y$) still verify,
  # so an operator can migrate an existing database: the account is rehashed on
  # the next successful login. Neither function ever logs its input.
  module Password
    # m_cost is a log2 exponent in this gem: 16 => 2^16 KiB = 64 MiB.
    ARGON2_OPTIONS = { t_cost: 3, m_cost: 16, p_cost: 2 }.freeze

    module_function

    def create(plaintext)
      Argon2::Password.create(plaintext, ARGON2_OPTIONS)
    end

    def verify(hash, plaintext)
      return false if hash.nil? || hash.empty? || plaintext.nil?

      if legacy_bcrypt?(hash)
        require "bcrypt"
        BCrypt::Password.new(hash) == plaintext
      else
        Argon2::Password.verify_password(plaintext, hash)
      end
    rescue StandardError
      false
    end

    def legacy_bcrypt?(hash)
      hash.start_with?("$2a$", "$2b$", "$2y$")
    end
  end
end
