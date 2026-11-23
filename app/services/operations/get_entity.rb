# frozen_string_literal: true

module Operations
  class GetEntity < Base
    key "get_entity"
    version 1
    title "Get entity"
    summary "Read one customer-owned, active, non-bridge entity in the public vocabulary. Call this before update_entity. Shared entities, bridges, and trash are not returned."
    schema "get_entity.json"
    shared_defs "entity.defs.json"
    vocabulary EntityDefinitions::Api::Vocabulary
    annotations read_only: true, confirmation: :never

    register!

    def validate(input)
      name = input["entity"].to_s
      target = EntityDefinitions::Api::SemanticValidator.locate(customer: context.customer, name: name)
      Array.wrap(target.violation(name: name, pointer: "/entity"))
    end

    def perform(input)
      entity = Entity.where(customer_id: context.customer.id).non_bridge.find_by!(name: input["entity"])
      mapper = EntityDefinitions::Api::Mapper.new(customer: context.customer)
      Outcome.succeeded(
        operation: self.class.key,
        data: { "entity" => mapper.from_entity(entity) }
      )
    end
  end
end
