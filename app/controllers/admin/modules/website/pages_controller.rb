# frozen_string_literal: true

module Admin
  module Modules
    module Website
      class PagesController < BaseController
        include Listable
        layout :website_pages_layout

        before_action :load_page, only: %i[edit update destroy preview]

        def index
          @website = current_website
          @columns = index_columns
          scope = website_pages_scope
          if scope
            result = ModuleEntriesResolver.call(
              scope: scope.order(:position, :id),
              columns: @columns,
              params: params.permit(:page, :per_page, :sort, :dir, :q).to_h.symbolize_keys
            )
            @rows = result[:rows]
            @pagination = result[:pagination]
          else
            @rows = []
            @pagination = { page: 1, per_page: ModuleEntriesResolver::DEFAULT_PER_PAGE, total: 0, total_pages: 1 }
          end
        end

        def new
          @website = current_website
          @layouts = Websites::Catalog.layouts
          @page = website_pages_scope.new(
            website: @website,
            layout_key: @website&.default_layout_key.presence || @layouts.first&.key
          )
        end

        def create
          website = current_website
          unless website
            redirect_to admin_settings_modules_website_path(current_customer_id),
                        alert: t("website.admin.settings.missing_site")
            return
          end

          page = website_pages_scope.new(website: website)
          save_page(page, :new, created: true)
        end

        def edit
          @website = current_website
        end

        def update
          save_page(@page, :edit)
        end

        def destroy
          result = call_website_activity("DestroyPage", page: @page)
          if website_activity_ok?(result)
            redirect_to admin_modules_website_root_path(current_customer_id),
                        notice: t("website.admin.flash.page_deleted")
          else
            redirect_to admin_modules_website_root_path(current_customer_id),
                        alert: t("website.admin.flash.page_destroy_home")
          end
        end

        def preview
          @website = current_website
          @embed = params[:embed].to_s == "1"
          apply_draft_preview
          assign_preview_chrome
        end

        def reorder
          website = current_website
          return head :not_found unless website

          ordered_ids = Array(params[:ordered_ids].presence || params[:page_ids])
          call_website_activity("ReorderPages", website: website, ordered_ids: ordered_ids)
          redirect_to admin_modules_website_root_path(current_customer_id)
        end

        private

        def index_columns
          [
            {
              key: :title,
              label: I18n.t("website.admin.pages.index.columns.title"),
              sortable: true,
              searchable: true,
              subtitle: ->(page) { public_path_for(page) }
            },
            {
              key: :slug,
              label: I18n.t("website.admin.pages.index.columns.slug"),
              sortable: true,
              searchable: true,
              cell: ->(page) {
                page.try(:home?) || page.try(:slug).to_s.blank? ?
                  I18n.t("website.admin.pages.index.home_slash") : page.slug
              }
            },
            {
              key: :layout_key,
              label: I18n.t("website.admin.pages.index.columns.layout"),
              sortable: true,
              cell: ->(page) {
                key = page.try(:layout_key).to_s
                next I18n.t("common.labels.em_dash") if key.blank?

                I18n.exists?("website.layouts.#{key}.name") ? I18n.t("website.layouts.#{key}.name") : key
              }
            },
            {
              key: :published,
              label: I18n.t("website.admin.pages.index.columns.published"),
              type: :badge,
              sortable: true,
              badge: ->(page) {
                if page.try(:published?)
                  { variant: :success, label: I18n.t("common.status.published") }
                else
                  { variant: :default, label: I18n.t("common.status.draft") }
                end
              },
              cell: ->(page) {
                page.try(:published?) ? I18n.t("common.status.published") : I18n.t("common.status.draft")
              }
            },
            {
              key: :updated_at,
              label: I18n.t("website.admin.pages.index.columns.updated"),
              type: :datetime,
              relative: true,
              sortable: true
            }
          ]
        end

        def public_path_for(page)
          helpers.page_shortcuts_mounted_path(PageShortcuts::PublicPath.website_page(page: page, host: request.host))
        end

        def website_pages_layout
          action_name == "preview" ? "website" : dashboard_layout
        end

        def load_page
          scope = website_pages_scope
          return head :not_found unless scope

          @page = scope.find(params[:id])
        end

        def save_page(page, fail_view, created: false)
          attrs = page_params
          result = call_website_activity("SavePage", page: page, params: attrs)
          page = result.model if result.respond_to?(:model) && result.model
          persisted = website_activity_ok?(result)

          if persisted && page.respond_to?(:persisted?) && page.persisted?
            if composer_request?
              render json: { ok: true }
            else
              redirect_to edit_admin_modules_website_page_path(current_customer_id, page),
                          notice: t(created ? "website.admin.flash.page_created" : "website.admin.flash.page_saved")
            end
          elsif composer_request?
            render json: { ok: false, error: t("website.admin.flash.page_save_failed") },
                   status: :unprocessable_entity
          else
            @page = page
            @website = current_website
            @layouts = Websites::Catalog.layouts
            flash.now[:alert] = t("website.admin.flash.page_save_failed")
            render fail_view, status: :unprocessable_entity
          end
        end

        def page_params
          src = params[:website_page] || params
          permitted = src.permit(:title, :slug, :published, :nav_visible, :home, :position, :layout_key, :theme_key, :sections, :sections_json)
          h = permitted.to_h
          json = h.delete("sections_json") || h.delete(:sections_json)
          h[:sections] = json if json.present? && h[:sections].blank?
          h[:sections] = src[:sections] if src[:sections].present? && h[:sections].blank?
          h
        end

        def composer_request?
          request.headers["X-Website-Composer"].to_s == "1"
        end

        def apply_draft_preview
          return unless request.post?

          attrs = page_params
          title = attrs["title"] || attrs[:title]
          @page.title = title if title.present?
          slug = attrs.key?("slug") ? attrs["slug"] : attrs[:slug]
          @page.slug = slug unless slug.nil?
          @page.theme_key = attrs["theme_key"].presence if attrs.key?("theme_key")
          raw = attrs["sections"] || attrs[:sections]
          return if raw.blank?

          parsed = raw.is_a?(String) ? JSON.parse(raw) : raw
          @page.sections = parsed if parsed.is_a?(Array)
        rescue JSON::ParserError
          nil
        end

        def assign_preview_chrome
          @preview = true
          @edit_url = edit_admin_modules_website_page_path(current_customer_id, @page)
          @theme = Websites::Theme.for_page(website: @website, page: @page)
          @nav_pages = preview_nav_pages
        end

        def preview_nav_pages
          return [] unless @website.respond_to?(:pages)

          pages = @website.pages
          pages = pages.in_nav if pages.respond_to?(:in_nav)
          pages.to_a
        end

      end
    end
  end
end
