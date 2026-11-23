# frozen_string_literal: true

module PageBuilder
  class ConditionBuilderComponent < ApplicationComponent
    include ComponentClasses

    OPERATOR_VALUES = %w[equals not_equals contains not_contains greater_than less_than is_empty is_not_empty].freeze

    attr_reader :field_id, :conditions, :available_fields, :action

    def initialize(field_id:, conditions: [], available_fields: [], action: "show")
      @field_id = field_id
      @conditions = conditions || []
      @available_fields = available_fields || []
      @action = action
    end

    def operators
      OPERATOR_VALUES.map do |v|
        { value: v, label: I18n.t("comp_page_builder.condition_builder.operators.#{v}") }
      end
    end
  end
end
