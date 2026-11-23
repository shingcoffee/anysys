# frozen_string_literal: true

module Admin
module Maintenance
module Platform
  module Sms
    # SMS templates — platform-wide config exposed under the
    # platform owner's tenant at /:customer_id/maintenance/platform/module_settings/sms/templates
    # per the four-part module URL rule (AGENTS.md, part d).
    class TemplatesController < ApplicationController
      dashboard_menu_item :maintenance

      include Listable
      include ::Sms::PlatformParameters
      before_action :set_template, only: %i[edit update destroy]

      def index
        @columns = [
          { key: :key,                  label: I18n.t("common.labels.key"),         sortable: true, searchable: true },
          { key: :provider_codes,       label: I18n.t("common.labels.provider_codes"), sortable: false, searchable: false,
            cell: ->(t) { t.provider_codes.map { |k, v| "#{k}: #{v}" }.join(", ") } },
          { key: :variables,            label: I18n.t("common.labels.variables"),   type: :truncate, sortable: false, searchable: false,
            cell: ->(t) { Array(t.variables).join(", ") } },
          { key: :status,               label: I18n.t("common.labels.status"),      type: :badge, sortable: true,
            badge: ->(t) { { variant: t.active? ? :success : :default, label: I18n.t("common.status.#{t.status}") } },
            cell:  ->(t) { I18n.t("common.status.#{t.status}") } },
          { key: :updated_at,           label: I18n.t("common.labels.updated_at"),     type: :datetime, sortable: true }
        ]

        scope  = ::Sms::Template.order(updated_at: :desc)
        result = listable(scope, columns: @columns)
        @templates  = result[:rows]
        @rows       = result[:rows]
        @pagination = result[:pagination]
      end

      def new
        @template = ::Sms::Template.new(variables: [])
      end

      def create
        @template = ::Sms::Template.new
        @template.assign_attributes(template_params.merge(variables: parsed_variables))
        if @template.save
          redirect_to admin_maintenance_platform_module_settings_sms_templates_path(current_customer_id), status: :see_other, notice: t("maint_platform.flash.sms_templates.registered")
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        if @template.update(template_params.merge(variables: parsed_variables))
          redirect_to admin_maintenance_platform_module_settings_sms_templates_path(current_customer_id), status: :see_other, notice: t("maint_platform.flash.sms_templates.updated")
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        # Hard-delete only if no messages reference it; otherwise retire.
        # A message created concurrently between the exists? check and destroy!
        # trips the DeleteRestrictionError guard — fall back to the same
        # graceful retire path instead of surfacing a 500.
        if @template.sms_messages.exists?
          retire_template
        else
          begin
            @template.destroy!
            redirect_to "/#{current_customer.id}/admin/maintenance/platform/module_settings/sms/templates", notice: t("maint_platform.flash.sms_templates.deleted")
          rescue ActiveRecord::DeleteRestrictionError
            retire_template
          end
        end
      end

      private

      def retire_template
        @template.update!(status: "retired")
        redirect_to "/#{current_customer.id}/admin/maintenance/platform/module_settings/sms/templates", notice: t("maint_platform.flash.sms_templates.retired")
      end

      def set_template
        @template = ::Sms::Template.find(params[:id])
      end

      def template_params
        attrs = platform_attributes(:sms_template,
                                    allowed: %i[key description status purpose body_template variables_raw provider_template_codes],
                                    objects: [:provider_template_codes])
        @variables_supplied = attrs.key?(:variables_raw)
        @variables_raw = attrs.delete(:variables_raw)
        if attrs.key?(:provider_template_codes)
          codes = attrs[:provider_template_codes]
          unknown = codes.keys.map(&:to_s) - ::Sms::Adapters.keys.map(&:to_s)
          raise ::Sms::RequestAttributes::Invalid.new(:provider_template_codes, :unknown_parameters) if unknown.any?
          attrs[:provider_template_codes] = codes.reject { |_, value| value.strip.empty? }
        end
        attrs
      end

      # The native form submits comma-separated text; omission preserves vars.
      def parsed_variables
        return @template.required_vars unless @variables_supplied

        raw = @variables_raw.to_s
        raw.split(",").map(&:strip).reject(&:empty?)
      end
    end
  end
end
end
end
