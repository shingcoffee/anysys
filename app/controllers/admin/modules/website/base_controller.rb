# frozen_string_literal: true

module Admin
  module Modules
    module Website
      # Shared base for Website admin controllers.
      #
      # Role gates for /:cid/admin/* come from RouteAuthorization (global).
      # This base only 404s when the Website feature module is off for the
      # current tenant — same pattern as payments.
      class BaseController < ApplicationController
        include Websites::CurrentSite

        dashboard_menu_item :modules

        before_action :require_website_module!

        rescue_from ActiveRecord::RecordNotFound, with: :website_record_not_found

        private

        def require_website_module!
          return if website_module_enabled?

          head :not_found
        end

        def website_record_not_found
          head :not_found
        end
      end
    end
  end
end
