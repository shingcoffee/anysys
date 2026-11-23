# frozen_string_literal: true

module FlowchartRuntime
  # Scalar math for math_operation. Arithmetic uses BigDecimal so money
  # totals are not corrupted by binary float rounding.
  module Numbers
    class Error < StandardError; end

    UNARY = %w[abs floor ceil round sqrt].freeze
    BINARY = %w[add subtract multiply divide modulo power min max percent].freeze
    CLAMP = %w[clamp].freeze
    OPERATIONS = (UNARY + BINARY + %w[random] + CLAMP).freeze
    PRECISION_OPERATIONS = %w[add subtract multiply divide power percent clamp sqrt].freeze
    DIVIDE_POLICIES = %w[raise nil zero infinity nan].freeze
    ROUNDING_MODES = Money::ROUNDING.keys.freeze
    SQRT_DIGITS = 16

    module_function

    def apply(source, operation:, other: nil, precision: nil, divide_by_zero: "raise",
              min_value: 0, max_value: 100, rounding_mode: "half_up")
      name = operation.to_s
      raise Error, "unsupported operation" unless OPERATIONS.include?(name)

      result = if UNARY.include?(name)
        unary(name, source, precision, rounding_mode)
      elsif BINARY.include?(name)
        binary(name, source, other, divide_by_zero)
      elsif CLAMP.include?(name)
        clamp_value(source, min_value, max_value)
      else
        random_value(min_value, max_value)
      end

      apply_precision(result, precision, name, rounding_mode)
    rescue Math::DomainError, ZeroDivisionError, FloatDomainError, RangeError, TypeError, ArgumentError => error
      raise Error, error.message
    rescue Money::Error => error
      raise Error, error.message
    end

    def unary(operation, source, precision, rounding_mode)
      value = decimal!(source)
      case operation
      when "abs" then value.abs
      when "floor" then value.floor
      when "ceil" then value.ceil
      when "round"
        places = precision.nil? || precision == "" ? 0 : precision.to_i
        Money.round(value, places, rounding_mode)
      when "sqrt"
        raise Error, "square root of a negative number" if value.negative?

        value.sqrt(SQRT_DIGITS)
      end
    end

    def binary(operation, source, other, divide_by_zero)
      left = decimal!(source)
      right = decimal!(other)
      case operation
      when "add" then left + right
      when "subtract" then left - right
      when "multiply" then left * right
      when "divide" then divide(left, right, divide_by_zero, :divide)
      when "modulo" then divide(left, right, divide_by_zero, :modulo)
      when "power" then left ** right
      when "min" then [left, right].min
      when "max" then [left, right].max
      when "percent" then percent(left, right, divide_by_zero)
      end
    end

    def percent(left, right, divide_by_zero)
      quotient = divide(left, right, divide_by_zero, :divide)
      quotient.nil? || !quotient.is_a?(Numeric) ? quotient : quotient * 100
    end

    def clamp_value(source, min_value, max_value)
      lo = decimal!(min_value)
      hi = decimal!(max_value)
      raise Error, "clamp bounds are invalid" if lo > hi

      decimal!(source).clamp(lo, hi)
    end

    def random_value(min_value, max_value)
      lo = min_value.to_i
      hi = max_value.to_i
      raise Error, "random bounds are invalid" if lo > hi

      rand(lo..hi)
    end

    def divide(left, right, policy, op)
      return fallback(policy) if right.zero?

      op == :modulo ? left % right : left / right
    end

    def fallback(policy)
      case policy.to_s
      when "infinity" then Float::INFINITY
      when "nan" then Float::NAN
      when "zero" then Money.zero
      when "nil" then nil
      else raise Error, "division by zero"
      end
    end

    def apply_precision(result, precision, operation, rounding_mode = "half_up")
      return result if precision.nil? || precision == ""
      return result unless PRECISION_OPERATIONS.include?(operation)
      return result unless result.is_a?(Numeric)
      return result if result.is_a?(Float) && !result.finite?

      Money.round(result, precision.to_i, rounding_mode)
    end

    def decimal!(value)
      amount = Money.decimal(value)
      raise Error, "not a number" if amount.nil?

      amount
    end
  end
end
