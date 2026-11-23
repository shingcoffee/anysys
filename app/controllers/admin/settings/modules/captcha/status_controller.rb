# frozen_string_literal: true

module Admin
module Settings
module Modules
  module Captcha
    # Customer-facing Captcha settings: provider status + public-page throttles.
    # Canonical URL: GET /:cid/admin/settings/modules/captcha
    # Helper: admin_settings_modules_captcha_path(cid)
    # Authorization: RouteAuthorization (admin/owner). No extra role filter.
    class StatusController < ApplicationController
      dashboard_menu_item :settings

      def show
        @settings       = ::Captcha::ProviderSettings.active
        @module_enabled = module_enabled?
        @pages          = public_pages.map { |page| page_for_view(page) }
        @customer_id    = current_customer_id
      end

      private

      def module_enabled?
        ::FeatureModules::Module.enabled?(key: "captcha", customer_id: current_customer_id)
      end

      # Customer-owned public pages only. for_current_customer excludes
      # shared (customer_id NULL) rows. Includes unpublished (launched: false).
      def public_pages
        ::Page.for_current_customer.for_audience("public").by_name
      end

      def page_for_view(page)
        {
          id: page.id,
          name: page.name,
          public_path: "/#{current_customer_id}/page/#{page.public_uuid}",
          launched: page.launched?,
          update_url: admin_settings_modules_captcha_page_path(current_customer_id, page),
          **::Captcha::ThrottleRegistry.display_for(
            match_kind: "exact",
            url_pattern: "/#{current_customer_id}/page/#{page.public_uuid}"
          )
        }
      end
    end
  end
end
end
end
