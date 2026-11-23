# frozen_string_literal: true

module Admin
  module Maintenance
    # Domains on the entities index. RouteAuthorization admits only
    # the platform owner here (OwnerOnlySurfaces); every record is scoped to
    # the URL customer.
    class EntityDomainsController < ApplicationController
      dashboard_menu_item :maintenance
      before_action :find_domain, only: %i[edit update destroy]

      def new
        @domain = EntityDomain.new(customer_id: current_customer_id, color: EntityDomain::COLORS.first)
      end

      def create
        save_domain(EntityDomain.new(customer_id: current_customer_id), :new, :created)
      end

      def edit; end

      def update
        save_domain(@domain, :edit, :updated)
      end

      # Deletes the domain with its entities, records, pages and journeys;
      # the index's confirmation dialog lists them first.
      def destroy
        name = @domain.name
        result = ::EntityDomains::Activities::Destroy.call(domain: @domain, customer_id: current_customer_id)
        if result.success?
          redirect_to admin_maintenance_entities_path(current_customer_id), status: :see_other,
                      notice: t("maint_core.entity_domains.flash.deleted", name: name)
        else
          redirect_to admin_maintenance_entities_path(current_customer_id, domain_id: @domain.id), status: :see_other,
                      alert: result.errors.values.flatten.to_sentence
        end
      end

      private

      def find_domain
        @domain = EntityDomain.for_customer(current_customer_id).find(params[:id])
      end

      def save_domain(domain, template, notice)
        @domain = domain
        result = ::EntityDomains::Activities::Save.call(domain: domain, params: domain_params, customer_id: current_customer_id)
        if result.success?
          redirect_to admin_maintenance_entities_path(current_customer_id, domain_id: domain.id),
                      status: :see_other, notice: t("maint_core.entity_domains.flash.#{notice}", name: domain.name)
        else
          render template, status: :unprocessable_entity
        end
      end

      def domain_params
        params.require(:entity_domain).permit(:name, :description, :color)
      end
    end
  end
end
