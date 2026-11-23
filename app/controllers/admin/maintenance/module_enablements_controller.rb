# frozen_string_literal: true

module Admin
  module Maintenance
    class ModuleEnablementsController < ApplicationController
      dashboard_menu_item :maintenance

      def create
        feature_module = FeatureModules::Module.find_by_param!(params[:module_id])

        unless feature_module.active?
          redirect_to admin_maintenance_modules_path(current_customer_id),
                      alert: t("maint_core.flash.module_enablements.not_available", name: feature_module.display_name)
          return
        end

        customer_feature = FeatureModules::CustomerAssignment.find_or_initialize_by(
          customer: current_customer,
          feature_module: feature_module
        )
        customer_feature.assign_attributes(
          status: :active,
          enabled_at: Time.current,
          configuration: customer_feature.configuration.presence || {}.to_json
        )

        ActiveRecord::Base.transaction do
          feature_module.registration_class.provision!(current_customer)
          customer_feature.save!
        end

        redirect_to admin_maintenance_modules_path(current_customer_id),
                    notice: t("maint_core.flash.module_enablements.enabled", name: feature_module.display_name)
      rescue StandardError => e
        Rails.logger.warn("[module_enablements] enable failed: #{e.class}: #{e.message}")
        redirect_to admin_maintenance_modules_path(current_customer_id),
                    alert: t("maint_core.flash.module_enablements.enable_failed")
      end

      def destroy
        feature_module = FeatureModules::Module.find_by_param!(params[:module_id])

        if feature_module.required?
          redirect_to admin_maintenance_modules_path(current_customer_id),
                      alert: t("maint_core.flash.module_enablements.required_module", name: feature_module.display_name)
          return
        end

        customer_feature = FeatureModules::CustomerAssignment.find_by!(
          customer_id: current_customer_id,
          feature_module_id: feature_module.id
        )

        ActiveRecord::Base.transaction do
          customer_feature.update!(status: :suspended)
          feature_module.registration_class.deprovision!(current_customer)
        end

        redirect_to admin_maintenance_modules_path(current_customer_id),
                    notice: t("maint_core.flash.module_enablements.disabled", name: feature_module.display_name)
      rescue StandardError => e
        Rails.logger.warn("[module_enablements] disable failed: #{e.class}: #{e.message}")
        redirect_to admin_maintenance_modules_path(current_customer_id),
                    alert: t("maint_core.flash.module_enablements.disable_failed")
      end
    end
  end
end
