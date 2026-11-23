# frozen_string_literal: true

module Websites
  module HomeSite
    class StatsComponent < SectionComponent
      def items = list("items").select { |item| present_text?(item["value"]) }
      def render? = items.any?
      def padding_class = "py-14 lg:py-20"
      def grid_class = { 1 => "lg:grid-cols-1", 2 => "lg:grid-cols-2", 3 => "lg:grid-cols-3" }.fetch(items.size, "lg:grid-cols-4")
    end
  end
end
