# frozen_string_literal: true

module EntityDefinitions
  # Tenant-scoped list of visible entity definitions (customer-specific + shared).
  class List < Trailblazer::Activity::Railway
    step :load_entities
    step :serialize

    def load_entities(ctx, **)
      ctx[:entities] = Entity.accessible.by_name.to_a
    end

    def serialize(ctx, entities:, **)
      ctx[:json] = { entities: entities.map { |entity| Serializer.call(entity) } }
    end
  end
end
