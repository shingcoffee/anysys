# frozen_string_literal: true

module Websites
  module HomeSite
    # The first named column is the hero column; the rest are the alternatives
    # it is compared against.
    class ComparisonComponent < SectionComponent
      EXCLUDED = Websites::Sections::ComparisonTableComponent::EXCLUDED
      INCLUDED = Websites::Sections::ComparisonTableComponent::INCLUDED

      def columns
        @columns ||= Websites::SectionKit::COMPARISON_COLUMNS.filter_map do |number|
          name = prop("column_#{number}")
          { number: number, name: name } if present_text?(name)
        end
      end

      def rows = list("rows").select { |row| present_text?(row["title"]) }
      def render? = columns.any? && rows.any?
      def section_class = "bg-gradient-to-b from-white via-slate-50 to-white"
      def lead?(column) = column.equal?(columns.first)
      def table_width_class = columns.size > 2 ? "min-w-[34rem]" : "min-w-0"

      def cell_text(row, column)
        value = row["value_#{column[:number]}"].to_s.strip
        INCLUDED.include?(value) || EXCLUDED.include?(value) ? "" : value
      end

      def positive?(row, column)
        value = row["value_#{column[:number]}"].to_s.strip
        return false if EXCLUDED.include?(value)

        INCLUDED.include?(value) || lead?(column)
      end
    end
  end
end
