# frozen_string_literal: true

module Payments
  module Contracts
    module NormalizesAmount
      extend ActiveSupport::Concern

      included do
        validate :normalize_payment_amount
      end

      private

      def normalize_payment_amount
        return if amount.blank?

        amount_currency = respond_to?(:currency) ? currency : nil
        self.amount = Payments::Money.normalize(amount, amount_currency)
      rescue ArgumentError
        # Infinity/NaN pass Rails numericality (`Float("Infinity") > 0`) and
        # would 500 later in Money.normalize. Record a number error here.
        errors.add(:amount, :not_a_number)
        self.amount = nil
      end
    end
  end
end
