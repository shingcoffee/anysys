# frozen_string_literal: true

module Admin
module Help
  # Customer reader protected by RouteAuthorization and TenantContext.
  class DocsController < ApplicationController
    dashboard_menu_item :help

    def index
      render_page(CustomerDocs::Catalog::HOME_SLUG)
    end

    def show
      render_page(params[:slug])
    end

    private

    def render_page(slug)
      response.headers["Cache-Control"] = "private, no-store"
      repository = CustomerDocs::Repository.new(
        customer_id: current_customer_id, locale: current_locale, route_options: { locale: current_locale }
      )
      @page = repository.page(
        slug,
        query: params[:q],
        search_path: search_path
      )
      @guide_groups = @page&.slug == CustomerDocs::Catalog::HOME_SLUG ? repository.guide_groups : nil
      if @page
        render :show
      else
        render :missing, status: :not_found
      end
    end

    def search_path
      if action_name == "index"
        helpers.admin_help_docs_path(current_customer_id, locale: current_locale)
      else
        helpers.admin_help_doc_path(current_customer_id, params[:slug], locale: current_locale)
      end
    end
  end
end
end
