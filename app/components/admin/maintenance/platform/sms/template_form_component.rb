# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module Sms
        # Renders the platform-owner SMS template form (new/edit). Renders one
        # provider-code input per registered `Sms::Adapters` vendor, so adding a
        # vendor needs no change here.
        class TemplateFormComponent < ViewComponent::Base
          def initialize(template:, form_url:, form_method:, cancel_path:)
            @template    = template
            @form_url    = form_url
            @form_method = form_method
            @cancel_path = cancel_path
          end

          attr_reader :template, :form_url, :form_method, :cancel_path

          def provider_keys = ::Sms::Adapters.keys

          def provider_adapter(key) = ::Sms::Adapters.for(key)

          def provider_code_label(adapter)
            t("maint_platform.sms.templates.form.provider_code_label", provider: adapter.display_name)
          end

          def provider_code_field_id(key)   = "sms_template_provider_template_codes_#{key}"
          def provider_code_field_name(key) = "sms_template[provider_template_codes][#{key}]"

          def status_options = ::Sms::Template::STATUSES

          def variables_raw
            Array(template.variables).join(", ")
          end

          def submit_label
            template.persisted? ? t("common.actions.update") : t("common.actions.create")
          end

          def field_grid_class
            "grid grid-cols-1 gap-2 sm:grid-cols-[12rem_minmax(0,1fr)] sm:items-start sm:gap-6"
          end
        end
      end
    end
  end
end
