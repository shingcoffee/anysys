# frozen_string_literal: true

module Billing
  module OneTimeProviders
    SUPPORTED_CURRENCIES = %w[USD CNY].freeze

    def self.call(currency:)
      return [] unless SUPPORTED_CURRENCIES.include?(currency.to_s.upcase)
      platform = Customer.find_by(id: Collector::PLATFORM_OWNER_CUSTOMER_ID)
      return [] unless platform

      Payments::EligibleGateways.for(platform, currency: currency).filter_map do |gateway|
        next unless gateway.capabilities.include?(:one_time)
        key = gateway.key.to_s
        { key: key, label_key: "comp_payments.gateways.#{key}.name",
          supported_currencies: gateway.supported_currencies.map(&:upcase) }
      end
    end

    def self.options(currency:)
      return [] unless SUPPORTED_CURRENCIES.include?(currency.to_s.upcase)
      platform = Customer.find_by(id: Collector::PLATFORM_OWNER_CUSTOMER_ID)
      return [] unless platform

      Payments::EligibleGateways.for(platform, currency: nil).filter_map do |gateway|
        next unless gateway.capabilities.include?(:one_time)
        key = gateway.key.to_s
        compatible = gateway.supported_currencies.map(&:upcase).include?(currency.to_s.upcase)
        { key: key, label_key: "comp_payments.gateways.#{key}.name",
          supported_currencies: gateway.supported_currencies.map(&:upcase),
          enabled: compatible, currency_compatible: compatible,
          reason_key: compatible ? nil : "settings_billing.payment_methods.currency_incompatible" }
      end
    end
  end
end
