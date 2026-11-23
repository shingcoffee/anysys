# frozen_string_literal: true

module Websites
  module Sections
    # "Trusted by" row. Uploaded marks render monochrome; names without a
    # mark are set as wordmarks in the headline face (Stripe / Linear).
    class LogoCloudComponent < Websites::SectionComponent
      def items
        list("items").select { |item| present_text?(item["name"]) || Websites::Href.media?(item["image_url"].to_s.strip) }
      end

      def grid_class
        count = items.size
        return "grid-cols-2 sm:grid-cols-3" if count <= 3
        return "grid-cols-2 sm:grid-cols-4" if count == 4
        return "grid-cols-2 sm:grid-cols-3 lg:grid-cols-5" if count == 5

        "grid-cols-2 sm:grid-cols-3 lg:grid-cols-6"
      end

      def mark?(item)
        Websites::Href.media?(item["image_url"].to_s.strip)
      end

      def wordmark_class
        tone = theme.dark? ? "text-white/55 hover:text-white/80" : "text-neutral-900/45 hover:text-neutral-900/70"
        "truncate text-site-lg tracking-tight transition-colors md:text-site-xl #{headline_font_class} #{tone}"
      end

      def mark_class
        invert = theme.dark? ? "invert" : ""
        "h-7 w-auto max-w-[8rem] object-contain opacity-60 grayscale md:h-8 #{invert}"
      end
    end
  end
end
