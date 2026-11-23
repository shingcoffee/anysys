# frozen_string_literal: true

module FlowchartElements
  class LoopElementComponent < BaseElementComponent
    def initialize(**args)
      super(element_type: :loop, **args)
    end

    private

    def default_label
      I18n.t("comp_misc.flowchart_elements.loop")
    end

    def element_specific_classes
      "bg-purple-50 border-purple-400 text-purple-800 hover:border-purple-600"
    end
  end
end
