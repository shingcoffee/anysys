# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module Captcha
        # Platform-owner settings: the live vendor first, then credentials
        # and tunables for the selected vendor.
        class SettingsComponent < ViewComponent::Base
          PARAM_KEY = "captcha_provider_settings"

          def initialize(settings:, mode:, customer_id:, providers: [], active_key: nil, errors: [])
            @settings    = settings
            @mode        = mode
            @customer_id = customer_id
            @providers   = providers
            @active_key  = active_key
            @errors      = errors
          end

          attr_reader :settings, :mode, :customer_id, :providers, :active_key, :errors

          def param_key = PARAM_KEY

          def show_mode?
            mode.to_sym == :show
          end

          def edit_active?
            mode.to_sym == :edit_active
          end

          def edit_vendor?
            %i[edit edit_vendor].include?(mode.to_sym)
          end

          def provider_class
            ::Captcha::Providers.for(settings.provider)
          end

          def provider_name          = provider_class.display_name
          def config_fields          = Array(provider_class.config_fields)
          def field_label(field)     = provider_class.field_label(field)
          def credential_label(name) = provider_class.credential_label(name)
          def score_based?           = provider_class.score_based?

          def active_provider_name
            return if active_key.blank?

            from_list = providers.find { |pc| pc.respond_to?(:key) && pc.key.to_s == active_key.to_s }
            return from_list.display_name if from_list

            ::Captcha::Providers.for(active_key).display_name
          rescue ArgumentError
            active_key.to_s
          end

          def switcher_items
            providers.filter_map do |pc|
              next unless pc.respond_to?(:key)

              {
                name: pc.display_name,
                path: tab_path(pc.key),
                current: pc.key.to_s == settings.provider.to_s,
                active: false
              }
            end
          end

          def base_path
            "/#{customer_id}/admin/maintenance/platform/module_settings/captcha/settings"
          end

          def settings_path(provider_key = settings.provider)
            "#{base_path}?provider=#{provider_key}"
          end

          def tab_path(provider_key = settings.provider)
            return vendor_edit_path(provider_key) if edit_vendor?

            settings_path(provider_key)
          end

          def active_edit_path
            "#{base_path}/edit?section=active&provider=#{settings.provider}"
          end

          def vendor_edit_path(provider_key = settings.provider)
            "#{base_path}/edit?section=vendor&provider=#{provider_key}"
          end

          def edit_path
            vendor_edit_path
          end

          def test_connection_path
            "#{base_path}/test_connection?provider=#{settings.provider}"
          end

          def health_status_key
            case settings.last_health_check_status
            when "ok"                  then "ok"
            when "configuration_error" then "configuration_error"
            when "unreachable"         then "unreachable"
            else                            "unknown"
            end
          end

          def health_badge_variant
            case health_status_key
            when "ok"                  then :success
            when "configuration_error" then :danger
            when "unreachable"         then :warning
            else                            :default
            end
          end

          def field_value(field)
            from_config = settings.config_value(field[:name])
            from_config.presence || field[:default]
          end

          def config_secret_present?(field)
            settings.config_value(field[:name]).present?
          end

          def errors_message
            Array(errors).join(" · ")
          end

          def secret_placeholder
            I18n.t("comp_admin.captcha_platform_settings.secret_placeholder")
          end
        end
      end
    end
  end
end
