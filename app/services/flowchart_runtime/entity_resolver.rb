# frozen_string_literal: true

module FlowchartRuntime
  # Tenant-safe entity lookup for generated flowchart steps.
  #
  # Generated query code used to emit a bare `Entity.find(id)`, which resolves
  # an entity belonging to ANY customer. In a multi-tenant application that is
  # a cross-tenant disclosure: a flowchart in customer A could join against
  # customer B's entity and read B's `entity_entries`. Every generated entity
  # lookup must go through this facade so the tenant predicate is applied in
  # one auditable place.
  #
  # An entity is reachable from a tenant when it belongs to that tenant, or
  # when it is a platform-wide shared entity (`customer_id IS NULL`).
  module EntityResolver
    class Error < StandardError; end

    module_function

    # @param id [Integer] entity primary key
    # @param customer_id [Integer] the tenant executing the flowchart
    # @return [Entity]
    # @raise [Error] when the entity does not exist or is not reachable
    def find(id, customer_id:)
      raise Error, I18n.t("flowchart_actions.shared.errors.missing_customer_scope") if customer_id.nil?

      entity = scope(customer_id).find_by(id: id)
      return entity if entity

      raise Error, I18n.t("flowchart_actions.shared.errors.entity_not_accessible", id: id)
    end

    # Like #find, but also takes the entity's name, which is what the
    # assistant writes; the tenant's own entity wins over a shared one.
    def named(value, customer_id:)
      key = value.to_s.strip
      return find(key, customer_id: customer_id) if key.match?(/\A\d+\z/)
      raise Error, I18n.t("flowchart_actions.shared.errors.missing_customer_scope") if customer_id.nil?

      entity = scope(customer_id).where(name: key).order(Arel.sql("customer_id IS NULL")).first
      return entity if entity

      raise Error, I18n.t("flowchart_actions.shared.errors.entity_not_accessible", id: key)
    end

    # @return [Boolean] whether +id+ is reachable from +customer_id+
    def accessible?(id, customer_id:)
      return false if customer_id.nil?

      scope(customer_id).exists?(id: id)
    end

    def scope(customer_id)
      Entity.where(customer_id: customer_id).or(Entity.shared)
    end
  end
end
