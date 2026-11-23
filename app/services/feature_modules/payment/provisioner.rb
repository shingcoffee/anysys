# frozen_string_literal: true

module FeatureModules
  module Payment
    # Seeds a (customer, provider, mode) credential row for every registered
    # gateway when a customer enables the Payments module. The customer is
    # then free to activate any subset of those rows (see MerchantAccount#status).
    class Provisioner
      MODES = %w[sandbox production].freeze

      def self.call(customer)
        available = Payments::PlatformGateway.available_providers.map(&:to_s)
        Payments::Gateways.keys.each do |provider|
          next unless available.include?(provider.to_s)

          MODES.each do |mode|
            Payments::MerchantAccount.unscoped_by_tenant.find_or_create_by!(
              customer_id: customer.id, provider: provider.to_s, mode: mode
            ) do |acc|
              acc.merchant_id = "unset-#{provider}-#{mode}-#{customer.id}"
              acc.status      = "disabled"
            end
          end
        end
      end

      # Turning the module off must NOT destroy live credentials — an accidental
      # (or reversible) toggle would otherwise vaporize encrypted production
      # secrets. Disable every account instead: EligibleGateways filters by
      # status: "active", so disabling removes the gateways from checkout while
      # preserving credentials for when the module is re-enabled.
      def self.revoke(customer)
        Payments::MerchantAccount.unscoped_by_tenant
                                 .where(customer_id: customer.id)
                                 .update_all(status: "disabled", updated_at: Time.current)
      end
    end
  end
end
