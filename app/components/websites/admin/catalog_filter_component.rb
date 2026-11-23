# frozen_string_literal: true

module Websites
  module Admin
    # Segmented chip row for catalog filters (category / family).
    class CatalogFilterComponent < ApplicationComponent
      def initialize(label:, all_path:, items:, current: nil, all_count: nil)
        @label = label
        @all_path = all_path
        @items = Array(items)
        @current = current.to_s.presence
        @all_count = all_count
      end

      attr_reader :label, :all_path, :items, :current, :all_count

      def all_active?
        current.blank?
      end

      def item_active?(item)
        item[:id].to_s == current
      end

      def chip_class(active)
        base = "inline-flex h-8 items-center gap-1.5 whitespace-nowrap rounded-full px-3 text-sm transition-colors duration-150"
        if active
          "#{base} bg-accent font-semibold text-white shadow-xs"
        else
          "#{base} bg-surface font-medium text-text-secondary ring-1 ring-inset ring-border-subtle hover:bg-surface-hover hover:text-text-primary"
        end
      end

      def count_class(active)
        if active
          "text-xs font-medium tabular-nums text-white"
        else
          "text-xs font-medium tabular-nums text-text-secondary"
        end
      end

      def count_for(item)
        item[:count]
      end
    end
  end
end
