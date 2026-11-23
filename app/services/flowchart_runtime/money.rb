# frozen_string_literal: true

module FlowchartRuntime
  # Shared BigDecimal rounding for finance step actions.
  # Amounts are serialized as fixed-scale decimal strings because BigDecimal
  # is not a JSON native type (stdlib JSON.generate raises TypeError).
  # Not the money gem: steps need currency-agnostic precision and the
  # remainder strategies its subunit-only Money#allocate does not offer.
  module Money
    class Error < StandardError; end

    ROUNDING = {
      "half_up" => BigDecimal::ROUND_HALF_UP,
      "half_even" => BigDecimal::ROUND_HALF_EVEN,
      "floor" => BigDecimal::ROUND_FLOOR,
      "ceiling" => BigDecimal::ROUND_CEILING
    }.freeze

    module_function

    def decimal(value)
      case value
      when BigDecimal then value
      when Integer then BigDecimal(value)
      when nil then nil
      else
        text = value.to_s.strip
        return nil if text.empty?

        BigDecimal(text)
      end
    rescue ArgumentError, TypeError
      nil
    end

    def round(value, precision, mode = "half_up")
      amount = value.is_a?(BigDecimal) ? value : decimal(value)
      raise Error, "not a number" if amount.nil?

      amount.round(precision.to_i, rounding_mode(mode))
    end

    def serialize(value, precision, mode = "half_up")
      places = precision.to_i
      rounded = round(value, places, mode)
      format_decimal(rounded, places)
    end

    def format_decimal(amount, precision)
      places = precision.to_i
      sign = amount.negative? ? "-" : ""
      text = amount.abs.to_s("F")
      integer, fraction = text.split(".", 2)
      return "#{sign}#{integer}" if places <= 0

      frac = (fraction || "").ljust(places, "0")[0, places]
      "#{sign}#{integer}.#{frac}"
    end

    def unit(precision)
      BigDecimal(10)**-precision.to_i
    end

    def rounding_mode(mode)
      ROUNDING.fetch(mode.to_s) { ROUNDING.fetch("half_up") }
    end

    def zero
      BigDecimal("0")
    end
  end
end
