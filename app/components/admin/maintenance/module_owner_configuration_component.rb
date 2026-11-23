# frozen_string_literal: true

module Admin
  module Maintenance
    class ModuleOwnerConfigurationComponent < ApplicationComponent
      attr_reader :customer_id, :feature_module, :assignment

      def initialize(customer_id:, feature_module:, assignment:)
        @customer_id, @feature_module, @assignment = customer_id, feature_module, assignment
      end

      def fields
        keys = Array(feature_module.registration_class.try(:owner_managed_configuration_keys)).map(&:to_s)
        feature_module.configuration_schema_json.to_h.slice(*keys)
      end

      def field_label(key)
        I18n.t("settings_modules.configuration.fields.#{feature_module.key}.#{key}",
               default: I18n.t("admin_misc.module_config.fields.#{feature_module.key}.#{key}",
                               default: I18n.t("settings_modules.configuration.field_fallback", number: 1)))
      end

      def field_value(key, definition)
        assignment.configuration_json.fetch(key, definition["default"])
      end
    end
  end
end
