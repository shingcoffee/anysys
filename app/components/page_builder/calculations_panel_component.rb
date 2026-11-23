# frozen_string_literal: true

module PageBuilder
  class CalculationsPanelComponent < ApplicationComponent
    include ComponentClasses

    def initialize(calculations: [], fields: [])
      @calculations = calculations || []
      @fields = fields || []
    end

    private

    attr_reader :calculations, :fields

    def empty?
      calculations.empty?
    end

    def field_label(field_id)
      field = fields.find { |f| f["id"] == field_id }
      field&.dig("label") || field_id
    end

    def truncate_formula(formula, length: 60)
      return "" if formula.blank?

      formula.length > length ? "#{formula[0...length]}…" : formula
    end

    def format_badge(calc)
      fmt_type = calc.dig("format", "type")
      return nil if fmt_type.blank? || fmt_type == "plain"

      fmt_type
    end

    def show_search?
      calculations.length > 6
    end
  end
end
