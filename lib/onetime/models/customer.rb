# frozen_string_literal: true

require "digest"

module Onetime
  module Models
    # Redis-backed customer records for simple auth mode.
    #
    # `customer:index:<sha256(email)>` is a uniqueness/lookup index; raw emails
    # are never part of a Redis key. Passwords are Argon2id hashes only.
    module Customer
      INDEX_PREFIX = "customer:index:"

      # Verified when the email is unknown so sign-in latency does not reveal
      # whether an account exists. This hash is not usable for any account.
      DUMMY_PASSWORD_HASH = "$argon2id$v=19$m=65536,t=3,p=2$kRpHDNnnm9xtXTuJlEV+wA$nEp2M4MNhO8Im2zDbJRH3usyGjMFX5EMv2rJeswGICw"

      CREATE_SCRIPT = <<~LUA
        if redis.call('EXISTS', KEYS[1]) == 1 then return 0 end
        redis.call('SET', KEYS[1], ARGV[1])
        redis.call('HSET', KEYS[2],
          'id', ARGV[1],
          'email', ARGV[2],
          'password_hash', ARGV[3],
          'role', ARGV[4],
          'created_at', ARGV[5])
        return 1
      LUA

      module_function

      def key(id)
        "customer:#{id}"
      end

      def index_key(email)
        "#{INDEX_PREFIX}#{Ids.opaque_index(normalize_email(email))}"
      end

      def normalize_email(email)
        email.to_s.strip.downcase
      end

      def create(email:, password_hash:, role: "customer")
        email = normalize_email(email)
        id = Ids.extid
        created_at = Time.now.to_i
        created = Store.redis.eval(
          CREATE_SCRIPT,
          keys: [index_key(email), key(id)],
          argv: [id, email, password_hash, role, created_at.to_s]
        ).to_i
        raise EmailTaken if created.zero?

        { id: id, email: email, role: role, created_at: created_at }
      end

      def find(id)
        return nil if id.to_s.empty?

        raw = Store.redis.hgetall(key(id))
        return nil if raw.empty?

        normalize(raw)
      end

      def find_by_email(email)
        id = Store.redis.get(index_key(email))
        id && find(id)
      end

      def authenticate(email, password)
        customer = find_by_email(email)
        unless customer
          Password.verify(DUMMY_PASSWORD_HASH, password)
          return nil
        end
        return nil unless Password.verify(customer[:password_hash], password)

        rehash_legacy(customer, password)
        customer
      end

      def update_password(customer_id, password)
        Store.redis.hset(key(customer_id), "password_hash", Password.create(password))
      end

      # Only fields safe to return from the API.
      def public_view(customer)
        {
          id: customer[:id],
          email: customer[:email],
          role: customer[:role],
          created_at: customer[:created_at]
        }
      end

      def normalize(raw)
        {
          id: raw["id"],
          email: raw["email"],
          password_hash: raw["password_hash"],
          role: raw["role"],
          created_at: raw["created_at"].to_i
        }
      end
      private_class_method :normalize

      def rehash_legacy(customer, password)
        return unless Password.legacy_bcrypt?(customer[:password_hash])

        update_password(customer[:id], password)
      end
      private_class_method :rehash_legacy
    end
  end
end
