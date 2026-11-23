# frozen_string_literal: true

module Websites
  module Sections
    # Rounded split panel — photograph on one side, invitation on the other (Airbnb).
    class CtaSplitComponent < Websites::SectionComponent
      def image_left?
        props["image_side"].to_s == "left"
      end

      def image_order_class
        image_left? ? "order-first" : "order-first md:order-last"
      end

      def copy_order_class
        image_left? ? "" : "md:order-first"
      end

      def panel_class
        if theme.dark?
          "bg-white/[0.03] ring-1 ring-inset ring-white/[0.08]"
        else
          "bg-neutral-100 ring-1 ring-inset ring-neutral-900/[0.06]"
        end
      end
    end
  end
end
