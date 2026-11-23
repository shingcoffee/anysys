# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module Emails
        # Renders the platform-owner Email credential form (new/edit). SMTP keeps
        # its typed-column fieldset + DKIM fieldset; API providers (SES, Aliyun, …)
        # render their `config_fields` generically — mirrors
        # Admin::Maintenance::Platform::Sms::CredentialFormComponent so adding a
        # provider needs no change here, only a new file under
        # app/services/email/providers/<name>.rb.
        class CredentialFormComponent < ViewComponent::Base
          SMTP_KEY = "smtp"

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

          def providers
            ::Email::Providers.all
          end

          # Non-SMTP providers render a generic config-field group (SES,
          # SES, Aliyun, …); SMTP keeps its hand-authored fieldset below since
          # it uses typed columns rather than the JSON config blob.
          def api_providers
            providers.reject { |p| p.key.to_s == SMTP_KEY }
          end

          def selected_provider
            credential.provider.presence || ::Email::Providers.default_key.to_s
          end

          def selected_provider_class
            ::Email::Providers.for(selected_provider)
          rescue ArgumentError
            ::Email::Providers.for(::Email::Providers.default_key)
          end

          def smtp?
            selected_provider == SMTP_KEY
          end

          def mode_options   = ::Emails::Credential::MODES
          def status_options = ::Emails::Credential::STATUSES

          def secret_label = selected_provider_class.credential_label(:password)

          # Per-provider secret-field label map handed to the Stimulus controller
          # so it can swap the label client-side when the user changes the
          # provider select, without a round trip.
          def labels_by_provider
            providers.each_with_object({}) do |provider, memo|
              memo[provider.key] = provider.credential_label(:password)
            end
          end

          def field_label(provider, field) = provider.field_label(field)

          # Webhook providers that share a secret (Aliyun) render the
          # encrypted `webhook_secret` column. SES verifies SNS certs instead.
          def webhook_provider?(provider)
            provider.delivery_mechanism == :webhook && provider.uses_webhook_secret?
          end

          def config_field_id(provider, field) = "emails_credential_#{provider.key}_#{field[:name]}"

          def config_field_name(field) = "emails_credential[#{field[:name]}]"

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
              t("maint_platform.emails.credentials.form.identity_hint_locked")
            else
              t("maint_platform.emails.credentials.form.identity_hint")
            end
          end
        end
      end
    end
  end
end
