# frozen_string_literal: true

module EntityDomains
  # What a domain holds for its customer, and so what deleting it removes:
  # the customer-owned entities placed in it (trashed ones included) with
  # their records, the customer's pages bound to those entities, and the
  # domain's journeys. Shared entities only leave the domain.
  #
  # `outside_links` names the customer's entities in other domains (trashed
  # ones too, since they can be restored) whose associations or reference
  # fields point into this one; deleting the domain would break them, so it
  # is refused while any remain.
  class Contents
    def initialize(domain)
      @domain = domain
    end

    def entities
      @entities ||= Entity.with_deleted.where(customer_id: @domain.customer_id, id: member_ids).to_a
    end

    def journeys = @domain.journeys

    def pages
      @pages ||= Page.with_deleted.where(customer_id: @domain.customer_id).joins(current_version: :content)
                     .where("CAST(#{Page::CONFIG_ENTITY_ID_SQL} AS TEXT) IN (?)", entity_ids.map(&:to_s)).to_a
    end

    def record_count = EntityEntry.where(entity_id: entity_ids).count

    def outside_links
      @outside_links ||= Entity.with_deleted.where(customer_id: @domain.customer_id).non_bridge.where.not(id: entity_ids)
                               .includes(current_version: :content).select { |entity| links_in?(entity) }
    end

    private

    def member_ids
      @member_ids ||= @domain.memberships.pluck(:entity_id)
    end

    def entity_ids
      @entity_ids ||= entities.to_set(&:id)
    end

    def links_in?(entity)
      targets = entity.associations_list.map { |association| association["target_entity_id"] }
      references = Array(entity.property_schema_json).grep(Hash).map { |attribute| Entities::BridgeParticipants.referenced_entity_id(attribute) }
      (targets + references).any? { |id| entity_ids.include?(id.to_s.to_i) }
    end
  end
end
