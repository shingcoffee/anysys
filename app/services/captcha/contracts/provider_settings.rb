# frozen_string_literal: true

require "reform/form"

module Captcha
  module Contracts
    # Generic platform-settings contract. Every provider has access_key_id /
    # access_key_secret / enabled / fail_policy / score_threshold. Vendor-specific
    # config keys are validated against the provider's declared fields — no
    # per-vendor contract subclass needed. All messages are I18n (en + zh-CN).
    class ProviderSettings < Reform::Form
      property :provider
      property :access_key_id
      property :access_key_secret
      property :enabled
      property :fail_policy
      property :config

      validate :access_key_id_present
      validate :fail_policy_valid
      validate :required_config_fields_present
      validate :provider_configuration_valid

      private

      def provider_configuration_valid
        return if Captcha::Providers.for(provider).valid_configuration?(parsed_config)

        errors.add(:base, I18n.t("captcha.platform_settings.errors.configuration_invalid"))
      rescue ArgumentError
        # required_config_fields_present reports an unknown provider.
      end

      def access_key_id_present
        return if access_key_id.to_s.strip.present?

        errors.add(:base, I18n.t("captcha.platform_settings.errors.access_key_id_blank"))
      end

      def fail_policy_valid
        return if Captcha::ProviderSettings::FAIL_POLICIES.include?(fail_policy.to_s)

        errors.add(:base, I18n.t("captcha.platform_settings.errors.fail_policy_invalid"))
      end

      def required_config_fields_present
        provider_class = Captcha::Providers.for(provider)
        cfg = parsed_config
        provider_class.config_fields.each do |field|
          name = field[:name].to_s
          next if field[:default].present? && cfg[name].to_s.empty?
          next unless cfg[name].to_s.strip.empty?

          errors.add(:base, I18n.t("captcha.platform_settings.errors.field_blank",
                                   field: provider_class.field_label(field)))
        end
      rescue ArgumentError
        errors.add(:base, I18n.t("captcha.platform_settings.errors.unknown_provider"))
      end

      def parsed_config
        parsed = config.is_a?(String) ? JSON.parse(config) : config
        parsed.is_a?(Hash) ? parsed.stringify_keys : {}
      rescue JSON::ParserError
        {}
      end
    end
  end
end
