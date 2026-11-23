# frozen_string_literal: true

module Admin
  module Maintenance
    class PageVisibilitiesController < ApplicationController
      include SharedResourceMode
      dashboard_menu_item :maintenance
      include SafeReturnTo
      before_action :find_page
      guard_shared_global_writes :@page, json_error: "shared_page_readonly" do
        admin_maintenance_page_path(current_customer_id, @page)
      end

      def update
        contract = ::Pages::VisibilityContract.new(@page)
        destination = safe_return_to || admin_maintenance_page_path(current_customer_id, @page)
        if contract.validate(visibility_params) && contract.save
          redirect_to destination, notice: t("maint_core.flash.page_visibilities.updated")
        else
          redirect_to destination,
                      alert: t("maint_core.flash.page_visibilities.update_failed", errors: contract.errors.full_messages.join("; "))
        end
      end

      private

      def find_page
        @page = definition_scope(Page).find(params[:page_id])
      end

      def visibility_params
        params.require(:page).permit(:action_key, visible_audiences: []).to_h
      end
    end
  end
end
