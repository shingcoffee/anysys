# frozen_string_literal: true

module Websites
  # Right-side mobile nav panel. Markup only — open/close lives on website-nav.
  class MobileNavSheetComponent < NavComponent
    def initialize(website:, pages: [], current_slug: nil, theme:, open_label:, close_label:)
      super(website: website, pages: pages, current_slug: current_slug, theme: theme)
      @open_label = open_label
      @close_label = close_label
    end

    def open_label = @open_label
    def close_label = @close_label
  end
end
