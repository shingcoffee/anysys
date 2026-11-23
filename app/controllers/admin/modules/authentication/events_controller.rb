# frozen_string_literal: true

module Admin
  module Modules
    module Authentication
      # Read-only browser for the auth audit ledger (Authentication::Event):
      # sign-ins, lockouts, MFA changes, password resets, role grants, throttling.
      # Admin/owner-only via RouteAuthorization (admin path).
      #
      # Authentication::Event is intentionally NOT TenantScoped (rows are written
      # on pre-auth paths), so scope explicitly with for_customer rather than a
      # tenant default — a bare .all would leak every tenant's events.
      class EventsController < ApplicationController
        dashboard_menu_item :modules

        # Events that indicate a failure or security concern render in red.
        WARN_EVENTS = %w[login_failed locked_out mfa_failed throttled].freeze

        def index
          @columns = [
            { key: :created_at, label: I18n.t("common.labels.at"), type: :datetime, sortable: true },
            { key: :event, label: I18n.t("admin_modules.authentication.events.columns.event"), type: :badge, sortable: true,
              badge: ->(e) { { variant: WARN_EVENTS.include?(e.event) ? :danger : :default,
                               label: event_kind_label(e.event) } },
              cell:  ->(e) { event_kind_label(e.event) } },
            { key: :user_id, label: I18n.t("admin_modules.authentication.events.columns.user_id"), sortable: true, searchable: false },
            { key: :ip, label: I18n.t("admin_modules.authentication.events.columns.ip"), sortable: true, searchable: true },
            { key: :user_agent, label: I18n.t("admin_modules.authentication.events.columns.user_agent"), type: :truncate, truncate: 60, sortable: false, searchable: true }
          ]

          @filters = [
            { key: :event, label: I18n.t("admin_modules.authentication.events.columns.event"),
              options: ::Authentication::Event::EVENTS.map { |e| [event_kind_label(e), e] },
              column: :event },
            { key: :window, label: I18n.t("admin_modules.authentication.events.columns.window"),
              options: [[I18n.t("admin_modules.authentication.events.windows.d1"),  "1"],
                        [I18n.t("admin_modules.authentication.events.windows.d7"),  "7"],
                        [I18n.t("admin_modules.authentication.events.windows.d30"), "30"]],
              scope: ->(rel, v) { rel.where(created_at: v.to_i.days.ago..) } }
          ]

          scope  = ::Authentication::Event.for_customer(current_customer_id).order(created_at: :desc)
          result = ModuleEntriesResolver.call(
            scope: scope, columns: @columns, filters: @filters,
            params: params.permit(:q, :sort, :dir, :page, :event, :window).to_h.symbolize_keys
          )
          @rows       = result[:rows]
          @pagination = result[:pagination]
        end

        private

        def event_kind_label(event)
          key = event.to_s
          return key unless ::Authentication::Event::EVENTS.include?(key)

          I18n.t("admin_modules.authentication.events.kinds.#{key}")
        end
      end
    end
  end
end
