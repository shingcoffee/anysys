# frozen_string_literal: true

module Flowcharts
  # Launch lifecycle card for the flowchart detail show surface — mirrors the
  # pages DistributionCard header pattern (status + launch/take-offline) without
  # audience visibility rows, which do not apply to flowcharts.
  class LifecycleCardComponent < ViewComponent::Base
    def initialize(flowchart:, customer_id:, launch_editable: true)
      @flowchart       = flowchart
      @customer_id     = customer_id
      @launch_editable = launch_editable
    end

    def launch_path
      helpers.admin_maintenance_flowchart_launch_path(customer_id, flowchart)
    end

    def launch_editable?
      @launch_editable
    end

    def hint
      if flowchart.pending_draft?
        t("comp_misc.flowchart_lifecycle.pending_hint", live: flowchart.launched_version.version_number,
                                                        draft: flowchart.current_version.version_number)
      elsif flowchart.launched?
        t("comp_misc.flowchart_lifecycle.launched_edit_hint")
      else
        t("comp_misc.flowchart_lifecycle.draft_hint")
      end
    end

    private

    attr_reader :flowchart, :customer_id
  end
end
