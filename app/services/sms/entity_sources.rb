# frozen_string_literal: true

module Sms
  # Explicit source catalog: no native model extensions, bridge traversal, or
  # dynamic Ruby access. Always resolves shared heads for the supplied tenant.
  class EntitySources
    SCALAR_CONTROLS = %w[text textarea email tel url number range checkbox select radio date datetime-local time color hidden].freeze

    def initialize(customer:)
      @customer = customer
    end

    def entities
      in_context do
        scope.order(:display_label, :id).map { |entity| { id: entity.id, label: entity.display_label } }
      end
    end

    def find(id)
      in_context { scope.find(id) }
    end

    def fields(id)
      return { phone: [], scalar: [] } if id.nil?

      source = find(id)
      rows = schema(source).filter_map do |field|
        next unless field.is_a?(Hash) && field["name_slug"].is_a?(String) &&
          field["name_slug"].match?(EntitySchemaValidation::ATTRIBUTE_SLUG_RE) &&
          SCALAR_CONTROLS.include?(field["html_type"]) && !%w[Calculated Computed EntityReference].include?(field["type"])

        type = case field["html_type"]
        when "number", "range" then :float
        when "checkbox" then :boolean
        else :string
        end
        { value: field["name_slug"], label: field["display_label"].presence || field["name"].presence || field["name_slug"],
          type: type, telephone: field["html_type"] == "tel" }
      end
      { phone: rows.select { |row| row[:telephone] }.map { |row| row.slice(:value, :label) },
        scalar: rows.map { |row| row.slice(:value, :label, :type) } }
    end

    def schema(source)
      in_context do
        version = source.resolved_current_version(@customer.id)
        payload = version&.content&.payload
        definition = payload && JSON.parse(payload)
        schema = definition.is_a?(Hash) && definition["property_schema"]
        schema.is_a?(Array) ? schema : []
      end
    rescue JSON::ParserError
      []
    end

    private

    def scope
      Entity.accessible.active.where(category: :plain, extended_model: [nil, ""])
    end

    def in_context(&block)
      Current.set(customer: @customer, shared_resources_mode: false, &block)
    end
  end
end
