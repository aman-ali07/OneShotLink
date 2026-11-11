# frozen_string_literal: true

require "digest"
require "securerandom"

module Onetime
  # Opaque, unguessable identifiers. There are no sequential IDs anywhere in
  # the public surface: everything a user can see is 128+ bits of randomness.
  module Ids
    module_function

    def extid(bytes: 16)
      SecureRandom.urlsafe_base64(bytes, false)
    end

    # Deterministic, non-reversible index key (never store raw emails as keys).
    def opaque_index(value)
      Digest::SHA256.hexdigest("ots-index/v1:#{value.to_s.strip.downcase}")
    end

    def session_token
      SecureRandom.hex(32)
    end
  end
end
