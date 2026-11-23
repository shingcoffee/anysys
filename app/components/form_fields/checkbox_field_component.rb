# frozen_string_literal: true

module FormFields
  class CheckboxFieldComponent < BaseFieldComponent
    attr_reader :checked

    def initialize(checked: false, **args)
      super(**args)
      @checked = checked
    end

    private

    def field_type
      :checkbox
    end

    def wrapper_classes
      "w-full"
    end

    def input_classes
      palette = color_palette(theme)
      "w-4 h-4 #{palette[:text]} border-gray-300 #{palette[:ring]} focus:ring-2 rounded transition-colors cursor-pointer"
    end

    def checkbox_classes
      input_classes
    end

    def render_input
      if input_only
        return tag.input(**input_attributes.merge(type: "checkbox", checked: checked, value: "1"))
      end

      tag.div(class: "flex items-center") do
        safe_join([
          tag.input(
            type: "checkbox",
            name: field_name,
            id: field_id,
            class: checkbox_classes,
            checked: checked,
            value: "1"
          ),
          tag.label(label, for: field_id, class: "ml-2 text-sm text-gray-700")
        ])
      end
    end
  end
end
