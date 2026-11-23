# frozen_string_literal: true

require "reform/form"

module Billing
  module Contracts
    # Validates input for authorizing a billing payment method for a tenant.
    class PaymentMethod < Reform::Form
      property :provider
      property :request_key

      attr_accessor :customer, :currency

      validates :provider, presence: true
      validates :request_key, presence: true, length: { maximum: 128 }
      validates :request_key, format: { with: Billing::PlanChangePolicy::REQUEST_KEY,
        message: ->(*) { I18n.t("admin_settings.errors.validations.billing_request_key") } }, allow_blank: true
      validate :provider_must_be_available

      def provider_must_be_available
        return if provider.blank?
        return if Billing::AvailableProviders.call(customer: customer, currency: currency).any? { |entry| entry[:key] == provider.to_s }

        errors.add(:provider, I18n.t("admin_settings.errors.validations.provider_not_available"))
      end
    end
  end
end
