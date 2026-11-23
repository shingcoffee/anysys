# frozen_string_literal: true

module Admin
  module Dashboard
    # One enabled-module card. The default variant is the compact card used on
    # Admin Home; the :rich variant powers the Modules hub with a full quick
    # link list for module records.
    class ModuleCardComponent < ApplicationComponent
      include Admin::Maintenance::Platform::ModuleSettingsHelper

      Link = Struct.new(:label, :href, keyword_init: true)

      attr_reader :key, :name, :description, :primary, :secondaries, :links, :variant

      def initialize(key:, name:, description:, primary: nil, secondaries: [],
                     links: nil, variant: :default)
        @key = key
        @name = name
        @description = description
        @primary = primary
        @secondaries = Array(secondaries)
        @links = links
        @variant = variant.to_sym
      end

      def rich?
        variant == :rich
      end

      def module_icon_path
        Admin::Maintenance::Platform::ModuleSettingsHelper::MODULE_ICON_PATHS.fetch(
          key.to_s,
          Admin::Maintenance::Platform::ModuleSettingsHelper::DEFAULT_MODULE_ICON_PATH
        )
      end

      def icon_well_classes
        module_color_classes(key)
      end

      def show_footer?
        primary_link.present? || secondary_links.any?
      end

      def primary_link
        coerce_link(primary)
      end

      def secondary_links
        secondaries.filter_map { |link| coerce_link(link) }
      end

      def quick_links
        source = links.presence || [primary, *Array(secondaries)]
        all = source.filter_map { |link| coerce_link(link) }
        all.uniq(&:href)
      end

      private

      def coerce_link(link)
        return if link.nil?

        label = read_attr(link, :label)
        href = read_attr(link, :href)
        return if href.blank?

        Link.new(label: label, href: href)
      end

      def read_attr(obj, name)
        return if obj.nil?
        return obj[name] || obj[name.to_s] if obj.is_a?(Hash)

        obj.public_send(name) if obj.respond_to?(name)
      end
    end
  end
end
