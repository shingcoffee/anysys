# frozen_string_literal: true

require "hashdiff"

module FlowchartRuntime
  # Hash comparison for compare_data (deep gem diff plus equality / schema / keys).
  module HashDiff
    class Error < StandardError; end

    module_function

    def diff(left, right)
      raise Error, "left operand is required" if left.nil?
      raise Error, "right operand is required" if right.nil?

      Hashdiff.diff(left, right)
    end

    def compare(left, right, mode: "keys", comparison_type: "diff",
                ignore_keys: [], case_insensitive: false, numeric_tolerance: 0)
      left_hash = except_keys(coerce(left), ignore_keys)
      right_hash = except_keys(coerce(right), ignore_keys)
      if case_insensitive
        left_hash = downcase_strings(left_hash)
        right_hash = downcase_strings(right_hash)
      end

      case comparison_type.to_s
      when "equal", "deep_equal" then hashes_equal?(left_hash, right_hash, numeric_tolerance.to_f)
      when "schema_match" then left_hash.keys.sort == right_hash.keys.sort
      when "equality" then equality_mode(left_hash, right_hash, mode.to_s, numeric_tolerance.to_f)
      else
        {
          added: right_hash.except(*left_hash.keys),
          removed: left_hash.except(*right_hash.keys),
          changed: changed_fields(left_hash, right_hash, numeric_tolerance.to_f)
        }
      end
    end

    def coerce(value)
      return {} if value.nil?
      return value if value.is_a?(Hash)
      return value.to_liquid if value.is_a?(EntityEntry)
      return value.to_h if value.respond_to?(:to_h)

      raise Error, "not a hash"
    end

    def hashes_equal?(left, right, tolerance)
      return left == right unless tolerance.positive?

      changed_fields(left, right, tolerance).empty? &&
        left.keys == right.keys
    end

    def except_keys(hash, keys)
      names = Array(keys).map { |key| key.respond_to?(:to_sym) ? key.to_sym : key }
      string_names = names.map(&:to_s)
      hash.except(*names, *string_names)
    end

    def downcase_strings(value)
      case value
      when Hash then value.transform_values { |item| downcase_strings(item) }
      when Array then value.map { |item| downcase_strings(item) }
      when String then value.downcase
      else value
      end
    end

    def equality_mode(left, right, mode, tolerance)
      case mode
      when "values"
        common = left.keys & right.keys
        left_slice = left.slice(*common)
        right_slice = right.slice(*common)
        { equal: left_slice == right_slice, left: left_slice, right: right_slice }
      when "deep"
        diff(left, right)
      else
        {
          added: right.except(*left.keys),
          removed: left.except(*right.keys),
          changed: changed_fields(left, right, tolerance)
        }
      end
    end

    def list_diff(left, right, tolerance)
      {
        added: right.keys - left.keys,
        removed: left.keys - right.keys,
        changed: changed_fields(left, right, tolerance)
      }
    end

    def changed_fields(left, right, tolerance)
      left.each_with_object({}) do |(key, val), acc|
        next unless right.key?(key)

        other = right[key]
        equal = if tolerance.positive? && val.is_a?(Numeric) && other.is_a?(Numeric)
          (val - other).abs <= tolerance
        else
          val == other
        end
        acc[key] = { from: val, to: other } unless equal
      end
    end
  end
end
