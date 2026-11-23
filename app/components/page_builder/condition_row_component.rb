# frozen_string_literal: true

module PageBuilder
  class ConditionRowComponent < ApplicationComponent
    include ComponentClasses

    OPERATORS_BY_TYPE = {
      "number"  => %w[equals not_equals greater_than less_than greater_or_equal less_or_equal between is_empty is_not_empty],
      "date"    => %w[equals not_equals greater_than less_than between is_empty is_not_empty],
      "select"  => %w[is_selected is_not_selected equals not_equals is_empty is_not_empty],
      "radio"   => %w[is_selected is_not_selected equals not_equals is_empty is_not_empty],
      "boolean" => %w[is_selected is_not_selected],
      "default" => %w[equals not_equals contains not_contains starts_with ends_with matches_regex is_empty is_not_empty]
    }.freeze

    NO_VALUE_OPERATORS = %w[is_empty is_not_empty is_selected is_not_selected].freeze

    def initialize(item:, fields:, group_index:, item_index:)
      @item        = item || {}
      @fields      = fields || []
      @group_index = group_index
      @item_index  = item_index
    end

    def operators_for_type
      ft = field_type
      keys = OPERATORS_BY_TYPE[ft] || OPERATORS_BY_TYPE["default"]
      keys.map { |k| { value: k, label: I18n.t("comp_page_builder.operators.#{k}", default: k) } }
    end

    # Returns: :none | :select | :number | :number_range | :date | :date_range | :boolean | :text
    def value_editor_kind
      return :none if NO_VALUE_OPERATORS.include?(current_operator)
      case field_type
      when "select", "radio"     then :select
      when "boolean"             then :boolean
      when "number"
        current_operator == "between" ? :number_range : :number
      when "date"
        current_operator == "between" ? :date_range : :date
      else
        :text
      end
    end

    def field
      @field ||= fields.find { |f| f["id"] == item["field_id"] }
    end

    def field_options
      field ? (field["options"] || []) : []
    end

    private

    attr_reader :item, :fields, :group_index, :item_index

    def field_type
      field&.dig("property_type") || "default"
    end

    def current_operator
      item["operator"] || "equals"
    end

    def current_value
      item["value"]&.to_s || ""
    end
  end
end
