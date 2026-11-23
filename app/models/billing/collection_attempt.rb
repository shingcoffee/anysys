# frozen_string_literal: true

module Billing
  class CollectionAttempt < ApplicationRecord
    self.table_name = "billing_collection_attempts"
    include TenantScoped

    STATES = %w[prepared submitting pending requires_action succeeded failed unknown].freeze
    INFLIGHT_STATES = %w[prepared submitting pending requires_action unknown].freeze
    belongs_to :invoice, class_name: "Billing::Invoice", foreign_key: :billing_invoice_id
    belongs_to :payment, class_name: "Payments::Payment", optional: true
    belongs_to :payment_method, class_name: "Billing::PaymentMethod", foreign_key: :billing_payment_method_id, optional: true
    belongs_to :merchant_account, class_name: "Payments::MerchantAccount"

    def one_time? = billing_payment_method_id.nil?
    validates :customer_id, :request_key, presence: true
    validates :ordinal, numericality: { only_integer: true, greater_than: 0 }
    validates :state, inclusion: { in: STATES }
    scope :inflight, -> { where(state: INFLIGHT_STATES) }
  end
end
