# frozen_string_literal: true

module Websites
  module Sections
    # Dark tone: a full-bleed photograph with the headline set low (Apple
    # product film). Light tone: a centered headline over a framed still.
    class HeroCinematicComponent < Websites::SectionComponent
      def dark_tone?
        props["tone"].to_s == "dark"
      end

      def placeholder_appearance
        dark_tone? ? "dark" : theme.appearance
      end

      def kicker_class
        dark_tone? ? "text-site-xs font-semibold uppercase tracking-[0.2em] text-white/80" : super
      end

      def headline_class
        size = dark_tone? ? "text-site-4xl sm:text-site-6xl md:text-site-7xl lg:text-site-8xl" : "text-site-4xl sm:text-site-5xl md:text-site-6xl lg:text-site-7xl"
        "text-balance break-words leading-[0.98] #{size} #{headline_font_class}"
      end

      def subhead_class
        dark_tone? ? "max-w-2xl text-pretty text-site-md text-white/85 md:text-site-lg" : "mx-auto max-w-2xl #{super}"
      end

      def primary_button_class
        dark_tone? ? cinematic_primary_button_class : super
      end

      def secondary_button_class
        return super unless dark_tone?

        "#{button_base_class} bg-white/10 text-white ring-1 ring-inset ring-white/25 backdrop-blur-md hover:bg-white/20"
      end
    end
  end
end
