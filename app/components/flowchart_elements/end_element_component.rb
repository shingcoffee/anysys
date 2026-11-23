# frozen_string_literal: true

module FlowchartElements
  class EndElementComponent < BaseElementComponent
    def initialize(**args)
      super(element_type: :end, **args)
    end

    private

    def default_label
      I18n.t("comp_misc.flowchart_elements.end")
    end

    def element_specific_classes
      "bg-red-50 border-red-400 text-red-800 hover:border-red-600"
    end
  end
end
