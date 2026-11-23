# frozen_string_literal: true

module Flowcharts
  # Top toolbar for the flowchart editor: zoom controls, undo/redo, save,
  # and overflow actions (auto-layout, export, clear). Wired entirely through
  # Stimulus `toolbar` and `flowchart-canvas` controllers — no server-side
  # interactivity required.
  class ToolbarComponent < ApplicationComponent
    attr_reader :flowchart

    def initialize(flowchart:)
      @flowchart = flowchart
    end

    private

    def flowchart_path
      customer_id = flowchart.customer_id || helpers.current_customer_id
      helpers.admin_maintenance_flowchart_path(customer_id, flowchart)
    end

    def launch_path
      customer_id = flowchart.customer_id || helpers.current_customer_id
      helpers.admin_maintenance_flowchart_launch_path(customer_id, flowchart)
    end
  end
end
