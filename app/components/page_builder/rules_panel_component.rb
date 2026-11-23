# frozen_string_literal: true

module PageBuilder
  class RulesPanelComponent < ApplicationComponent
    include ComponentClasses

    def initialize(rules: [], fields: [])
      @rules = rules || []
      @fields = fields || []
    end

    private

    attr_reader :rules, :fields

    def empty?
      rules.empty?
    end

    def show_search?
      rules.length > 6
    end

    def field_label(field_id)
      field = fields.find { |f| f["id"] == field_id }
      field&.dig("label") || field_id
    end

    def rule_summary(rule)
      groups = rule.dig("conditions", "groups") || []
      first_item = groups.first&.dig("items")&.first
      actions = rule["actions"] || []
      first_action = actions.first

      parts = []
      if first_item && first_item["field_id"].present?
        parts << "#{I18n.t("comp_page_builder.rules_panel.summary_when")} #{field_label(first_item["field_id"])} #{first_item["operator"]}"
      end
      if first_action && first_action["target_id"].present?
        parts << "→ #{first_action["type"]&.tr("_", " ")} #{field_label(first_action["target_id"])}"
      end
      parts.join(" ")
    end
  end
end
