# frozen_string_literal: true

module Admin
  module Maintenance
    class FlowchartVersionsController < BaseVersionsController
      versioned_resource finder: -> { definition_scope(Flowchart).find(params[:flowchart_id]) },
                         ivar: :@flowchart

      before_action :guard_launched_version!, only: :destroy

      # GET .../versions/:id/edit — open this version in the flowchart editor.
      def edit
        @version = line_version
        @flowchart.configuration = @version.payload # in-memory only; not persisted
        @based_on_version_id = @version.id
        @editing_version = @version
        @design_entity = ::Flowcharts::DesignEntity.for(@flowchart, customer_id: shared_resources_mode? ? nil : current_customer_id)
        render template: "admin/maintenance/flowcharts/edit"
      end

      private

      # Tenant-path version writes operate on that customer's override line
      # (current_line_versions). Shared Resources mode writes the global line.
      # An empty override line 404s rather than rewriting the global default.
      def guard_write!; end

      # Live submissions run the launched version until another is launched.
      def guard_launched_version!
        return unless line_version.id == @flowchart.launched_version_id

        render json: {
          error: "launched_version_undeletable",
          message: t("maint_core.errors.versions.launched_undeletable")
        }, status: :unprocessable_entity
      end
    end
  end
end
