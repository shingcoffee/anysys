# frozen_string_literal: true

# ConditionBuilderComponent
#
# Reusable ViewComponent for building condition rules in the flowchart
# and page builder editors. Used for:
# - Connection conditions (Decision/Switch branching)
# - Loop break conditions
# - Page display rules (show/hide fields)
#
# Renders an AND/OR toggle with a dynamic list of condition rules.
# Each rule has: field picker, operator picker, value input.
#
# @example In an ERB template
#   <%= render ConditionBuilderComponent.new(
#     conditions: connection.condition,
#     fields: entity.property_schema_json,
#     form_target: "connectionCondition"
#   ) %>
#
class ConditionBuilderComponent < ApplicationComponent
  # Programmatic operator value + i18n key. Labels are resolved at render time
  # (never at class-load) via #operators so the current locale is honoured.
  OPERATORS = [
    { value: "==", key: "equals" },
    { value: "!=", key: "not_equals" },
    { value: ">", key: "greater_than" },
    { value: ">=", key: "greater_or_equal" },
    { value: "<", key: "less_than" },
    { value: "<=", key: "less_or_equal" },
    { value: "blank?", key: "is_blank" },
    { value: "present?", key: "is_present" },
    { value: "contains", key: "contains" },
    { value: "starts_with", key: "starts_with" },
    { value: "ends_with", key: "ends_with" },
    { value: "in", key: "is_one_of" },
    { value: "matches?", key: "matches_pattern" }
  ].freeze

  NO_VALUE_OPERATORS = %w[blank? present?].freeze

  attr_reader :conditions, :fields, :form_target, :context_name

  # @param conditions [Hash, nil] existing condition config {operator: "AND", rules: [...]}
  # @param fields [Array<Hash>] available fields [{name_slug: "...", name: "..."}]
  # @param form_target [String] data attribute target name for form binding
  # @param context_name [String] label for the context variable (default: "ctx")
  def initialize(conditions: nil, fields: [], form_target: "conditions", context_name: "ctx")
    @conditions = conditions || { "operator" => "AND", "rules" => [] }
    @fields = fields
    @form_target = form_target
    @context_name = context_name
  end

  def rules
    conditions["rules"] || []
  end

  def top_operator
    conditions["operator"] || "AND"
  end

  def operators
    OPERATORS.map do |op|
      { value: op[:value], label: I18n.t("chrome.condition_builder.operators.#{op[:key]}") }
    end
  end

  def no_value_operator?(op)
    NO_VALUE_OPERATORS.include?(op)
  end

  def system_fields
    [
      { "name_slug" => "customer_id", "name" => I18n.t("chrome.condition_builder.system_fields.customer_id"), "type" => "integer" },
      { "name_slug" => "current_user_id", "name" => I18n.t("chrome.condition_builder.system_fields.current_user_id"), "type" => "integer" },
      { "name_slug" => "created_at", "name" => I18n.t("chrome.condition_builder.system_fields.created_at"), "type" => "datetime" },
      { "name_slug" => "updated_at", "name" => I18n.t("chrome.condition_builder.system_fields.updated_at"), "type" => "datetime" }
    ]
  end

  def all_fields
    fields + system_fields
  end
end
