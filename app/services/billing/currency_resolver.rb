# frozen_string_literal: true

module Billing
  # Single app-level interface for currency presentation. Backed by RubyMoney
  # (the `money` gem) for the ISO 4217 symbol table, per-currency subunit
  # (decimal-place) knowledge, and zero-decimal awareness — none of which should
  # be hand-maintained. Locale→currency selection stays app domain logic.
  #
  # Formatting is pinned to "symbol immediately before the amount, no thousands
  # separator" ("%u%n") so rendered output is deterministic across tenants and
  # request locales.
  module CurrencyResolver
    module_function

    # Map a UI locale to the tenant's display currency.
    def for_locale(locale)
      locale.to_s.downcase.start_with?("zh") ? "CNY" : "USD"
    end

    def for_customer(customer)
      locale = customer.respond_to?(:locale) ? customer.locale : nil
      for_locale(locale.presence || I18n.locale)
    end

    # ISO 4217 symbol for the currency (e.g. "$", "¥", "€"), falling back to the
    # upcased code itself for currencies RubyMoney does not know.
    def symbol(currency)
      money_currency(currency)&.symbol || currency.to_s.upcase
    end

    # Format an integer amount of minor units (cents) for display, e.g.
    # 99900, "CNY" => "¥999.00"; 1000, "JPY" => "¥1000" (zero-decimal).
    def format(cents, currency)
      if (cur = money_currency(currency))
        Money.new(cents.to_i, cur).format(format: "%u%n", thousands_separator: "")
      else
        # Unknown currency: preserve the legacy 2-decimal fallback.
        "#{symbol(currency)}#{'%.2f' % (BigDecimal(cents.to_s) / 100)}"
      end
    end

    # Format a major-unit (whole-currency, e.g. dollars) amount for display, e.g.
    # 29.5, "USD" => "$29.50". Used where a price is stored as a decimal rather
    # than integer minor units.
    def format_amount(amount, currency)
      if (cur = money_currency(currency))
        Money.from_amount(amount.to_d, cur).format(format: "%u%n", thousands_separator: "")
      else
        "#{symbol(currency)}#{'%.2f' % amount.to_d}"
      end
    end

    # True for currencies with no minor unit (JPY, KRW, …). Delegates to
    # RubyMoney's ISO exponent table instead of a hand-maintained list.
    def zero_decimal?(currency)
      cur = money_currency(currency)
      cur ? cur.exponent.zero? : false
    end

    # @api private
    def money_currency(currency)
      return nil if currency.to_s.strip.empty?

      Money::Currency.new(currency)
    rescue Money::Currency::UnknownCurrency
      nil
    end
  end
end
