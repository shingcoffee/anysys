# frozen_string_literal: true

module Websites
  module HomeSite
    class DraftComponent < SectionComponent
      OUTPUT_GLYPHS = [
        "M4 4h16v16H4zM4 9h16M9 9v11M4 14h16",
        "M7 3h10v3H7zM6 5H4v16h16V5h-2M8 11h8M8 15h5",
        "M3 4h18v16H3zM3 9h18M7 6.5h.01M10 6.5h.01M7 13h4v4H7zM14 13h3M14 17h3"
      ].freeze

      def items = list("items").select { |item| item.values_at("title", "body", "status").any? { |value| present_text?(value) } }
      def brief? = present_text?(prop("prompt")) || present_text?(prop("prompt_label"))
      def board? = brief? || items.any? || %w[example_label output_label review_note].any? { |key| present_text?(prop(key)) }
      def output_glyph(index) = OUTPUT_GLYPHS[index % OUTPUT_GLYPHS.size]
      def body_lines(item) = item["body"].to_s.split(/\r?\n/).reject(&:blank?)
    end
  end
end
