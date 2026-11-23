# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Website
        class SkeletonsController < ::Admin::Modules::Website::BaseController
          dashboard_menu_item :settings

          def create
            website = current_website
            unless website
              redirect_to admin_settings_modules_website_path(current_customer_id),
                          alert: t("website.admin.settings.missing_site")
              return
            end

            key = params[:skeleton_key].presence || params.dig(:website, :skeleton_key)
            result = call_website_activity("ReplaceSkeleton", site: website, skeleton_key: key)
            if website_activity_ok?(result)
              redirect_to admin_modules_website_root_path(current_customer_id),
                          notice: t("website.admin.flash.skeleton_replaced")
            else
              redirect_to admin_settings_modules_website_path(current_customer_id),
                          alert: t("website.admin.flash.site_save_failed")
            end
          end
        end
      end
    end
  end
end
