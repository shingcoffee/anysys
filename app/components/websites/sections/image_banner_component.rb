# frozen_string_literal: true

module Websites
  module Sections
    # Full-bleed campaign photograph with a gradient scrim (Nike / Patagonia).
    class ImageBannerComponent < Websites::SectionComponent
      def tall?
        props["height"].to_s != "medium"
      end

      def centered?
        props["placement"].to_s == "center"
      end

      def height_class
        if tall?
          "min-h-[28rem] sm:min-h-[36rem] md:min-h-[80vh]"
        else
          "min-h-[22rem] sm:min-h-[26rem] md:min-h-[32rem]"
        end
      end

      def placement_class
        if centered?
          "my-auto py-16 md:py-24"
        else
          "mt-auto pb-12 pt-36 md:pb-20 md:pt-48"
        end
      end

      def copy_align_class
        centered? ? "items-center text-center mx-auto" : "items-start text-left"
      end

      def primary_button_class
        cinematic_primary_button_class
      end

      def button_href
        resolved_href("button_href")
      end
    end
  end
end
