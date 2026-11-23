# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module Website
        # Skeleton catalog. Owner-gated by RouteAuthorization on the
        # /admin/maintenance/platform/ prefix — do not add a duplicate role filter.
        class SkeletonsController < ApplicationController
          include Websites::CatalogPreview

          dashboard_menu_item :maintenance

          before_action :load_feature_module
          before_action :load_skeleton, only: %i[edit update preview]

          def show
            Websites::Catalog.sync!
            @default_key = default_skeleton_key
            @skeletons = Websites::Catalog.skeletons
            @category = params[:category].to_s.presence
          end

          def edit
            @layouts = Websites::Catalog.layouts
          end

          def preview
            pages = @skeleton.page_list.select { |page| page.is_a?(Hash) }
            home = pages.find { |page| ActiveModel::Type::Boolean.new.cast(page["home"]) }
            pages = ([home] + (pages - [home])).compact
            render_catalog_preview(
              key: @skeleton.key,
              name: @skeleton.display_name,
              pages: pages,
              current_slug: params[:page].presence || home&.dig("slug").to_s,
              edit_path: admin_maintenance_platform_module_settings_website_edit_skeleton_path(current_customer_id, @skeleton.key),
              back_path: admin_maintenance_platform_module_settings_website_skeletons_path(current_customer_id),
              page_path: ->(slug) {
                admin_maintenance_platform_module_settings_website_preview_skeleton_path(current_customer_id, @skeleton.key, page: slug.presence)
              }
            )
          end

          def update
            pages = pages_list
            pages << blank_page if params[:add_page].present?
            if params[:remove_page].present?
              pages.delete_at(params[:remove_page].to_i)
            end

            result = Websites::Activities::SaveSkeleton.call(
              skeleton: @skeleton,
              params: skeleton_params.merge("pages" => pages)
            )
            @skeleton = result.model if result.respond_to?(:model) && result.model
            if result.success?
              if params[:add_page].present? || params[:remove_page].present?
                redirect_to admin_maintenance_platform_module_settings_website_edit_skeleton_path(
                  current_customer_id, @skeleton.key
                )
              else
                redirect_to admin_maintenance_platform_module_settings_website_skeletons_path(current_customer_id),
                            notice: t("website.platform.skeletons.flash.saved")
              end
            else
              @layouts = Websites::Catalog.layouts
              flash.now[:alert] = t("website.platform.skeletons.flash.save_failed")
              render :edit, status: :unprocessable_entity
            end
          end

          private

          def load_feature_module
            @feature_module = FeatureModules::Module.find_by(key: "website")
          end

          def load_skeleton
            @skeleton = WebsiteSkeleton.find_by!(key: params[:key])
          end

          def default_skeleton_key
            schema = @feature_module&.configuration_schema
            schema = JSON.parse(schema) if schema.is_a?(String)
            return "presence" unless schema.is_a?(Hash)

            field = schema["default_skeleton_key"] || schema[:default_skeleton_key]
            return "presence" unless field.is_a?(Hash)

            (field["default"] || field[:default]).presence || "presence"
          rescue JSON::ParserError
            "presence"
          end

          def skeleton_params
            src = params[:website_skeleton] || params
            src.permit(
              :key, :name, :description, :position, :archived, :theme_key,
              pages: [:title, :slug, :home, :nav_visible, :layout_key, :role, :sections_json, :sections]
            ).to_h
          end

          def pages_list
            raw = skeleton_params["pages"] || skeleton_params[:pages]
            case raw
            when Hash
              raw.sort_by { |key, _| key.to_i }.map { |_, page| page }
            when Array
              raw
            else
              @skeleton.page_list
            end
          end

          def blank_page
            layout = Websites::Catalog.layouts.first
            {
              "title" => I18n.t("website.admin.pages.new.title"),
              "slug" => "page",
              "home" => false,
              "nav_visible" => true,
              "role" => "page",
              "layout_key" => layout&.key.to_s,
              "sections" => Array(layout&.instantiate_sections)
            }
          end
        end
      end
    end
  end
end
