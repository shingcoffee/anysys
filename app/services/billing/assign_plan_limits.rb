# frozen_string_literal: true

module Billing
  class AssignPlanLimits
    # Blank, "unlimited", and any negative integer are the unlimited sentinel.
    # A missing catalog row means the same thing; only an explicit finite number caps usage.
    def self.allowed_key?(key)
      key = key.to_s
      Countable::Registry.keys.include?(key) || CountableItem.exists?(key: key)
    end

    def self.valid?(raw)
      return true if raw.blank?
      text = raw.to_s.strip
      text.casecmp("unlimited").zero? || text.match?(/\A-?\d+\z/)
    end

    def self.parse(raw)
      raise ArgumentError, "Invalid plan limit" unless valid?(raw)
      text = raw.to_s.strip
      return PlanLimit::UNLIMITED if raw.blank? || text.casecmp("unlimited").zero?

      value = Integer(text, 10)
      value.negative? ? PlanLimit::UNLIMITED : value
    end

    # Only validated values; SavePlan owns the surrounding transaction.
    def self.call(plan:, limits:)
      limits.each do |key, value|
        raise ArgumentError, "Unsupported countable item" unless allowed_key?(key)
        record = plan.plan_limits.find_or_initialize_by(item_key: key.to_s)
        record.update!(limit_value: parse(value))
      end
      plan.plan_limits.reset
      plan
    end
  end
end
