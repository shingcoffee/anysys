# frozen_string_literal: true

module Websites
  module Admin
    # Move / duplicate / remove controls for one in-section list item.
    class ArrayItemToolbarComponent < ApplicationComponent
      def initialize(min_reached: false, max_reached: false, first: false, last: false, workspace: false, number: 1, title: nil)
        @min_reached = min_reached
        @max_reached, @first, @last, @workspace = max_reached, first, last, workspace
        @number, @title = number, title
      end

      def min_reached?
        @min_reached
      end

      def workspace?
        @workspace
      end

      def action_label(key)
        label = t(key)
        return label unless workspace?

        t("website.admin.pages.form.item_action_format").gsub("{action}", label).gsub("{number}", @number.to_s).gsub("{title}") { @title.to_s }
      end

      # Wide workspace panels lift the toolbar into the item's header row, where
      # it fades in while the item is hovered or focused (always on touch).
      def wrapper_class
        return "flex flex-wrap items-center gap-0.5 pt-1" unless workspace?

        [
          "flex items-center justify-end gap-0.5 @min-[21rem]/content:absolute @min-[21rem]/content:right-2 @min-[21rem]/content:top-1.5",
          "transition-opacity @min-[21rem]/content:pointer-fine:opacity-0 group-hover/item:opacity-100 group-focus-within/item:opacity-100"
        ].join(" ")
      end

      def button_class(danger: false)
        base = "flex size-8 items-center justify-center rounded-md transition-colors disabled:cursor-not-allowed disabled:opacity-30 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"
        tone = if danger
          workspace? ? "text-text-tertiary hover:bg-danger-subtle hover:text-danger" : "text-danger hover:bg-danger-subtle"
        else
          workspace? ? "text-text-tertiary hover:bg-surface-active hover:text-text-primary" : "text-text-muted hover:bg-surface-active hover:text-text-primary"
        end
        "#{base} #{tone}"
      end
    end
  end
end
