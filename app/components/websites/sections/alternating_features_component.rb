# frozen_string_literal: true

module Websites
  module Sections
    class AlternatingFeaturesComponent < Websites::SectionComponent
      def items
        list("items")
      end

      def image_side_for(index)
        index.even? ? "left" : "right"
      end

      def image_order_class(index)
        image_side_for(index) == "right" ? "order-first md:order-last" : "order-first"
      end

      def copy_order_class(index)
        image_side_for(index) == "right" ? "md:order-first" : ""
      end
    end
  end
end
