# frozen_string_literal: true

module Websites
  module Sections
    # Centered launch hero over a soft accent glow, with the product still in
    # a browser frame below (Vercel / Linear launch pages).
    class HeroCenteredComponent < Websites::SectionComponent
      def media_visible?
        prop("media_mode") != "none"
      end

      def hero_padding_class
        return "pt-14 pb-8 md:pt-20 md:pb-10" unless media_visible?

        "pt-20 md:pt-32 #{theme.density == "compact" ? "pb-16 md:pb-20" : "pb-20 md:pb-28"}"
      end

      def hero_heading_class
        if media_visible?
          "max-w-5xl text-site-4xl sm:text-site-5xl md:text-site-6xl lg:text-site-7xl"
        else
          "max-w-4xl text-site-4xl sm:text-site-5xl lg:text-site-6xl"
        end
      end

      def frame_chrome_class
        theme.dark? ? "border-white/[0.08] bg-white/[0.04]" : "border-neutral-900/[0.06] bg-neutral-50"
      end

      def chrome_dot_class
        theme.dark? ? "bg-white/15" : "bg-neutral-900/10"
      end

      def frame_class
        if theme.dark?
          "bg-neutral-900 ring-1 ring-white/10 shadow-2xl shadow-black/60"
        else
          "bg-white ring-1 ring-neutral-900/[0.08] shadow-2xl shadow-neutral-900/10"
        end
      end

      def grid_line_class
        theme.dark? ? "bg-[linear-gradient(to_right,rgb(255_255_255/0.04)_1px,transparent_1px),linear-gradient(to_bottom,rgb(255_255_255/0.04)_1px,transparent_1px)]" : "bg-[linear-gradient(to_right,rgb(0_0_0/0.035)_1px,transparent_1px),linear-gradient(to_bottom,rgb(0_0_0/0.035)_1px,transparent_1px)]"
      end
    end
  end
end
