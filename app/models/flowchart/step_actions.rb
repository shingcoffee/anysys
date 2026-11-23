# frozen_string_literal: true

# Reads the step actions off whatever #elements the includer exposes, so a
# FlowchartRuntime::RuntimeFlowchart answers from the definition its tenant
# actually runs.
module Flowchart::StepActions
  # Step actions used anywhere on the canvas (process steps).
  def step_actions
    elements.flat_map { |element| Array(element.dig("properties", "steps")) }
            .filter_map { |step| step["action"].to_s.presence if step.is_a?(Hash) }
            .uniq
  end

  # Whether a run ends by handing the visitor off to a module.
  def hands_off?
    step_actions.intersect?(FlowchartRuntime::Handoff::ACTIONS)
  end
end
