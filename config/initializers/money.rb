# frozen_string_literal: true

require "money"

# RubyMoney global configuration. Money is used only through the thin
# Billing::CurrencyResolver wrapper (ISO 4217 symbols, subunit math, zero-decimal
# awareness). Formatting is pinned deterministically there, so we disable the
# locale backend to keep output independent of the request's I18n.locale.
Money.locale_backend = nil
Money.rounding_mode  = BigDecimal::ROUND_HALF_UP
Money.default_currency = "USD"
