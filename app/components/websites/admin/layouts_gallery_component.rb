# frozen_string_literal: true

module Websites
  module Admin
    class LayoutsGalleryComponent < ApplicationComponent
      STANDALONE_FAMILY = Websites::LayoutFamily::STANDALONE
      # Section-type chips shown before collapsing the rest into a "+N" chip,
      # so the single-line chip row never clips a label mid-word.
      CHIP_LIMIT = 2

      def initialize(layouts:, customer_id:, family: nil)
        @layouts = Array(layouts)
        @customer_id = customer_id
        @family = family.to_s.presence
      end

      def preview_theme_for(layout)
        Websites::Theme.for_record(layout)
      end

      def section_types(layout)
        Array(layout.sections).filter_map { |section| section.to_h.stringify_keys["type"].presence }
      end

      def visible_section_types(layout)
        section_types(layout).uniq.first(CHIP_LIMIT)
      end

      def extra_section_count(layout)
        [section_types(layout).uniq.size - CHIP_LIMIT, 0].max
      end

      def edit_path(layout)
        helpers.edit_admin_maintenance_platform_module_settings_website_layout_path(@customer_id, layout.key)
      end

      def preview_path(layout)
        helpers.preview_admin_maintenance_platform_module_settings_website_layout_path(@customer_id, layout.key)
      end

      def new_path
        helpers.new_admin_maintenance_platform_module_settings_website_layout_path(@customer_id)
      end

      def family_for(layout)
        Websites::LayoutFamily.of(layout.key)
      end

      def family_label(family)
        return I18n.t("website.platform.catalog.families.standalone") if family == STANDALONE_FAMILY

        name_key = "website.skeletons.#{family}.name"
        I18n.exists?(name_key) ? I18n.t(name_key) : family.to_s
      end

      def filtered_layouts
        return @layouts if @family.blank?

        @layouts.select { |layout| family_for(layout) == @family }
      end

      def grouped_layouts
        @grouped_layouts ||= Websites::LayoutFamily.group(filtered_layouts)
      end

      def show_group_headings?
        @family.blank? && grouped_layouts.size > 1
      end

      def filter_items
        Websites::LayoutFamily.group(@layouts).map do |family, items|
          {
            id: family,
            label: family_label(family),
            count: items.size,
            path: helpers.admin_maintenance_platform_module_settings_website_layouts_path(@customer_id, family: family)
          }
        end
      end

      def all_count
        @layouts.size
      end

      def all_filter_path
        helpers.admin_maintenance_platform_module_settings_website_layouts_path(@customer_id)
      end

      def current_family
        @family
      end

      def show_filters?
        @customer_id.present? && filter_items.size > 1
      end

      def section_type_label(type)
        I18n.t("website.sections.#{type}.name")
      end

      def thumbnail_sections(layout)
        Array(layout.sections).first(CatalogThumbnailComponent::SECTION_LIMIT)
      end
    end
  end
end
