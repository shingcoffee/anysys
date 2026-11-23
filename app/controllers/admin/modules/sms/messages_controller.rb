# frozen_string_literal: true

module Admin
  module Modules
    module Sms
    # Tenant-scoped SMS audit log. Mirrors the Payments::Admin::*
    # controllers — renders a Dashboard-style entries table via
    # ModuleEntriesResolver so we get search / sort / pagination
    # for free. Every lookup uses `for_current_customer` per the
    # TenantScoped rule.
    class MessagesController < ApplicationController
      dashboard_menu_item :modules

      def index
        @columns = [
          { key: :to,           label: I18n.t("common.labels.to"),        sortable: true, searchable: true },
          { key: :template_key, label: I18n.t("common.labels.template"),  sortable: true, searchable: true },
          { key: :status,       label: I18n.t("common.labels.status"),    type: :badge, sortable: true,
            badge: ->(m) {
              v = { "pending" => :default, "sent" => :info, "delivered" => :success,
                    "failed" => :danger, "unknown" => :default, "suppressed" => :warning,
                    "expired" => :warning }[m.status] || :default
              { variant: v, label: message_status_label(m) }
            },
            cell: ->(m) { message_status_label(m) } },
          { key: :sent_at,      label: I18n.t("common.labels.sent"),      type: :datetime, sortable: true },
          { key: :delivered_at, label: I18n.t("common.labels.delivered"), type: :datetime, sortable: true },
          { key: :failure_code, label: I18n.t("common.labels.failure"),   sortable: true, searchable: false }
        ]
        scope  = ::Sms::Message.for_current_customer.order(created_at: :desc)
        result = ModuleEntriesResolver.call(
          scope: scope, columns: @columns,
          params: params.permit(:page, :per_page, :sort, :dir, :q).to_h.symbolize_keys
        )
        @rows       = result[:rows]
        @pagination = result[:pagination]
      end

      def show
        @message = ::Sms::Message.for_current_customer.find(params[:id])
      end

      private

      def message_status_label(message)
        I18n.t(message.status == "expired" ? "sms.statuses.expired" : "common.status.#{message.status}")
      end
    end
    end
  end
end
