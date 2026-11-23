# frozen_string_literal: true

module Admin
  module Maintenance
    class ModuleOwnerConfigurationsController < ApplicationController
      dashboard_menu_item :maintenance
      before_action :require_platform_owner!

      def update
        feature_module = FeatureModules::Module.find_by_param!(params[:module_id])
        raise ActiveRecord::RecordNotFound unless feature_module.active?
        assignment = FeatureModules::CustomerAssignment.enabled.find_by!(
          customer: current_customer, feature_module: feature_module
        )
        keys = Array(feature_module.registration_class.try(:owner_managed_configuration_keys)).map(&:to_s)
        raw = params[:configuration]
        raise ArgumentError unless raw.is_a?(ActionController::Parameters)

        updates = raw.permit(*keys).to_h
        raise ArgumentError if updates.empty?

        updates.each do |key, value|
          minimum = key == "max_duration_seconds" ? 1 : 0
          raise ArgumentError unless value.is_a?(String) && value.match?(/\A\d+\z/) &&
                                     Integer(value, 10).between?(minimum, 2_147_483_647)
        end

        assignment.merge_configuration!(updates)
        redirect_to admin_maintenance_modules_path(current_customer_id),
                    notice: t("maint_core.flash.module_owner_configurations.updated")
      rescue ArgumentError
        redirect_to admin_maintenance_modules_path(current_customer_id),
                    alert: t("maint_core.flash.module_owner_configurations.invalid")
      end

      private

      def require_platform_owner!
        head :forbidden unless current_user&.platform_owner?
      end
    end
  end
end
