# frozen_string_literal: true

module Admin
  module Maintenance
    class FlowchartCopiesController < ApplicationController
      include SharedResourceMode
      dashboard_menu_item :maintenance

      def show
        source = definition_scope(Flowchart).find(params[:flowchart_id])
        require_copyable_source!(source)

        @flowchart = Flowchart.new_with_defaults(name: I18n.t("maint_core.entities.copy_name", name: source.name))
        @flowchart.configuration = source.configuration
        @flowchart.description   = source.description
        apply_create_identity!(@flowchart)
        render "admin/maintenance/flowcharts/new"
      end
    end
  end
end
