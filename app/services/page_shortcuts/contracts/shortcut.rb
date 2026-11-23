# frozen_string_literal: true

require "reform/form"

module PageShortcuts
  module Contracts
    class Shortcut < Reform::Form
      property :path
      property :target_type
      property :target_id

      validate :path_rules
      validate :target_rules
      validate :path_uniqueness
      validate :automatic_collision

      private

      def path_rules
        normalized = PathPolicy.normalize(path)
        if normalized.nil?
          errors.add(:path, I18n.t("page_shortcuts.errors.invalid_path"))
        elsif PathPolicy.reserved?(normalized)
          errors.add(:path, I18n.t("page_shortcuts.errors.reserved_path"))
        else
          self.path = normalized
        end
      end

      def target_rules
        return if TargetEligibility.resolve(type: target_type, id: target_id, customer_id: model.customer_id)

        errors.add(:target, I18n.t("page_shortcuts.errors.unavailable_target"))
      end

      def path_uniqueness
        return if errors[:path].present?

        scope = PageShortcut.for_customer(model.customer_id).where(path: path)
        scope = scope.where.not(id: model.id) if model.persisted?
        errors.add(:path, I18n.t("page_shortcuts.errors.path_taken")) if scope.exists?
      end

      def automatic_collision
        return if errors[:path].present?
        return unless Collisions.shortcut_conflict?(path: path, customer_id: model.customer_id,
                                                   target_type: target_type, target_id: target_id)

        errors.add(:path, I18n.t("page_shortcuts.errors.website_path_taken"))
      end
    end
  end
end
