# frozen_string_literal: true

module Admin
  module Maintenance
    class PageRestorationsController < ApplicationController
      include SharedResourceMode
      dashboard_menu_item :maintenance

      def update
        page = deleted_definition_scope(Page).find(params[:page_id])

        if page.restore
          respond_to do |format|
            format.html { redirect_to admin_maintenance_pages_url(current_customer_id), notice: t("maint_core.flash.page_restorations.restored", name: page.name) }
            format.json { render json: { status: "success", id: page.id }, status: :ok }
          end
        else
          respond_to do |format|
            format.html { redirect_to admin_maintenance_pages_url(current_customer_id), alert: page.errors.full_messages.to_sentence.presence || t("maint_core.flash.page_restorations.restore_failed") }
            format.json { render json: { status: "error", errors: page.errors.full_messages }, status: :unprocessable_entity }
          end
        end
      rescue ActiveRecord::RecordNotFound
        respond_to do |format|
          format.html { redirect_to admin_maintenance_pages_url(current_customer_id), alert: t("maint_core.flash.page_restorations.not_found") }
          format.json { render json: { status: "error", message: t("maint_core.flash.page_restorations.not_found_message") }, status: :not_found }
        end
      end
    end
  end
end
