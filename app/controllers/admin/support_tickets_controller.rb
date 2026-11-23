# frozen_string_literal: true

module Admin
  class SupportTicketsController < ApplicationController
    def show
      @support_ticket = own_requests.find(params[:id])
      SupportTicketRead.record!(support_ticket: @support_ticket, user_id: current_user.id)
      @messages = @support_ticket.thread_messages
    end

    def create
      if current_user.platform_owner?
        redirect_back fallback_location: admin_dashboard_path(current_customer_id),
                      alert: t("help.errors.owner_cannot_notify")
        return
      end

      result = ::Help::Activities::CreateRequest.call(
        customer: current_customer,
        user: current_user,
        params: request_params
      )
      if result.success?
        redirect_to admin_support_ticket_path(current_customer_id, result.model),
                    notice: t("help.flash.created")
      else
        redirect_back fallback_location: admin_dashboard_path(current_customer_id),
                      alert: result.messages.to_sentence
      end
    end

    private

    def own_requests
      SupportTicket.for_customer(current_customer_id).where(user_id: current_user.id)
    end

    def request_params
      params.require(:support_ticket).permit(:subject, :body, images: [])
    end
  end
end
