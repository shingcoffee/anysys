# frozen_string_literal: true

module Admin
  module Maintenance
    class ModuleSubTogglesController < ApplicationController
      dashboard_menu_item :maintenance

      def update
        feature_module = FeatureModules::Module.find_by_param!(params[:module_id])
        key = params[:key].to_s

        unless boolean_configuration_key?(feature_module, key)
          redirect_to admin_maintenance_modules_path(current_customer_id),
                      alert: t("maint_core.flash.module_sub_toggles.invalid_key")
          return
        end

        cfm = FeatureModules::CustomerAssignment.find_by!(
          customer: current_customer,
          feature_module: feature_module
        )
        cfm.merge_configuration!(key => params[:enabled] == "1")

        redirect_to admin_maintenance_modules_path(current_customer_id),
                    notice: t("maint_core.flash.module_sub_toggles.updated")
      end

      private

      # This endpoint always writes a boolean. configuration_keys also lists
      # numbers/selects (daily_send_cap, language, …) owned by the Settings
      # form — those must not be clobbered with true/false.
      def boolean_configuration_key?(feature_module, key)
        registration = feature_module.registration_class
        allowed = Array(registration.try(:configuration_keys)).map(&:to_s)
        return false unless allowed.include?(key)

        field = (registration.try(:configuration_schema) || {})[key]
        field.is_a?(Hash) && field["type"].to_s == "boolean"
      end
    end
  end
end
