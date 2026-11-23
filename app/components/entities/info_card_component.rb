# frozen_string_literal: true

module Entities
# Compact sidebar summary on the entity detail show surface (pages-style).
    # Shows name + icon chip, kind, referenced template, optional description,
    # and timestamps. Entries access lives on Entities::AccessCardComponent.
  class InfoCardComponent < ApplicationComponent
    attr_reader :entity, :customer_id

    def initialize(entity:, customer_id:)
      @entity      = entity
      @customer_id = customer_id
    end

    # The base model this entity extends, or nil. The label is the class name
    # without its namespace ("User"); the module key comes from the registry
    # when this customer may still extend that model.
    def base_model
      class_name = entity.extended_model.presence
      return if class_name.blank?

      listed = ExtendableModelRegistry.for_customer(customer_id).find { |model| model[:class_name] == class_name }
      { label: listed&.dig(:label) || class_name.demodulize, module_key: listed&.dig(:module_key) }
    end

    # Parsed referenced_template JSON, or nil when absent/invalid.
    def ref_data
      return nil unless entity.referenced_template.present?

      @ref_data ||= begin
        JSON.parse(entity.referenced_template).with_indifferent_access
      rescue JSON::ParserError
        nil
      end
    end
  end
end
