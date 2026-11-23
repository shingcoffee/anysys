# frozen_string_literal: true

class FlowchartSequence < ApplicationRecord
  include TenantScoped

  validates :customer_id, :name, :period, presence: true
  validates :last_value, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
