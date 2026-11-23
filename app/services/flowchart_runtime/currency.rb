# frozen_string_literal: true

module FlowchartRuntime
  # Amount conversion for the currency_convert step. Rates come from a fixed
  # number, a ctx hash, or an inline table — never an arbitrary HTTP URL.
  module Currency
    class Error < StandardError; end

    RATE_SOURCES = %w[fixed ctx config].freeze
    MISSING_RATE = "missing rate"
    ON_MISSING_RATE = %w[fail identity].freeze
    ROUNDING = Money::ROUNDING
    CURRENCY_RE = /\A[A-Z]{3}\z/

    module_function

    def convert(ctx, amount:, from:, to:, rate_source:, fixed_rate: nil, rates: nil,
                static_rates: {}, rounding: "half_up", precision: 2, on_missing_rate: "fail")
      source = rate_source.to_s
      raise Error, "unsupported rate source" unless RATE_SOURCES.include?(source)

      from_code = normalize_code(from)
      to_code = normalize_code(to)
      value = Money.decimal(amount)
      raise Error, "not a number" if value.nil?

      rate = resolve_rate(source, from_code: from_code, to_code: to_code,
                                  fixed_rate: fixed_rate, rates: rates, static_rates: static_rates)
      Money.serialize(value * rate, precision, rounding)
    rescue Error => error
      raise unless on_missing_rate.to_s == "identity" && error.message == MISSING_RATE

      Money.serialize(value, precision, rounding)
    end

    def resolve_rate(source, from_code:, to_code:, fixed_rate:, rates:, static_rates:)
      return Money.decimal("1") if from_code == to_code

      case source
      when "fixed"
        rate = Money.decimal(fixed_rate)
        raise Error, MISSING_RATE if rate.nil?

        rate
      when "ctx"
        table_rate(rates, from_code, to_code)
      else
        table_rate(static_rates, from_code, to_code)
      end
    end

    def table_rate(table, from_code, to_code)
      hash = stringify_rates(table)
      pair = hash["#{from_code}_#{to_code}"] || hash["#{from_code}#{to_code}"]
      return pair if pair

      if hash.key?(from_code) && hash.key?(to_code)
        from_rate = hash[from_code]
        raise Error, MISSING_RATE if from_rate.zero?

        return hash[to_code] / from_rate
      end
      raise Error, MISSING_RATE unless hash.key?(to_code)

      hash[to_code]
    end

    def stringify_rates(raw)
      return {} unless raw.is_a?(Hash)

      raw.each_with_object({}) do |(key, value), memo|
        amount = Money.decimal(value)
        next if amount.nil?

        memo[key.to_s.upcase] = amount
      end
    end

    def normalize_code(code)
      token = code.to_s.strip.upcase
      raise Error, "invalid currency" unless CURRENCY_RE.match?(token)

      token
    end
    private_class_method :resolve_rate, :table_rate, :stringify_rates, :normalize_code
  end
end
