# frozen_string_literal: true

module FlowchartElements
  class ProcessElementComponent < BaseElementComponent
    def initialize(**args)
      super(element_type: :process, **args)
    end

    private

    def default_label
      I18n.t("comp_misc.flowchart_elements.process")
    end

    def element_specific_classes
      "bg-blue-50 border-blue-400 text-blue-800 hover:border-blue-600"
    end
  end
end
