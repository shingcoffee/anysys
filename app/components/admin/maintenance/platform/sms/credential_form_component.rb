# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module Sms
        # Renders the platform-owner SMS credential form (new/edit). The
        # vendor-specific config-field groups and access-key labels come from
        # `Sms::Adapters` so adding a vendor needs no change here — mirrors
        # Admin::Maintenance::Platform::Emails::CredentialFormComponent.
        class CredentialFormComponent < ViewComponent::Base
          def initialize(credential:, form_url:, form_method:, cancel_path:, lock_identity: false)
            @credential    = credential
            @form_url      = form_url
            @form_method   = form_method
            @cancel_path   = cancel_path
            @lock_identity = lock_identity
          end

          attr_reader :credential, :form_url, :form_method, :cancel_path

          def lock_identity?
            @lock_identity
          end

          def adapters
            ::Sms::Adapters.all
          end

          def selected_provider
            credential.provider.presence || ::Sms::Adapters.default_key.to_s
          end

          def selected_adapter
            ::Sms::Adapters.for(selected_provider)
          rescue ArgumentError
            ::Sms::Adapters.for(::Sms::Adapters.default_key)
          end

          def mode_options   = ::Sms::Credential::MODES
          def status_options = ::Sms::Credential::STATUSES

          def access_key_id_label     = selected_adapter.credential_label(:access_key_id)
          def access_key_secret_label = selected_adapter.credential_label(:access_key_secret)

          # Per-provider { access_key_id:, access_key_secret: } label map handed
          # to the Stimulus controller so it can swap labels client-side without
          # a round trip when the user changes the provider select.
          def labels_by_provider
            adapters.each_with_object({}) do |adapter, memo|
              memo[adapter.key] = {
                access_key_id:     adapter.credential_label(:access_key_id),
                access_key_secret: adapter.credential_label(:access_key_secret)
              }
            end
          end

          def field_label(adapter, field) = adapter.field_label(field)

          def config_field_id(field) = "sms_credential_#{field[:name]}"

          def config_field_name(field) = "sms_credential[#{field[:name]}]"

          def submit_label
            credential.persisted? ? t("common.actions.update") : t("common.actions.create")
          end

          def field_grid_class
            "grid grid-cols-1 gap-2 sm:grid-cols-[12rem_minmax(0,1fr)] sm:items-start sm:gap-6"
          end

          def form_class
            "flex w-full flex-col gap-6 #{'pb-20' unless lock_identity?}"
          end

          def identity_hint
            if lock_identity?
              t("maint_platform.sms.credentials.form.identity_hint_locked")
            else
              t("maint_platform.sms.credentials.form.identity_hint")
            end
          end
        end
      end
    end
  end
end
