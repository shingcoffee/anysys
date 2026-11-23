# frozen_string_literal: true

module Websites
  module Admin
    # Live scaled page preview inside a browser-window frame. Only the first
    # few sections render so a large catalog stays cheap.
    class CatalogThumbnailComponent < ApplicationComponent
      SECTION_LIMIT = 3
      FRAME_CLASS = "aspect-[4/5] md:aspect-[16/10]"

      def initialize(sections:, theme:, page_component_class: nil, frame_class: FRAME_CLASS)
        @sections = Array(sections)
        @theme = theme
        @page_component_class = page_component_class
        @frame_class = frame_class
      end

      attr_reader :theme, :frame_class

      def preview_sections
        @sections.first(SECTION_LIMIT)
      end

      def preview_types
        preview_sections.filter_map { |section| section_type(section) }
      end

      def page_component_class
        @page_component_class || Websites::PageComponent
      end

      def render_live_preview?
        page_component_class.present? && preview_types.any? { |type| Websites::SectionKit.component_class(type) }
      end

      def section_type_label(type)
        I18n.t("website.sections.#{type}.name")
      end

      # The window crops a full page render, so tall heroes get sliced. Fading
      # the bottom edge to the preview background makes the cut read as depth.
      def fade_class
        theme.dark? ? "from-neutral-950 to-transparent" : "from-white to-transparent"
      end

      private

      def section_type(section)
        hash = section.respond_to?(:to_h) ? section.to_h.stringify_keys : {}
        hash["type"].to_s.presence
      end
    end
  end
end
