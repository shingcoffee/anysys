# frozen_string_literal: true

module Billing
  module Countable
    # Idempotently ensures a Billing::CountableItem row exists for every registry key.
    # Seeds metadata defaults (label, description, unit, category, period) only when blank.
    # Returns the ordered items.
    module CatalogSync
      module_function

      def call
        Billing::Countable::Registry.all.each_with_index do |defn, i|
          item = Billing::CountableItem.find_or_initialize_by(key: defn.key)
          item.label       = defn.default_label       if item.label.blank?
          item.description = defn.default_description if item.description.blank?
          item.unit        = defn.default_unit        if item.unit.blank?
          item.category    = defn.default_category    if item.category.blank?
          item.period      = defn.default_period      if item.new_record? || item.period.blank?
          item.position    = i                        if item.new_record?
          item.save!
        end
        Billing::CountableItem.ordered
      end
    end
  end
end
