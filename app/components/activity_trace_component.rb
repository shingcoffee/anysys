# frozen_string_literal: true

class ActivityTraceComponent < ApplicationComponent
  attr_reader :flowchart

  def initialize(flowchart:)
    @flowchart = flowchart
  end

  def render?
    flowchart.activity.present?
  end

  def trace_url
    helpers.admin_maintenance_flowchart_traces_path(effective_customer_id, flowchart)
  end

  # Returns the effective customer_id for URL generation
  # For custom flowcharts: uses the flowchart's customer_id
  # For blueprints (shared): uses the current customer's ID
  def effective_customer_id
    flowchart.customer_id || Current.customer_id
  end
end
