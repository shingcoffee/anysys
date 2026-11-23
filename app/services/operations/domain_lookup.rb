# frozen_string_literal: true

module Operations
  # Finds the tenant domain an operation names, or the violation to return.
  module DomainLookup
    private

    def named_domain(name)
      EntityDomain.find_by_name(context.customer.id, name.to_s.strip)
    end

    def domain_violation(name)
      return if named_domain(name)

      Violation.new(pointer: "/domain", code: "entity_domain.not_found", details: { "name" => name.to_s.strip })
    end
  end
end
