# frozen_string_literal: true

module Admin
module Maintenance
module Platform
  class SupportTicketsController < ApplicationController
    dashboard_menu_item :maintenance

    def index
      result = ModuleEntriesResolver.call(
        scope:   SupportTicket.unscoped_by_tenant.includes(:customer, :user, :reads, :messages).newest_first,
        columns: index_columns,
        filters: index_filters,
        params:  index_params
      )
      @columns    = index_columns
      @filters    = index_filters
      @rows       = result[:rows]
      @pagination = result[:pagination]
    end

    def show
      @support_ticket = SupportTicket.unscoped_by_tenant.find(params[:id])
      SupportTicketRead.record!(support_ticket: @support_ticket, user_id: current_user.id)
      @messages = @support_ticket.thread_messages
    end

    private

    def index_params
      params.permit(:q, :sort, :dir, :page, :status).to_h.symbolize_keys
    end

    def index_columns
      @index_columns ||= [
        { key: :subject, label: column_label(:subject), sortable: true, searchable: true,
          leading: ->(row) { { icon: :mail, tone: row.unread_for?(current_user) ? :accent : :default } },
          subtitle: ->(row) { row.latest_message&.body.to_s.squish.truncate(96) } },
        { key: :customer, label: column_label(:customer), sortable: false, searchable: false,
          cell: ->(row) { row.customer&.name } },
        { key: :requester, label: column_label(:requester), sortable: false, searchable: false,
          cell: ->(row) { row.user&.email } },
        { key: :status, label: column_label(:status), type: :badge, sortable: true,
          badge: ->(row) { status_badges(row) },
          cell:  ->(row) { status_badge(row)[:label] } },
        { key: :last_message_at, label: column_label(:last_message_at), type: :datetime, sortable: true }
      ]
    end

    def index_filters
      @index_filters ||= [
        { key: :status, label: t("maint_platform.support_tickets.index.filters.status"), column: :status,
          options: SupportTicket::STATUSES.map { |s| [ t("help.status.#{s}"), s ] } }
      ]
    end

    def column_label(key)
      t("maint_platform.support_tickets.index.columns.#{key}")
    end

    def status_badges(row)
      badges = [ status_badge(row) ]
      badges << { label: t("help.unread"), variant: :info } if row.unread_for?(current_user)
      badges
    end

    def status_badge(row)
      if row.open?
        { label: t("help.status.open"), variant: :info }
      else
        { label: t("help.status.resolved"), variant: :default }
      end
    end
  end
end
end
end
