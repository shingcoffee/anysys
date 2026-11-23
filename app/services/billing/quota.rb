# frozen_string_literal: true

module Billing
  class Quota
    PLATFORM_OWNER_CUSTOMER_ID = Authentication::User::PLATFORM_CUSTOMER_ID
    def self.for(customer) = new(customer)
    def initialize(customer) = (@customer = customer)
    def entitlements = Entitlements.for(customer: @customer)
    def plan = Plan.find_by(id: entitlements.plan_snapshot["plan_id"])
    def limit(item_key) = entitlements.limits.fetch(item_key.to_s, 0)
    def usage(item_key) = Countable::Registry.count_for(item_key, @customer)
    def unlimited?(item_key) = limit(item_key) == PlanLimit::UNLIMITED

    def remaining(item_key)
      return Float::INFINITY if unlimited?(item_key)
      [limit(item_key) - usage(item_key), 0].max
    end

    def allow?(item_key, by: 1)
      raise ArgumentError, "Capacity increment must be nonnegative" unless by.is_a?(Integer) && by >= 0
      unlimited?(item_key) || usage(item_key) + by <= limit(item_key)
    end
  end
end
