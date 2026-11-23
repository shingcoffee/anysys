# frozen_string_literal: true

module Admin
module Maintenance
module Platform
  class SupportTicketResolutionsController < ApplicationController
    dashboard_menu_item :maintenance

    def create
      request = SupportTicket.unscoped_by_tenant.find(params[:support_ticket_id])
      result = ::Help::Activities::Resolve.call(request: request)
      if result.success?
        redirect_to admin_maintenance_platform_support_ticket_path(current_customer_id, request),
                    notice: t("help.flash.resolved")
      else
        redirect_to admin_maintenance_platform_support_ticket_path(current_customer_id, request),
                    alert: result.messages.to_sentence
      end
    end
  end
end
end
end
