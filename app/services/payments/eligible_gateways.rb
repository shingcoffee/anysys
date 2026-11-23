# frozen_string_literal: true

module Payments
  # Gateway classes a customer may use right now: platform-available AND backed
  # by an active+configured MerchantAccount for that customer. Registry order.
  class EligibleGateways
    def self.for(customer, currency: nil)
      available = Payments::PlatformGateway.available_providers.map(&:to_s).to_set
      accounts  = Payments::MerchantAccount.unscoped_by_tenant.active.where(
        customer_id: customer.id, mode: CredentialResolver.default_mode
      )
      configured_providers = accounts.select(&:configured?).map(&:provider).to_set
      wanted = currency.to_s.downcase.presence

      Payments::Gateways.all.select do |gw|
        key = gw.key.to_s
        next false unless available.include?(key) && configured_providers.include?(key)
        next true if wanted.blank?

        gw.supported_currencies.include?(wanted)
      end
    end
  end
end
