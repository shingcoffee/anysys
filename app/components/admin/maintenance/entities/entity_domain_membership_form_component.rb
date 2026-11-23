# frozen_string_literal: true

module Admin
  module Maintenance
    module Entities
      # Moves one entity, with the bridges it declares, to another domain.
      # An entity always belongs to a domain, so there is no blank choice.
      class EntityDomainMembershipFormComponent < ApplicationComponent
        attr_reader :entity, :domains, :customer_id

        def initialize(entity:, domains:, selected_domain_id:, customer_id:)
          @entity = entity
          @domains = Array(domains)
          @selected_domain_id = selected_domain_id
          @customer_id = customer_id
        end

        def form_url = helpers.admin_maintenance_entity_domain_membership_path(customer_id, entity)
        def cancel_path = helpers.admin_maintenance_entities_path(customer_id, domain_id: @selected_domain_id)
        def new_domain_path = helpers.new_admin_maintenance_entity_domain_path(customer_id)

        def hint = t("maint_core.entity_domains.move.hint")
        def options = domains.map { |domain| [domain.name, domain.id] }

        def selected = @selected_domain_id.to_s
        def errors = entity.errors.full_messages
      end
    end
  end
end
