# frozen_string_literal: true

module Admin
  module Maintenance
    # Moves one entity, with the bridges it declares, to another domain.
    # Platform owner only via RouteAuthorization (OwnerOnlySurfaces); the
    # entity and the domain are both resolved inside the URL customer.
    class EntityDomainMembershipsController < ApplicationController
      dashboard_menu_item :maintenance
      before_action :find_entity

      def edit
        prepare_form
      end

      def update
        domain_id = params.fetch(:entity_domain_membership, {}).permit(:entity_domain_id)[:entity_domain_id]
        result = ::EntityDomains::Activities::Assign.call(entity: @entity, domain_id: domain_id, customer_id: current_customer_id)
        if result.success?
          redirect_to admin_maintenance_entities_path(current_customer_id, domain_id: domain_id),
                      status: :see_other, notice: t("maint_core.entity_domains.flash.moved", name: @entity.display_label)
        else
          prepare_form(domain_id)
          render :edit, status: :unprocessable_entity
        end
      end

      private

      def find_entity
        @entity = ::EntityDomains::Catalog.entities(current_customer_id).find(params[:entity_id])
      end

      def prepare_form(selected_domain_id = nil)
        @domains = EntityDomain.for_customer(current_customer_id).by_name.to_a
        @current_domain_id = ::EntityDomains::Memberships.domain_id_for(current_customer_id, @entity.id)
        @selected_domain_id = selected_domain_id || @current_domain_id
      end
    end
  end
end
