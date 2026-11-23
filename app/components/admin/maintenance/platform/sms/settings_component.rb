# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module Sms
        # Platform-owner SMS settings: live delivery assignment first, then
        # credentials for the selected vendor — same IA as email / captcha / STT.
        class SettingsComponent < ViewComponent::Base
          MODES = ::Sms::Credential::MODES

          def initialize(provider_key:, providers:, credentials_by_mode:, all_credentials:,
                         delivery_by_mode:, customer_id:, mode: :show, edit_mode_key: nil,
                         credential: nil, errors: [])
            @provider_key = provider_key.to_s
            @providers = Array(providers)
            @credentials_by_mode = credentials_by_mode || {}
            @all_credentials = Array(all_credentials)
            @delivery_by_mode = delivery_by_mode || {}
            @customer_id = customer_id
            @mode = mode.to_sym
            @edit_mode_key = edit_mode_key.to_s.presence
            @credential = credential
            @errors = errors
          end

          attr_reader :provider_key, :providers, :credentials_by_mode, :all_credentials,
                      :delivery_by_mode, :customer_id, :mode, :edit_mode_key, :credential,
                      :errors

          def show_mode?
            mode == :show
          end

          def edit_delivery?
            mode == :edit_delivery
          end

          def edit_vendor?
            mode == :edit_vendor
          end

          def adapter_class
            ::Sms::Adapters.for(provider_key)
          end

          def provider_name
            adapter_class.display_name
          end

          def mode_title(mode_key)
            I18n.t("common.modes.#{mode_key}")
          end

          def credential_for(mode_key)
            credentials_by_mode[mode_key]
          end

          def editing_mode?(mode_key)
            edit_vendor? && edit_mode_key == mode_key.to_s
          end

          def editing_record
            credential || credential_model_new
          end

          def form_url
            record = editing_record
            if record.persisted?
              helpers.admin_maintenance_platform_module_settings_sms_credential_path(customer_id, record)
            else
              helpers.admin_maintenance_platform_module_settings_sms_credentials_path(customer_id)
            end
          end

          def form_method
            editing_record.persisted? ? :patch : :post
          end

          def switcher_items
            providers.filter_map do |pc|
              next unless pc.respond_to?(:key)

              key = pc.key.to_s
              {
                name: pc.display_name,
                path: settings_path(key),
                current: key == provider_key,
                active: live_provider?(key)
              }
            end
          end

          def delivery_jobs
            MODES.map do |mode_key|
              selected = delivery_by_mode[mode_key].to_s
              {
                key: mode_key,
                title: mode_title(mode_key),
                hint: I18n.t("maint_platform.sms.platform_settings.delivery_mode_hint.#{mode_key}"),
                selected: selected,
                provider_name: assignee_name(selected),
                choices: delivery_choices(mode_key)
              }
            end
          end

          def show_rows(record)
            return [] unless record

            rows = adapter_class.config_fields.map do |field|
              if field[:type] == :password
                masked_row(adapter_class.field_label(field), record.config_value(field[:name]).present?)
              else
                text_row(adapter_class.field_label(field), record.config_value(field[:name]))
              end
            end
            rows << text_row(adapter_class.credential_label(:access_key_id), record.access_key_id)
            rows << masked_row(adapter_class.credential_label(:access_key_secret), record.access_key_secret.present?)
            rows
          end

          def settings_path(provider = provider_key)
            helpers.admin_maintenance_platform_module_settings_sms_credentials_path(
              customer_id, provider: provider
            )
          end

          def delivery_path
            helpers.delivery_admin_maintenance_platform_module_settings_sms_credentials_path(customer_id)
          end

          def delivery_edit_path
            helpers.admin_maintenance_platform_module_settings_sms_credentials_path(
              customer_id, provider: provider_key, section: "delivery"
            )
          end

          def vendor_edit_path(mode_key, record = credential_for(mode_key))
            if record
              helpers.edit_admin_maintenance_platform_module_settings_sms_credential_path(customer_id, record)
            else
              helpers.new_admin_maintenance_platform_module_settings_sms_credential_path(
                customer_id, provider: provider_key, mode: mode_key
              )
            end
          end

          def status_badge_variant(record)
            record.status == "active" ? :success : :default
          end

          def configured_badge_variant(record)
            record.configured? ? :success : :default
          end

          def configured_label(record)
            if record.configured?
              I18n.t("common.status.configured")
            else
              I18n.t("common.status.partial")
            end
          end

          def health_rows
            MODES.map do |mode_key|
              record = credential_for(mode_key)
              {
                label: mode_title(mode_key),
                status: record ? configured_label(record) : I18n.t("common.status.partial"),
                status_variant: record&.configured? ? :success : :warning,
                state: record ? I18n.t("common.status.#{record.status}") : I18n.t("common.status.disabled")
              }
            end
          end

          def errors_message
            Array(errors).join(" · ")
          end

          def masked_value
            I18n.t("maint_platform.sms.platform_settings.masked")
          end

          def dash
            I18n.t("common.labels.em_dash")
          end

          private

          def live_provider?(key)
            delivery_by_mode.values.map(&:to_s).include?(key)
          end

          def delivery_choices(mode_key)
            providers.select do |pc|
              all_credentials.any? do |c|
                c.provider == pc.key.to_s && c.mode == mode_key && c.configured?
              end
            end
          end

          def assignee_name(key)
            return if key.blank?

            from_list = providers.find { |pc| pc.respond_to?(:key) && pc.key.to_s == key }
            return from_list.display_name if from_list

            ::Sms::Adapters.for(key).display_name
          rescue ArgumentError
            key.to_s
          end

          def text_row(label, value)
            { label: label, value: value.presence || dash, masked: false }
          end

          def masked_row(label, present)
            { label: label, value: present ? masked_value : dash, masked: true }
          end

          def credential_model_new
            ::Sms::Credential.new(provider: provider_key, mode: edit_mode_key, status: "disabled")
          end
        end
      end
    end
  end
end
