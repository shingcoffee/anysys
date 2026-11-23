# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Authentication
        # Single-toggle settings page for the customer-scoped forgot-password
        # surface. Reads/writes the `allow_password_reset` key on the existing
        # `customer_feature_modules.configuration` JSON blob; the gating in
        # `Authentication::PasswordsController` consumes the same key via
        # `Authentication::Settings#password_reset_enabled?`.
        class ForgetPasswordController < ApplicationController
          dashboard_menu_item :settings
          before_action :load_assignment

          CONFIG_KEY = "allow_password_reset"

          def show
            @enabled = ::Authentication::Settings.for(current_customer.id).password_reset_enabled?
          end

          def update
            new_value = ActiveModel::Type::Boolean.new.cast(params.dig(:setting, :enabled).presence) || false
            @assignment.merge_configuration!(CONFIG_KEY => new_value)
            redirect_to admin_settings_modules_authentication_forget_password_path(current_customer.id),
                        notice: t(new_value ? "admin_settings.flash.forget_password.enabled" : "admin_settings.flash.forget_password.disabled")
          end

          private

          def load_assignment
            fm = FeatureModules::Module.find_by!(key: "authentication")
            @assignment = FeatureModules::CustomerAssignment.find_by!(
              customer_id: current_customer.id, feature_module_id: fm.id
            )
          end
        end
      end
    end
  end
end
