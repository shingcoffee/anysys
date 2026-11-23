# frozen_string_literal: true

module Websites
  module Contracts
    # Pinned named theme on a page, layout or skeleton: blank (inherit /
    # paired default) or a registered preset key.
    module ThemeKey
      def self.included(base)
        base.class_eval do
          property :theme_key
          validate :theme_key_known
        end
      end

      private

      def theme_key_known
        return if theme_key.blank? || Websites::ThemePresets.known?(theme_key)

        errors.add(:theme_key, :inclusion)
      end
    end
  end
end
