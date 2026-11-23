# frozen_string_literal: true

module Payments
  # Sets a customer's default gateway, but only to a currently-eligible provider
  # (platform-available + active + configured). Upserts the single per-customer row.
  class SetDefaultGateway
    def self.call(customer:, provider:)
      provider = provider.to_s
      eligible = Payments::EligibleGateways.for(customer).map { |gw| gw.key.to_s }
      unless eligible.include?(provider)
        raise ArgumentError, I18n.t("comp_payments.flash.gateway_not_eligible", provider: provider)
      end

      row = Payments::DefaultGateway.unscoped_by_tenant.find_or_initialize_by(customer_id: customer.id)
      row.provider = provider
      row.save!
      row
    rescue ActiveRecord::RecordNotUnique
      # Concurrent create for the same customer (unique customer_id index) —
      # the row now exists; update it instead of raising.
      existing = Payments::DefaultGateway.unscoped_by_tenant.find_by!(customer_id: customer.id)
      existing.update!(provider: provider)
      existing
    end
  end
end
