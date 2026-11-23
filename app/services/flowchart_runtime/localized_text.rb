# frozen_string_literal: true

module FlowchartRuntime
  # Resolves author-written `{ "en", "zh-CN" }` hashes (Q2) for public flash
  # and fail_message. English is required at validation; request locale falls
  # back to en.
  module LocalizedText
    class Error < StandardError; end

    module_function

    def resolve(value, locale:, variables: nil)
      table = stringify(value)
      return "" if table.empty?

      requested = locale.to_s
      interpolate(table[requested].presence || table["en"].to_s, variables)
    end

    def interpolate(text, variables)
      return text.to_s if variables.blank?

      vars = variables.to_h.each_with_object({}) do |(key, value), acc|
        acc[key.to_s] = value.to_s
      end
      text.to_s.gsub(/%\{(\w+)\}/) { |match| vars.fetch(Regexp.last_match(1), match) }
    end

    def interpolate_each(value, variables)
      return value if value.nil? || variables.blank?

      stringify(value).transform_values { |text| interpolate(text, variables) }
    end

    def stringify(value)
      return {} if value.nil?
      return { "en" => value.to_s } unless value.respond_to?(:to_h)

      value.to_h.stringify_keys
    end
    private_class_method :stringify
  end
end
