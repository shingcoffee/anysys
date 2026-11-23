# frozen_string_literal: true

module CodeGenerators
  # Validates the contents of a flat condition group (`{ "type" => "group",
  # "joins", "conditions" }`) for every element that stores one, so a group that
  # passes here always builds through Shared::ConditionBuilder. Blank and
  # non-Hash values are left to the schema's `required` and `conditions` role
  # checks. Errors are addressed to the owning field.
  module ConditionRules
    module_function

    # @param condition [Hash, nil] the stored group
    # @param field [String] config key the group lives under
    # @param required [Boolean] whether a group without rows is an error
    # @return [Array<CodeGenerators::ConfigError>]
    def errors(condition, field:, required: false)
      return [] unless condition.is_a?(Hash)

      group = condition.deep_stringify_keys
      return [error(field, :invalid_condition)] unless group["type"] == "group"

      rows = group["conditions"]
      return [error(field, :invalid_condition)] unless rows.is_a?(Array)
      return [error(field, :empty_condition)] if required && rows.empty?

      rows.each_with_index.flat_map { |row, index| row_errors(row, field, index + 1) }
    end

    def query_count_row?(row)
      row["kind"] == "query_count"
    end

    def row_errors(row, field, index)
      return [error(field, :invalid_row, index: index)] unless row.is_a?(Hash)

      row = row.deep_stringify_keys
      return [error(field, :nested_group, index: index)] if row["type"] == "group"
      return query_count_errors(row, field, index) if query_count_row?(row)

      left = row["leftOperand"].to_s.strip
      operator = row["operator"].to_s.strip
      return [error(field, :missing_left, index: index)] if left.empty?
      return [error(field, :missing_operator, index: index)] if operator.empty?
      return [error(field, :unknown_operator, index: index)] unless ConditionOperators.known?(operator)
      unless ConditionOperators.unary?(operator) || present?(row["rightOperand"])
        return [error(field, :missing_right, index: index, operator: operator)]
      end
      return [error(field, :invalid_regex, index: index)] if operator == "matches_regex" && !regexp?(row["rightOperand"])

      []
    end

    def query_count_errors(row, field, index)
      return [error(field, :missing_entity, index: index)] if row.dig("queryConfig", "entityId").blank?
      return [error(field, :unknown_count_operator, index: index)] unless ConditionOperators.count?(row["countOperator"])

      []
    end

    def present?(value)
      !(value.nil? || (value.is_a?(String) && value.strip.empty?))
    end

    def regexp?(pattern)
      Regexp.new(pattern.to_s)
      true
    rescue RegexpError
      false
    end

    def error(field, code, **vars)
      ConfigError.new(
        field: field.to_s,
        code: code,
        message: I18n.t("flowchart_elements.conditions.errors.#{code}", **vars)
      )
    end

    private_class_method :row_errors, :query_count_errors, :present?, :regexp?, :error
  end
end
