# frozen_string_literal: true

class EntityAssociationGraph
  def self.build(customer_id)
    entities = Entity.where(customer_id: customer_id).or(Entity.shared).non_bridge.to_a
    by_id = entities.index_by(&:id)

    targeted_ids = entities.flat_map { |e|
      e.associations_list.map { |a| a["target_entity_id"].to_s.to_i }
    }.compact.to_set

    primaries = entities.reject { |e| targeted_ids.include?(e.id) }

    children_of = entities.each_with_object({}) { |e, h|
      h[e.id] = e.associations_list
                .map { |a| by_id[a["target_entity_id"].to_s.to_i] }
                .compact
                .uniq(&:id)
    }

    # Cyclic components may have no natural root. Retain their relationships,
    # adding a navigation root for every component unreachable from the roots.
    reached = Set.new
    visit = lambda do |root|
      pending = [root]
      until pending.empty?
        entity = pending.pop
        next unless reached.add?(entity.id)

        pending.concat(children_of.fetch(entity.id, []))
      end
    end
    primaries.each { |entity| visit.call(entity) }
    entities.each do |entity|
      next if reached.include?(entity.id)

      primaries << entity
      visit.call(entity)
    end

    new(primaries: primaries, children_of: children_of, entities: entities)
  end

  attr_reader :primaries, :entities

  def initialize(primaries:, children_of:, entities:)
    @primaries = primaries
    @children_of = children_of
    @entities = entities
  end

  def children_of(entity)
    @children_of.fetch(entity.id, [])
  end

  def all_entities
    @entities
  end
end
