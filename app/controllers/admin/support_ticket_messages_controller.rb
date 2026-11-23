# frozen_string_literal: true

module Admin
  class SupportTicketMessagesController < ApplicationController
    def create
      request = SupportTicket.for_customer(current_customer_id)
                           .where(user_id: current_user.id)
                           .find(params[:support_ticket_id])
      result = ::Help::Activities::AddMessage.call(
        request: request,
        user: current_user,
        author_role: "requester",
        params: message_params
      )
      if result.success?
        redirect_to admin_support_ticket_path(current_customer_id, request),
                    notice: t("help.flash.replied")
      else
        redirect_to admin_support_ticket_path(current_customer_id, request),
                    alert: result.messages.to_sentence
      end
    end

    private

    def message_params
      params.require(:support_ticket_message).permit(:body, images: [])
    end
  end
end
