# frozen_string_literal: true

module Billing
  module Activities
    class ApplyCoupon
      TERMS = %w[code name discount_type percent_off amount_off_cents currency duration duration_in_cycles].freeze

      def self.call(subscription:, coupon:)
        Result.transaction(subscription) do
          existing = subscription.coupon_redemption
          if existing
            next Result.new(status: existing.billing_coupon_id == coupon.id ? :unchanged : :invalid,
              subscription: subscription, reason: :already_applied)
          end
          next Result.invalid(:subscription_ended, subscription: subscription) unless Subscription::LIVE_STATUSES.include?(subscription.status)
          Result.transaction(coupon) do
            next Result.invalid(:not_redeemable, subscription: subscription) unless coupon.redeemable?
            next Result.invalid(:currency_mismatch, subscription: subscription) unless coupon.applies_to_currency?(subscription.currency)

            inventory = Coupon.where(id: coupon.id, times_redeemed: coupon.times_redeemed)
            changed = inventory.update_all(["times_redeemed = times_redeemed + 1, updated_at = ?", Time.current])
            raise ActiveRecord::StaleObjectError.new(coupon, "redeem") unless changed == 1

            subscription.create_coupon_redemption!(customer_id: subscription.customer_id,
              billing_coupon_id: coupon.id, terms_snapshot: coupon.attributes.slice(*TERMS), redeemed_at: Time.current)
            subscription.update!(billing_coupon_id: coupon.id)
            Result.new(status: :applied, subscription: subscription)
          end
        end
      end
    end
  end
end
