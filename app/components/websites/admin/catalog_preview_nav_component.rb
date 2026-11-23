# frozen_string_literal: true

module Websites
  module Admin
    # Public nav for a catalog preview: page links switch preview pages
    # instead of resolving against a tenant's live site.
    class CatalogPreviewNavComponent < Websites::NavComponent
      def initialize(page_path:, **options)
        super(**options)
        @page_path = page_path
      end

      def home_href
        preview_href("")
      end

      def page_href(page)
        home_page?(page) ? home_href : preview_href(page_slug(page))
      end

      private

      def preview_href(slug)
        @page_path.respond_to?(:call) ? @page_path.call(slug) : "#"
      end
    end
  end
end
