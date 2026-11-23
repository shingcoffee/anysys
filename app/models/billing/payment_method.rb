# frozen_string_literal: true

module Billing
  class PaymentMethod < ApplicationRecord
    self.table_name = "billing_payment_methods"

    include TenantScoped

    STATUSES = %w[pending active failed removed].freeze
    REVOCATION_STATES = %w[none pending complete failed].freeze
    # Historical rows are intentionally left unbound by A's preflight/backfill.
    # They must remain removable; new authorizations always require an account.
    belongs_to :merchant_account, class_name: "Payments::MerchantAccount", optional: true
    belongs_to :authorized_by, class_name: "Authentication::User", optional: true

    belongs_to :payments_subscription,
               class_name: "Payments::Subscription",
               foreign_key: :payments_subscription_id,
               optional: true

    validates :customer_id, presence: true
    validates :provider,    presence: true
    validates :status,      inclusion: { in: STATUSES }
    validates :request_key, presence: true
    validates :revocation_state, inclusion: { in: REVOCATION_STATES }
    validates :merchant_account, presence: true, on: :create

    scope :active,         -> { where(status: "active") }
    scope :default_method, -> { active.where(is_default: true) }

    def active? = status == "active"
    def removed? = status == "removed"
  end
end
