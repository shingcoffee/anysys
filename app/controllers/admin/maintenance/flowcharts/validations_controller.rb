# frozen_string_literal: true

module Admin
  module Maintenance
    module Flowcharts
      # Stateless server-side validation for the editor's Validate button.
      # Accepts the in-memory canvas configuration (never persisted) and
      # returns structured problems from FlowchartServerValidator.
      #
      # Authorization: this is an admin URL (/:cid/admin/...), so the
      # RouteAuthorization concern on ApplicationController enforces
      # admin-or-owner centrally — per its contract, no per-controller
      # role filter is repeated here. Tenant scoping happens in
      # #find_flowchart below.
      class ValidationsController < ApplicationController
        dashboard_menu_item :maintenance

        # Runs OUTSIDE create's rescue so an out-of-scope id surfaces as the
        # standard 404, exactly like Admin::Maintenance::FlowchartsController.
        before_action :find_flowchart

        def create
          configuration = params.to_unsafe_h["configuration"]
          # to_unsafe_h is deliberate: element/connection shapes are arbitrary
          # user content; the hash is never mass-assigned or persisted — the
          # validator only mutates an in-memory copy of the flowchart.
          unless configuration.is_a?(Hash) && configuration["elements"].is_a?(Array)
            return render json: { problems: [] }, status: :unprocessable_entity
          end

          problems = FlowchartServerValidator.new(@flowchart, configuration).call
          render json: { problems: problems.map { |p| camelize_problem(p) } }
        rescue StandardError => e
          Rails.logger.error("[FlowchartValidation] #{e.class}: #{e.message}")
          render json: { problems: [] }, status: :unprocessable_entity
        end

        private

        # Same tenant-scoped lookup as FlowchartsController#find_flowchart:
        # the current tenant's own flowcharts plus platform-wide shared ones
        # (validation is read-only, so shared visibility is safe — the write
        # guard only applies to mutating CRUD actions). Anything else raises
        # RecordNotFound → 404, indistinguishable from a missing id.
        def find_flowchart
          @flowchart = Flowchart.accessible.find(params[:flowchart_id])
        end

        def camelize_problem(problem)
          {
            type: problem[:type],
            severity: problem[:severity],
            message: problem[:message],
            elementId: problem[:element_id],
            connectionId: problem[:connection_id],
            field: problem[:field],
            fixHint: problem[:fix_hint]
          }
        end
      end
    end
  end
end
