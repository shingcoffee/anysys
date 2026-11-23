# frozen_string_literal: true

module PageBuilder
  class CalculationEditorComponent < ApplicationComponent
    include ComponentClasses

    # Canonical value list. Labels are resolved at render time via I18n in
    # #format_types; the English labels here are kept only as documentation and
    # for specs that assert on the value set.
    FORMAT_TYPES = [
      { value: "plain",    label: "Plain" },
      { value: "number",   label: "Number" },
      { value: "currency", label: "Currency" },
      { value: "percent",  label: "Percent" }
    ].freeze

    FUNCTIONS = {
      "Math"  => %w[SUM SUBTRACT MULTIPLY DIVIDE MIN MAX AVERAGE ROUND FLOOR CEIL ABS MOD],
      "Logic" => %w[IF AND OR NOT SWITCH],
      "Text"  => %w[CONCAT UPPER LOWER TRIM LENGTH LEFT RIGHT],
      "Date"  => %w[TODAY NOW YEAR MONTH DAY DATE_DIFF DATE_ADD]
    }.freeze

    def functions = FUNCTIONS

    def initialize(calculation: nil, fields: [], pages: [])
      @calculation = calculation || default_calculation
      # Only value-bearing fields can be referenced in a formula or hold a
      # calculation result — exclude layout elements (sections, dividers,
      # headings, cards) and field-group containers.
      @fields = (fields || []).reject { |f| layout_or_group?(f) }
      @pages = pages || []
    end

    def format_types
      FORMAT_TYPES.map do |ft|
        { value: ft[:value], label: I18n.t("comp_page_builder.calc_editor.format_types.#{ft[:value]}") }
      end
    end

    private

    attr_reader :calculation, :fields, :pages

    def default_calculation
      { "id" => nil, "target_field_id" => "", "formula" => "", "format" => {} }
    end

    def calculation_id
      calculation["id"]
    end

    def target_field_id
      calculation["target_field_id"] || ""
    end

    def formula
      calculation["formula"] || ""
    end

    def format
      calculation["format"] || {}
    end

    def new_calculation?
      calculation["id"].nil?
    end

    def fields_json
      fields.map { |f| { "id" => f["id"], "label" => f["label"] || f["id"], "type" => f["property_type"] } }.to_json
    end

    def pages_grouped?
      pages.length > 1
    end

    def layout_or_group?(field)
      field["property_type"] == "layout" ||
        field["type"] == "field_group" ||
        field["field_type"] == "field_group"
    end
  end
end
