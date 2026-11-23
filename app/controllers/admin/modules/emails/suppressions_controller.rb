# frozen_string_literal: true

module Admin
  module Modules
    module Emails
      # Read-only view of this tenant's own email suppressions. Global provider
      # suppressions are enforced at delivery time but are not visible or
      # deletable from a tenant admin UI.
      class SuppressionsController < ApplicationController
        dashboard_menu_item :modules
        before_action :require_email_module!, only: :batch_unblock

        def index
          @columns = [
            { key: :select, label: "", sortable: false, searchable: false,
              cell: ->(s) { selection_checkbox(s) } },
            { key: :email, label: I18n.t("common.labels.email"), sortable: true, searchable: true },
            { key: :scope, label: I18n.t("admin_modules.emails.suppressions.scope"),
              cell: ->(s) { s.customer_id ? I18n.t("admin_modules.emails.suppressions.tenant") : I18n.t("admin_modules.emails.suppressions.global") } },
            { key: :reason, label: I18n.t("admin_modules.emails.suppressions.reason"), sortable: true,
              cell: ->(s) { I18n.t("admin_modules.emails.suppressions.reasons.#{s.reason}", default: s.reason) } },
            { key: :provider, label: I18n.t("common.labels.provider"), sortable: true },
            { key: :created_at, label: I18n.t("common.labels.at"), type: :datetime, sortable: true }
          ]
          scope = ::Emails::Suppression.where(customer_id: current_customer_id)
          reason = scalar_filter(params[:reason])
          provider = scalar_filter(params[:provider])
          scope = scope.where(reason: reason) if reason
          scope = scope.where(provider: provider) if provider
          @provider_options = provider_filter_options
          result = ModuleEntriesResolver.call(
            scope: scope.order(created_at: :desc), columns: @columns,
            params: params.permit(:page, :per_page, :sort, :dir, :q, :reason, :provider).to_h.symbolize_keys,
            filters: [
              { key: :reason, label: t("admin_modules.emails.suppressions.filter_reason"),
                options: ::Emails::Suppression::REASONS.map { |r| [t("admin_modules.emails.suppressions.reasons.#{r}"), r] } },
              { key: :provider, label: t("admin_modules.emails.suppressions.filter_provider"),
                options: @provider_options }
            ]
          )
          @rows       = result[:rows]
          @pagination = result[:pagination]
        end

        def batch_unblock
          ids = Array.wrap(params[:suppression_ids]).filter_map { |id|
            s = id.to_s
            s if s.match?(/\A\d+\z/)
          }
          ::Emails::Suppression.where(id: ids, customer_id: current_customer.id).destroy_all
          redirect_to admin_modules_emails_suppressions_path(current_customer_id), notice: t("admin_modules.flash.suppressions.unblocked")
        end

        private

        def require_email_module!
          return if FeatureModules::Module.enabled?(key: "email", customer_id: current_customer.id)

          head :not_found
        end

        def scalar_filter(value)
          Array.wrap(value).find { |v| v.is_a?(String) || v.is_a?(Symbol) }&.to_s.presence
        end

        def selection_checkbox(suppression)
          helpers.tag.input(type: "checkbox",
                            name: "suppression_ids[]",
                            value: suppression.id,
                            form: "bulk-unblock-form",
                            class: "rounded border-border text-accent focus:ring-accent",
                            data: { "batch-select-target": "item",
                                    action: "change->batch-select#refresh" })
        end

        def provider_filter_options
          ::Emails::Suppression.where(customer_id: current_customer_id)
                               .where.not(provider: nil)
                               .distinct
                               .pluck(:provider)
                               .map { |p| [p, p] }
        end
      end
    end
  end
end
