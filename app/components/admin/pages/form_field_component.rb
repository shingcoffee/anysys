# frozen_string_literal: true

module Admin
  module Pages
    # A page-form input drawn exactly like an entity entry form field. The page
    # generator supplies the submitted name and the element id; cleared
    # checkboxes and multi-selects post nothing, as on every other page surface.
    class FormFieldComponent < Admin::Entities::EntryFieldComponent
      def initialize(id:, slug:, field_name:, label:, html_type:, value: nil, required: false, help_text: nil,
                     options: [], placeholder: nil, quick_add: nil, data: nil, errors: [])
        field = ::Entities::EntryForm::Field.new(
          slug: slug, label: label, help_text: help_text, html_type: html_type, required: required,
          options: options, constraints: {}, full_width: false, invalid_literal: false
        )
        super(field: field, value: value, errors: errors, quick_add: quick_add)
        @id = id
        @field_name = field_name
        @placeholder = placeholder
        @data = data
      end

      def field_id = @id
      def field_name = @field_name
      def cleared_value = nil

      private

      def control_options
        options = super
        options[:placeholder] = @placeholder if @placeholder.present?
        options[:data] = @data if @data.present?
        options
      end
    end
  end
end
