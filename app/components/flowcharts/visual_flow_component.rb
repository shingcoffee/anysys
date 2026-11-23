# frozen_string_literal: true

module Flowcharts
  # "Visual Flow" card on the flowchart show page: the compiled activity drawn
  # by Mermaid, a legend of the shapes in use, and a switch that adds the
  # failure paths every step shares.
  class VisualFlowComponent < ApplicationComponent
    # Swatches match ActivityDiagramGenerator::MermaidRenderer::CLASS_DEFS.
    LEGEND = {
      start: { label: "start", swatch: "rounded-full bg-green-50 border-green-500" },
      step: { label: "process", swatch: "rounded-md bg-blue-50 border-blue-400" },
      decision: { label: "decision", swatch: "rotate-45 scale-75 bg-yellow-50 border-yellow-400" },
      loop: { label: "loop", swatch: "rounded-sm bg-purple-50 border-purple-400" },
      subflow: { label: "subflow", swatch: "border-x-4 bg-indigo-50 border-indigo-400" },
      end: { label: "end", swatch: "rounded-full bg-red-50 border-red-400" }
    }.freeze

    def initialize(flowchart:)
      @flowchart = flowchart
    end

    def graph
      return @graph if defined?(@graph)

      @graph = ActivityDiagramGenerator.new(drawn_flowchart).graph
    end

    def legend
      graph.kinds.filter_map do |kind|
        entry = LEGEND[kind]
        entry && { label: t("maint_core.flowcharts.editor.element_default_labels.#{entry[:label]}"), swatch: entry[:swatch] }
      end
    end

    private

    # The activity column holds the launched version's code, so a pending
    # draft's elements would mislabel it.
    def drawn_flowchart
      @flowchart.pending_draft? ? FlowchartRuntime::RuntimeFlowchart.new(@flowchart) : @flowchart
    end
  end
end
