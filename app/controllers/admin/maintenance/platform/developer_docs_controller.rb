# frozen_string_literal: true

module Admin
module Maintenance
module Platform
  # Platform-owner reader for doc/reference.
  # Path /admin/maintenance/platform/* is already gated to platform_owner?
  # by RouteAuthorization — do not add a duplicate role before_action.
  class DeveloperDocsController < ApplicationController
    dashboard_menu_item :maintenance

    def index
      render_page(DeveloperDocs::Catalog::HOME_SLUG)
    end

    def show
      render_page(params[:slug])
    end

    private

    def default_url_options
      super.merge(locale: current_locale.to_s)
    end

    def render_page(slug)
      repository = DeveloperDocs::Repository.new(customer_id: current_customer_id, route_options: { locale: current_locale.to_s })
      @page = repository.page(
        slug,
        query: params[:q],
        search_path: url_for(request.path_parameters.merge(only_path: true, locale: current_locale.to_s))
      )
      @hub_groups = localized_hub_groups(repository) if @page&.slug == DeveloperDocs::Catalog::HOME_SLUG
      if @page
        render :show
      else
        render :missing, status: :not_found
      end
    end

    def localized_hub_groups(repository)
      repository.hub_groups.map do |group|
        entries = group.entries.map do |entry|
          entry.with(path: admin_maintenance_platform_developer_doc_path(current_customer_id, entry.slug, locale: current_locale.to_s))
        end
        group.with(entries: entries)
      end
    end
  end
end
end
end
