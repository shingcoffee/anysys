# frozen_string_literal: true

module Websites
  # Full-size, read-only render of a platform catalog layout or skeleton page
  # inside the public website chrome, themed with the entry's catalog tokens.
  # Nothing is persisted: the site and page exist only for this request.
  module CatalogPreview
    extend ActiveSupport::Concern

    private

    # pages: [{ "title", "slug", "home", "sections" }]; the bar lists them
    # when there is more than one.
    def render_catalog_preview(key:, name:, pages:, current_slug:, edit_path:, back_path:, page_path:)
      page = pages.find { |item| item["slug"].to_s == current_slug.to_s } || pages.first
      @theme = Websites::Theme.for_catalog(key)
      @website = ::Website.new(customer_id: current_customer_id, name: name, skeleton_key: key, theme: @theme.to_stored)
      @page_document_title = [page&.dig("title").presence, name].compact.join(" · ")
      @catalog_preview = {
        name: name,
        pages: pages.map { |item| item.slice("title", "slug", "home") },
        current_slug: page&.dig("slug").to_s,
        sections: Websites::Skeletons.decorate_sections(page&.dig("sections"), key),
        edit_path: edit_path,
        back_path: back_path,
        page_path: page_path
      }
      @preview_sections = @catalog_preview[:sections]
      render "admin/maintenance/platform/website/catalog_previews/show", layout: "website"
    end
  end
end
