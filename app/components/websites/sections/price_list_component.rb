# frozen_string_literal: true

module Websites
  module Sections
    # A set menu / service list with dotted leaders (restaurant cards, salons).
    class PriceListComponent < Websites::SectionComponent
      def items
        list("items").select { |item| present_text?(item["title"]) }
      end

      def leader_class
        theme.dark? ? "border-white/20" : "border-neutral-900/20"
      end
    end
  end
end
