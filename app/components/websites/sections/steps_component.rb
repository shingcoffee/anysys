# frozen_string_literal: true

module Websites
  module Sections
    # "How it works" in numbered stages joined by a hairline (Airbnb hosting).
    class StepsComponent < Websites::SectionComponent
      def items
        list("items").select { |item| present_text?(item["title"]) || present_text?(item["body"]) }
      end

      def grid_class
        case items.size
        when 2 then "md:grid-cols-2"
        when 4 then "md:grid-cols-2 lg:grid-cols-4"
        else "md:grid-cols-3"
        end
      end

      def badge_class
        "relative z-10 flex size-10 items-center justify-center rounded-full text-site-sm font-medium tabular-nums ring-4 #{theme.accent_soft_class} #{theme.dark? ? "ring-neutral-950" : "ring-white"}"
      end
    end
  end
end
