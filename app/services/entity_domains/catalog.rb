# frozen_string_literal: true

module EntityDomains
  # The entities a customer may place in a domain: its own entities plus
  # shared ones, bridges included. Explicit customer id rather than
  # Entity.accessible so callers do not depend on Current.
  module Catalog
    module_function

    def entities(customer_id)
      Entity.where(customer_id: [customer_id, nil])
    end

    def entity_ids(customer_id)
      entities(customer_id).pluck(:id)
    end

    # The two entity ids a bridge joins. BridgeEntityManagement writes the
    # source and target references as the first two schema fields.
    def bridge_ends(entity)
      schema = entity.property_schema_json
      return [] unless entity.bridge_entity? && schema.is_a?(Array)

      ends = schema.first(2).map { |field| field.is_a?(Hash) ? field["entity_id"].to_s.to_i : 0 }
      ends.size == 2 && ends.all?(&:positive?) ? ends : []
    end
  end
end
