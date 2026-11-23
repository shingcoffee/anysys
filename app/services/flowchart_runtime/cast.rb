# frozen_string_literal: true

require "bigdecimal"
require "json"

module FlowchartRuntime
  # Type conversion for type_cast using ActiveModel::Type (locale-safe).
  module Cast
    class Error < StandardError; end

    module_function

    ON_ERRORS = %w[fail nil default].freeze

    def apply(value, type:, format: nil, timezone_aware: false, timezone: nil, strict_boolean: false,
              on_error: "fail", default_value: nil)
      case type.to_s
      when "string" then ActiveModel::Type::String.new.cast(value)
      when "integer" then integer_cast(value)
      when "decimal", "float", "big_decimal" then decimal_cast(value)
      when "boolean" then boolean_cast(value, strict_boolean)
      when "date" then date_cast(value, format)
      when "datetime", "date_time", "time" then datetime_cast(value, format, timezone.presence || (timezone_aware ? Time.zone&.name : nil))
      when "array" then array_cast(value)
      when "hash" then hash_cast(value)
      when "json" then value.to_json
      else raise Error, "unsupported type: #{type}"
      end
    rescue ArgumentError, TypeError, Date::Error, RangeError, JSON::ParserError => error
      recover(on_error, default_value, error)
    end

    def recover(on_error, default_value, error)
      case on_error.to_s
      when "nil" then nil
      when "default" then default_value
      else raise Error, error.message
      end
    end
    private_class_method :recover

    def integer_cast(value)
      return value if value.is_a?(Integer)
      raise ArgumentError, "invalid integer" unless integer_text?(value)

      ActiveModel::Type::Integer.new.cast(value)
    end
    private_class_method :integer_cast

    def decimal_cast(value)
      return value if value.is_a?(BigDecimal) || value.is_a?(Integer) || value.is_a?(Float)
      raise ArgumentError, "invalid decimal" unless decimal_text?(value)

      ActiveModel::Type::Decimal.new.cast(value)
    end
    private_class_method :decimal_cast

    def integer_text?(value)
      value.to_s.strip.match?(/\A[+-]?\d+\z/)
    end
    private_class_method :integer_text?

    def decimal_text?(value)
      value.to_s.strip.match?(/\A[+-]?\d+(?:\.\d+)?\z/)
    end
    private_class_method :decimal_text?

    def boolean_cast(value, strict)
      if strict
        [true, "true", 1].include?(value)
      else
        ActiveModel::Type::Boolean.new.cast(value)
      end
    end
    private_class_method :boolean_cast

    def date_cast(value, format)
      return value if value.is_a?(Date) && !value.is_a?(DateTime)

      if format.to_s.present?
        Date.strptime(value.to_s, format.to_s)
      else
        ActiveModel::Type::Date.new.cast(value) || Date.parse(value.to_s)
      end
    end
    private_class_method :date_cast

    def datetime_cast(value, format, timezone)
      zone = timezone.to_s.presence
      Time.use_zone(zone || Time.zone&.name || "UTC") do
        if format.to_s.present?
          Time.zone.strptime(value.to_s, format.to_s)
        elsif value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
          zone ? value.in_time_zone(zone) : value.in_time_zone
        else
          Time.zone.parse(value.to_s) || raise(ArgumentError, "invalid datetime")
        end
      end
    end
    private_class_method :datetime_cast

    def array_cast(value)
      return value if value.is_a?(Array)
      if value.is_a?(String)
        stripped = value.strip
        if stripped.start_with?("[")
          parsed = JSON.parse(stripped)
          return parsed if parsed.is_a?(Array)
        end
      end
      Array(value)
    end
    private_class_method :array_cast

    def hash_cast(value)
      return value if value.is_a?(Hash)
      return value.to_h if value.respond_to?(:to_h)

      raise ArgumentError, "invalid hash"
    end
    private_class_method :hash_cast
  end
end
