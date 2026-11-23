# frozen_string_literal: true

require "reform/form"

module AiAssistant
  module Contracts
    # Generic platform-settings contract. Every provider has api_key plus the
    # two exclusive job flags. Vendor-specific config keys are validated
    # against the provider's declared fields. All messages are I18n (en + zh-CN).
    class ProviderSettings < Reform::Form
      property :provider
      property :api_key
      property :transcribe_active
      property :generation_active
      property :config

      validate :api_key_present
      validate :required_config_fields_present
      validate :supported_jobs

      private

      def api_key_present
        return if api_key.to_s.strip.present?

        errors.add(:base, I18n.t("ai_assistant.platform_settings.errors.api_key_blank"))
      end

      def required_config_fields_present
        provider_class = AiAssistant::Providers.for(provider)
        cfg = parsed_config
        provider_class.config_fields.each do |field|
          next unless field[:required]

          name = field[:name].to_s
          next if field[:default].present? && cfg[name].to_s.empty?
          next unless cfg[name].to_s.empty?

          errors.add(:base, I18n.t("ai_assistant.platform_settings.errors.field_blank",
                                   field: provider_class.field_label(field)))
        end
      rescue ArgumentError
        errors.add(:base, I18n.t("ai_assistant.platform_settings.errors.unknown_provider"))
      end

      def supported_jobs
        provider_class = AiAssistant::Providers.for(provider)
        if truthy?(transcribe_active) && !provider_class.supports_transcribe?
          errors.add(:base, I18n.t("ai_assistant.platform_settings.errors.transcribe_unsupported"))
        end
        if truthy?(generation_active) && !provider_class.supports_generation?
          errors.add(:base, I18n.t("ai_assistant.platform_settings.errors.generation_unsupported"))
        end
      rescue ArgumentError
        # required_config_fields_present already records unknown_provider.
      end

      def truthy?(value)
        ::ActiveModel::Type::Boolean.new.cast(value)
      end

      def parsed_config
        config.is_a?(String) ? JSON.parse(config) : config.to_h
      rescue JSON::ParserError
        {}
      end
    end
  end
end
