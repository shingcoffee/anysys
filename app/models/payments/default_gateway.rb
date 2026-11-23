# frozen_string_literal: true

module Payments
  # One row per customer naming their default payment gateway provider.
  class DefaultGateway < ApplicationRecord
    include TenantScoped

    self.table_name = "payment_default_gateways"

    validates :customer_id, presence: true, uniqueness: true
    validates :provider,    presence: true

    # The stored default provider for a customer, or nil. Bypasses tenant
    # default scope so it works from any context given an explicit id.
    def self.provider_for(customer_id)
      return nil if customer_id.blank?

      unscoped_by_tenant.where(customer_id: customer_id).pick(:provider)
    end
  end
end
