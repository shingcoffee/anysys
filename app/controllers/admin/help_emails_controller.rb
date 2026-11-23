# frozen_string_literal: true

module Admin
  class HelpEmailsController < ApplicationController
    def create
      result = ::Help::Activities::SendEmail.call(
        customer: current_customer,
        user: current_user,
        params: email_params.merge(page_url: request.referer)
      )
      if result.success?
        redirect_back fallback_location: admin_dashboard_path(current_customer_id),
                      notice: t("help.flash.email_sent")
      else
        redirect_back fallback_location: admin_dashboard_path(current_customer_id),
                      alert: result.messages.to_sentence
      end
    end

    private

    def email_params
      params.require(:help_email).permit(:subject, :body, attachments: [])
    end
  end
end
