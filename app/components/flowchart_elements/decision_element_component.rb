# frozen_string_literal: true

module FlowchartElements
  class DecisionElementComponent < BaseElementComponent
    def initialize(**args)
      super(element_type: :decision, **args)
    end

    private

    def default_label
      I18n.t("comp_misc.flowchart_elements.decision")
    end

    def element_specific_classes
      "bg-yellow-50 border-yellow-400 text-yellow-800 hover:border-yellow-600"
    end
  end
end
