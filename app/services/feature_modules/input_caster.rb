# frozen_string_literal: true

module FeatureModules
  # Coerces a resolved handoff input payload to each target field's declared
  # type BEFORE it hits the module's Reform input_contract. Form values arrive
  # as strings; without this the contract validates raw strings and each module
  # is left to coerce implicitly (e.g. Payments upcasing currency at charge
  # time). Coercion is deliberately lenient: an uncoercible value is passed
  # through unchanged so the contract reports a precise validation error rather
  # than this caster masking it.
  class InputCaster
    def self.call(input:, fields:)
      new(fields: fields).call(input)
    end

    def initialize(fields:)
      @by_name = Array(fields).index_by(&:name)
    end

    # Returns a new hash with the same keys, values coerced by declared type.
    def call(input)
      (input || {}).each_with_object({}) do |(key, value), out|
        out[key] = cast(value, @by_name[key.to_s])
      end
    end

    private

    def cast(value, field)
      return value if field.nil?
      # A blank string means "not supplied" — nil so `presence` fires for
      # required fields and optional fields don't persist an empty string.
      return nil if value.is_a?(String) && value.strip.empty?

      case field.type
      when "integer" then coerce_integer(value)
      when "number"  then coerce_float(value)
      when "boolean" then coerce_boolean(value)
      else
        # Case-normalize against an inclusion set whenever one is declared —
        # keyed on allowed_values (not type == "enum"), even for a field
        # declared with an explicit non-enum type:.
        field.allowed_values.present? ? coerce_enum(value, field.allowed_values) : value
      end
    end

    def coerce_integer(value)
      return value if value.is_a?(Integer)
      Integer(value.to_s.strip, 10)
    rescue ArgumentError, TypeError
      value
    end

    def coerce_float(value)
      return value if value.is_a?(Numeric)
      Float(value.to_s.strip)
    rescue ArgumentError, TypeError
      value
    end

    def coerce_boolean(value)
      return value if value == true || value == false

      case value.to_s.strip.downcase
      when "true", "1", "yes", "on"  then true
      when "false", "0", "no", "off" then false
      else value
      end
    end

    # Case-normalize to the canonical allowed value (e.g. "cny" -> "CNY") so an
    # author's casing doesn't fail an exact-match inclusion validation.
    def coerce_enum(value, allowed)
      return value if Array(allowed).empty?

      Array(allowed).find { |a| a.to_s.casecmp?(value.to_s) } || value
    end
  end
end
