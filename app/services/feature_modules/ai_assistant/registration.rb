# frozen_string_literal: true

module FeatureModules
  module AiAssistant
    class Registration < FeatureModules::BaseModule
      def self.module_key         = "ai_assistant"
      def self.module_name        = "AI Assistant"
      def self.module_description = "Admin AI assistant with typed chat and optional speech-to-text dictation."

      def self.provision!(_customer)   = nil
      def self.deprovision!(_customer) = nil

      # Per-tenant config surfaced by the generic Settings / AI Assistant page.
      # Keep descriptions and option labels out of the schema — it is serialized
      # to JSON at boot, so an I18n.t here would freeze at the boot locale.
      def self.configuration_schema
        {
          "language" => {
            "type" => "select",
            "options" => %w[auto en zh-CN],
            "default" => "auto"
          },
          "max_duration_seconds" => {
            "type" => "number",
            "default" => 60
          }
        }
      end

      def self.configuration_keys
        %i[language max_duration_seconds]
      end

      def self.owner_managed_configuration_keys = %i[max_duration_seconds]

      entry_path { |customer| "/#{customer.id}/admin/assistant" }
      default_exit kind: "route", name: "customer_home"

      def self.sidebar_contributions(_controller)
        {
          entries: [],
          settings: [
            ModuleContribution.new(
              label: I18n.t("feature_modules.ai_assistant.settings.status"),
              entry_key: "status",
              path: ->(cid) { "/#{cid}/admin/settings/modules/ai_assistant" }
            )
          ]
        }
      end
    end
  end
end
