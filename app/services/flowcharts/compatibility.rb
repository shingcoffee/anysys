# frozen_string_literal: true

module Flowcharts
  # Whether a flowchart can process an entity's page submissions: every
  # attribute its steps name must exist on that entity. A flowchart compiles
  # without an entity, so this runs per page (when it launches or a live page
  # is rebound) against the definition the page's tenant runs.
  module Compatibility
    module_function

    # The code generator's reasons, which name the flowchart and its steps:
    # show them to the platform owner only. Empty when compatible.
    def problems(flowchart, entity)
      return [] unless flowchart && entity

      runtime = FlowchartRuntime::RuntimeFlowchart.new(flowchart)
      ActivityGenerator.new(runtime, entity: entity).generate
      []
    rescue ActivityGenerator::Error => e
      [located(runtime, e, [e.message, *e.details].join(" — "))]
    end

    # Names the step at fault, so whoever fixes the flowchart knows where.
    def located(runtime, error, text)
      element = runtime&.elements&.find { |candidate| candidate["id"] == error.element_id } if error.element_id
      return text unless element

      I18n.t("maint_core.flowcharts.config_problems.step_invalid",
             step: element["label"].presence || element["id"],
             action: FlowchartDefinitions::ActionLabel.for(error.action.presence || element["type"]),
             error: text)
    end
    private_class_method :located

    # Messages any admin may read; empty when compatible.
    def errors(flowchart, entity)
      return [] if problems(flowchart, entity).empty?

      [I18n.t("maint_core.errors.page_launch.submission_process_incompatible", entity: entity.display_label)]
    end
  end
end
