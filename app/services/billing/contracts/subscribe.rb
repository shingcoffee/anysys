# frozen_string_literal: true

require "reform/form"

module Billing
  module Contracts
    # Validates input for subscribing a customer to a billing plan.
    class Subscribe < Reform::Form
      property :plan_code
      property :coupon_code
      property :currency
      property :request_key

      validates :plan_code, presence: true
      validates :currency, inclusion: { in: %w[USD CNY] }
      validates :request_key, format: { with: Billing::PlanChangePolicy::REQUEST_KEY,
        message: ->(*) { I18n.t("admin_settings.errors.validations.billing_request_key") } }

      validate :plan_must_be_active
      validate :coupon_must_be_redeemable, if: -> { coupon_code.present? }

      private

      def plan_must_be_active
        return if plan_code.blank?

        plan = Billing::Plan.active.find_by(code: plan_code)
        errors.add(:plan_code, I18n.t("admin_settings.errors.validations.plan_not_active")) if plan.nil?
      end

      def coupon_must_be_redeemable
        coupon = Billing::Coupon.find_by(code: coupon_code)
        if coupon.nil?
          errors.add(:coupon_code, I18n.t("admin_settings.errors.validations.coupon_not_found"))
        elsif !coupon.redeemable?
          errors.add(:coupon_code, I18n.t("admin_settings.errors.validations.coupon_not_redeemable"))
        elsif !coupon.applies_to_currency?(currency)
          errors.add(:coupon_code, I18n.t("admin_settings.errors.validations.coupon_currency"))
        end
      end
    end
  end
end
