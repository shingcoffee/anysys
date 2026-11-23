# frozen_string_literal: true

module Journeys
  # Public URL category: GET /:customer_id/journeys/:key — opens a launched
  # journey's first page for the visitor's audience. No auth guard: the page
  # enforces its own, and its submit starts the run. A journey that opens with
  # a user step starts on Authentication › Users › New, which is admin-only.
  class StartsController < ApplicationController
    include PageRendering
    include PageAudienceRouting
    include PageShortcuts::PublicPathContext

    rescue_from ActiveRecord::RecordNotFound, with: :render_unavailable

    def show
      journey = Journey.launched.find_by(customer_id: current_customer_id, key: params[:key].to_s)
      raise ActiveRecord::RecordNotFound unless journey

      path = start_path(journey, page_runtime_audience)
      return redirect_to(path, status: :see_other) if path

      if !user_signed_in? && (journey.visible_to?(EntityAttributeAudience::MEMBER) || journey.steps_definition.user_start)
        store_location_for(:user, request.fullpath)
        return redirect_to(new_user_session_path)
      end

      raise ActiveRecord::RecordNotFound
    end

    private

    def start_path(journey, audience)
      first = journey.steps_definition.first_step
      return unless first && journey.visible_to?(audience)

      if first.user?
        return unless audience == EntityAttributeAudience::ADMIN

        return new_admin_modules_authentication_user_path(current_customer_id, journey: journey.key)
      end

      page = Pages::ActionResolver.page_for(customer_id: current_customer_id, action_key: first.action_key, audience: audience)
      run_surface_path(page, nil) if page
    end

    def render_unavailable
      render plain: t("journeys.runtime.unavailable"), status: :not_found
    end
  end
end
