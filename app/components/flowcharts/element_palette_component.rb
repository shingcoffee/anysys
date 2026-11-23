# frozen_string_literal: true

module Flowcharts
  # Left sidebar element palette for the flowchart editor: draggable element
  # tiles (Start, Process, Decision, etc.) and a live-loaded list of existing
  # flowcharts that can be embedded as sub-flows. Wired to the Stimulus
  # `element-palette` controller.
  class ElementPaletteComponent < ApplicationComponent
    attr_reader :flowchart

    def initialize(flowchart:)
      @flowchart = flowchart
    end
  end
end
