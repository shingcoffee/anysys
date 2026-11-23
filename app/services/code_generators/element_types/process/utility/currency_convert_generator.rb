# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Utility
        class CurrencyConvertGenerator < BaseGenerator
          RATE_SOURCES = FlowchartRuntime::Currency::RATE_SOURCES
          ROUNDING_MODES = FlowchartRuntime::Currency::ROUNDING.keys.freeze

          generator_metadata do
            description "Converts amount from fromCurrency to toCurrency with BigDecimal rounding and " \
                        "stores a fixed-scale decimal string on resultVar (default converted). Use this " \
                        "for checkout totals, refunds, and invoices; do not call an external rate API " \
                        "(none is configured). rateSource fixed (default) uses fixedRate (1 USD = 0.92 " \
                        "EUR). ctx reads a rates hash from ratesVariable (pair USD_EUR, a to-code, or " \
                        "a base table for a cross rate). config uses staticRates. fromCurrencyFrom / " \
                        "toCurrencyFrom override the ISO codes from ctx. onMissingRate fail refuses; " \
                        "identity keeps the original amount. Same-currency copies the rounded amount."
            category :utility
            version "2.0.0"
            presentation icon: "M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z",
                         color: "emerald", single_use: false, privileged: false
          end

          config_schema do
            input :amount, required: true, example: "price",
                  description: "Ctx path of the amount to convert, such as price or order.total. " \
                               "Required. Parsed with BigDecimal; blank or non-numeric values fail."
            literal :fromCurrency, default: "USD", placeholder: true,
                    description: "Source ISO-4217 code (three letters), such as USD. Default USD. " \
                                 "Ignored when fromCurrencyFrom is set."
            literal :toCurrency, required: true, example: "EUR", placeholder: true,
                    description: "Target ISO-4217 code (three letters), such as EUR. Required. " \
                                 "Ignored when toCurrencyFrom is set."
            enum :rateSource, RATE_SOURCES, default: "fixed",
                 description: "Where the rate comes from. fixed (default) uses fixedRate. ctx reads " \
                              "ratesVariable. config uses the staticRates table. No HTTP fetch."
            decimal :fixedRate, min: 0, example: 0.92, visible: { rateSource: "fixed" },
                    description: "Multiplier when rateSource is fixed, such as 0.92 for 1 USD to EUR. " \
                                 "Required for fixed. Must be zero or greater."
            enum :rounding, ROUNDING_MODES, default: "half_up",
                 description: "BigDecimal rounding: half_up (default), half_even (banker's), floor, or " \
                              "ceiling. Applied after multiplying by the rate."
            integer :precision, min: 0, max: 12, default: 2,
                    description: "Decimal places kept on the result string (0-12). Default 2 for most " \
                                 "currencies. Use 0 for zero-decimal currencies such as JPY."
            input :ratesVariable, default: "exchange_rates", visible: { rateSource: "ctx" },
                  description: "Ctx path of a rates hash when rateSource is ctx. Default exchange_rates. " \
                               "Keys may be USD_EUR, EUR (rate from fromCurrency), or a base table for a cross rate."
            mapping :staticRates, key: :literal, value: :literal, default: [], visible: { rateSource: "config" },
                    description: "Inline rate table when rateSource is config. Keys are ISO codes or " \
                                 "pairs (USD_EUR); values are multipliers such as 0.92."
            output :resultVar, default: "converted",
                   description: "Ctx variable for the rounded decimal string, such as 9.20. Default converted."
            input :fromCurrencyFrom, placeholder: true, group: :advanced,
                  description: "Ctx path that overrides fromCurrency when set, such as order.currency. " \
                               "Leave blank to use the From Currency literal."
            input :toCurrencyFrom, placeholder: true, group: :advanced,
                  description: "Ctx path that overrides toCurrency when set, such as display_currency. " \
                               "Leave blank to use the To Currency literal."
            enum :onMissingRate, FlowchartRuntime::Currency::ON_MISSING_RATE, default: "fail", group: :advanced,
                 description: "When the table has no rate: fail (default) refuses the step; identity " \
                              "stores the original amount rounded to precision."
            requires :fixedRate, when: { rateSource: "fixed" }
            validate do |cfg, errors|
              %w[fromCurrency toCurrency].each do |field|
                code = cfg[field].to_s.strip
                next if code.empty?

                errors.add(field.to_sym, :invalid_currency) unless code.match?(/\A[A-Za-z]{3}\z/)
              end
            end
          end

          def generate_body
            attempt('"currency_convert.failed"', FlowchartRuntime::Currency::Error) do
              [
                "converted = FlowchartRuntime::Currency.convert(ctx, #{convert_args})",
                assign(:resultVar, "converted"),
                "true"
              ]
            end
          end

          private

          def convert_args
            source = value(:rateSource).to_s
            [
              "amount: #{read(:amount)}",
              "from: #{currency_arg(:fromCurrencyFrom, :fromCurrency)}",
              "to: #{currency_arg(:toCurrencyFrom, :toCurrency)}",
              "rate_source: #{read(:rateSource)}",
              ("fixed_rate: #{read(:fixedRate)}" if source == "fixed"),
              ("rates: #{read(:ratesVariable)}" if source == "ctx"),
              ("static_rates: #{static_rates_hash}" if source == "config"),
              ("rounding: #{read(:rounding)}" unless value(:rounding).to_s == "half_up"),
              ("precision: #{read(:precision)}" unless value(:precision) == 2),
              ("on_missing_rate: #{read(:onMissingRate)}" unless value(:onMissingRate).to_s == "fail")
            ].compact.join(", ")
          end

          def currency_arg(from_field, literal_field)
            value(from_field).to_s.strip.empty? ? read(literal_field) : read(from_field)
          end

          def static_rates_hash
            pairs = mapping_rows(:staticRates).filter_map do |row|
              next unless row.is_a?(Hash)

              key = row["key"] || row[:key]
              val = row["value"] || row[:value]
              next if key.to_s.strip.empty?

              amount = FlowchartRuntime::Money.decimal(val)
              serialized = amount ? amount.to_s("F").inspect : val.to_s.inspect
              "#{key.to_s.upcase.inspect} => #{serialized}"
            end
            "{#{pairs.join(', ')}}"
          end

          def mapping_rows(name)
            raw = value(name)
            case raw
            when Hash then raw.map { |key, val| { "key" => key.to_s, "value" => val } }
            when Array then raw
            else []
            end
          end
        end
      end
    end
  end
end
