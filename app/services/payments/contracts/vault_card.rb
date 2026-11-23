# frozen_string_literal: true

require "reform/form"

module Payments
  module Contracts
    # Validates the inputs for vaulting a card token via a SetupIntent flow.
    # The gateway must be registered AND declare the :tokenized_cards capability.
    class VaultCard < Reform::Form
      property :provider
      property :return_url

      validates :return_url, presence: true
      validates :provider,   presence: true

      validate :provider_supports_tokenized_cards

      private

      def provider_supports_tokenized_cards
        return if provider.blank?

        gateway_klass = begin
          Payments::Gateways.for(provider)
        rescue ArgumentError
          errors.add(:provider, :invalid)
          return
        end

        unless gateway_klass.capabilities.include?(:tokenized_cards)
          errors.add(:provider, :tokenized_cards_unsupported)
        end
      end
    end
  end
end
