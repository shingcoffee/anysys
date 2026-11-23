# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      # Segmented control for switching among platform-owner vendor settings
      # (speech-to-text, captcha, email, sms). Deliberately not an underline tab
      # strip: it sits *inside* a section that the page-level SectionNav already
      # marks, and two identical underline rows read as one broken nav. Current
      # item uses aria-current="page"; the live platform vendor gets an Active
      # badge.
      class ProviderSwitcherComponent < ApplicationComponent
        Item = Struct.new(:name, :path, :current, :active, keyword_init: true) do
          def current? = !!current
          def active?  = !!active
        end

        def initialize(nav_label:, items:)
          @nav_label = nav_label
          @items = Array(items).map { |item| coerce_item(item) }
        end

        attr_reader :nav_label, :items

        def render?
          items.any?
        end

        def item_classes(item)
          base = "inline-flex items-center gap-2 whitespace-nowrap rounded-md px-3 py-1.5 text-body-sm font-medium transition-colors"
          state = if item.current?
            "bg-surface text-text-primary shadow-sm ring-1 ring-border-subtle"
          else
            "text-text-muted hover:text-text-primary"
          end

          "#{base} #{state}"
        end

        private

        def coerce_item(item)
          return item if item.is_a?(Item)

          Item.new(**item.to_h.symbolize_keys.slice(:name, :path, :current, :active))
        end
      end
    end
  end
end
