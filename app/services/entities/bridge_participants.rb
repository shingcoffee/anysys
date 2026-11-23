# frozen_string_literal: true

module Entities
  # The two participant references of a bridge entity (BridgeEntityManagement
  # writes them as its first schema fields). Only the target participant is
  # stored as a record picker; the declaring one is a bare id field, so the
  # declaring entity's own schema never gains a display-field dependency.
  # Readers that edit or show bridge rows from either end use #pickers, which
  # labels a bare participant by its entity's first labelable admin field in
  # the tenant's definition.
  module BridgeParticipants
    SLUG = /\A\w+\z/

    module_function

    def participant?(attribute)
      attribute.is_a?(Hash) && attribute["type"] == Entity::ENTITY_REFERENCE_TYPE && attribute["entity_id"].to_s.match?(/\A\d+\z/)
    end

    def bare?(attribute) = participant?(attribute) && !ReferenceLabels.reference?(attribute)

    # The entity whose records +attribute+ holds, for a picker or a participant.
    def referenced_entity_id(attribute)
      return attribute.dig("config", "entity_id").to_s if ReferenceLabels.reference?(attribute)

      attribute["entity_id"].to_s if participant?(attribute)
    end

    def pickers(attributes, customer_id:)
      labels = {}
      attributes.map do |attribute|
        next attribute unless bare?(attribute)

        entity_id = attribute["entity_id"].to_s
        label_field = labels.fetch(entity_id) { labels[entity_id] = label_field(entity_id, customer_id) }
        next attribute unless label_field

        attribute.merge("html_type" => "select",
                        "config" => { "options_source" => ReferenceLabels::OPTIONS_SOURCE,
                                      "entity_id" => entity_id, "label_field" => label_field })
      end
    end

    def label_field(entity_id, customer_id)
      entity = Entity.where(customer_id: [customer_id, nil]).non_bridge.find_by(id: entity_id)
      payload = entity&.resolved_current_version(customer_id)&.content&.payload
      schema = payload.present? ? Array(JSON.parse(payload)["property_schema"]) : []
      schema.grep(Hash).find do |attribute|
        attribute["name_slug"].to_s.match?(SLUG) && ReferenceLabels.labelable?(attribute) &&
          EntityAttributeAudience.visible_to?(attribute, EntityAttributeAudience::ADMIN)
      end&.fetch("name_slug")
    rescue JSON::ParserError
      nil
    end
  end
end
