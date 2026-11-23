# frozen_string_literal: true

module Captcha
  module Activities
    # Updates one provider's Captcha::ProviderSettings row. The form posts a flat
    # params hash; vendor-specific keys are funneled into the JSON `config` blob.
    #
    # `enabled` is applied through activate!/deactivate! so that at most one
    # provider is ever the active one (enforced atomically against the partial
    # unique index). A blank secret keeps the existing encrypted value; a blank
    # non-secret config field clears it back to the provider default.
    class UpdateProviderSettings
      Result = Struct.new(:success?, :model, :errors, keyword_init: true)

      def self.call(provider:, params:)
        settings = Captcha::ProviderSettings.for_provider(provider)
        h = params.to_h.symbolize_keys

        if active_only?(h, settings)
          return persist_active_only(settings, h[:active_assignee])
        end

        attrs, enabled = sanitize(params, settings)
        settings.assign_attributes(attrs)

        contract = Captcha::Contracts::ProviderSettings.new(settings)
        if contract.validate({}) && settings.valid?
          persist!(settings, enabled)
          Result.new(success?: true, model: settings, errors: [])
        else
          errors = contract.errors.full_messages + settings.errors.full_messages
          Result.new(success?: false, model: settings, errors: errors.uniq)
        end
      end

      def self.active_only?(h, settings)
        return false unless h.key?(:active_assignee)
        return false if h.key?(:access_key_id) || h.key?(:access_key_secret) || h.key?(:fail_policy)

        provider_class = Captcha::Providers.for(settings.provider)
        provider_class.config_fields.none? { |field| h.key?(field[:name].to_sym) }
      end

      def self.persist_active_only(settings, key)
        if key.to_s.blank?
          Captcha::ProviderSettings.where(enabled: true).first&.deactivate!
        else
          begin
            Captcha::Providers.for(key)
          rescue ArgumentError
            return Result.new(
              success?: false,
              model: settings,
              errors: [ I18n.t("captcha.platform_settings.errors.unknown_provider") ]
            )
          end
          Captcha::ProviderSettings.for_provider(key).activate!
        end
        Result.new(success?: true, model: settings.reload, errors: [])
      end

      def self.persist!(settings, enabled)
        Captcha::ProviderSettings.transaction do
          settings.save!
          enabled ? settings.activate! : settings.deactivate!
        end
      end

      def self.sanitize(params, settings)
        h = params.to_h.symbolize_keys
        attrs = {}

        attrs[:access_key_id] = h[:access_key_id] if h.key?(:access_key_id)

        # Secret: blank means "keep existing" so the encrypted value is never
        # clobbered by an empty form field.
        if h.key?(:access_key_secret)
          attrs[:access_key_secret] = h[:access_key_secret].presence || settings.access_key_secret
        end

        attrs[:fail_policy]     = h[:fail_policy].presence || "open" if h.key?(:fail_policy)
        attrs[:score_threshold] = h[:score_threshold].presence       if h.key?(:score_threshold)

        attrs[:config] = merged_config(h, settings).to_json

        enabled = h.key?(:enabled) ? ActiveModel::Type::Boolean.new.cast(h[:enabled]) : settings.enabled?
        [attrs, enabled]
      end

      # Merge provider config fields. A blank value DELETES the key so reads fall
      # back to the provider default (config_value(key, default)); a present
      # value overwrites.
      def self.merged_config(h, settings)
        provider_class = Captcha::Providers.for(settings.provider)
        config = settings.config_json.is_a?(Hash) ? settings.config_json.dup : {}
        provider_class.config_fields.each do |field|
          key = field[:name].to_sym
          next unless h.key?(key)

          value = h[key].to_s
          value.strip.empty? ? config.delete(field[:name].to_s) : config[field[:name].to_s] = value
        end
        config
      end
    end
  end
end
