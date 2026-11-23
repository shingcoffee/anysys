# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Website
        class SitesController < ::Admin::Modules::Website::BaseController
          dashboard_menu_item :settings

          def show
            @website = current_website
          end

          def update
            website = current_website
            unless website
              redirect_to admin_settings_modules_website_path(current_customer_id),
                          alert: t("website.admin.settings.missing_site")
              return
            end

            attrs = site_params
            result = call_website_activity("SaveSite", site: website, params: attrs)
            if website_activity_ok?(result)
              redirect_to admin_settings_modules_website_path(current_customer_id),
                          notice: t("website.admin.flash.site_saved")
            else
              @website = result.respond_to?(:model) && result.model ? result.model : website
              flash.now[:alert] = t("website.admin.flash.site_save_failed")
              render :show, status: :unprocessable_entity
            end
          end

          private

          def site_params
            src = params[:website] || params
            src.permit(
              :name, :tagline, :published, :skeleton_key, :default_layout_key,
              theme: {},
              seo: {},
              footer: [:blurb, { columns: [:heading, :position, { links: %i[label url] }] }]
            ).to_h
          end
        end
      end
    end
  end
end
