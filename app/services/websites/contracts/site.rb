# frozen_string_literal: true

require "reform/form"

module Websites
  module Contracts
    class Site < Reform::Form
      property :name
      property :tagline
      property :published
      property :skeleton_key
      property :theme
      property :seo
      property :footer

      validates :name, presence: true
      validate :skeleton_is_known
      validate :theme_tokens_allowed
      validate :footer_hrefs_valid

      private

      def skeleton_is_known
        return if Websites::Skeletons.known?(skeleton_key)

        errors.add(:skeleton_key, I18n.t("website.errors.unknown_skeleton"))
      end

      def theme_tokens_allowed
        hash = theme_hash
        return if hash.blank?

        invalid = Websites::Theme::OPTIONS.any? { |token, values| !allowed?(hash[token], values) }
        invalid ||= !allowed?(hash["preset"], Websites::ThemePresets.keys)
        errors.add(:theme, :inclusion) if invalid
      end

      def footer_hrefs_valid
        columns = footer_hash["columns"]
        Array(columns).each do |column|
          Array(column.to_h.stringify_keys["links"]).each do |link|
            url = link.to_h.stringify_keys["url"]
            next if Websites::Href.valid?(url)

            errors.add(:footer, Websites::Href.error_message(url))
          end
        end
      end

      def allowed?(value, set)
        value.blank? || set.include?(value.to_s)
      end

      def theme_hash
        (theme || {}).to_h.stringify_keys
      end

      def footer_hash
        (footer || {}).to_h.stringify_keys
      end
    end
  end
end
