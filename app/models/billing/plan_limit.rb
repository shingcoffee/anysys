# frozen_string_literal: true

module Billing
  class PlanLimit < ApplicationRecord
    self.table_name = "billing_plan_limits"

    belongs_to :plan, class_name: "Billing::Plan", foreign_key: :billing_plan_id

    validates :item_key,    presence: true, uniqueness: { scope: :billing_plan_id }
    validates :limit_value, numericality: { only_integer: true, greater_than_or_equal_to: -1 }

    UNLIMITED = -1

    def unlimited? = limit_value == UNLIMITED
  end
end
