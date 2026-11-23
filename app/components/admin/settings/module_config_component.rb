# frozen_string_literal: true

module Admin
  module Settings
    class ModuleConfigComponent < ApplicationComponent
      TASKS = {
        "ai_assistant" => "ai_assistant", "email" => "email_sending_limit",
        "sms" => "sms_sending_limit", "authentication" => "account_security",
        "captcha" => "public_page_protection", "payment" => "payment_providers"
      }.freeze

      attr_reader :customer_id, :feature_module, :assignment, :entry_key, :default_exit, :exit_override

      def initialize(customer_id:, feature_module:, assignment:, entry_key: nil, default_exit: nil, exit_override: nil)
        @customer_id, @feature_module, @assignment = customer_id, feature_module, assignment
        @entry_key, @default_exit, @exit_override = entry_key, default_exit, exit_override
      end

      def module_key
        key = feature_module.key.to_s
        TASKS.key?(key) ? key : key.singularize
      end
      def task = TASKS[module_key]

      def title
        return t("settings_navigation.items.#{task}") if task

        module_name = feature_module.display_name
        return module_name if entry_key.blank?

        t("feature_modules.#{module_key}.settings.#{entry_key}", default: module_name)
      end

      def description
        t("settings_modules.configuration.descriptions.#{module_key}", default: t("settings_modules.configuration.description"))
      end

      def schema = feature_module.configuration_schema_json || {}
      def owner_managed_field?(key)
        Array(feature_module.registration_class.try(:owner_managed_configuration_keys)).map(&:to_s).include?(key)
      end
      def editable_schema = schema.reject { |key, _| owner_managed_field?(key) }
      def owner_managed_schema = schema.select { |key, _| owner_managed_field?(key) }
      def active? = assignment&.active?
      def return_url_available? = active? && feature_module.handoff_enabled?
      def form_url = helpers.admin_module_config_path(customer_id, feature_module.key.pluralize)

      def field_value(key, definition)
        (assignment.configuration_json || {}).fetch(key, definition["default"])
      end

      def field_label(key, index)
        t("settings_modules.configuration.fields.#{module_key}.#{key}",
          default: t("admin_misc.module_config.fields.#{module_key}.#{key}",
            default: t("settings_modules.configuration.field_fallback", number: index + 1)))
      end

      def field_hint(key)
        t("settings_modules.configuration.hints.#{module_key}.#{key}", default: t("settings_modules.configuration.field_hint"))
      end

      def option_label(key, option, index)
        t("admin_misc.module_config.options.#{module_key}.#{key}.#{option}",
          default: t("settings_modules.configuration.options.#{module_key}.#{key}.#{option}",
            default: t("settings_modules.configuration.option_fallback", number: index + 1)))
      end

      def status_label
        return t("common.status.enabled") if active?
        return t("admin_misc.module_config.suspended") if assignment

        t("admin_misc.module_config.not_enabled")
      end

      def default_destination
        definition = (default_exit || {}).stringify_keys
        if definition["kind"] == "url" && definition["url"].present?
          definition["url"]
        elsif definition["name"] == "customer_home"
          t("settings_modules.configuration.home_destination")
        else
          t("settings_modules.configuration.default_destination")
        end
      end

      def return_description
        t("settings_modules.configuration.return_explanations.#{module_key}",
          default: t("settings_modules.configuration.return_description"))
      end

      def return_hint
        "#{t('settings_modules.configuration.return_hint')} #{t('settings_modules.configuration.default_return', destination: default_destination)}"
      end
    end
  end
end
