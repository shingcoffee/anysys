# frozen_string_literal: true

module Websites
  module Sections
    # Side-by-side comparison (Apple "Compare models", Stripe and Notion plan
    # tables): up to four named columns and a row per feature. A ✓ cell
    # renders a check, a blank or dash cell renders "not included", anything
    # else is shown as written.
    class ComparisonTableComponent < Websites::SectionComponent
      INCLUDED = %w[✓ ✔ ✔️].freeze
      EXCLUDED = ["", "-", "–", "—", "✕", "✗", "×"].freeze

      def columns
        @columns ||= Websites::SectionKit::COMPARISON_COLUMNS.filter_map do |number|
          name = prop("column_#{number}")
          { number: number, name: name } if present_text?(name)
        end
      end

      def rows
        list("rows").select { |row| present_text?(row["title"]) }
      end

      def cell(row, column)
        value = row["value_#{column[:number]}"].to_s.strip
        return :included if INCLUDED.include?(value)
        return :excluded if EXCLUDED.include?(value)

        value
      end

      def table?
        columns.any? && rows.any?
      end

      def head_band_class
        theme.dark? ? "bg-white/[0.04]" : "bg-neutral-50"
      end

      def public_label(key)
        I18n.t("website.public.comparison.#{key}")
      end
    end
  end
end
