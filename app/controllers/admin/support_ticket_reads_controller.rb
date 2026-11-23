# frozen_string_literal: true

module Admin
  # Persistent per-user mark-read of a help ticket from the admin-chrome
  # bell. Lives under /:cid/admin/ (tenant admin), not
  # /admin/maintenance/platform/ — every tenant admin must be able to POST
  # it. RouteAuthorization already requires admin_or_owner? on this prefix.
  class SupportTicketReadsController < ApplicationController
    def create
      request = readable_support_ticket
      if request
        SupportTicketRead.record!(support_ticket: request, user_id: current_user.id)
        redirect_to inbox.thread_path_for(request)
      else
        redirect_back fallback_location: admin_dashboard_path(current_customer_id)
      end
    end

    private

    def inbox
      @inbox ||= Notifications::Inbox.new(user: current_user, customer_id: current_customer_id)
    end

    def readable_support_ticket
      id = read_support_ticket_id
      return nil if id.blank? || current_user.blank?

      inbox.visible_support_ticket(id)
    end

    def read_support_ticket_id
      raw = params[:support_ticket_id]
      raw = params.dig(:support_ticket_read, :support_ticket_id) if raw.blank?
      raw.to_s.presence
    end
  end
end
