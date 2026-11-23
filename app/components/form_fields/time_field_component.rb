# frozen_string_literal: true

module FormFields
  class TimeFieldComponent < BaseFieldComponent
    attr_reader :min, :max, :step

    def initialize(min: nil, max: nil, step: nil, **args)
      super(**args)
      @min = min
      @max = max
      @step = step
    end

    private

    def field_type
      :time
    end

    def input_attributes
      base = super
      base[:type] = "time"
      base[:min] = min if min.present?
      base[:max] = max if max.present?
      base[:step] = step if step.present?
      base
    end
  end
end
