# frozen_string_literal: true

module Payments
  # Platform-wide availability flag for a payment tender (gateway). One row per
  # provider, created on demand (default unavailable). Mirrors
  # Captcha::ProviderSettings.for_provider — adding a new gateway file needs no
  # migration; its row is created the first time the platform owner views it.
  #
  # Use `.available_providers` to get the list of provider keys the platform
  # owner has opened up. The customer provisioner and gallery filter to this set.
  class PlatformGateway < ApplicationRecord
    self.table_name = "payment_platform_gateways"

    validates :provider, presence: true, uniqueness: true

    # Fetch (or create) the availability row for +provider_key+. The row is
    # created with available: false so that new gateways are off by default
    # until the platform owner explicitly enables them.
    def self.for_provider(provider_key)
      find_or_create_by!(provider: provider_key.to_s)
    end

    # Returns the array of provider key strings that the platform owner has
    # marked available. Used by the provisioner and gallery to filter the
    # visible/seedable gateway set.
    def self.available_providers
      where(available: true).pluck(:provider)
    end

    # Convenience predicate. Creates the row on first call (available: false).
    def self.available?(provider_key)
      for_provider(provider_key).available?
    end
  end
end
