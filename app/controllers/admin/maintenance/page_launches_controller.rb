# frozen_string_literal: true

module Admin
  module Maintenance
    class PageLaunchesController < ApplicationController
      include SharedResourceMode
      dashboard_menu_item :maintenance
      include SafeReturnTo
      before_action :find_page
      guard_shared_global_writes :@page, json_error: "shared_page_readonly" do
        admin_maintenance_page_path(current_customer_id, @page)
      end

      def create
        errors = @page.launch_errors
        if errors.any?
          redirect_to(safe_return_to || edit_admin_maintenance_page_path(current_customer_id, @page),
                      alert: t("maint_core.flash.page_launches.launch_failed", errors: errors.join("; ")))
          return
        end
        @page.launch!
        redirect_to(safe_return_to || admin_maintenance_page_path(current_customer_id, @page),
                    notice: t("maint_core.flash.page_launches.launched"))
      end

      def destroy
        @page.take_offline!
        redirect_to(safe_return_to || admin_maintenance_page_path(current_customer_id, @page),
                    notice: t("maint_core.flash.page_launches.taken_offline"))
      end

      private

      def find_page
        @page = definition_scope(Page).find(params[:page_id])
      end
    end
  end
end
