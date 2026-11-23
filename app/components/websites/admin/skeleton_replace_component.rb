# frozen_string_literal: true

module Websites
  module Admin
    # Visual starter picker with a per-card destructive replace form. Each card
    # previews the starter's home page in that starter's own catalog theme.
    class SkeletonReplaceComponent < ApplicationComponent
      def initialize(website:, skeletons: nil, replace_url: nil, customer_id: nil)
        @website = website
        @skeletons = skeletons
        @replace_url = replace_url
        @customer_id = customer_id
      end

      attr_reader :website

      def entries
        @entries ||= skeleton_rows.filter_map { |item| entry_for(item) }
      end

      def skeleton_keys
        entries.map { |entry| entry[:key] }
      end

      def current_key
        website.try(:skeleton_key).to_s.presence
      end

      def current?(key)
        key.to_s == current_key.to_s
      end

      def current_entry
        entries.find { |entry| current?(entry[:key]) }
      end

      def preview_theme(key)
        @skeleton_records ||= WebsiteSkeleton.where(key: skeleton_keys).index_by(&:key)
        Websites::Theme.for_catalog(key, records: @skeleton_records)
      end

      def card_class(entry)
        base = "flex min-w-0 flex-col overflow-hidden rounded-xl border bg-surface shadow-xs [content-visibility:auto] [contain-intrinsic-size:auto_24rem]"
        "#{base} #{current?(entry[:key]) ? 'border-accent ring-1 ring-accent' : 'border-border-subtle'}"
      end

      def skeleton_name(key)
        entry = entries.find { |item| item[:key] == key.to_s }
        return entry[:name] if entry

        i18n_key = "website.skeletons.#{key}.name"
        I18n.exists?(i18n_key) ? I18n.t(i18n_key) : I18n.t("website_settings.starter.unavailable")
      end

      def current_caption
        return I18n.t("website_settings.starter.not_selected") if current_key.blank?

        I18n.t("website.admin.settings.skeleton.current", name: skeleton_name(current_key))
      end

      def confirm_message(key = current_key)
        I18n.t("website_settings.starter.confirm", name: skeleton_name(key))
      end

      def replace_url
        return @replace_url if @replace_url.present?

        helpers.admin_settings_modules_website_skeleton_path(resolved_customer_id)
      end

      def resolved_customer_id
        @customer_id.presence || website.try(:customer_id)
      end

      def category_label(category)
        I18n.t("website.skeletons.categories.#{category}")
      end

      def page_role_label(role, title: nil)
        i18n_key = "website.platform.skeletons.pages.#{role}"
        role.present? && I18n.exists?(i18n_key) ? I18n.t(i18n_key) : title.presence || I18n.t("website_settings.starter.page")
      end

      private

      def skeleton_rows
        return Array(@skeletons) unless @skeletons.nil?

        rows = Websites::Catalog.skeletons
        rows.presence || Websites::Skeletons.keys
      end

      def entry_for(item)
        key = extract_key(item)
        return if key.blank? || !Websites::Skeletons.known?(key)

        raw_pages = raw_pages_for(item, key)
        {
          key: key,
          name: name_for(item, key),
          description: description_for(item, key),
          pages: page_labels(raw_pages),
          home_sections: Websites::Skeletons.home_sections(key, raw_pages, limit: CatalogThumbnailComponent::SECTION_LIMIT),
          category: Websites::Skeletons.category_for(key)
        }
      end

      def extract_key(item)
        if item.respond_to?(:key) && !item.is_a?(String) && !item.is_a?(Symbol)
          item.key.to_s.presence
        elsif item.respond_to?(:to_h) && !item.is_a?(String)
          hash = item.to_h
          (hash[:key] || hash["key"]).to_s.presence
        else
          item.to_s.presence
        end
      end

      def name_for(item, key)
        return item.display_name if item.respond_to?(:display_name)

        i18n_key = "website.skeletons.#{key}.name"
        return I18n.t(i18n_key) if I18n.exists?(i18n_key)
        return item.name if item.respond_to?(:name) && item.name.present?

        I18n.t("website_settings.starter.unnamed")
      end

      def description_for(item, key)
        return item.display_description if item.respond_to?(:display_description)

        i18n_key = "website.skeletons.#{key}.description"
        return I18n.t(i18n_key) if I18n.exists?(i18n_key)
        return item.description.to_s if item.respond_to?(:description)

        ""
      end

      def raw_pages_for(item, key)
        raw = if item.respond_to?(:page_list)
          item.page_list
        elsif item.respond_to?(:pages)
          Array(item.pages)
        elsif item.respond_to?(:to_h) && !item.is_a?(String)
          Array(item.to_h.stringify_keys["pages"])
        else
          []
        end
        raw.presence || Websites::Skeletons.pages_for(key)
      end

      def page_labels(raw)
        Array(raw).filter_map { |page|
          hash = page.respond_to?(:stringify_keys) ? page.stringify_keys : {}
          page_role_label(hash["role"], title: hash["title"])
        }
      end
    end
  end
end
