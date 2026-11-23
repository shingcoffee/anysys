# frozen_string_literal: true

module Admin
  module Maintenance
    # Rebinds the flowchart that processes a page's submissions. Platform
    # owner only: FlowchartVisibility gates this controller by its path. A
    # shared page is rebound on the platform prefix only; a tenant customises
    # a shared page's processing through its flowchart override instead.
    class FlowchartBindingsController < ApplicationController
      include SharedResourceMode
      dashboard_menu_item :maintenance
      before_action :find_page
      guard_shared_global_writes :@page, json_error: "shared_page_readonly" do
        admin_maintenance_page_path(current_customer_id, @page)
      end

      def update
        contract = ::Pages::ProcessingContract.new(@page)
        destination = admin_maintenance_page_path(current_customer_id, @page)
        if contract.validate(binding_params) && contract.save
          redirect_to destination, notice: t("maint_core.flash.flowchart_bindings.updated", name: @page.flowchart.name)
        else
          redirect_to destination,
                      alert: t("maint_core.flash.flowchart_bindings.update_failed", errors: contract.errors.full_messages.join("; "))
        end
      end

      private

      def find_page
        @page = definition_scope(Page).find(params[:page_id])
      end

      def binding_params
        params.require(:page).permit(:flowchart_id).to_h
      end
    end
  end
end
