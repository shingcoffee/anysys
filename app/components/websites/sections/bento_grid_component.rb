# frozen_string_literal: true

module Websites
  module Sections
    class BentoGridComponent < Websites::SectionComponent
      COLUMNS = 6
      WIDTH = { "hero" => 4, "wide" => 4, "unit" => 2 }.freeze
      SPAN = {
        2 => "md:col-span-2",
        4 => "md:col-span-4",
        6 => "md:col-span-6"
      }.freeze

      def cells
        list("cells")
      end

      def span_class(cell, index)
        width = packed_widths[index] || WIDTH["unit"]
        [SPAN.fetch(width), hero?(cell) ? "md:row-span-2" : nil].compact.join(" ")
      end

      def hero?(cell)
        cell["span"].to_s == "hero"
      end

      def wide?(index)
        packed_widths[index].to_i >= WIDTH["wide"]
      end

      private

      # Mirrors CSS grid auto-placement on a 6-column track and widens the last
      # tile of any row that would otherwise leave an empty gap.
      def packed_widths
        @packed_widths ||= begin
          widths = cells.map { |cell| WIDTH.fetch(cell["span"].to_s, WIDTH["unit"]) }
          occupied = Hash.new { |hash, row| hash[row] = Array.new(COLUMNS, false) }
          placements = []
          widths.each_with_index do |width, index|
            rows = hero?(cells[index]) ? 2 : 1
            row, col = first_fit(occupied, width, rows)
            rows.times { |offset| width.times { |step| occupied[row + offset][col + step] = true } }
            placements << { row: row, col: col, rows: rows }
          end
          stretch_row_ends(widths, placements, occupied)
        end
      end

      def first_fit(occupied, width, rows)
        (0..).each do |row|
          (0..(COLUMNS - width)).each do |col|
            free = rows.times.all? { |offset| occupied[row + offset][col, width].none? }
            return [row, col] if free
          end
        end
      end

      def stretch_row_ends(widths, placements, occupied)
        widths.each_with_index.map do |width, index|
          place = placements[index]
          next width if place[:rows] > 1

          trailing = occupied[place[:row]][(place[:col] + width)..].take_while { |taken| !taken }.size
          later = placements.drop(index + 1).any? { |other| other[:row] == place[:row] }
          later || trailing.zero? ? width : width + trailing
        end
      end
    end
  end
end
