# frozen_string_literal: true

module Admin
  module Modules
    module Payments
    # Shared base for payments admin controllers.
    #
    # Enforces:
    #   - Tenant context from the :customer_id route param.
    #   - Devise authentication (must be signed in).
    #   - Role gate: only admin or owner users of the current tenant are allowed.
    #
    # Subclasses inherit these before_actions automatically and can focus on
    # their resource-specific behaviour.
    class BaseController < ApplicationController
      dashboard_menu_item :modules

      before_action :require_payments_module!

      private

      def require_payments_module!
        return if FeatureModules::Module.enabled?(key: "payment", customer_id: current_customer.id)

        head :not_found
      end
    end
    end
  end
end
