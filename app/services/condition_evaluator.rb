# frozen_string_literal: true

class ConditionEvaluator
  def initialize(conditions, field_values)
    @conditions = conditions || []
    @field_values = field_values || {}
  end

  def evaluate
    return true if conditions.empty?

    results = conditions.map { |condition| evaluate_condition(condition) }
    logic_types = conditions.map { |c| c["logic"] || "and" }

    combine_results(results, logic_types)
  end

  private

  attr_reader :conditions, :field_values

  def evaluate_condition(condition)
    field_id = condition["field_id"]
    operator = condition["operator"]
    expected_value = condition["value"]
    actual_value = field_values[field_id]

    case operator
    when "equals"
      actual_value == expected_value
    when "not_equals"
      actual_value != expected_value
    when "contains"
      actual_value.to_s.include?(expected_value.to_s)
    when "greater_than"
      numeric_compare(actual_value, expected_value) { |a, e| a > e }
    when "less_than"
      numeric_compare(actual_value, expected_value) { |a, e| a < e }
    when "is_empty"
      actual_value.nil? || actual_value.to_s.strip.empty?
    when "is_not_empty"
      actual_value.present? && actual_value.to_s.strip.present?
    else
      false
    end
  end

  def numeric_compare(actual, expected)
    actual_num = actual.to_f
    expected_num = expected.to_f
    yield(actual_num, expected_num)
  rescue
    false
  end

  # Flat left-fold: each condition (after the first) is combined into the running
  # result using its own "and"/"or" logic flag. No operator precedence by design —
  # conditions apply left-to-right in author order.
  def combine_results(results, logic_types)
    results.each_with_index.reduce(nil) do |combined, (result, index)|
      next result if index.zero?

      (logic_types[index] || "and") == "or" ? (combined || result) : (combined && result)
    end
  end
end
