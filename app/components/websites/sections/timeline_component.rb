# frozen_string_literal: true

module Websites
  module Sections
    # Dated milestones on a vertical rail (Patagonia's history, Linear's
    # changelog). A year reads as a large numeral in the headline face; a
    # longer date stays small caps so a changelog does not shout.
    class TimelineComponent < Websites::SectionComponent
      YEAR_LENGTH = 4

      def items
        list("items").select { |item| %w[date title body].any? { |key| present_text?(item[key]) } }
      end

      def date_class(item)
        if item["date"].to_s.strip.length <= YEAR_LENGTH
          "text-site-3xl leading-none tabular-nums md:text-site-4xl #{headline_font_class} #{theme.kicker_class}"
        else
          "text-site-sm font-semibold uppercase leading-snug tracking-[0.14em] tabular-nums #{theme.kicker_class}"
        end
      end

      def rail_class
        theme.dark? ? "bg-white/15" : "bg-neutral-900/10"
      end

      def dot_class
        ring = theme.dark? ? "ring-neutral-950" : "ring-white"
        "relative mt-2 size-3 shrink-0 rounded-full ring-[6px] #{theme.accent_dot_class} #{ring}"
      end
    end
  end
end
