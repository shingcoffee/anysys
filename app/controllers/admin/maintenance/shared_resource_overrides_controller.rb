# frozen_string_literal: true

module Admin
  module Maintenance
    # Drop the current customer's override of a shared definition resource so
    # reads fall back to the global default. Nested under constants / entities /
    # flowcharts / pages; the parent param selects the record.
    class SharedResourceOverridesController < ApplicationController
      dashboard_menu_item :maintenance
      before_action :find_record

      PARENTS = {
        "constant_id"  => Constant,
        "entity_id"    => Entity,
        "flowchart_id" => Flowchart,
        "page_id"      => Page
      }.freeze

      def destroy
        cleared = @record.reset_customer_override!(current_customer_id)

        respond_to do |format|
          format.html do
            if cleared
              redirect_to record_show_path,
                          notice: t("maint_core.flash.shared_resources.override_reverted")
            else
              redirect_to record_show_path,
                          alert: t("maint_core.flash.shared_resources.override_missing")
            end
          end
          format.json do
            if cleared
              render json: { success: true }
            else
              render json: { success: false }, status: :unprocessable_entity
            end
          end
        end
      end

      private

      def find_record
        param, klass = PARENTS.find { |key, _| params[key].present? }
        raise ActiveRecord::RecordNotFound unless param

        record = klass.accessible.find(params[param])
        raise ActiveRecord::RecordNotFound unless record.shared?

        @record = record
      end

      def record_show_path
        public_send(
          "admin_maintenance_#{@record.model_name.singular}_path",
          current_customer_id,
          @record
        )
      end
    end
  end
end
