# frozen_string_literal: true

module FlowchartRuntime
  # Normalizes the condition inputs the flowchart property editor collects for
  # model-operation actions, so a generator either honors what the user typed
  # or reports a validation error — never silently drops it.
  #
  # Two shapes are supported:
  #
  # * **structured** — the nested condition Hash the condition builder emits
  #   (`{"type" => "group", "conditions" => [...]}`). The editor exposes some
  #   of these fields as free text, so an equivalent JSON document is accepted
  #   and parsed.
  # * **literal pairs** — a `key_value_list` of `column -> expression` entries
  #   compiled into a `where(column: expression)` call. Column names are held
  #   to a bare-identifier rule so a crafted key cannot splice extra hash keys
  #   (or arbitrary Ruby) into the emitted query.
  module ConditionInput
    COLUMN_RE = /\A[a-z_][a-zA-Z0-9_]*\z/

    module_function

    # True when the user supplied something for the field.
    def provided?(raw)
      case raw
      when nil then false
      when Hash, Array then raw.any?
      else raw.to_s.strip.present?
      end
    end

    # The structured condition Hash, or nil when the input cannot be used.
    def structured(raw)
      case raw
      when Hash then usable_hash(raw)
      when String then usable_hash(parse_json(raw))
      end
    end

    # [[column, raw_value], ...] for a key_value_list / Hash input, keeping
    # only entries whose column is a bare identifier.
    def literal_pairs(raw)
      entries =
        case raw
        when Hash then raw.map { |k, v| [k.to_s, v] }
        when Array
          raw.filter_map do |entry|
            next nil unless entry.is_a?(Hash)

            [(entry["key"] || entry[:key]).to_s, entry["value"] || entry[:value]]
          end
        else []
        end

      entries.select { |column, _| safe_column?(column) }
    end

    def safe_column?(name)
      COLUMN_RE.match?(name.to_s)
    end

    # Numeric comparison for decision/loop operators. Both sides must be
    # finite Numeric or numeric strings; otherwise the comparison is false
    # (never raises on form strings like "150" > 100). Only the four
    # relational operators are valid — the builder is the sole emitter.
    def compare(left, operator, right)
      op = operator.to_s
      unless %w[> >= < <=].include?(op)
        raise ArgumentError, "unsupported comparison operator: #{op.inspect}"
      end

      left_n = coerce_numeric(left)
      right_n = coerce_numeric(right)
      return false if left_n.nil? || right_n.nil?

      left_n.public_send(op, right_n)
    end

    def usable_hash(value)
      return nil unless value.is_a?(Hash)
      return nil if value["type"].to_s.strip.empty?

      value
    end

    def parse_json(text)
      JSON.parse(text)
    rescue JSON::ParserError, TypeError
      nil
    end

    def coerce_numeric(value)
      number =
        case value
        when Integer then value
        when Float then value
        when Numeric then value.to_f
        when String
          stripped = value.strip
          return nil if stripped.empty?

          Float(stripped)
        end
      return nil unless finite_number?(number)

      number
    rescue ArgumentError, TypeError
      nil
    end

    def finite_number?(number)
      return false if number.nil?
      return number.finite? if number.is_a?(Float)
      return number.finite? if number.respond_to?(:finite?)

      true
    end
  end
end
