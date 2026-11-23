# frozen_string_literal: true

# ActivityDiagramGenerator
#
# Draws a flowchart's compiled activity — the stored Ruby that actually runs —
# as a Mermaid flowchart. CircuitReader turns the Railway circuit into a
# Graph mapped back to the canvas; MermaidRenderer writes the source.
#
# @example
#   graph = ActivityDiagramGenerator.new(flowchart).graph
#   graph.to_mermaid                      # the designed path
#   graph.to_mermaid(failure_paths: true) # plus every route to Failure
#
class ActivityDiagramGenerator
  include ActivityClassBuilder
  include Loggable

  attr_reader :flowchart

  def initialize(flowchart)
    @flowchart = flowchart
  end

  # @return [Graph, nil] nil when there is no activity or it does not load
  def graph
    return if flowchart.activity.blank?

    activity_class = build_activity_class(flowchart.activity, flowchart: flowchart)
    activity_class && CircuitReader.new(activity_class, flowchart).call
  rescue StandardError => e
    log_error e.message
    nil
  end

  def generate(failure_paths: false)
    graph&.to_mermaid(failure_paths: failure_paths)
  end
end
