# frozen_string_literal: true

module Websites
  module Sections
    # Centered product reveal with a large still and a spec row (Apple).
    class ProductSpotlightComponent < Websites::SectionComponent
      def specs
        list("specs").select { |spec| present_text?(spec["value"]) || present_text?(spec["label"]) }
      end

      def links
        [
          apple_link("primary"),
          apple_link("secondary")
        ].compact
      end

      def apple_link_class
        "inline-flex items-center gap-1 text-site-lg font-medium underline-offset-4 hover:underline #{theme.kicker_class}"
      end

      SPEC_GRIDS = {
        1 => [1, 1, "grid-cols-1"],
        2 => [2, 2, "grid-cols-2"],
        3 => [3, 3, "grid-cols-3"],
        4 => [2, 4, "grid-cols-2 sm:grid-cols-4"]
      }.freeze
      WIDE_SPEC_GRID = [2, 3, "grid-cols-2 sm:grid-cols-3"].freeze

      def spec_grid_class
        spec_grid.last
      end

      def spec_cell_class(index)
        mobile, desktop, = spec_grid
        ruled = !(index % mobile).zero?
        classes = [ruled ? "border-l" : nil]
        classes << (ruled ? "sm:border-l-0" : "sm:border-l") if ruled != !(index % desktop).zero?
        classes << spec_rule_class
        classes.compact.join(" ")
      end

      def spec_rule_class
        theme.dark? ? "border-white/[0.12]" : "border-neutral-900/[0.1]"
      end

      private

      def spec_grid
        @spec_grid ||= SPEC_GRIDS.fetch(specs.size, WIDE_SPEC_GRID)
      end

      def apple_link(key)
        label = prop("#{key}_label")
        return unless present_text?(label)

        { label: label, href: resolved_href("#{key}_href"), role: key.to_sym }
      end
    end
  end
end
