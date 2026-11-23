# frozen_string_literal: true

module CodeGenerators
  # Operators accepted by condition rows (Decision, Loop and the step
  # `conditions` role). Unary operators take no right operand; record-count
  # rows compare the count with one of the COUNT operators.
  module ConditionOperators
    BINARY = %w[== != > >= < <= contains starts_with ends_with matches_regex in_range is_type].freeze
    UNARY = %w[is_true is_false is_empty is_not_empty is_nil].freeze
    KEYS = (BINARY + UNARY).freeze
    COUNT = %w[== != > >= < <=].freeze

    module_function

    def known?(operator)
      KEYS.include?(operator.to_s)
    end

    def unary?(operator)
      UNARY.include?(operator.to_s)
    end

    def count?(operator)
      COUNT.include?(operator.to_s)
    end

    def export(locale:)
      KEYS.map do |key|
        {
          "value" => key,
          "label" => I18n.t("flowchart_elements.operators.#{key}", locale: locale),
          "unary" => unary?(key),
          "count" => count?(key)
        }
      end
    end
  end
end
