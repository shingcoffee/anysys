# frozen_string_literal: true

module Admin
  module Maintenance
    module Entities
      # Create / edit form for a domain: name, description and color.
      # Entities join a domain when they are created into it or moved to it.
      class EntityDomainFormComponent < ApplicationComponent
        attr_reader :domain, :customer_id

        def initialize(domain:, customer_id:)
          @domain = domain
          @customer_id = customer_id
        end

        def form_url
          if domain.persisted?
            helpers.admin_maintenance_entity_domain_path(customer_id, domain)
          else
            helpers.admin_maintenance_entity_domains_path(customer_id)
          end
        end

        def form_method = domain.persisted? ? :patch : :post
        def cancel_path = helpers.admin_maintenance_entities_path(customer_id, domain_id: domain.id)

        def submit_label
          t(domain.persisted? ? "common.actions.save" : "maint_core.entity_domains.form.create")
        end

        def colors = EntityDomain::COLORS
        def dot_class(color) = EntityDomainColors.dot(color)
        def color_label(color) = t("maint_core.entity_domains.colors.#{color}")
        def current_color = domain.color.presence || colors.first

        def field_errors(attribute) = domain.errors[attribute]
        def base_errors = domain.errors[:base]

        def field_aria(attribute, hint: true)
          ids = []
          ids << "entity-domain-#{attribute}-hint" if hint
          ids << "entity-domain-#{attribute}-error" if field_errors(attribute).any?
          { invalid: field_errors(attribute).any?, describedby: ids.join(" ").presence }
        end
      end
    end
  end
end
