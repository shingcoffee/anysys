# frozen_string_literal: true

module Billing
  class CouponRedemption < ApplicationRecord
    self.table_name = "billing_coupon_redemptions"
    include TenantScoped
    belongs_to :subscription, class_name: "Billing::Subscription", foreign_key: :billing_subscription_id
    belongs_to :coupon, class_name: "Billing::Coupon", foreign_key: :billing_coupon_id
    has_many :invoices, class_name: "Billing::Invoice", foreign_key: :billing_coupon_redemption_id, dependent: :restrict_with_error
    validates :customer_id, :redeemed_at, presence: true
    validates :cycles_used, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  end
end
