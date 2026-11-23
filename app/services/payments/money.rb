# frozen_string_literal: true

require "bigdecimal"

module Payments
  # Currency + minor-unit aware money value object: the single source of truth for
  # turning our canonical major-unit decimal `amount` into the numeric/string form
  # each PSP expects, and back. Zero-decimal awareness (JPY, KRW, …) comes from
  # RubyMoney's ISO 4217 exponent table via Billing::CurrencyResolver — never a
  # hand-rolled /100 that silently mis-scales a zero-decimal currency.
  class Money
    attr_reader :amount, :currency

    def initialize(amount, currency)
      @amount   = BigDecimal(amount.to_s)
      @currency = currency.to_s.upcase
    end

    def zero_decimal?
      Billing::CurrencyResolver.zero_decimal?(currency)
    end

    # Smallest currency unit as an integer — what Stripe's `amount` field wants:
    # cents for 2-decimal currencies, whole units for zero-decimal.
    def smallest_unit
      zero_decimal? ? amount.round.to_i : (amount * 100).round.to_i
    end

    # Major-unit decimal string — what Alipay `total_amount` / PayPal
    # `amount.value` want: "12.34" for 2-decimal, "1000" for zero-decimal.
    def decimal_string
      zero_decimal? ? amount.round.to_s : format("%.2f", amount)
    end

    # Parse a PSP-reported MAJOR-unit amount (yuan/dollars string) into a Money.
    def self.from_major(value, currency)
      return nil if value.nil? || value.to_s.strip.empty?

      new(value.to_s, currency)
    end

    # Parse a PSP-reported SMALLEST-unit integer (Stripe's `amount` field — cents
    # for 2-decimal, whole units for zero-decimal) into a Money.
    def self.from_smallest_unit(value, currency)
      return nil if value.nil?

      smallest = value.to_i
      Billing::CurrencyResolver.zero_decimal?(currency.to_s) ? new(smallest.to_s, currency) : new((smallest / 100.0).to_s, currency)
    end

    # Convert canonical major-unit decimal `amount` to ISO-4217 minor units —
    # what Billing::CurrencyResolver.format expects as its `cents` argument: cents
    # for 2-decimal currencies, whole units for zero-decimal (e.g. JPY). Exposed as
    # a class method so display-layer callers don't need to instantiate a Money.
    def self.to_iso_minor_units(amount, currency)
      new(amount, currency).smallest_unit
    end

    def self.normalize(value, currency)
      decimal = BigDecimal(value.to_s, exception: false)
      raise ArgumentError, "invalid amount" if decimal.nil? || !decimal.finite?

      scale = Billing::CurrencyResolver.zero_decimal?(currency.to_s) ? 0 : 2
      decimal.round(scale, BigDecimal::ROUND_HALF_UP)
    end

    def ==(other)
      other.is_a?(Money) && amount == other.amount && currency == other.currency
    end
  end
end
