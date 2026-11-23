# frozen_string_literal: true

module Payments
  module Admin
    # Renders the responsive grid of GatewayCardComponents.
    # 1-column on mobile, 2-column on tablet (sm), 3-column on desktop (lg).
    #
    #   gateways            — array of Payments::Gateways::Base subclasses
    #   accounts_by_provider — hash keyed by provider string → MerchantAccount
    class GatewayGalleryComponent < ApplicationComponent
      attr_reader :gateways, :accounts_by_provider, :default_provider

      def initialize(gateways:, accounts_by_provider:, default_provider: nil)
        @gateways             = gateways
        @accounts_by_provider = accounts_by_provider
        @default_provider     = default_provider
      end

      def account_for(gateway)
        accounts_by_provider[gateway.key.to_s]
      end

      def empty?
        gateways.empty?
      end
    end
  end
end
