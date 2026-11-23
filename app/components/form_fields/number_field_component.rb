# frozen_string_literal: true

module FormFields
  class NumberFieldComponent < BaseFieldComponent
    attr_reader :min, :max, :step

    def initialize(min: nil, max: nil, step: nil, **args)
      super(**args)
      @min = min
      @max = max
      @step = step
    end

    private

    def field_type
      :number
    end

    def render_input
      attrs = input_attributes.merge(type: "number")
      attrs[:min] = min if min
      attrs[:max] = max if max
      attrs[:step] = step if step
      tag.input(**attrs)
    end
  end
end
