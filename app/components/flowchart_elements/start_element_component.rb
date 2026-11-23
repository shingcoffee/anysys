# frozen_string_literal: true

module FlowchartElements
  class StartElementComponent < BaseElementComponent
    def initialize(**args)
      super(element_type: :start, **args)
    end

    private

    def default_label
      I18n.t("comp_misc.flowchart_elements.start")
    end

    def element_specific_classes
      "bg-green-50 border-green-400 text-green-800 hover:border-green-600"
    end
  end
end
