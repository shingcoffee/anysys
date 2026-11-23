# frozen_string_literal: true

class FieldTemplate < ApplicationRecord
  validates :customer_id, presence: true
  validates :name, presence: true, length: { maximum: 100 }
  validates :category, length: { maximum: 50 }, allow_blank: true
  validates :configuration, presence: true

  scope :for_customer, ->(customer_id) { where(customer_id: customer_id) }
  scope :custom, -> { where(built_in: false) }
  scope :built_in, -> { where(built_in: true) }
end
