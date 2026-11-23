# frozen_string_literal: true

module Pages
  # Public URL category: GET /:customer_id/actions/:action_key
  # Redirect-only. No auth guard — each target surface enforces its own.
  class ActionsController < ApplicationController
    include PageRendering
    include PageAudienceRouting
    include PageShortcuts::PublicPathContext

    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

    def show
      page = ActionResolver.page_for(
        customer_id: current_customer_id,
        action_key: params[:action_key],
        audience: page_runtime_audience
      )
      if page
        prefill = sanitized_action_prefill
        path = audience_surface_path(page, prefill: prefill)
        path = with_public_continuation(path, prefill) if public_continuation?
        redirect_to path, status: :see_other
        return
      end

      if !user_signed_in?
        member_page = ActionResolver.page_for(
          customer_id: current_customer_id,
          action_key: params[:action_key],
          audience: EntityAttributeAudience::MEMBER
        )
        if member_page
          store_location_for(
            :user,
            audience_surface_path(
              member_page,
              audience: EntityAttributeAudience::MEMBER,
              prefill: sanitized_action_prefill
            )
          )
          redirect_to new_user_session_path
          return
        end
      end

      raise ActiveRecord::RecordNotFound
    end

    private

    # A public hand-off is only useful when the same action also has a live
    # member page the visitor can continue on after they sign in.
    def public_continuation?
      page_runtime_audience.to_s == EntityAttributeAudience::PUBLIC &&
        ActionResolver.page_for(
          customer_id: current_customer_id,
          action_key: params[:action_key],
          audience: EntityAttributeAudience::MEMBER
        )
    end

    def with_public_continuation(path, prefill)
      token = Pages::Continuation.sign(action_key: params[:action_key], prefill: prefill)
      joiner = path.include?("?") ? "&" : "?"
      "#{path}#{joiner}#{ { continuation: token }.to_query }"
    end

    def render_not_found
      render plain: t("public_views.public_pages.not_found"), status: :not_found
    end
  end
end
