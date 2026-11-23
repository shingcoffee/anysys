# frozen_string_literal: true

module Websites
  module Sections
    # A masonry wall of short endorsements (Notion / Figma customer walls).
    class TestimonialsComponent < Websites::SectionComponent
      def items
        list("items").select { |item| present_text?(item["quote"]) }
      end

      def columns_class
        items.size <= 2 ? "md:columns-2" : "md:columns-2 lg:columns-3"
      end

      def initials(name)
        name.to_s.split.first(2).map { |part| part[0] }.join.upcase
      end
    end
  end
end
