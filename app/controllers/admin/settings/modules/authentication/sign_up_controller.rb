# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Authentication
        # Single-toggle settings page for the customer-scoped self-sign-up
        # surface. Reads/writes the `allow_registration` key on the existing
        # `customer_feature_modules.configuration` JSON blob; the gating in
        # the public Devise controllers consumes the same key via
        # `Authentication::Settings#signup_enabled?`.
        class SignUpController < ApplicationController
          dashboard_menu_item :settings
          before_action :load_assignment

          CONFIG_KEY = "allow_registration"

          def show
            @enabled = ::Authentication::Settings.for(current_customer.id).signup_enabled?
          end

          def update
            new_value = ActiveModel::Type::Boolean.new.cast(params.dig(:setting, :enabled))
            @assignment.merge_configuration!(CONFIG_KEY => new_value)
            redirect_to admin_settings_modules_authentication_sign_up_path(current_customer.id),
                        notice: t(new_value ? "admin_settings.flash.sign_up.enabled" : "admin_settings.flash.sign_up.disabled")
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
