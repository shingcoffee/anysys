# frozen_string_literal: true

module Billing
  module AvailableProviders
    def self.call(customer:, currency:, interval: nil)
      return [] unless %w[USD CNY].include?(currency.to_s.upcase)
      platform = Customer.find_by(id: Collector::PLATFORM_OWNER_CUSTOMER_ID)
      return [] unless platform
      interval ||= Entitlements.current_subscription(customer: customer)&.interval || "monthly"

      Payments::EligibleGateways.for(platform, currency: currency).filter_map do |gateway|
        key = gateway.key.to_s
        caps = gateway.capabilities
        next unless Providers.supported?(key) && caps.include?(:recurring) &&
          (caps.include?(:billing_agreements) || caps.include?(:tokenized_cards))
        next if key == "alipay" && (currency.to_s.upcase != "CNY" || interval != "monthly")
        { key: key, label_key: "comp_payments.gateways.#{key}.name",
          setup_kind: key == "stripe" ? :stripe_setup : :redirect,
          supported_currencies: gateway.supported_currencies.map(&:upcase) }
      end
    end
  end
end
