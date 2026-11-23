# frozen_string_literal: true

module People
  # One outstanding registration claim per user. Written by People::Claim;
  # completed on a fully established sign-in; leftover rows are swept by
  # People::ExpirePendingClaimsJob.
  class PendingClaim < ApplicationRecord
    self.table_name = "people_pending_claims"

    include TenantScoped

    belongs_to :user, class_name: "Authentication::User"
    belongs_to :entity_entry, optional: true

    scope :expired, -> { where(expires_at: ..Time.current) }
  end
end
