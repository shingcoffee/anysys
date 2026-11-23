# frozen_string_literal: true

module People
  # Daily sweep of leftover registration claims (config/recurring.yml:
  # people_expire_pending_claims). Expired rows are deleted; a created_user
  # claim whose account is still unconfirmed also drops the unclaimed entry
  # and that user.
  class ExpirePendingClaimsJob < ApplicationJob
    queue_as :default

    BATCH_SIZE = 500

    def perform
      PendingClaim.expired.find_in_batches(batch_size: BATCH_SIZE) do |claims|
        claims.each { |claim| expire(claim) }
      end
    end

    private

    def expire(claim)
      Customer.transaction do
        Customer.lock.find(claim.customer_id)
        current = PendingClaim.find_by(id: claim.id)
        if current&.expires_at&.<= Time.current
          created_user = current.created_user?
          customer_id = current.customer_id
          user_id = current.user_id
          entry_id = current.entity_entry_id

          current.destroy!

          if created_user
            user = Authentication::User.find_by(id: user_id)
            if user && user.customer_id == customer_id && !user.confirmed?
              destroy_unclaimed_entry(entry_id, customer_id)
              user.destroy!
            end
          end
        end
      end
    end

    def destroy_unclaimed_entry(entry_id, customer_id)
      return if entry_id.blank?

      entry = EntityEntry.find_by(id: entry_id)
      return unless entry
      return unless entry.customer_id == customer_id
      return if entry.linked?

      entry.destroy!
    end
  end
end
