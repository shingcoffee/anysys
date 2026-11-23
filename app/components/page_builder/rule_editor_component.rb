# frozen_string_literal: true

module PageBuilder
  class RuleEditorComponent < ApplicationComponent
    include ComponentClasses

    # Canonical operator/action definitions. Labels are resolved at render time
    # via I18n in #operators / #action_types; the English labels here are kept
    # only as documentation and for specs asserting on the value set.
    OPERATORS = [
      { value: "equals",          label: "Equals" },
      { value: "not_equals",      label: "Not equals" },
      { value: "contains",        label: "Contains" },
      { value: "not_contains",    label: "Does not contain" },
      { value: "starts_with",     label: "Starts with" },
      { value: "ends_with",       label: "Ends with" },
      { value: "greater_than",    label: "Greater than" },
      { value: "less_than",       label: "Less than" },
      { value: "greater_or_equal", label: "Greater or equal" },
      { value: "less_or_equal",   label: "Less or equal" },
      { value: "between",         label: "Between" },
      { value: "is_empty",        label: "Is empty" },
      { value: "is_not_empty",    label: "Is not empty" },
      { value: "is_selected",     label: "Is selected" },
      { value: "is_not_selected", label: "Is not selected" },
      { value: "matches_regex",   label: "Matches pattern" }
    ].freeze

    ACTION_TYPES = [
      { value: "show_field",    label: "Show field",    target: "field" },
      { value: "hide_field",    label: "Hide field",    target: "field" },
      { value: "show_page",     label: "Show page",     target: "page" },
      { value: "hide_page",     label: "Hide page",     target: "page" },
      { value: "skip_to_page",  label: "Skip to page",  target: "page" },
      { value: "enable_field",  label: "Enable field",  target: "field" },
      { value: "disable_field", label: "Disable field", target: "field" },
      { value: "set_required",  label: "Set required",  target: "field", has_value: true },
      { value: "set_value",     label: "Set value",     target: "field", has_value: true }
    ].freeze

    def initialize(rule: nil, fields: [], pages: [])
      @rule   = rule || default_rule
      @fields = fields || []
      @pages  = pages || []
    end

    def operators
      OPERATORS.map do |o|
        { value: o[:value], label: I18n.t("comp_page_builder.operators.#{o[:value]}") }
      end
    end

    def action_types
      ACTION_TYPES.map do |at|
        at.merge(label: I18n.t("comp_page_builder.rule_editor.action_types.#{at[:value]}"))
      end
    end

    private

    attr_reader :rule, :fields, :pages

    def default_rule
      {
        "id"         => nil,
        "name"       => "",
        "enabled"    => true,
        "conditions" => { "logic" => "all", "groups" => [] },
        "actions"    => []
      }
    end

    def rule_name
      rule["name"] || ""
    end

    def rule_id
      rule["id"]
    end

    def conditions
      rule["conditions"] || { "logic" => "all", "groups" => [] }
    end

    def condition_groups
      conditions["groups"] || []
    end

    def actions
      rule["actions"] || []
    end

    def new_rule?
      rule["id"].nil?
    end

    # Condition fields: only value-bearing fields. Testing a layout element
    # (section/divider/heading) makes no sense — it has no input/value.
    def fields_json
      serialize_fields(condition_fields)
    end

    # Action targets: all fields, including layout elements — show_field /
    # hide_field can legitimately reveal/hide a section or divider.
    def action_fields_json
      serialize_fields(fields)
    end

    def pages_json
      pages.map { |p| { id: p["id"], name: p["name"] || p["id"] } }.to_json
    end

    def serialize_fields(list)
      list.map { |f| { id: f["id"], label: f["label"] || f["id"], type: f["property_type"], options: f["options"] || [] } }.to_json
    end

    def condition_fields
      fields.reject { |f| layout_or_group?(f) }
    end

    def layout_or_group?(field)
      field["property_type"] == "layout" ||
        field["type"] == "field_group" ||
        field["field_type"] == "field_group"
    end
  end
end
