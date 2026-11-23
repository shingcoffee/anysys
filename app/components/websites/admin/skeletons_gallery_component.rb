# frozen_string_literal: true

module Websites
  module Admin
    # Read-only catalog of code-defined starters for platform owners.
    class SkeletonsGalleryComponent < ApplicationComponent
      # Page-role chips shown before collapsing the rest into a "+N" chip, so
      # the single-line chip row never clips a label mid-word.
      CHIP_LIMIT = 2

      def initialize(skeletons: nil, default_key: "presence", customer_id: nil, category: nil)
        @skeletons = skeletons
        @default_key = default_key.to_s.presence || "presence"
        @customer_id = customer_id
        @category = category.to_s.presence
        @category = nil unless Websites::Skeletons::CATEGORIES.include?(@category)
      end

      def default_key
        @default_key
      end

      def current_category
        @category
      end

      def entries
        keys.filter_map { |key| entry_for(key) }
      end

      def filtered_entries
        return entries if current_category.blank?

        entries.select { |entry| entry[:category] == current_category }
      end

      def grouped_entries
        groups = filtered_entries.group_by { |entry| entry[:category] }
        Websites::Skeletons::CATEGORIES.filter_map { |category|
          items = groups[category]
          next if items.blank?

          [category, items]
        }
      end

      def show_group_headings?
        current_category.blank? && grouped_entries.size > 1
      end

      def preview_theme_for(key)
        @skeleton_records ||= WebsiteSkeleton.where(key: keys).index_by(&:key)
        Websites::Theme.for_catalog(key, records: @skeleton_records)
      end

      def page_component_class
        Websites::PageComponent
      end

      def render_page_preview?(entry)
        page_component_class.present? && preview_types(entry).any? { |type| Websites::SectionKit.component_class(type) }
      end

      def default?(entry)
        entry[:key] == default_key
      end

      def edit_path(key)
        return if @customer_id.blank?

        helpers.admin_maintenance_platform_module_settings_website_edit_skeleton_path(@customer_id, key)
      end

      def preview_path(key)
        return if @customer_id.blank?

        helpers.admin_maintenance_platform_module_settings_website_preview_skeleton_path(@customer_id, key)
      end

      def skeleton_name(key)
        i18n_key = "website.skeletons.#{key}.name"
        I18n.exists?(i18n_key) ? I18n.t(i18n_key) : key.to_s
      end

      def skeleton_description(key)
        i18n_key = "website.skeletons.#{key}.description"
        I18n.exists?(i18n_key) ? I18n.t(i18n_key) : ""
      end

      def visible_page_roles(entry)
        Array(entry[:pages]).first(CHIP_LIMIT)
      end

      def extra_page_count(entry)
        [Array(entry[:pages]).size - CHIP_LIMIT, 0].max
      end

      def page_role_label(role)
        i18n_key = "website.platform.skeletons.pages.#{role}"
        I18n.exists?(i18n_key) ? I18n.t(i18n_key) : role.to_s
      end

      def section_type_label(type)
        I18n.t("website.sections.#{type}.name")
      end

      def category_label(category)
        I18n.t("website.skeletons.categories.#{category}")
      end

      def inspired_by_credit(key)
        brand_key = "website.skeletons.#{key}.inspired_by"
        format_key = "website.skeletons.inspired_by_format"
        return unless I18n.exists?(brand_key) && I18n.exists?(format_key)

        I18n.t(format_key, brand: I18n.t(brand_key))
      end

      def filter_items
        Websites::Skeletons.categories.map do |category|
          {
            id: category,
            label: category_label(category),
            count: category_counts[category],
            path: helpers.admin_maintenance_platform_module_settings_website_skeletons_path(@customer_id, category: category)
          }
        end
      end

      def all_count
        entries.size
      end

      def all_filter_path
        helpers.admin_maintenance_platform_module_settings_website_skeletons_path(@customer_id)
      end

      def show_filters?
        @customer_id.present? && filter_items.size > 1
      end

      def thumbnail_sections(entry)
        Array(entry[:home_sections]).first(CatalogThumbnailComponent::SECTION_LIMIT)
      end

      private

      def category_counts
        @category_counts ||= entries.each_with_object(Hash.new(0)) { |entry, counts|
          counts[entry[:category]] += 1
        }
      end

      def keys
        raw = @skeletons.nil? ? Websites::Skeletons.keys : Array(@skeletons)
        raw.filter_map { |item| normalize_key(item) }.select { |key| Websites::Skeletons.known?(key) }
      end

      def normalize_key(item)
        if item.respond_to?(:key) && !item.is_a?(String)
          item.key.to_s.presence
        elsif item.respond_to?(:to_h) && (item[:key] || item["key"])
          (item[:key] || item["key"]).to_s
        else
          item.to_s.presence
        end
      end

      def entry_for(key)
        pages = Websites::Skeletons.pages_for(key)
        return if pages.blank?

        sections = Websites::Skeletons.home_sections(key, pages)
        {
          key: key,
          category: Websites::Skeletons.category_for(key),
          pages: pages.filter_map { |page| page.stringify_keys["role"].presence },
          home_sections: sections,
          home_types: sections.filter_map { |section| section["type"].to_s.presence }
        }
      end

      def preview_types(entry)
        Array(entry[:home_types])
      end
    end
  end
end
