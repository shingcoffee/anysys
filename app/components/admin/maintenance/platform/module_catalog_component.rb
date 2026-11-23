# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      # Platform-owner module directory: a toolbar (locate + status filter) over
      # a grid of module cards. Each card is one link to that module's workspace,
      # so the whole tile is the target rather than a small button in a corner.
      class ModuleCatalogComponent < ApplicationComponent
        def initialize(modules:, customer_id:)
          @modules = Array(modules)
          @customer_id = customer_id
        end

        attr_reader :modules, :customer_id

        def empty?
          modules.empty?
        end

        def total_count
          modules.size
        end

        def active_count
          modules.count { |fm| fm.active? }
        end

        def required_count
          modules.count { |fm| fm.required? }
        end

        def status_for(feature_module)
          return :mandatory if feature_module.mandatory?
          return :required if feature_module.required?

          feature_module.active? ? :active : :inactive
        end

        def status_variant(feature_module)
          { mandatory: :primary, required: :warning, active: :success, inactive: :default }
            .fetch(status_for(feature_module))
        end

        def status_label(feature_module)
          I18n.t("maint_platform.module_settings.workspace.status.#{status_for(feature_module)}")
        end

        def description_for(feature_module)
          return feature_module.description unless feature_module.key.to_s == "sms"

          feature_module.registration_class.module_description
        end

        # What an operator actually has to configure for this module — the one
        # fact that tells them whether opening it means picking a vendor or just
        # tuning defaults.
        def configuration_context_for(feature_module)
          if feature_module.key.to_s.in?(%w[captcha email payment sms ai_assistant])
            :provider
          elsif feature_module.configuration_schema_json.present?
            :defaults
          else
            :none
          end
        end

        def configuration_label(feature_module)
          I18n.t("maint_platform.module_settings.index.configuration_context.#{configuration_context_for(feature_module)}")
        end

        def stats_summary
          I18n.t("maint_platform.module_settings.index.stats_summary",
            total: total_count, active: active_count, required: required_count)
        end

        def show_path(feature_module)
          helpers.admin_maintenance_platform_module_setting_path(customer_id, feature_module)
        end

        def module_icon_path(key)
          Admin::Maintenance::Platform::ModuleSettingsHelper::MODULE_ICON_PATHS.fetch(
            key.to_s,
            Admin::Maintenance::Platform::ModuleSettingsHelper::DEFAULT_MODULE_ICON_PATH
          )
        end

        def module_color_classes(key)
          helpers.module_color_classes(key)
        end

        def filter_count(filter_id)
          case filter_id.to_s
          when "active"   then active_count
          when "inactive" then modules.count { |m| !m.active? }
          when "required" then required_count
          else                 total_count
          end
        end

        def filter_pills
          %w[all active inactive required].map do |id|
            {
              id: id,
              label: I18n.t("maint_platform.module_settings.index.filter_#{id}"),
              count: filter_count(id)
            }
          end
        end

        def pill_classes(pill)
          base = "inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 text-body-sm font-medium transition-colors"
          if pill[:id] == "all"
            "#{base} bg-surface text-text-primary shadow-sm ring-1 ring-border-subtle"
          else
            "#{base} text-text-muted hover:text-text-primary"
          end
        end

        def pill_count_classes(pill)
          base = "rounded-full px-1.5 py-0.5 text-2xs font-semibold tabular-nums"
          if pill[:id] == "all"
            "#{base} bg-surface-active text-text-secondary"
          else
            "#{base} bg-border-subtle/80 text-text-muted"
          end
        end
      end
    end
  end
end
