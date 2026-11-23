# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module AiAssistant
        # Platform-owner settings: platform job assignment first, then the
        # selected vendor's credentials and tunables.
        class SettingsComponent < ViewComponent::Base
          PARAM_KEY = "ai_assistant_provider_settings"
          CREDENTIAL_FIELD = /\A(access_key_id|api_key|secret|token|password)/i
          CURSOR_KEY = "cursor"
          JOBS = [
            { key: :transcribe, field_name: "model", assignee_param: :transcribe_assignee,
              support: :supports_transcribe? },
            { key: :generation, field_name: "chat_model", assignee_param: :generation_assignee,
              support: :supports_generation? }
          ].freeze

          def initialize(settings:, mode:, customer_id:, providers: [], transcribe_key: nil,
                         generation_key: nil, transcribe_settings: nil, generation_settings: nil,
                         errors: [])
            @settings             = settings
            @mode                 = mode
            @customer_id          = customer_id
            @providers            = providers
            @transcribe_key       = transcribe_key
            @generation_key       = generation_key
            @transcribe_settings  = transcribe_settings
            @generation_settings  = generation_settings
            @errors               = errors
          end

          attr_reader :settings, :mode, :customer_id, :providers, :errors

          def param_key = PARAM_KEY

          def show_mode?
            mode.to_sym == :show
          end

          def edit_jobs?
            mode.to_sym == :edit_jobs
          end

          def edit_vendor?
            mode.to_sym == :edit_vendor
          end

          def provider_class
            ::AiAssistant::Providers.for(settings.provider)
          end

          def provider_name          = provider_class.display_name
          def config_fields          = Array(provider_class.config_fields)
          def field_label(field)     = provider_class.field_label(field)
          def credential_label(name) = provider_class.credential_label(name)

          def transcribe_settings
            @transcribe_settings || lookup_assignee_row(@transcribe_key)
          end

          def generation_settings
            @generation_settings || lookup_assignee_row(@generation_key)
          end

          def transcribe_key
            @transcribe_key.presence || transcribe_settings&.provider
          end

          def generation_key
            @generation_key.presence || generation_settings&.provider
          end

          def credential_like_field?(field)
            field[:type] == :password || field[:name].to_s.match?(CREDENTIAL_FIELD)
          end

          def credential_config_fields
            config_fields.select { |field| credential_like_field?(field) }
          end

          def option_config_fields
            config_fields.reject { |field| credential_like_field?(field) }
          end

          def cursor_provider?
            settings.provider.to_s == CURSOR_KEY
          end

          def generation_models(row = settings)
            Array(row.config_value(:generation_models)).filter_map { |item| normalize_generation_model(item) }
          end

          def cursor_chat_model_choices
            models = generation_models
            stored = stored_chat_model
            ids = models.map { |model| model[:id] }
            extra = stored.present? && ids.exclude?(stored) ? [ { id: stored, display_name: stored } ] : []
            extra + models
          end

          def stored_chat_model
            field_value(chat_model_field).to_s
          end

          def chat_model_field
            config_fields.find { |field| field[:name].to_s == "chat_model" }
          end

          def jobs
            JOBS.map { |spec| job_view(spec) }
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

          def api_key_present?
            settings.api_key.present?
          end

          def base_path
            "/#{customer_id}/admin/maintenance/platform/module_settings/ai_assistant/settings"
          end

          def settings_path(provider_key = settings.provider)
            "#{base_path}?provider=#{provider_key}"
          end

          def tab_path(provider_key = settings.provider)
            return vendor_edit_path(provider_key) if edit_vendor?

            settings_path(provider_key)
          end

          def jobs_edit_path
            "#{base_path}/edit?section=jobs&provider=#{settings.provider}"
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

          def health_error_message
            return if %w[ok unknown].include?(health_status_key)

            settings.last_health_check_message.presence
          end

          def health_badge_variant
            case health_status_key
            when "ok"                  then :success
            when "configuration_error" then :danger
            when "unreachable"         then :warning
            else                            :default
            end
          end

          def field_value(field, row = settings)
            from_config = row.config_value(field[:name])
            from_config.presence || field[:default]
          end

          def config_secret_present?(field)
            settings.config_value(field[:name]).present?
          end

          def field_input_id(name)
            "#{PARAM_KEY}_#{name}"
          end

          def errors_message
            Array(errors).join(" · ")
          end

          def cursor_models_empty_caption?(field)
            cursor_provider? && field[:name].to_s == "chat_model" && generation_models.empty?
          end

          def cursor_select?(field)
            cursor_provider? && field[:name].to_s == "chat_model" && generation_models.any?
          end

          def option_field_display(field)
            return generation_model_display(settings) if field[:name].to_s == "chat_model" && cursor_provider?

            field_value(field).presence || I18n.t("common.labels.em_dash")
          end

          private

          def job_view(spec)
            row = spec[:key] == :transcribe ? transcribe_settings : generation_settings
            selected = row&.provider.to_s
            {
              key: spec[:key],
              title: I18n.t("ai_assistant.platform_settings.jobs.#{spec[:key]}"),
              hint: I18n.t("ai_assistant.platform_settings.jobs.#{spec[:key]}_hint"),
              param: spec[:assignee_param],
              selected: selected,
              provider_name: assignee_name(selected),
              model_label: assignee_model_label(row, spec[:field_name]),
              model_value: assignee_model_value(row, spec[:field_name]),
              choices: providers_supporting(spec[:support])
            }
          end

          def providers_supporting(method_name)
            providers.select do |pc|
              next false unless pc.respond_to?(:key)
              next true unless pc.respond_to?(method_name)

              pc.public_send(method_name)
            end
          end

          def assignee_model_label(row, field_name)
            field = assignee_field(row, field_name)
            field && field_label(field)
          end

          def assignee_model_value(row, field_name)
            field = assignee_field(row, field_name)
            return if field.blank?

            if field_name.to_s == "chat_model" && row.provider.to_s == CURSOR_KEY
              return generation_model_display(row)
            end

            field_value(field, row).presence || I18n.t("common.labels.em_dash")
          end

          def assignee_field(row, field_name)
            return if row.nil?

            Array(provider_class_for(row.provider).config_fields).find { |field| field[:name].to_s == field_name.to_s }
          rescue ArgumentError
            nil
          end

          def generation_model_display(row)
            stored = field_value({ name: :chat_model }, row).to_s
            match = generation_models(row).find { |model| model[:id] == stored }
            return match[:display_name] if match && match[:display_name].present?

            stored.presence || I18n.t("common.labels.em_dash")
          end

          def lookup_assignee_row(key)
            return if key.blank?

            ::AiAssistant::ProviderSettings.find_by(provider: key.to_s)
          rescue StandardError
            nil
          end

          def assignee_name(key)
            return if key.blank?

            from_list = providers.find { |pc| pc.respond_to?(:key) && pc.key.to_s == key.to_s }
            return from_list.display_name if from_list

            provider_class_for(key).display_name
          rescue ArgumentError
            key.to_s
          end

          def provider_class_for(key)
            ::AiAssistant::Providers.for(key)
          end

          def normalize_generation_model(item)
            return unless item.is_a?(Hash)

            id = (item["id"] || item[:id]).to_s
            return if id.blank?

            { id: id, display_name: (item["display_name"] || item[:display_name] || id).to_s }
          end
        end
      end
    end
  end
end
