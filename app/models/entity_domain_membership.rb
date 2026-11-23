# frozen_string_literal: true

# Places one entity in one EntityDomain for one customer. The unique
# (customer_id, entity_id) index makes an entity belong to at most one
# domain per customer.
class EntityDomainMembership < ApplicationRecord
  belongs_to :customer
  belongs_to :entity_domain, inverse_of: :memberships
  belongs_to :entity

  scope :for_customer, ->(customer_id) { where(customer_id: customer_id) }
end
