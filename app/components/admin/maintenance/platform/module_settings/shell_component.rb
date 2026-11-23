# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module ModuleSettings
        # Chrome shared by every platform surface of one feature module: the
        # canonical admin page header (breadcrumbs, identity, actions) plus the
        # section nav. Built on AdminPageComponent so a module page is
        # indistinguishable in layout from any other admin page — only the
        # identity tile and status badge are module-specific.
        class ShellComponent < ApplicationComponent
          def initialize(feature_module:, customer_id:, current:, health: nil, actions: [])
            @feature_module = feature_module
            @customer_id = customer_id
            @current = current.to_sym
            @health = health
            @actions = Array(actions).compact
          end

          attr_reader :feature_module, :customer_id, :current, :health, :actions

          def breadcrumbs
            [
              {
                label: I18n.t("maint_platform.module_settings.breadcrumbs.maintenance"),
                path: helpers.admin_maintenance_path(customer_id)
              },
              {
                label: I18n.t("maint_platform.module_settings.breadcrumbs.module_settings"),
                path: helpers.admin_maintenance_platform_module_settings_path(customer_id)
              },
              { label: feature_module.display_name }
            ]
          end

          def badges
            list = [
              {
                label: I18n.t("maint_platform.module_settings.workspace.status.#{status}"),
                variant: status_variant
              }
            ]
            if health.present?
              list << {
                label: health.fetch(:label),
                variant: health_variant,
                data: { module_settings_health: health_status }
              }
            end
            list
          end

          def status
            return :mandatory if feature_module.mandatory?
            return :required if feature_module.required?

            feature_module.active? ? :active : :inactive
          end

          def status_variant
            { mandatory: :primary, required: :warning, active: :success, inactive: :default }.fetch(status)
          end

          def health_status
            health&.fetch(:status, :default)&.to_sym
          end

          def health_variant
            { success: :success, warning: :warning, danger: :danger, error: :danger }.fetch(health_status, :default)
          end

          def icon_path
            Admin::Maintenance::Platform::ModuleSettingsHelper::MODULE_ICON_PATHS.fetch(
              feature_module.key.to_s,
              Admin::Maintenance::Platform::ModuleSettingsHelper::DEFAULT_MODULE_ICON_PATH
            )
          end

          def icon_class
            helpers.module_color_classes(feature_module.key)
          end
        end
      end
    end
  end
end
