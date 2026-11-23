# frozen_string_literal: true

module Admin
  module Maintenance
    # "Generate journey": the journeys each of the customer's domains (or the
    # one `domain_id` names) can start, one card per candidate, each marked
    # with the journey already generated from it. Owner-only through
    # RouteAuthorization (OwnerOnlySurfaces).
    class JourneyGenerationsController < ApplicationController
      dashboard_menu_item :maintenance

      def new
        @domain = EntityDomain.for_customer(current_customer_id).find(params[:domain_id]) if params[:domain_id].present?
        sections = EntityDomains::Layout.call(customer_id: current_customer_id, entities: EntityDomains::Catalog.entities(current_customer_id))
        sections = sections.select { |section| section.domain == @domain } if @domain
        @groups = sections.reject(&:ungrouped?).filter_map do |section|
          candidates = EntityDomains::JourneyPlanner.call(customer_id: current_customer_id, entities: section.items.map(&:entity))
          [section.domain, candidates] if candidates.any?
        end
        @journeys = Journey.for_customer(current_customer_id).where(entity_domain_id: @groups.map { |domain, _| domain.id }).order(:id).to_a
      end

      def create
        domain = EntityDomain.for_customer(current_customer_id).find(params[:domain_id])
        result = Journeys::Activities::Generate.call(customer: current_customer, domain_id: domain.id, candidate_key: params[:candidate])
        if result.ok
          redirect_to edit_admin_maintenance_journey_path(current_customer_id, result.journey), notice: t("journeys.admin.flash.generated")
        else
          redirect_to generate_admin_maintenance_journeys_path(current_customer_id, domain_id: domain.id), alert: result.errors.first
        end
      end
    end
  end
end
