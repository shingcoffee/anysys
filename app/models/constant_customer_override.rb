# frozen_string_literal: true

# Per-customer options payload for a shared constant. Constants are not
# versioned; this table is the override store. One row per (constant, customer);
# absence means the customer follows the shared constant's options.
class ConstantCustomerOverride < ApplicationRecord
  belongs_to :constant

  validates :customer_id, presence: true, uniqueness: { scope: :constant_id }
  validates :options, presence: true
end
