# frozen_string_literal: true

require "reform/form"
module Payments
  module Contracts
    class Charge < Reform::Form
      include Payments::Contracts::NormalizesAmount

      property :external_ref
      property :amount
      property :currency
      property :subject
      property :body
      property :provider
      property :openid
      property :metadata

      validates :external_ref, presence: true
      validates :amount, presence: true, numericality: { greater_than: 0 }
      validates :currency,     presence: true
      validates :subject,      presence: true
      validates :provider,     inclusion: { in: ->(_) { Payments::Gateways.keys.map(&:to_s) } }

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
