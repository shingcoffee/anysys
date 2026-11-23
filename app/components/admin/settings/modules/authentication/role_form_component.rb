# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Authentication
        class RoleFormComponent < ViewComponent::Base
          def initialize(role:, customer:)
            @role = role
            @customer = customer
          end

          attr_reader :role, :customer

          def submit_label = role.persisted? ? I18n.t("comp_admin.role_form.update_role") : I18n.t("comp_admin.role_form.create_role")
          def form_url
            if role.persisted?
              helpers.admin_settings_modules_authentication_role_path(customer.id, role)
            else
              helpers.admin_settings_modules_authentication_roles_path(customer.id)
            end
          end
        end
      end
    end
  end
end
