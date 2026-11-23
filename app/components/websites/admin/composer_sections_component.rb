# frozen_string_literal: true

module Websites
  module Admin
    # Section list + kit for the page/layout composer.
    class ComposerSectionsComponent < ApplicationComponent
      TAB_NUMBER_CLASS = "flex size-6 shrink-0 items-center justify-center rounded-md bg-canvas text-2xs font-medium tabular-nums text-text-tertiary transition-colors group-aria-selected/tab:bg-accent-subtle group-aria-selected/tab:text-accent-text"

      renders_one :inspector_header

      def initialize(composer:)
        @composer = composer
      end

      delegate :sections, :structure_locked?, :kit_types, :template_section,
               :layout_kind?, :site_pages, :defaults_for, :empty_defaults_for,
                :workspace?, :image_upload?, :presentation, :site_theme, to: :@composer

      def section_nav_items
        @section_nav_items ||= sections.filter_map do |section|
          id = section["id"].to_s
          next if id.blank?

          type = section["type"].to_s
          label = if Websites::SectionKit.known?(type)
            key = "website.sections.#{type}.name"
            I18n.exists?(key) ? I18n.t(key) : type.humanize
          else
            I18n.t("website.admin.pages.edit.unknown_section")
          end
          preview = %w[headline heading quote kicker eyebrow].filter_map { |key| section.dig("props", key).presence }.first
          { id: id, label: label, preview: preview }
        end
      end

      # Previous/next neighbours for the locked workspace, where section order
      # is fixed so server-rendered links cannot go stale.
      def step_for(section)
        return unless workspace? && structure_locked?

        items = section_nav_items
        position = items.index { |item| item[:id] == section["id"].to_s }
        return unless position

        {
          number: position + 1,
          total: items.size,
          previous: position.positive? ? items[position - 1] : nil,
          next: items[position + 1]
        }
      end

      def outline_item_class
        if workspace?
          "group/tab flex w-full min-w-0 items-start gap-3 rounded-lg px-2.5 py-2 text-left transition-colors hover:bg-surface-hover aria-selected:bg-accent-subtle focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-accent"
        else
          "flex max-w-[12rem] shrink-0 flex-col gap-0.5 rounded-lg border border-border-subtle bg-surface px-3 py-2 text-left hover:bg-surface-hover aria-[current=true]:border-accent aria-[current=true]:bg-accent-subtle/50 aria-[current=true]:ring-1 aria-[current=true]:ring-accent/40"
        end
      end

      def section_tab(item, index: nil)
        selected = index == 0
        preview = item[:preview].to_s
        tag.button(type: "button", id: "website-section-tab-#{item[:id]}", role: "tab",
                   class: outline_item_class, tabindex: selected ? 0 : -1,
                   aria: { controls: "website-section-panel-#{item[:id]}", selected: selected, current: selected },
                   data: { website_builder_target: "sectionNav", section_id: item[:id],
                           action: "click->website-builder#focusSection keydown->website-builder#navigateSectionTabs" }) do
          safe_join([
            tag.span(index.nil? ? "" : index + 1, class: TAB_NUMBER_CLASS, data: { section_number: true }),
            tag.span(class: "min-w-0 flex-1") do
              safe_join([
                tag.span(item[:label], class: "block truncate text-sm font-medium text-text-secondary group-aria-selected/tab:text-text-primary", data: { section_label: true }),
                tag.span(preview, class: "mt-0.5 block truncate text-xs text-text-tertiary#{' hidden' if preview.blank?}", data: { section_preview: true })
              ])
            end
          ])
        end
      end
    end
  end
end
