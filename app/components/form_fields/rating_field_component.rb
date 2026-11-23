# frozen_string_literal: true

module FormFields
  class RatingFieldComponent < BaseFieldComponent
    attr_reader :max

    def initialize(max: 5, **args)
      super(**args)
      @max = max.to_i
    end

    def current_value
      value.to_i
    end

    private

    def field_type
      :hidden
    end
  end
end
