# frozen_string_literal: true

require "reform/form"

module Websites
  module Contracts
    class Skeleton < Reform::Form
      Input = Struct.new(:pages, :theme_key)
      PAGE_KEYS = %w[title slug home nav_visible role layout_key sections].freeze

      include ThemeKey

      property :pages
      validate :page_list_is_valid

      private

      def page_list_is_valid
        unless pages.is_a?(Array) && pages.any? && pages.all? { |page| page.is_a?(Hash) }
          return errors.add(:pages, I18n.t("website.errors.invalid_sections"))
        end

        list = pages.map(&:deep_stringify_keys)
        errors.add(:pages, I18n.t("website.errors.home_required")) unless list.count { |page| page["home"] == true } == 1
        slugs = []
        list.each do |page|
          validate_identity(page)
          slug = page["slug"]
          errors.add(:pages, I18n.t("website.errors.slug_taken")) if slugs.include?(slug)
          slugs << slug

          form = Sections.new(Sections::Input.new(page["sections"]))
          unless form.validate({})
            form.errors.full_messages.each { |message| errors.add(:pages, message) }
          end
        end
      end

      def validate_identity(page)
        if (page.keys - PAGE_KEYS).any? || !page["title"].is_a?(String) || page["title"].blank? ||
            ![true, false].include?(page["home"]) ||
            (page.key?("nav_visible") && ![true, false].include?(page["nav_visible"])) ||
            (page.key?("role") && !page["role"].is_a?(String))
          errors.add(:pages, I18n.t("website.errors.invalid_sections"))
        end

        slug = page["slug"]
        valid_slug = slug.is_a?(String) && if page["home"] == true
          slug.empty?
        else
          Page::SLUG_FORMAT.match?(slug) && slug.length <= Page::SLUG_MAX && !WebsitePage::RESERVED_SLUGS.include?(slug)
        end
        errors.add(:pages, I18n.t("website.errors.reserved_slug")) unless valid_slug
        unless page["layout_key"].is_a?(String) && Catalog.known_layout?(page["layout_key"])
          errors.add(:pages, I18n.t("website.errors.unknown_layout"))
        end
      end
    end
  end
end
