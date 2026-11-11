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

        receipts = Store.redis.zrange(Models::Secret.owner_index(customer_id), 0, -1)
        receipts.each { |objid| Store.redis.del(Models::Secret.receipt_key(objid)) }
        Store.redis.del(Models::Secret.owner_index(customer_id))

        sessions = Models::Session.revoke_all(customer_id)

        # The index key is looked up by the normalized email hash, so it has to
        # be removed by the same derivation used when the account was created.
        Store.redis.del(Models::Customer.index_key(@customer[:email]))
        Store.redis.del(Models::Customer.key(customer_id))

        { receipts: receipts.size, sessions: sessions }
      end
    end
  end
end
