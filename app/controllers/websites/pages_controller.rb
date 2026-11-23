# frozen_string_literal: true

module Websites
  # Public marketing site. No auth. Unpublished / disabled / missing → empty 404
  # (never leak page titles or site name).
  class PagesController < ApplicationController
    include Websites::CurrentSite
    include PageShortcuts::RouteContext
    include PageShortcuts::PublicPathContext

    layout "website"

    rescue_from ActiveRecord::RecordNotFound, with: :public_not_found

    def home
      return public_not_found unless public_site_available?

      @page = page_shortcut_target ? page_shortcut_page : home_page_for(@website)
      return public_not_found unless @page&.try(:published?)

      assign_public_chrome
      render :show
    end

    def show
      return public_not_found unless public_site_available?

      @page = page_shortcut_target ? page_shortcut_page : inner_page_for(params[:page_slug].to_s)
      return public_not_found unless @page&.try(:published?)

      assign_public_chrome
    end

    private

    def public_site_available?
      return false unless website_module_enabled?

      @website = current_website
      @website&.try(:published?)
    end

    def home_page_for(website)
      return unless website

      website.home_page
    end

    def page_shortcut_page
      return unless page_shortcut_target.target_type == "WebsitePage"

      WebsitePage.find_by(
        id: page_shortcut_target.target_id,
        customer_id: current_customer_id,
        website_id: @website.id
      )
    end

    def inner_page_for(slug)
      return if slug.blank?

      page = WebsitePage.find_by(
        customer_id: current_customer_id,
        website_id: @website.id,
        slug: slug
      )
      return if page.nil? || page.home?

      page
    end

    def assign_public_chrome
      # Resolve associations on the saved site before making presentation copies.
      localization = Websites::HomeSiteLocalization.new
      @nav_pages = public_nav_pages.map { |page| localization.page(page) }
      @page = localization.page(@page)
      @website = localization.website(@website)
      site_name = @website.try(:name)
      page_title = @page.try(:title)
      @page_document_title = [page_title, site_name].compact.reject(&:blank?).join(" · ")
      @meta_description = seo_description
      @theme = Websites::Theme.for_page(website: @website, page: @page)
    end

    def public_nav_pages
      return [] unless @website.respond_to?(:pages)

      pages = @website.pages
      pages = pages.published if pages.respond_to?(:published)
      pages = pages.in_nav if pages.respond_to?(:in_nav)
      pages.to_a
    end

    def seo_description
      seo = @website.try(:seo)
      seo = seo.stringify_keys if seo.is_a?(Hash)
      seo.is_a?(Hash) ? seo["description"].presence : nil
    end

    def public_not_found
      head :not_found
    end
  end
end
