# frozen_string_literal: true

module Billing
  module Admin
    # Renders the new/edit form for a billing coupon (platform owner, Area d).
    # Keeps all submitted fields visible so validation can be corrected without
    # JavaScript; Reform decides which discount/duration fields are applicable.
    #
    # Constructor:
    #   coupon:      Billing::Coupon instance (new or persisted)
    #   customer_id: current customer_id (owner's) for route helpers
    class CouponFormComponent < ApplicationComponent
      include Presentation

      def initialize(coupon:, customer_id:, form: nil)
        @coupon      = coupon
        @customer_id = customer_id.to_s
        @form = form || Billing::Contracts::Coupon.new(coupon)
      end

      attr_reader :coupon, :customer_id
      attr_reader :form
      def form_record = coupon
      def form_scope = "billing_coupon"

      def form_url
        if coupon.persisted?
          helpers.admin_maintenance_platform_billing_coupon_path(customer_id, coupon)
        else
          helpers.admin_maintenance_platform_billing_coupons_path(customer_id)
        end
      end

      def form_method
        coupon.persisted? ? :patch : :post
      end

      def index_path
        helpers.admin_maintenance_platform_billing_coupons_path(customer_id)
      end

      def discount_type_options
        submitted_options(Billing::Coupon::DISCOUNT_TYPES.map { |type| [I18n.t("comp_billing.coupon_form.discount_types.#{type}"), type] }, :discount_type)
      end

      def duration_options
        submitted_options(Billing::Coupon::DURATIONS.map { |duration| [I18n.t("comp_billing.coupon_table.durations.#{duration}"), duration] }, :duration)
      end

      def stimulus_discount_type
        form_value(:discount_type).presence || Billing::Coupon::DISCOUNT_TYPES.first
      end

      def stimulus_duration
        form_value(:duration).presence || Billing::Coupon::DURATIONS.first
      end
    end
  end
end
