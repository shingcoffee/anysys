# frozen_string_literal: true

module Admin
  module Maintenance
    class EntityCopiesController < ApplicationController
      include SharedResourceMode
      dashboard_menu_item :maintenance

      # A copy is a manual create, which only the platform owner may do.
      before_action do
        raise CanCan::AccessDenied, t("common.errors.authorization.platform_owner_required") unless current_user.platform_owner?
      end

      def show
        source = definition_scope(Entity).find(params[:entity_id])
        require_copyable_source!(source)
        copied_associations = source.associations_json.map do |assoc|
          assoc.slice("target_entity_id", "target_entity_name", "display_field", "display_field_label", "additional_attributes")
        end
        @entity = Entity.new(
          name: I18n.t("maint_core.entities.copy_name", name: source.name),
          display_label: source.display_label,
          icon: source.icon,
          color: source.color,
          description: source.description,
          property_schema: source.property_schema,
          default_properties: source.default_properties,
          associations: copied_associations.to_json,
          attribute_groups: source.attribute_groups,
          extended_model: source.extended_model,
          referenced_template: source.referenced_template
        )
        apply_create_identity!(@entity)
        prepare_domain_choice(source) unless shared_resources_mode?
        render "admin/maintenance/entities/new"
      end

      private

      # The copy starts in the source's domain, like any customer-owned create.
      def prepare_domain_choice(source)
        @domains = EntityDomain.for_customer(current_customer_id).by_name.to_a
        @entity_domain_id = ::EntityDomains::Memberships.domain_id_for(current_customer_id, source.id)
      end
    end
  end
end
