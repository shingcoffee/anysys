# frozen_string_literal: true

module Websites
  module Admin
    # Paintbrush button that opens one element's StylePanelComponent. Every
    # element (section, text field, buttons, list) gets the same button size so
    # the Design affordance never shifts. With a mouse, revealed triggers fade
    # in only while their `group/design` element is hovered or focused; edited
    # and open triggers always show.
    class StyleTriggerComponent < ApplicationComponent
      CLASS = [
        "group/style-trigger relative inline-flex size-7 shrink-0 items-center justify-center rounded-md text-text-muted",
        "transition hover:bg-surface-hover hover:text-text-primary pointer-coarse:size-9",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent",
        "aria-expanded:bg-accent-subtle aria-expanded:text-accent data-[edited]:text-text-secondary"
      ].join(" ")
      REVEAL_CLASS = [
        "pointer-fine:opacity-0 group-hover/design:opacity-100 group-focus-within/design:opacity-100",
        "focus-visible:opacity-100 aria-expanded:opacity-100 data-[edited]:opacity-100"
      ].join(" ")

      attr_reader :panel_id

      def initialize(panel_id:, label:, edited: false, reveal: false)
        @panel_id = panel_id
        @label = label
        @edited = edited
        @reveal = reveal
      end

      def edited?
        @edited
      end

      def aria_label
        t("website.admin.pages.style.trigger", target: @label)
      end

      def classes
        @reveal ? "#{CLASS} #{REVEAL_CLASS}" : CLASS
      end
    end
  end
end
