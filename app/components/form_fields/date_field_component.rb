# frozen_string_literal: true

module FormFields
  class DateFieldComponent < BaseFieldComponent
    private

    def field_type
      :date
    end

    def render_input
      tag.input(**input_attributes.merge(type: "date"))
    end
  end
end
