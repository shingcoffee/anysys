# frozen_string_literal: true

module Admin
  module Maintenance
    # Owner-only through RouteAuthorization (OwnerOnlySurfaces). Journeys are
    # customer-owned, so there is no Shared Resources route.
    class JourneyCopiesController < ApplicationController
      dashboard_menu_item :maintenance

      def create
        source = Journey.for_customer(current_customer_id).find(params[:journey_id])
        result = Journeys::Activities::Copy.call(journey: source)
        if result.ok
          redirect_to edit_admin_maintenance_journey_path(current_customer_id, result.journey),
                      notice: t("journeys.admin.flash.duplicated")
        else
          redirect_to edit_admin_maintenance_journey_path(current_customer_id, source), alert: result.errors.first
        end
      end
    end
  end
end
