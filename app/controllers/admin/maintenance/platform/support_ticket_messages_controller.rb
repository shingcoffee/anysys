# frozen_string_literal: true

module Admin
module Maintenance
module Platform
  class SupportTicketMessagesController < ApplicationController
    dashboard_menu_item :maintenance

    def create
      request = SupportTicket.unscoped_by_tenant.find(params[:support_ticket_id])
      result = ::Help::Activities::AddMessage.call(
        request: request,
        user: current_user,
        author_role: "owner",
        params: message_params
      )
      if result.success?
        redirect_to admin_maintenance_platform_support_ticket_path(current_customer_id, request),
                    notice: t("help.flash.replied")
      else
        redirect_to admin_maintenance_platform_support_ticket_path(current_customer_id, request),
                    alert: result.messages.to_sentence
      end
    end

    private

    def message_params
      params.require(:support_ticket_message).permit(:body, images: [])
    end
  end
end
end
end
