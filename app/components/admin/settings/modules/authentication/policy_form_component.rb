# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Authentication
        class PolicyFormComponent < ApplicationComponent
          def initialize(policy:, enabled:, customer:)
            @policy, @enabled, @customer = policy, enabled, customer
          end

          attr_reader :policy, :enabled, :customer

          def form_url
            if policy == :registration
              helpers.admin_settings_modules_authentication_sign_up_path(customer.id)
            else
              helpers.admin_settings_modules_authentication_forget_password_path(customer.id)
            end
          end
        end
      end
    end
  end
end
