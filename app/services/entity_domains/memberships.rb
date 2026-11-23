# frozen_string_literal: true

module EntityDomains
  # Writes EntityDomainMembership rows. Callers have already checked that the
  # domain and entity belong to the customer. A bridge lives in the domain of
  # the entity whose association declares it.
  module Memberships
    module_function

    # Places `entity` and the bridges it declares in `domain`, moving them
    # out of any other domain of the customer.
    def place!(entity, domain)
      ([entity.id] + declared_bridge_ids(entity, domain.customer_id)).each do |entity_id|
        EntityDomainMembership.for_customer(domain.customer_id).find_or_initialize_by(entity_id: entity_id)
                              .update!(entity_domain: domain)
      end
    end

    # Puts bridges `entity` declares that sit in no domain yet into the
    # entity's own domain. Runs after every bridge sync.
    def place_bridges!(entity, customer_id: entity.customer_id)
      return if customer_id.nil?

      domain_id = domain_id_for(customer_id, entity.id)
      return if domain_id.nil?

      scope = EntityDomainMembership.for_customer(customer_id)
      bridge_ids = declared_bridge_ids(entity, customer_id)
      (bridge_ids - scope.where(entity_id: bridge_ids).pluck(:entity_id)).each do |bridge_id|
        scope.create!(entity_domain_id: domain_id, entity_id: bridge_id)
      end
    end

    def domain_id_for(customer_id, entity_id)
      EntityDomainMembership.for_customer(customer_id).where(entity_id: entity_id).pick(:entity_domain_id)
    end

    def declared_bridge_ids(entity, customer_id)
      ids = entity.associations_list.filter_map { |association| association["bridge_entity_id"] }
      return [] if ids.empty?

      Entity.with_deleted.where(id: ids, customer_id: customer_id, category: :bridge).pluck(:id)
    end
  end
end
