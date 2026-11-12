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

        # Read first: MULTI only queues commands, so both sets must be known
        # before the block opens. Everything below is then applied in one EXEC,
        # so a crash part-way cannot leave a half-deleted account.
        receipts = Store.redis.zrange(owner_index, 0, -1)
        session_digests = Store.redis.smembers(session_index)

        Store.redis.multi do |tx|
          receipts.each { |objid| tx.del(Models::Secret.receipt_key(objid)) }
          tx.del(owner_index)
          session_digests.each { |digest| tx.del(Models::Session.digest_key(digest)) }
          tx.del(session_index)
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
