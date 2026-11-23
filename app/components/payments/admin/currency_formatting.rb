# frozen_string_literal: true

module Payments
  module Admin
    # Shared amount-display logic for admin payment tables. Our canonical
    # storage is major-unit decimals (e.g. 31.09 USD, 1000.00 JPY), so it must
    # be rescaled to ISO-4217 minor units via Payments::Money before handing it
    # to Billing::CurrencyResolver.format, which expects minor units (cents for
    # 2-decimal, whole units for zero-decimal).
    module CurrencyFormatting
      private

      # currency may be nil (e.g. an order lookup came back empty); falls back
      # to CNY like the call sites this replaces.
      def format_money(amount, currency)
        currency = currency.presence || "CNY"
        minor_units = Payments::Money.to_iso_minor_units(amount, currency)
        Billing::CurrencyResolver.format(minor_units, currency)
      end
    end
  end
end
