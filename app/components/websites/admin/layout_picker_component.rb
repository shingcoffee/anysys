# frozen_string_literal: true

module Websites
  module Admin
    # Step one of a new page: a searchable gallery of platform layouts grouped
    # by starter family. Thumbnails use the site's own theme, so each card looks
    # like the page the customer will publish. Stimulus: website-layout-picker.
    class LayoutPickerComponent < ApplicationComponent
      SUGGESTED = "suggested"
      ALL = "all"
      GENERAL = "general"

      CARD_CLASS = [
        "group/card relative flex cursor-pointer flex-col overflow-hidden rounded-xl bg-surface shadow-xs ring-1 ring-border-subtle",
        "transition duration-150 ease-out hover:-translate-y-px hover:shadow-md hover:ring-border",
        "has-[:checked]:ring-2 has-[:checked]:ring-accent has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-accent/60",
        "[content-visibility:auto] [contain-intrinsic-size:auto_18rem]"
      ].join(" ")

      CHIP_CLASS = [
        "group/chip inline-flex h-9 shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full bg-surface px-3.5 text-sm font-medium",
        "text-text-secondary ring-1 ring-inset ring-border-subtle transition-colors hover:bg-surface-hover hover:text-text-primary",
        "aria-pressed:bg-accent aria-pressed:text-white aria-pressed:ring-accent aria-pressed:hover:bg-accent-hover",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"
      ].join(" ")

      def initialize(form:, layouts:, selected_key: nil, website: nil)
        @form = form
        @layouts = Array(layouts)
        @selected_key = selected_key.to_s
        @website = website
      end

      attr_reader :form, :layouts

      def selected_layout
        @selected_layout ||= layouts.find { |layout| layout.key.to_s == @selected_key } ||
                             layouts.find { |layout| suggested?(layout) } ||
                             layouts.first
      end

      def selected?(layout)
        layout.key.to_s == selected_layout&.key.to_s
      end

      def site_default?(layout)
        default_key.present? && layout.key.to_s == default_key
      end

      def suggested?(layout)
        site_default?(layout) || (site_family.present? && family_for(layout) == site_family)
      end

      def theme
        @theme ||= Websites::Theme.new(@website.try(:theme))
      end

      def groups
        @groups ||= Websites::LayoutFamily.group(layouts, first: site_family)
      end

      def filters
        items = []
        items << { id: SUGGESTED, label: t("website.admin.pages.new.filters.suggested"), count: suggested_count } if suggested_count.positive?
        items << { id: ALL, label: t("website.platform.catalog.filter.all"), count: layouts.size }
        category_order.each do |category|
          count = category_counts[category]
          items << { id: category, label: category_label(category), count: count } if count.positive?
        end
        items
      end

      # The checked card must start visible, so an explicit non-suggested
      # choice (e.g. a re-rendered invalid form) opens on All.
      def initial_filter
        return ALL if suggested_count.zero? || (selected_layout && !suggested?(selected_layout))

        SUGGESTED
      end

      def initially_visible?(layout)
        initial_filter == ALL || suggested?(layout)
      end

      def initial_count_label
        t("website.admin.pages.new.layout_count", count: layouts.count { |layout| initially_visible?(layout) })
      end

      def family_for(layout)
        Websites::LayoutFamily.of(layout.key)
      end

      def category_for(layout)
        family = family_for(layout)
        Websites::LayoutFamily.standalone?(family) ? GENERAL : Websites::Skeletons.category_for(family)
      end

      def family_label(family)
        Websites::LayoutFamily.label(family)
      end

      def category_label(category)
        return t("website.admin.pages.new.filters.general") if category == GENERAL

        t("website.skeletons.categories.#{category}")
      end

      def group_category_label(family)
        return if Websites::LayoutFamily.standalone?(family)

        category_label(Websites::Skeletons.category_for(family))
      end

      def thumbnail_sections(layout)
        Websites::Media.fill_sections(Array(layout.sections).first(CatalogThumbnailComponent::SECTION_LIMIT))
      end

      def card_data(layout)
        labels = LayoutSummaryComponent.section_labels(layout)
        {
          website_layout_picker_target: "card",
          layout_key: layout.key,
          layout_category: category_for(layout),
          layout_suggested: suggested?(layout),
          layout_name: layout.display_name,
          layout_description: layout.display_description.to_s,
          layout_count: LayoutSummaryComponent.count_label(labels),
          layout_sections: LayoutSummaryComponent.sections_text(labels),
          layout_search: search_text(layout, labels)
        }
      end

      def card_class(layout)
        [CARD_CLASS, ("hidden" unless initially_visible?(layout))].compact.join(" ")
      end

      def group_class(items)
        ["flex min-w-0 flex-col gap-3", ("hidden" if items.none? { |layout| initially_visible?(layout) })].compact.join(" ")
      end

      def description_id(layout)
        "website-layout-#{layout.key}-description"
      end

      private

      def search_text(layout, labels)
        [layout.display_name, layout.display_description, family_label(family_for(layout)),
         category_label(category_for(layout)), *labels].compact_blank.join(" ").downcase
      end

      def default_key
        @website.try(:default_layout_key).to_s
      end

      def site_family
        @website.try(:skeleton_key).to_s.presence
      end

      def suggested_count
        @suggested_count ||= layouts.count { |layout| suggested?(layout) }
      end

      def category_counts
        @category_counts ||= layouts.each_with_object(Hash.new(0)) { |layout, counts| counts[category_for(layout)] += 1 }
      end

      def category_order
        Websites::Skeletons.categories + [GENERAL]
      end
    end
  end
end
