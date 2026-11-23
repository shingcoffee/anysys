# frozen_string_literal: true

module Entities
  # The one rule for showing a reference: which attributes may label it and
  # how a label reads when the record is unnamed, missing or not unique.
  module ReferenceLabels
    OPTIONS_SOURCE = EntityDefinitions::Capabilities::ENTITY_ENTRIES_OPTIONS_SOURCE
    LABEL_HTML_TYPES = %w[text search email tel url number date].freeze
    UNLABELABLE_TYPES = [Entity::COMPUTED_TYPE, "Calculated", Entity::ENTITY_REFERENCE_TYPE].freeze

    module_function

    # A stored input attribute whose value reads as a name: no derived or
    # reference fields, no free text, choices, secrets or files.
    def labelable?(attribute)
      return false unless attribute.is_a?(Hash)
      return false if UNLABELABLE_TYPES.include?(attribute["type"]) || attribute["storage"] == "computed"

      LABEL_HTML_TYPES.include?(attribute["html_type"].presence || "text")
    end

    def reference?(attribute)
      attribute.is_a?(Hash) && attribute["config"].is_a?(Hash) && attribute["config"]["options_source"] == OPTIONS_SOURCE
    end

    def text(raw_label, id)
      label = raw_label.to_s.strip
      label.empty? ? I18n.t("common.references.untitled", id: id) : label
    end

    def missing(id)
      I18n.t("common.references.missing", id: id)
    end

    def numbered(label, id)
      I18n.t("common.references.duplicate", label: label, id: id)
    end

    # [[label, id], ...] with every repeated label numbered by its id.
    def disambiguate(pairs)
      counts = pairs.map { |label, _id| label.to_s.strip }.tally
      pairs.map do |label, id|
        text = label.to_s.strip
        counts[text] > 1 ? [numbered(text, id), id] : [label, id]
      end
    end
  end
end
