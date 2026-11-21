# frozen_string_literal: true

module Onetime
  module Logic
    # Deletes a customer account: the record, its email index, every live
    # session, and its receipts.
    #
    # Secrets that are still inside their TTL are deliberately left alone: the
    # link may already be in someone's inbox, and that handover is not the
    # account's to cancel. They expire on their own schedule, and the account
    # can no longer be used to see them.
    class DeleteAccount
      def initialize(customer:)
        @customer = customer
      end

      def call
        customer_id = @customer[:id]
        owner_index = Models::Secret.owner_index(customer_id)
        session_index = Models::Session.index_key(customer_id)
        request_index = Models::SecretRequest.owner_index(customer_id)
        webhook_index = Webhook.owner_index(customer_id)

        # Read first: MULTI only queues commands, so every key set must be known
        # before the block opens. Everything below is then applied in one EXEC,
        # so a crash part-way cannot leave a half-deleted account.
        receipts = Store.redis.zrange(owner_index, 0, -1)
        session_digests = Store.redis.smembers(session_index)
        request_keys = Store.redis.zrange(request_index, 0, -1)
        endpoint_ids = Store.redis.zrange(webhook_index, 0, -1)
        delivery_keys = Store.redis.scan_each(match: "#{Webhook::DELIVERY_PREFIX}*").select do |key|
          endpoint_ids.include?(Store.redis.hget(key, "endpoint_id"))
        end

        Store.redis.multi do |tx|
          receipts.each { |objid| tx.del(Models::Secret.receipt_key(objid)) }
          tx.del(owner_index)
          session_digests.each { |digest| tx.del(Models::Session.digest_key(digest)) }
          tx.del(session_index)
          request_keys.each do |key|
            tx.del(Models::SecretRequest.object_key(key))
            tx.del(Models::SecretRequest.submission_key(key))
          end
          tx.del(request_index)
          endpoint_ids.each { |id| tx.del(Webhook.key(id)) }
          tx.del(webhook_index)
          delivery_keys.each { |key| tx.del(key) }
          # The index key is looked up by the normalized email hash, so it has to
          # be removed by the same derivation used when the account was created.
          tx.del(Models::Customer.index_key(@customer[:email]))
          tx.del(Models::Customer.key(customer_id))
        end

        { receipts: receipts.size, sessions: session_digests.size }
      end
    end
  end
end
