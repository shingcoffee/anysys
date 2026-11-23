# frozen_string_literal: true

module Pages
  # Server-side values for a page's locked inputs, taken from the visitor's run
  # and re-checked on every render and submit: the input must reference its
  # entity on the page's entity, and the record must exist in this tenant,
  # belong to that entity, and be reachable by the viewer.
  module InputBindings
    ID = /\A[1-9]\d*\z/

    # Slug => id, plus the checked records so the locked-inputs card needn't
    # load them again.
    class Bound < Hash
      def records = (@records ||= {})
    end

    def self.resolve(page:, run:, viewer:, audience:, customer_id:)
      return Bound.new unless run

      raw = run.bindings_for(page)
      page.page_inputs.each_with_object(Bound.new) do |input, kept|
        id = raw[input["field"]]
        next unless id.is_a?(String) && id.match?(ID) && references?(page, input)

        entity = Entity.where(customer_id: [customer_id, nil]).find_by(id: input["entity_id"])
        entry = entity && EntityEntry.find_by(customer_id: customer_id, entity_id: entity.id, id: id)
        next unless entry
        next unless People::Ownership.reachable_ids(entity, [id], viewer: viewer, audience: audience, customer_id: customer_id).include?(id)

        kept[input["field"]] = id
        kept.records[input["field"]] = entry
      end
    end

    def self.references?(page, input)
      attribute = Array(page.entity&.property_schema_json).grep(Hash).find { |item| item["name_slug"] == input["field"] }
      attribute.present? && Entities::BridgeParticipants.referenced_entity_id(attribute) == input["entity_id"]
    end
    private_class_method :references?
  end
end
