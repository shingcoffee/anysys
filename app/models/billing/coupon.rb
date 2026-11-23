# frozen_string_literal: true

module Billing
  class Coupon < ApplicationRecord
    self.table_name = "billing_coupons"

    DISCOUNT_TYPES = %w[percent fixed].freeze
    DURATIONS      = %w[once repeating forever].freeze

    validates :code,          presence: true, uniqueness: true
    validates :name,          presence: true
    validates :discount_type, inclusion: { in: DISCOUNT_TYPES }
    validates :duration,      inclusion: { in: DURATIONS }
    validates :percent_off,
              numericality: { in: 1..100, only_integer: true },
              if: -> { discount_type == "percent" }
    validates :amount_off_cents,
              numericality: { greater_than: 0, only_integer: true },
              if: -> { discount_type == "fixed" }
    validates :duration_in_cycles,
              numericality: { greater_than: 0, only_integer: true },
              if: -> { duration == "repeating" }

    has_many :subscriptions, class_name: "Billing::Subscription", foreign_key: :billing_coupon_id, dependent: :restrict_with_error
    has_many :redemptions, class_name: "Billing::CouponRedemption", foreign_key: :billing_coupon_id, dependent: :restrict_with_error
    has_many :invoices, class_name: "Billing::Invoice", foreign_key: :billing_coupon_id, dependent: :restrict_with_error
    scope :active, -> { where(active: true, archived_at: nil) }

    # Returns true if this coupon can still be redeemed right now.
    def redeemable?
      return false unless usable_on_invoice?
      return false if max_redemptions.present? && times_redeemed >= max_redemptions

      true
    end

    # Catalog gate for NEW redemptions only. Accepted discounts use the
    # CouponRedemption snapshot, never today's active/expiry flags.
    def usable_on_invoice?
      return false unless active? && archived_at.nil?
      return false if redeem_by.present? && redeem_by <= Time.zone.now

      true
    end

    # Fixed-amount coupons are denominated in `currency`. Percent coupons apply
    # in either supported billing currency. Fixed currency must be explicit.
    def applies_to_currency?(currency)
      return true unless discount_type == "fixed"
      self.currency.to_s.upcase == currency.to_s.upcase
    end

    # Returns the discount amount in cents for the given subtotal, clamped to
    # the subtotal so the discount can never exceed the charge.
    def discount_for(amount_cents)
      raw = if discount_type == "percent"
               amount_cents * percent_off / 100
      else
              amount_off_cents.to_i
      end
      [[raw, 0].max, [amount_cents, 0].max].min
    end

    def referenced? = subscriptions.exists? || redemptions.exists? || invoices.exists?
  end
end
