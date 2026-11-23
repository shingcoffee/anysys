# frozen_string_literal: true

module FormFields
  class EmailFieldComponent < BaseFieldComponent
    private

    def field_type
      :email
    end

    def render_input
      tag.input(**input_attributes.merge(type: "email"))
    end
  end
end
