# frozen_string_literal: true

module Authentication
  # Append-only auth audit-log ledger. NOT TenantScoped: rows are written on
  # pre-auth paths (e.g. a failed login for an unknown email) where the tenant
  # and user are not resolved, so customer_id / user_id are best-effort.
  class Event < ApplicationRecord
    self.table_name = "authentication_events"

    EVENTS = %w[
      login_succeeded login_failed logout locked_out
      mfa_enabled mfa_disabled mfa_verified mfa_failed
      password_reset_requested password_reset_completed
      role_granted role_revoked throttled
      oauth_authorized
    ].freeze

    validates :event, presence: true

    scope :for_customer, ->(cid) { where(customer_id: cid) }
    scope :for_user,     ->(uid) { where(user_id: uid) }
    scope :recent,       ->(since) { where(created_at: since..) }
  end
end
