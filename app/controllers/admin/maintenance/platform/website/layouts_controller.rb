# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module Website
        # Platform-owner layout catalog. Owner-gated by RouteAuthorization on
        # the /admin/maintenance/platform/ prefix.
        class LayoutsController < ApplicationController
          include Websites::CatalogPreview

          dashboard_menu_item :maintenance

          before_action :load_feature_module
          before_action :load_layout, only: %i[edit update preview]

          def index
            Websites::Catalog.sync!
            @layouts = WebsiteLayout.active.to_a
            @family = params[:family].to_s.presence
          end

          def new
            @layout = WebsiteLayout.new(
              sections: Websites::Skeletons.decorate_sections(
                [ { "type" => "rich_text", "props" => { "heading" => "", "body" => "" } } ]
              )
            )
          end

          def create
            @layout = WebsiteLayout.new
            persist(:created, :new)
          end

          def edit; end

          def update
            persist(:saved, :edit)
          end

          def preview
            render_catalog_preview(
              key: @layout.key,
              name: @layout.display_name,
              pages: [ { "title" => @layout.display_name, "slug" => "", "home" => true, "sections" => @layout.sections } ],
              current_slug: "",
              edit_path: edit_admin_maintenance_platform_module_settings_website_layout_path(current_customer_id, @layout.key),
              back_path: admin_maintenance_platform_module_settings_website_layouts_path(current_customer_id),
              page_path: nil
            )
          end

          private

          def load_feature_module
            @feature_module = FeatureModules::Module.find_by(key: "website")
          end

          def load_layout
            @layout = WebsiteLayout.find_by!(key: params[:key])
          end

          def persist(flash_key, fail_view)
            result = Websites::Activities::SaveLayout.call(layout: @layout, params: layout_params)
            @layout = result.model if result.respond_to?(:model) && result.model
            if result.success?
              redirect_to admin_maintenance_platform_module_settings_website_layouts_path(current_customer_id),
                          notice: t("website.platform.layouts.flash.#{flash_key}")
            else
              flash.now[:alert] = t("website.platform.layouts.flash.save_failed")
              render fail_view, status: :unprocessable_entity
            end
          end

          def layout_params
            src = params[:website_layout] || params
            permitted = src.permit(:key, :name, :description, :position, :archived, :theme_key, :sections, :sections_json)
            h = permitted.to_h
            json = h.delete("sections_json") || h.delete(:sections_json)
            h[:sections] = json if json.present? && h[:sections].blank?
            h[:sections] = src[:sections] if src[:sections].present? && h[:sections].blank?
            h
          end
        end
      end
    end
  end
end
