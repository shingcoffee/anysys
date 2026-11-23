# frozen_string_literal: true

require "reform/form"

module Billing
  module Catalog
    class UpdateCountableItems
      class Form < Reform::Form
        property :items, virtual: true
        validate :valid_items

        private

        def valid_items
          Array(items).each do |raw|
            attrs = raw.to_h.stringify_keys
            item = CountableItem.find_by(id: attrs["id"])
            invalid = !item || attrs["label"].blank? || !attrs["position"].to_s.match?(/\A\d+\z/) ||
              !%w[total monthly].include?(attrs["period"])
            invalid ||= Countable::Registry.keys.include?(item&.key) && attrs["period"] != "total"
            errors.add(:items, I18n.t("admin_settings.errors.validations.countable_item_invalid")) if invalid
          end
          fallback = Entitlements.fallback
          if Array(items).any? { |raw| ::ActiveModel::Type::Boolean.new.cast(raw.to_h.stringify_keys["enabled"]) } && fallback.reason
            errors.add(:items, I18n.t("admin_settings.errors.validations.free_limits_required"))
          end
        end
      end

      def self.call(items:)
        rows = items.respond_to?(:values) ? items.values : Array(items)
        ApplicationRecord.transaction do
          CountableItem.update_all("updated_at = updated_at")
          form = Form.new(OpenStruct.new)
          unless form.validate(items: rows)
            next Result.invalid(:validation_failed, form: form, errors: form.errors.messages)
          end
          rows.each do |raw|
            attrs = raw.to_h.stringify_keys.slice("id", "label", "enabled", "position", "description", "unit", "category", "period")
            CountableItem.find(attrs.delete("id")).update!(attrs)
          end
          Result.new(status: :saved, record: CountableItem.ordered, form: form)
        end
      end
    end
  end
end
