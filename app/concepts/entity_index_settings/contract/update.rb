# frozen_string_literal: true

module EntityIndexSettings
  module Contract
    class Update < Reform::Form
      MAX_VISIBLE_KEYS = 50

      property :visible_column_keys, virtual: true

      attr_accessor :allowed_slugs

      validate :visible_column_keys_shape

      def visible_column_keys_shape
        keys = Array(visible_column_keys).map(&:to_s).reject(&:blank?)
        if keys.size > MAX_VISIBLE_KEYS
          errors.add(:base, I18n.t("admin_misc.entities.index_setting.errors.too_many"))
        end

        return if allowed_slugs.nil?

        unknown = keys - Array(allowed_slugs).map(&:to_s)
        return if unknown.empty?

        errors.add(:base, I18n.t("admin_misc.entities.index_setting.errors.invalid_keys"))
      end
    end
  end
end
