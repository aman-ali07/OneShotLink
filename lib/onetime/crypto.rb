# frozen_string_literal: true

require "base64"
require "json"
require "openssl"

module Onetime
  # AES-256-GCM encryption at rest.
  #
  # The data key is derived from the instance-wide SECRET with HKDF, so the
  # SECRET never touches Redis. Every record gets a fresh random 96-bit IV and
  # its own random salt, and the AEAD tag is verified on decrypt: tampering with
  # a stored record makes reveal fail rather than emit garbage.
  module Crypto
    CIPHER = "aes-256-gcm"
    IV_BYTES = 12
    TAG_BYTES = 16
    SALT_BYTES = 16
    KEY_BYTES = 32

    module_function

    def data_key(secret = Config.secret!)
      OpenSSL::KDF.hkdf(
        secret,
        salt: "onetimesecret/v1",
        info: "secret-content-encryption",
        length: KEY_BYTES,
        hash: "SHA256"
      )
    end

    # Returns a hash safe to store as Redis hash fields.
    def encrypt(plaintext, secret: Config.secret!)
      raise ArgumentError, "plaintext must be a String" unless plaintext.is_a?(String)

      salt = OpenSSL::Random.random_bytes(SALT_BYTES)
      key = derive(secret, salt)
      iv = OpenSSL::Random.random_bytes(IV_BYTES)
      cipher = OpenSSL::Cipher.new(CIPHER)
      cipher.encrypt
      cipher.key = key
      cipher.iv = iv
      cipher.auth_data = salt
      ciphertext = cipher.update(plaintext) + cipher.final

      {
        "ciphertext" => Base64.strict_encode64(ciphertext),
        "iv" => Base64.strict_encode64(iv),
        "tag" => Base64.strict_encode64(cipher.auth_tag(TAG_BYTES)),
        "salt" => Base64.strict_encode64(salt),
        "cipher" => CIPHER
      }
    end

    def decrypt(payload, secret: Config.secret!)
      salt = Base64.strict_decode64(payload.fetch("salt"))
      key = derive(secret, salt)
      cipher = OpenSSL::Cipher.new(payload.fetch("cipher", CIPHER))
      cipher.decrypt
      cipher.key = key
      cipher.iv = Base64.strict_decode64(payload.fetch("iv"))
      cipher.auth_tag = Base64.strict_decode64(payload.fetch("tag"))
      cipher.auth_data = salt
      (cipher.update(Base64.strict_decode64(payload.fetch("ciphertext"))) + cipher.final).force_encoding(Encoding::UTF_8)
    rescue KeyError, ArgumentError => e
      raise Onetime::Error, "Stored secret is malformed: #{e.class}"
    rescue OpenSSL::Cipher::CipherError
      raise Onetime::Error, "Stored secret failed integrity verification"
    end

    def derive(secret, salt)
      OpenSSL::KDF.hkdf(secret, salt: salt, info: "ots-secret", length: KEY_BYTES, hash: "SHA256")
    end

    # Constant-time comparison for opaque tokens.
    def secure_compare(a, b)
      return false unless a.is_a?(String) && b.is_a?(String)
      return false unless a.bytesize == b.bytesize

      OpenSSL.fixed_length_secure_compare(a, b)
    end
  end
end
