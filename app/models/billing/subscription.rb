# frozen_string_literal: true

module Billing
  class Subscription < ApplicationRecord
    self.table_name = "billing_subscriptions"

    include TenantScoped

    STATUSES      = %w[pending trialing active past_due paused cancelled expired].freeze
    LIVE_STATUSES = %w[pending trialing active past_due paused].freeze

    belongs_to :plan,   class_name: "Billing::Plan",   foreign_key: :billing_plan_id
    belongs_to :coupon, class_name: "Billing::Coupon",  foreign_key: :billing_coupon_id, optional: true
    has_many :invoices, class_name: "Billing::Invoice", foreign_key: :billing_subscription_id, dependent: :restrict_with_error
    has_many :plan_changes, class_name: "Billing::PlanChange", foreign_key: :billing_subscription_id, dependent: :restrict_with_error
    has_one :coupon_redemption, class_name: "Billing::CouponRedemption", foreign_key: :billing_subscription_id, dependent: :restrict_with_error

    validates :customer_id,  presence: true
    validates :status,       inclusion: { in: STATUSES }
    validates :amount_cents, numericality: { greater_than_or_equal_to: 0, only_integer: true }
    validates :interval,     inclusion: { in: Billing::Plan::INTERVALS }
    validates :currency, inclusion: { in: %w[USD CNY] }

    scope :live, -> { where(status: LIVE_STATUSES) }
    scope :due_for_renewal, -> { live.where("current_period_end <= ?", Time.zone.now) }
    scope :trial_ending, ->(days) {
      where(status: "trialing")
        .where("trial_end <= ?", days.days.from_now)
        .where("trial_end >= ?", Time.zone.now)
    }
    def pending_plan_change = plan_changes.outstanding.first

    def period_end_from(time)
      Billing::PlanChangePolicy.period_end(time, interval: interval,
        anchor_day: billing_anchor_day || time.day, anchor_month: billing_anchor_month || time.month)
    end
  end
end
