# frozen_string_literal: true

module Admin
  module Maintenance
    module Entities
      # Kebab menu matching AdminTableComponent's row menu. Items are
      # `{ label:, path:, method:, tone:, data: }` hashes or `:separator`.
      # Every item escapes the surrounding turbo-frame.
      class ActionMenuComponent < ApplicationComponent
        ITEM_CLASSES = "flex w-full items-center rounded-md px-2.5 py-1.5 text-sm font-medium transition-base hover:bg-surface-hover"

        def initialize(items:, label: nil)
          @items = Array(items).compact
          @label = label
        end

        def render? = @items.any? { |item| item != :separator }

        def items = @items
        def label = @label || t("common.actions.more")

        def link_options(item)
          data = (item[:data] || {}).merge(turbo_frame: "_top")
          data[:turbo_method] = item[:method] if item[:method] && item[:method].to_sym != :get
          tone = item[:tone] == :danger ? "text-danger" : "text-text-primary"
          { class: "#{ITEM_CLASSES} #{tone}", role: "menuitem", data: data }
        end
      end
    end
  end
end
