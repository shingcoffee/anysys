# frozen_string_literal: true

module Flowcharts
  # Editor banner for a launched flowchart: the version live pages run, and
  # that saving stages a draft version which goes live when it is launched.
  class LaunchedNoticeComponent < ApplicationComponent
    def initialize(flowchart:, customer_id:)
      @flowchart = flowchart
      @customer_id = customer_id
    end

    def render?
      flowchart.launched? && flowchart.launched_version.present?
    end

    def message
      live = flowchart.launched_version.version_number
      if flowchart.pending_draft?
        t("maint_core.flowcharts.editor.launched_draft_notice", live: live, draft: flowchart.current_version.version_number)
      else
        t("maint_core.flowcharts.editor.launched_edit_notice", live: live)
      end
    end

    def launch_path
      helpers.admin_maintenance_flowchart_launch_path(customer_id, flowchart)
    end

    private

    attr_reader :flowchart, :customer_id
  end
end
