# frozen_string_literal: true

module FlowchartRuntime
  # Lookup-table mapping for map_value (exact / regex / range).
  module ValueMap
    class Error < StandardError; end

    RANGE_PATTERN = /\A\s*(-?\d+(?:\.\d+)?)?\s*(\.\.\.?)\s*(-?\d+(?:\.\d+)?)?\s*\z/

    module_function

    def apply(value, match_mode:, mappings: {}, rules: [], fallback: "default",
              default: nil, multi_match: false, case_sensitive: true)
      case match_mode.to_s
      when "regex" then rule_match(value, rules, :regex, fallback, default, multi_match, case_sensitive)
      when "range" then rule_match(value, rules, :range, fallback, default, multi_match, case_sensitive)
      else exact_match(value, mappings, fallback, default, multi_match, case_sensitive)
      end
    end

    def exact_match(value, mappings, fallback, default, multi_match, case_sensitive)
      table = mappings.to_h.each_with_object({}) do |(key, mapped), acc|
        lookup = case_sensitive ? key.to_s : key.to_s.downcase
        acc[lookup] = mapped.to_s
      end
      input = case_sensitive ? value.to_s : value.to_s.downcase
      if multi_match
        hits = table.keys.select { |key| key == input }.map { |key| table[key] }
        fallback_value(hits, input, value, fallback, default, multi: true)
      else
        return table[input] if table.key?(input)

        single_fallback(input, value, fallback, default)
      end
    end

    def rule_match(value, rules, kind, fallback, default, multi_match, case_sensitive)
      normalized = Array(rules).filter_map do |rule|
        row = rule.is_a?(Hash) ? rule.stringify_keys : { "pattern" => rule.to_s, "value" => rule.to_s }
        pattern = row["pattern"] || row["key"]
        next if pattern.nil?

        { "pattern" => pattern.to_s, "value" => (row.key?("value") ? row["value"] : row["key"]).to_s }
      end
      matcher = ->(pattern) { kind == :regex ? regex_hit?(pattern, value, case_sensitive) : range_hit?(pattern, value) }
      if multi_match
        hits = normalized.select { |rule| matcher.call(rule["pattern"]) }.map { |rule| rule["value"] }
        fallback_value(hits, value.to_s, value, fallback, default, multi: true)
      else
        hit = normalized.find { |rule| matcher.call(rule["pattern"]) }
        return hit["value"] if hit

        single_fallback(value.to_s, value, fallback, default)
      end
    end

    def regex_hit?(pattern, value, case_sensitive)
      flags = case_sensitive ? 0 : Regexp::IGNORECASE
      Regexp.new(pattern, flags).match?(value.to_s)
    end

    def range_hit?(pattern, value)
      range = parse_range(pattern)
      range&.cover?(value)
    end

    def parse_range(pattern)
      match = RANGE_PATTERN.match(pattern.to_s)
      return nil unless match && (match[1] || match[3])

      lo = numeric(match[1])
      hi = numeric(match[3])
      Range.new(lo, hi, match[2] == "...")
    end

    def numeric(raw)
      return if raw.nil?

      raw.include?(".") ? raw.to_f : raw.to_i
    end

    def fallback_value(hits, input, original, fallback, default, multi:)
      return hits if hits.any?

      single_fallback(input, original, fallback, default)
    end

    def single_fallback(input, original, fallback, default)
      case fallback.to_s
      when "pass_through" then original
      when "raise" then raise Error, "no mapping for #{input}"
      else default
      end
    end
  end
end
