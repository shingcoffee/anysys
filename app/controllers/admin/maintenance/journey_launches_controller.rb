# frozen_string_literal: true

module Admin
  module Maintenance
    # Owner-only through RouteAuthorization (OwnerOnlySurfaces). Journeys are
    # customer-owned, so there is no Shared Resources route.
    class JourneyLaunchesController < ApplicationController
      dashboard_menu_item :maintenance

      before_action :find_journey

      def create
        result = Journeys::Activities::Launch.call(journey: @journey)
        if result.ok
          redirect_to_journey(notice: t("journeys.admin.flash.launched"))
        else
          redirect_to_journey(alert: result.errors.first)
        end
      end

      def destroy
        @journey.update!(status: :draft)
        redirect_to_journey(notice: t("journeys.admin.flash.taken_offline"))
      end

      private

      def find_journey
        @journey = Journey.for_customer(current_customer_id).find(params[:journey_id])
      end

      def redirect_to_journey(flash)
        redirect_to edit_admin_maintenance_journey_path(current_customer_id, @journey), flash
      end
    end
  end
end
