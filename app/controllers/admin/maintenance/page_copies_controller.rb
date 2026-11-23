# frozen_string_literal: true

module Admin
  module Maintenance
    class PageCopiesController < PagesController
      # The copy resource nests under `resources :pages`, so the parent page id
      # arrives as params[:page_id] (not params[:id]). Override the inherited
      # PagesController#find_page — which reads params[:id] — so the before_action
      # resolves the source page from the correct param. Mirrors
      # PagePreviewsController#find_page.
      def show
        source = find_page
        require_copyable_source!(source)
        @page = Page.new_with_defaults(name: I18n.t("maint_core.entities.copy_name", name: source.name))
        @page.configuration = source.configuration
        @page.description   = source.description
        @page.content       = source.content
        apply_create_identity!(@page)
        load_entity_options
        render "admin/maintenance/pages/new"
      end

      private

      def find_page
        @page = definition_scope(Page).find(params[:page_id])
      end
    end
  end
end
