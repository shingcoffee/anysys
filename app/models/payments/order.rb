# frozen_string_literal: true

module Payments
  class Order < ApplicationRecord
    self.table_name = "payment_orders"

    include TenantScoped
    include Payments::NormalizesAmount

    normalizes_payment_amount :amount, currency: :currency

    STATUSES = %w[pending paid partial_refund refunded closed failed].freeze

    # Once money has been captured (or partially/fully refunded) the order is in a
    # settled family that a later failed/closed attempt on the SAME order must not
    # overwrite — a second payment attempt failing cannot un-pay a paid order.
    SETTLED_STATUSES = %w[paid partial_refund refunded].freeze

    has_many :payments, dependent: :destroy,
                        class_name: "Payments::Payment",
                        foreign_key: :payment_order_id

    validates :external_ref, presence: true, uniqueness: { scope: :customer_id }
    validates :amount,       presence: true, numericality: { greater_than: 0 }
    # Vendor-agnostic: a currency is valid if at least one registered gateway
    # supports it. CNY stays valid via Alipay/WeChat/Stripe; USD/EUR/etc become
    # valid via Stripe/PayPal. Orders store UPPERCASE; gateways declare lowercase.
    validates :currency, presence: true,
      inclusion: { in: ->(_) { Payments::Gateways.all.flat_map(&:supported_currencies).map(&:upcase).uniq } }
    validates :subject,      presence: true
    validates :status,       inclusion: { in: STATUSES }
    validates :customer_id,  presence: true

    # Idempotent + guarded transitions. A settled order (paid/…refund) is never
    # regressed by a later attempt: mark_paid! is a no-op once already settled,
    # and mark_failed!/mark_closed! refuse to overwrite a settled order.
    # mark_paid! returns true only when this call settled the order.
    def mark_paid!(at)
      return false if status.in?(SETTLED_STATUSES)
      update!(status: "paid", paid_at: at)
    end

    def mark_failed!
      return if status.in?(SETTLED_STATUSES) || status == "failed"
      update!(status: "failed")
    end

    def mark_closed!
      return if status.in?(SETTLED_STATUSES) || status == "closed"
      update!(status: "closed")
    end
  end
end
