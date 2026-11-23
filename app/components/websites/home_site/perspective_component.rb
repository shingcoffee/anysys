# frozen_string_literal: true

module Websites
  module HomeSite
    class PerspectiveComponent < SectionComponent
      CARD_GLYPHS = [
        "M3 4h18v12H3zM8 20h8M12 16v4",
        "M12 3l7 3v6c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6zM9 12l2 2 4-4",
        "M6 10V8a6 6 0 1 1 12 0v2M5 10h14v10H5zM12 14v2"
      ].freeze

      def cards = list("cards")
      def text_cards = cards.select { |card| present_text?(card["title"]) || present_text?(card["body"]) }
      def lead_image = cards.first&.fetch("image_url", nil)
      def card_glyph(index) = CARD_GLYPHS[index % CARD_GLYPHS.size]
      def supplementary_cards
        seen = [lead_image.to_s.strip]
        cards.drop(1).select do |card|
          src = card["image_url"].to_s.strip
          next false unless valid_media?(src)
          next false if Websites::Href::BUNDLED_ILLUSTRATION_PATH.match?(src) || seen.include?(src)

          seen << src
          true
        end
      end
    end
  end
end
