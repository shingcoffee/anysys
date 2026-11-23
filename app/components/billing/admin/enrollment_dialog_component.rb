# frozen_string_literal: true

module Billing
  module Admin
    # New-subscription enrollment modal for a single catalog plan. Replaces the
    # cramped in-card <details> so the coupon field and policy hints have room.
    class EnrollmentDialogComponent < ApplicationComponent
      attr_reader :plan, :catalog

      def initialize(plan:, catalog:)
        @plan = plan
        @catalog = catalog
      end

      def open? = catalog.enrollment_open?(plan)
      def dialog_id = "subscribe-plan-#{plan.code}"
      def coupon_field_id = "signup-coupon-#{plan.code}"
    end
  end
end
