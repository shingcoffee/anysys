# frozen_string_literal: true

# Per-customer head pointer for a shared entity: the current override version
# customer `customer_id` sees for `entity`. One row per (entity, customer);
# absence means the customer follows the entity's global default version.
class EntityCustomerHead < ApplicationRecord
  belongs_to :entity
  belongs_to :current_version, class_name: "EntityVersion"

  validates :customer_id, presence: true, uniqueness: { scope: :entity_id }
end
