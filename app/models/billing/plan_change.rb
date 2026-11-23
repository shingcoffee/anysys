# frozen_string_literal: true

module Billing
  class PlanChange < ApplicationRecord
    self.table_name = "billing_plan_changes"
    include TenantScoped

    STATUSES = %w[awaiting_payment scheduled applied cancelled expired].freeze
    belongs_to :subscription, class_name: "Billing::Subscription", foreign_key: :billing_subscription_id
    belongs_to :from_plan, class_name: "Billing::Plan"
    belongs_to :to_plan, class_name: "Billing::Plan"
    has_many :invoices, class_name: "Billing::Invoice", foreign_key: :billing_plan_change_id, dependent: :restrict_with_error
    validates :customer_id, :request_key, :effective_at, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :kind, inclusion: { in: %w[immediate scheduled] }
    scope :outstanding, -> { where(status: %w[awaiting_payment scheduled]) }

    def proration_invoice = invoices.find_by(purpose: "proration")
  end
end
