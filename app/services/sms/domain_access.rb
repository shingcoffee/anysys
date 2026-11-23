# frozen_string_literal: true

module Sms
  module DomainAccess
    module_function

    def actor_allowed?(customer, actor)
      return false unless customer&.persisted? && actor&.persisted?

      user = Authentication::User.find_by(id: actor.id)
      user&.active? && (user.platform_owner? || (user.admin? && user.customer_id == customer.id))
    end

    def scoped?(customer, record)
      customer&.persisted? && record&.persisted? && record.customer_id == customer.id
    end

    def failure(code, field: :base, errors: nil)
      Result.failure(code, errors: errors || { field => [I18n.t("sms_audience.errors.#{code}")] })
    end

    def attributes(input, allowed)
      return unless input.is_a?(Hash) && input.keys.all? { |key| key.is_a?(String) || key.is_a?(Symbol) }
      return if input.keys.map(&:to_s).uniq.size != input.size

      attrs = input.symbolize_keys
      attrs if (attrs.keys - allowed).empty?
    end

    def integer(value)
      return value if value.is_a?(Integer) && (0..(2**63 - 1)).cover?(value)
      return unless value.is_a?(String) && value.match?(/\A\d{1,19}\z/)

      parsed = Integer(value, 10)
      parsed if parsed <= 2**63 - 1
    end

    # Same customer-first boundary as final dispatch. The no-op write acquires
    # SQLite's reservation before reads; SELECT FOR UPDATE handles row-lock DBs.
    def synchronize(customer)
      Customer.transaction(requires_new: true) do
        Customer.where(id: customer.id).update_all("updated_at = updated_at")
        Customer.lock.find(customer.id)
        yield
      end
    end
  end
end
