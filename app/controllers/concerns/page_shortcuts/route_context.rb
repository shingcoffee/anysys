# frozen_string_literal: true

module PageShortcuts
  module RouteContext
    extend ActiveSupport::Concern

    included do
      prepend_before_action :set_page_shortcut_context
    end

    private

    attr_reader :page_shortcut_target

    def page_shortcut_request?
      match = request.env[RouteConstraint::MATCH_KEY]
      match && match[:controller] == controller_path && match[:action] == action_name
    end

    def set_page_shortcut_context
      return unless page_shortcut_request?

      match = request.env.fetch(RouteConstraint::MATCH_KEY)
      target = @page_shortcut_target = match.fetch(:target)
      # Replace query/body values as well as route parameters. TenantContext
      # normally extracts the tenant from PATH_INFO, which aliases may omit.
      request.path_parameters = request.path_parameters.merge(
        customer_id: target.customer_id, page_slug: target.page_slug, uuid: target.uuid
      )
      params[:customer_id] = target.customer_id
      params[:page_slug] = target.page_slug
      params[:uuid] = target.uuid
      set_current_tenant(target.customer_id, true)
    end
  end
end
