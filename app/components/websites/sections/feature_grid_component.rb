# frozen_string_literal: true

module Websites
  module Sections
    # Numbered capabilities on hairlines, no icons (Linear / Vercel).
    class FeatureGridComponent < Websites::SectionComponent
      def items
        list("items").select { |item| present_text?(item["title"]) || present_text?(item["body"]) }
      end

      def grid_class
        items.size == 4 ? "sm:grid-cols-2 lg:grid-cols-4" : "sm:grid-cols-2 lg:grid-cols-3"
      end
    end
  end
end
