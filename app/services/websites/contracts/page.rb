# frozen_string_literal: true

require "reform/form"

module Websites
  module Contracts
    class Page < Reform::Form
      include ThemeKey

      SLUG_FORMAT = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
      SLUG_MAX = 64

      property :title
      property :slug
      property :published
      property :nav_visible
      property :home
      property :layout_key
      property :sections

      validates :title, presence: true
      validate :slug_rules
      validate :slug_uniqueness
      validate :shortcut_collision
      validate :sections_are_valid

      def initialize(model, validate_sections: true)
        @validate_sections = validate_sections
        super(model)
      end

      private

      def slug_rules
        value = slug.to_s
        if home_flag?
          return if value.blank?
        end

        if WebsitePage::RESERVED_SLUGS.include?(value)
          errors.add(:slug, I18n.t("website.errors.reserved_slug"))
          return
        end

        return if !home_flag? && value.match?(SLUG_FORMAT) && value.length <= SLUG_MAX
        return if home_flag? && value.blank?

        errors.add(:slug, :invalid)
      end

      def slug_uniqueness
        return if model.website_id.blank?
        value = slug.to_s
        return if home_flag? && value.blank?
        return if value.blank?

        scope = WebsitePage.where(website_id: model.website_id, slug: value)
        scope = scope.where.not(id: model.id) if model.persisted?
        errors.add(:slug, I18n.t("website.errors.slug_taken")) if scope.exists?
      end

      def sections_are_valid
        return unless @validate_sections
        return if sections.nil?
        unless sections.is_a?(Array)
          errors.add(:sections, I18n.t("website.errors.unknown_section"))
          return
        end

        sections.each do |raw|
          item = raw.to_h.stringify_keys
          form = Section.new(OpenStruct.new(id: item["id"], type: item["type"], props: item["props"] || {}))
          next if form.validate("id" => item["id"], "type" => item["type"], "props" => item["props"] || {})

          form.errors.full_messages.each { |message| errors.add(:sections, message) }
        end
      end

      def shortcut_collision
        return if home_flag? || model.customer_id.blank?
        return unless PageShortcuts::Collisions.website_slug_taken?(
          slug: slug.to_s, customer_id: model.customer_id, page_id: model.id
        )

        errors.add(:slug, I18n.t("page_shortcuts.errors.shortcut_slug_taken"))
      end

      def home_flag?
        ::ActiveModel::Type::Boolean.new.cast(home)
      end
    end
  end
end
