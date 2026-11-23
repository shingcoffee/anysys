# frozen_string_literal: true

module Websites
  module HomeSite
    # Industry names scroll as an endless ribbon; the duplicate run exists only
    # to make the loop seamless and is hidden from assistive technology.
    class MarqueeComponent < SectionComponent
      GLYPHS = [
        "M15 8a3 3 0 1 1-6 0 3 3 0 0 1 6 0ZM5 20v-1a5 5 0 0 1 10 0v1M18 5a3 3 0 0 1 0 6M19 15a4 4 0 0 1 2 3v2",
        "M12 21s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 11c0 5.6-7 10-7 10Z",
        "M4 20 14 10M14 4l6 6-4 4-6-6zM4 20h5",
        "M3 9l9-5 9 5-9 5zM7 11v5c3 2 7 2 10 0v-5",
        "M12 3v18M3 12h18M5.6 5.6l12.8 12.8M18.4 5.6 5.6 18.4",
        "M4 7h16v13H4zM9 7V4h6v3"
      ].freeze

      def items = list("items").select { |item| present_text?(item["name"]) }
      def render? = items.any?
      def glyph_for(index) = GLYPHS[index % GLYPHS.size]
    end
  end
end
