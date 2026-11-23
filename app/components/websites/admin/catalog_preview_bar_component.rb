# frozen_string_literal: true

module Websites
  module Admin
    # Owner toolbar above a full-size catalog preview: back, entry name, page
    # switcher (skeletons) and edit.
    class CatalogPreviewBarComponent < ApplicationComponent
      def initialize(name:, pages:, current_slug:, edit_path:, back_path:, page_path: nil)
        @name = name
        @pages = Array(pages)
        @current_slug = current_slug.to_s
        @edit_path = edit_path
        @back_path = back_path
        @page_path = page_path
      end

      attr_reader :name, :pages, :edit_path, :back_path

      def page_switcher?
        @page_path.respond_to?(:call) && pages.size > 1
      end

      def page_href(page)
        @page_path.call(page["slug"].to_s)
      end

      def current?(page)
        page["slug"].to_s == @current_slug
      end

      def page_link_class(page)
        base = "inline-flex h-7 shrink-0 items-center rounded-md px-2.5 text-xs font-medium transition-colors"
        current?(page) ? "#{base} bg-white/15 text-white" : "#{base} text-white/60 hover:bg-white/10 hover:text-white"
      end
    end
  end
end
