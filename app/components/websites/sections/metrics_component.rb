# frozen_string_literal: true

module Websites
  module Sections
    # Oversized tabular figures with a short gloss — Stripe “global scale”.
    class MetricsComponent < Websites::SectionComponent
      def items
        list("items").select { |item| present_text?(item["value"]) || present_text?(item["label"]) || present_text?(item["body"]) }
      end

      def grid_class
        case items.size
        when 1 then "max-w-sm"
        when 2 then "sm:grid-cols-2"
        when 3 then "sm:grid-cols-3"
        else "sm:grid-cols-2 lg:grid-cols-4"
        end
      end

      def value_class
        "min-w-0 text-site-4xl tabular-nums leading-none md:text-site-6xl #{headline_font_class} #{theme.kicker_class}"
      end
    end
  end
end
