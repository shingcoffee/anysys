# frozen_string_literal: true

require "reform/form"
module Payments
  module Contracts
    class Subscribe < Reform::Form
      include Payments::Contracts::NormalizesAmount

      property :external_ref
      property :plan_name
      property :amount
      property :cycle
      property :currency
      property :provider

      validates :external_ref, :plan_name, :currency, presence: true
      validates :amount, numericality: { greater_than: 0 }
      validates :cycle,    inclusion: { in: Payments::Subscription::CYCLES }
      validates :provider, inclusion: { in: ->(_) { Payments::Gateways.keys.map(&:to_s) } }

      validate :currency_supported_by_gateway

      private

      def currency_supported_by_gateway
        return if provider.blank? || currency.blank?
        supported = begin
          Payments::Gateways.for(provider).supported_currencies
        rescue ArgumentError
          []
        end
        errors.add(:currency, :inclusion) unless supported.include?(currency.to_s.downcase)
      end
    end
  end
end
