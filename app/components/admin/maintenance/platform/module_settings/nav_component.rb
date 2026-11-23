# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module ModuleSettings
        # Section nav for one platform module. Every section is a real path, so
        # nested per-module surfaces (credentials, templates, webhook events)
        # sit in the nav at the same level as the panes this module's own
        # controller renders — one flat, predictable row of destinations.
        class NavComponent < ApplicationComponent
          # The module-specific middle sections. Overview always leads and
          # Developer always closes; Configuration slots in between whenever the
          # module actually has platform defaults to edit (see #section_ids).
          MODULE_SECTIONS = {
            "captcha" => %i[providers resources],
            "email" => %i[providers],
            "payment" => %i[providers operations],
            "sms" => %i[providers resources],
            "ai_assistant" => %i[providers],
            "website" => %i[layouts skeletons]
          }.freeze

          # Nested surfaces render the shell with the vocabulary of their own
          # controller (`:vendor`, `:templates`, …); map those onto the section
          # they belong to so the right tab highlights.
          CURRENT_ID_ALIASES = {
            vendor: :providers,
            credentials: :providers,
            templates: :resources,
            pages: :resources,
            webhooks: :operations,
            advanced: :developer,
            skeletons: :skeletons,
            layouts: :layouts
          }.freeze

          def initialize(module_key:, current:, customer_id:)
            @module_key = module_key.to_s
            current_id = current.to_sym
            @current = CURRENT_ID_ALIASES.fetch(current_id, current_id)
            @customer_id = customer_id
          end

          attr_reader :module_key, :current, :customer_id

          def tabs
            @tabs ||= section_ids.filter_map { |id| tab_for(id) }
          end

          def label
            I18n.t("maint_platform.module_settings.show.nav.label")
          end

          private

          def section_ids
            middle = MODULE_SECTIONS.fetch(module_key, [])
            middle = [:configuration, *middle] if configurable?

            [:overview, *middle, :developer]
          end

          # Configuration only earns a tab when the module has platform defaults
          # or module-specific settings behind it; an empty tab is worse than no
          # tab.
          def configurable?
            return true if module_key == "authentication"

            feature_module&.configuration_schema_json.present?
          end

          def tab_for(id)
            path = path_for(id)
            return if path.blank?

            {
              id: id,
              label: I18n.t("maint_platform.module_settings.show.nav.#{id}"),
              path: path,
              active: current == id
            }
          end

          def path_for(id)
            case id
            when :overview      then pane_path(:overview)
            when :configuration then pane_path(:configuration)
            when :developer     then pane_path(:developer)
            when :providers     then providers_path
            when :resources     then resources_path
            when :operations    then operations_path
            when :skeletons     then skeletons_path
            when :layouts       then layouts_path
            end
          end

          def pane_path(pane)
            return unless feature_module

            case pane
            when :configuration
              helpers.configuration_admin_maintenance_platform_module_setting_path(customer_id, feature_module)
            when :developer
              helpers.developer_admin_maintenance_platform_module_setting_path(customer_id, feature_module)
            else
              helpers.admin_maintenance_platform_module_setting_path(customer_id, feature_module)
            end
          end

          def providers_path
            case module_key
            when "email"
              helpers.admin_maintenance_platform_module_settings_email_credentials_path(customer_id)
            when "sms"
              helpers.admin_maintenance_platform_module_settings_sms_credentials_path(customer_id)
            when "captcha"
              helpers.admin_maintenance_platform_module_settings_captcha_settings_path(customer_id)
            when "ai_assistant"
              helpers.admin_maintenance_platform_module_settings_ai_assistant_settings_path(customer_id)
            when "payment"
              helpers.admin_maintenance_platform_module_settings_payment_gateways_path(customer_id)
            end
          end

          def resources_path
            case module_key
            when "sms"
              helpers.admin_maintenance_platform_module_settings_sms_templates_path(customer_id)
            when "captcha"
              helpers.admin_maintenance_platform_module_settings_captcha_pages_path(customer_id)
            end
          end

          def operations_path
            return unless module_key == "payment"

            helpers.admin_maintenance_platform_module_settings_payment_webhook_events_path(customer_id)
          end

          def layouts_path
            return unless module_key == "website"

            helpers.admin_maintenance_platform_module_settings_website_layouts_path(customer_id)
          end

          def skeletons_path
            return unless module_key == "website"

            helpers.admin_maintenance_platform_module_settings_website_skeletons_path(customer_id)
          end

          def feature_module
            @feature_module ||= FeatureModules::Module.find_by(key: module_key)
          end
        end
      end
    end
  end
end
