# frozen_string_literal: true

require "reform/form"

module Billing
  module Contracts
    # Validates input for changing a subscription's plan.
    class ChangePlan < Reform::Form
      property :plan_code
      property :request_key

      validates :plan_code, presence: true

      validate :plan_must_be_active
      validates :request_key, format: { with: Billing::PlanChangePolicy::REQUEST_KEY,
        message: ->(*) { I18n.t("admin_settings.errors.validations.billing_request_key") } }

      private

      def plan_must_be_active
        return if plan_code.blank?

        plan = Billing::Plan.active.find_by(code: plan_code)
        errors.add(:plan_code, I18n.t("admin_settings.errors.validations.plan_not_active")) if plan.nil?
      end

    end
  end
end
