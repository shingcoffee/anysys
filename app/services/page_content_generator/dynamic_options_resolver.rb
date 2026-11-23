# frozen_string_literal: true

class PageContentGenerator
  # Resolves `query` option lists for select / radio / multi-select fields at page-generation time. Values are record ids; labels follow `Entities::ReferenceLabels`, and the label field must be labelable and visible to the audience.
  #
  # Fields that carry a `dynamic_options` hash with `options_source == "query"`
  # are enriched with a pre-fetched `options` array at page-generation time.
  # All queries are automatically scoped to the owning customer so a field on
  # tenant A cannot reference an entity that belongs to tenant B.
  #
  # Usage:
  #   resolved_fields = DynamicOptionsResolver.new(customer_id).resolve(fields)
  #
  class DynamicOptionsResolver
    def initialize(customer_id, audience: EntityAttributeAudience.for_user(Current.user, customer_id: customer_id),
                   viewer: Current.user)
      @customer_id = customer_id
      @audience = audience
      @viewer = viewer
    end

    # @param fields [Array<Hash>] raw field configs from the page configuration
    # @return [Array<Hash>] fields with static `options` merged in where applicable
    def resolve(fields)
      fields.map { |field| resolve_field(field) }
    end

    private

    attr_reader :customer_id

    def resolve_field(field)
      if field["field_type"] == "columns"
        return field.merge("columns" => Array(field["columns"]).map { |column|
          column.merge("fields" => resolve(Array(column["fields"])))
        })
      end
      dynamic = field["dynamic_options"]
      return field unless dynamic && dynamic["options_source"] == "query"
      empty = field.merge("options" => [])
      return empty unless customer_id

      entity = Entity.where(customer_id: [customer_id, nil])
                     .find_by(id: dynamic["entity_id"])
      return empty unless entity

      schema = Array(entity.property_schema_json).grep(Hash)
      allowed = schema.filter_map do |attribute|
        attribute["name_slug"].to_s if EntityAttributeAudience.visible_to?(attribute, @audience)
      end
      label_field = dynamic["label_field"].to_s
      label_attribute = schema.find { |attribute| attribute["name_slug"].to_s == label_field }
      return empty unless Entities::ReferenceLabels.labelable?(label_attribute) && allowed.include?(label_field)

      builder = FlowchartRuntime::QueryBuilder.for_entity(
        entity,
        customer_id: customer_id,
        scope: People::Ownership.scope(entity, viewer: @viewer, audience: @audience, customer_id: customer_id)
      )

      conditions = dynamic["conditions"]
      builder = builder.where(conditions, {}) if conditions.present?

      order_by = dynamic["order_by"]
      if order_by.present?
        return empty unless allowed.include?(order_by.to_s.delete_prefix("data."))
        order_field = order_by.start_with?("data.") ? order_by : "data.#{order_by}"
        builder = builder.order(order_field, dynamic["order_direction"] || "asc")
      end

      limit = dynamic["limit"]
      builder = builder.paginate(page: 1, per_page: limit.present? ? limit.to_i : 200)

      result      = builder.execute

      pairs = result.records.map { |record| [Entities::ReferenceLabels.text(record.data_json[label_field], record.id), record.id.to_s] }
      options = Entities::ReferenceLabels.disambiguate(pairs).map { |label, value| { "label" => label, "value" => value } }

      field.merge("options" => options)
    rescue FlowchartRuntime::JsonPathValidator::Error, FlowchartRuntime::QueryBuilder::Error
      field.merge("options" => [])
    end
  end
end
