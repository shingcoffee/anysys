# frozen_string_literal: true

module Admin
  module Modules
    module Sms
      # Read-only view of SMS opt-outs visible to this tenant: its own manual
      # suppressions plus global opt-outs (recipients who replied STOP on the
      # shared vendor number) BUT only for numbers this tenant has actually
      # messaged — so one tenant can't enumerate another tenant's recipients.
      # Global rows show a blank "scope".
      class OptOutsController < ApplicationController
        dashboard_menu_item :modules

        def index
          @columns = [
            { key: :phone_e164, label: I18n.t("common.labels.to"), sortable: true, searchable: true },
            { key: :scope, label: I18n.t("admin_modules.sms.opt_outs.scope"),
              cell: ->(o) { o.customer_id ? I18n.t("admin_modules.sms.opt_outs.tenant") : I18n.t("admin_modules.sms.opt_outs.global") } },
            { key: :provider, label: I18n.t("common.labels.provider"), sortable: true },
            { key: :reason, label: I18n.t("admin_modules.sms.opt_outs.reason") },
            { key: :created_at, label: I18n.t("common.labels.at"), type: :datetime, sortable: true }
          ]
          messaged_phones = ::Sms::Message.where(customer_id: current_customer_id)
                                         .where.not(sent_at: nil).where.not(status: "suppressed").select(:to)
          scope  = ::Sms::OptOut.visible_to_customer(current_customer_id, messaged_phones)
                                .order(created_at: :desc)
          result = ModuleEntriesResolver.call(
            scope: scope, columns: @columns,
            params: params.permit(:page, :per_page, :sort, :dir, :q).to_h.symbolize_keys
          )
          @rows       = result[:rows]
          @pagination = result[:pagination]
        end
      end
    end
  end
end
