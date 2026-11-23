# frozen_string_literal: true

module Admin
  module Maintenance
    class FlowchartLaunchesController < ApplicationController
      include SharedResourceMode
      dashboard_menu_item :maintenance
      before_action :find_flowchart
      guard_shared_global_writes :@flowchart, json_error: "shared_flowchart_readonly" do
        admin_maintenance_flowchart_path(current_customer_id, @flowchart)
      end

      # Launches a draft flowchart, or publishes the draft version saved above
      # a launched one.
      def create
        if @flowchart.launched? && !@flowchart.pending_draft?
          flash[:alert] = t("maint_core.flash.flowchart_launches.already_launched")
          redirect_to admin_maintenance_flowchart_path(current_customer_id, @flowchart), status: :unprocessable_entity
          return
        end

        validation_result = FlowchartInputOutputValidator.call(@flowchart)
        return reject_launch(t("maint_core.flash.flowchart_launches.launch_failed", count: validation_result.errors.size)) if validation_result.errors.any?

        server_errors = server_validation_errors
        return reject_launch(t("maint_core.flash.flowchart_launches.problems_found", count: server_errors.size)) if server_errors.any?

        @flowchart.launch!
        redirect_to admin_maintenance_flowchart_path(current_customer_id, @flowchart), notice: t("maint_core.flash.flowchart_launches.launched")
      end

      def destroy
        if @flowchart.draft?
          flash[:alert] = t("maint_core.flash.flowchart_launches.already_draft")
          redirect_to admin_maintenance_flowchart_path(current_customer_id, @flowchart), status: :unprocessable_entity
        elsif @flowchart.update(status: :draft)
          redirect_to admin_maintenance_flowchart_path(current_customer_id, @flowchart),
                      notice: t("maint_core.flash.flowchart_launches.taken_offline")
        else
          redirect_to admin_maintenance_flowchart_path(current_customer_id, @flowchart),
                      alert: @flowchart.errors.full_messages.to_sentence
        end
      end

      private

      def find_flowchart
        @flowchart = definition_scope(Flowchart).find(params[:flowchart_id])
      end

      # The validator writes the configuration onto the record it is given, so
      # it gets its own copy; @flowchart is saved on launch.
      def server_validation_errors
        copy = definition_scope(Flowchart).find(@flowchart.id)
        FlowchartServerValidator.new(copy, copy.configuration_json).call
                                .select { |problem| problem[:severity] == "error" }
      end

      def reject_launch(alert)
        redirect_to edit_admin_maintenance_flowchart_path(current_customer_id, @flowchart, show_validation: true), alert: alert
      end
    end
  end
end
