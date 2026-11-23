# frozen_string_literal: true

module Billing
  module Admin
    # Renders a responsive table of billing coupons for the platform coupon catalog.
    # Used by the platform maintenance area (Area d).
    #
    # Constructor:
    #   coupons:     Array/relation of Billing::Coupon records
    #   customer_id: current customer_id for building route helpers
    class CouponTableComponent < ApplicationComponent
      include Presentation
      def initialize(coupons:, customer_id:, pagination: nil, page_path: nil)
        @coupons     = coupons
        @customer_id = customer_id.to_s
        @pagination, @page_path = pagination, page_path
      end

      attr_reader :coupons, :customer_id
      attr_reader :pagination, :page_path

      def format_amount_off(amount_cents, currency = "CNY")
        ::Billing::CurrencyResolver.format(amount_cents, currency)
      end

      def discount_summary(coupon)
        if coupon.discount_type == "percent"
          "#{coupon.percent_off}%"
        else
          billing_amount(coupon.amount_off_cents, coupon.currency)
        end
      end

      def duration_label(coupon)
        label = I18n.t("comp_billing.coupon_table.durations.#{coupon.duration}")
        if coupon.duration == "repeating" && coupon.duration_in_cycles
          I18n.t("comp_billing.coupon_table.duration_cycles", label: label, count: coupon.duration_in_cycles)
        else
          label
        end
      end

      def redemption_label(coupon)
        if coupon.max_redemptions
          "#{coupon.times_redeemed} / #{coupon.max_redemptions}"
        else
          coupon.times_redeemed.to_s
        end
      end

      def expires_label(coupon)
        coupon.redeem_by.present? ? I18n.l(coupon.redeem_by.to_date, format: :long) : I18n.t("common.labels.em_dash")
      end

      def coupons_count
        pagination.is_a?(Hash) ? pagination[:total] || pagination["total"] || coupons.size : coupons.size
      end

      def edit_coupon_path(coupon)
        helpers.edit_admin_maintenance_platform_billing_coupon_path(customer_id, coupon)
      end

      def coupon_path(coupon)
        helpers.admin_maintenance_platform_billing_coupon_path(customer_id, coupon)
      end

      def new_coupon_path
        helpers.new_admin_maintenance_platform_billing_coupon_path(customer_id)
      end
    end
  end
end
