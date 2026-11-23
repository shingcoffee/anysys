# frozen_string_literal: true

module Payments
  module NormalizesAmount
    extend ActiveSupport::Concern

    class_methods do
      def normalizes_payment_amount(attribute, currency:)
        before_validation do
          raw_amount = read_attribute_before_type_cast(attribute)
          next if raw_amount.blank?

          resolved_currency = currency.respond_to?(:call) ? currency.call(self) : public_send(currency)
          self[attribute] = Payments::Money.normalize(raw_amount, resolved_currency)
        rescue ArgumentError
          # Numericality validation reports malformed input.
        end
      end
    end
  end
end
