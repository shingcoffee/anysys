# frozen_string_literal: true

module Billing
  class CountableItem < ApplicationRecord
    self.table_name = "billing_countable_items"

    validates :key,    presence: true, uniqueness: true
    validates :label,  presence: true
    validates :period, inclusion: { in: %w[total monthly] }

    scope :enabled,      -> { where(enabled: true) }
    scope :ordered,      -> { order(:position, :key) }
    scope :by_category,  -> { order(:category, :position, :key) }

    # Disabled historical keys have no authoritative meter, not zero usage.
    def usage_for(customer) = Billing::Countable::Registry.find(key)&.count_for(customer)
  end
end
