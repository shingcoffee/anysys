# frozen_string_literal: true

module FormFields
  class TextareaFieldComponent < BaseFieldComponent
    attr_reader :rows

    def initialize(rows: 3, **args)
      super(**args)
      @rows = rows
    end

    private

    def field_type
      :textarea
    end

    def input_classes
      "#{super} resize-none"
    end

    def render_input
      content_tag :textarea, value, **input_attributes.merge(rows: rows).except(:value)
    end
  end
end
