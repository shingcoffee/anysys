# frozen_string_literal: true

module FormFields
  class DateTimeFieldComponent < BaseFieldComponent
    private

    def field_type
      :datetime
    end

    def render_input
      tag.input(**input_attributes.merge(type: "datetime-local"))
    end
  end
end
