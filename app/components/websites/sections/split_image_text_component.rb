# frozen_string_literal: true

module Websites
  module Sections
    class SplitImageTextComponent < Websites::SectionComponent
      def image_right?
        props["image_side"].to_s == "right"
      end

      def image_order_class
        image_right? ? "order-first md:order-last" : "order-first"
      end

      def copy_order_class
        image_right? ? "md:order-first" : ""
      end
    end
  end
end
