# frozen_string_literal: true

module FormFields
  class TextFieldComponent < BaseFieldComponent
    INPUT_TYPES = %w[text search password hidden tel url color].freeze

    def initialize(input_type: "text", **args)
      super(**args)
      @input_type = INPUT_TYPES.include?(input_type) ? input_type : "text"
    end

    private

    def field_type
      :text
    end

    def render_input
      attributes = input_attributes.merge(type: @input_type)
      attributes[:value] = nil if @input_type == "password"
      tag.input(**attributes)
    end

    def hidden_input?
      @input_type == "hidden"
    end
  end
end
