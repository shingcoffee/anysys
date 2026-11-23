# frozen_string_literal: true

module People
  # Thin facade for pending person-entry claims. Writes go through
  # record! (upsert) and Activities::CompleteClaim (consume + optional link).
  class Claim
    TTL = 3.days

    # A claim recorded with the account it created is never replaced: a later
    # submission for the same address must not strip its entry or redirect
    # its confirmation.
    def self.record!(user:, created_user:, entry: nil, continuation: nil)
      claim = PendingClaim.find_or_initialize_by(user_id: user.id)
      return claim if claim.persisted? && claim.created_user?

      claim.customer_id = user.customer_id
      claim.entity_entry = entry
      claim.continuation = continuation
      claim.created_user = created_user
      claim.expires_at = TTL.from_now
      PendingClaim.transaction(requires_new: true) { claim.save! }
      claim
    rescue ActiveRecord::RecordNotUnique
      PendingClaim.find_by!(user_id: user.id)
    end

    def self.complete!(user)
      Activities::CompleteClaim.call(user: user)
    end
  end
end
