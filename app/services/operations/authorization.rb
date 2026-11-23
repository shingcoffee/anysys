# frozen_string_literal: true

module Operations
  module Authorization
    module_function

    # Mirrors AiAssistant::Assistant::ExecutionPolicy#authorized_user?.
    # Members are always refused.
    def allowed?(actor:, customer:)
      return false unless actor&.active?
      return true if actor.platform_owner?

      actor.admin? && customer && actor.customer_id == customer.id
    end
  end
end
