# frozen_string_literal: true

# A domain: the entities and journeys of one sub-system (e.g. Course,
# Student, Course Offering, their bridges and the enrollment journey) inside
# one customer. Every customer-owned entity is created into a domain.
# Managed by hand by the platform owner only (EntityDomainVisibility); tenant
# admins create domains through the assistant's create_domain operation.
class EntityDomain < ApplicationRecord
  COLORS = %w[slate blue green amber rose purple teal].freeze

  belongs_to :customer
  has_many :memberships, class_name: "EntityDomainMembership", dependent: :delete_all, inverse_of: :entity_domain
  has_many :journeys, dependent: :destroy

  scope :for_customer, ->(customer_id) { where(customer_id: customer_id) }
  scope :by_name, -> { order(Arel.sql("LOWER(entity_domains.name)"), :id) }

  def self.find_by_name(customer_id, name)
    for_customer(customer_id).find_by("LOWER(name) = ?", name.to_s.strip.downcase)
  end
end
