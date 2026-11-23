# frozen_string_literal: true

module FeatureModules
  module Authentication
    # Deprovisioner
    #
    # Deactivates authentication for a customer when the module is disabled.
    # Does NOT destroy users — just marks them inactive so they cannot sign in.
    # Re-enabling the module will reactivate them.
    #
    class Deprovisioner
      def self.call(customer)
        ::Authentication::User.where(customer_id: customer.id, status: :active)
              .update_all(status: :inactive)
      end
    end
  end
end
