# frozen_string_literal: true

module Pages
  # The flowchart that processes a page's submissions, and a picker to rebind
  # it. Platform owner only: render it behind FlowchartVisibility.
  class ProcessingCardComponent < ApplicationComponent
    attr_reader :page, :customer_id

    def initialize(page:, customer_id:, editable:)
      @page = page
      @customer_id = customer_id
      @editable = editable
    end

    def editable? = @editable
    def flowchart = page.flowchart
    def default_flowchart? = Flowcharts::DefaultPageFlowchart.default?(flowchart)
    def problems = @problems ||= Flowcharts::Compatibility.problems(flowchart, page.entity)

    def flowchart_path = helpers.admin_maintenance_flowchart_path(customer_id, flowchart)
    def update_path = helpers.admin_maintenance_page_flowchart_path(customer_id, page)

    def options
      page.bindable_flowcharts.by_name.map do |candidate|
        label = candidate.launched? ? candidate.name : t("comp_misc.page_processing.draft_option", name: candidate.name)
        [label, candidate.id]
      end
    end
  end
end
