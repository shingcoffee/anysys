# frozen_string_literal: true

module FormFields
  class BaseFieldComponent < ApplicationComponent
    include ThemeResolver

    attr_reader :field_name, :label, :placeholder, :required, :width, :value, :html_attributes, :theme, :input_only

    def initialize(
      field_name:,
      label: nil,
      placeholder: nil,
      required: false,
      width: "full",
      value: nil,
      theme: {},
      input_only: false,
      **html_attributes
    )
      @field_name = field_name
      @label = label || field_name.to_s.humanize
      @placeholder = placeholder
      @required = required
      @width = width
      @value = value
      @theme = theme
      @input_only = input_only
      @html_attributes = html_attributes
    end

    private

    def field_type
      :text
    end

    def hidden_input?
      false
    end

    def wrapper_classes
      "w-full"
    end

    def label_classes
      resolve_label_classes(theme)
    end

    def input_classes
      resolve_input_classes(theme)
    end

    def required_indicator
      return "" unless required

      content_tag :span, "*", class: "text-red-500 ml-0.5"
    end

    def input_attributes
      base = {
        name: field_name,
        id: field_id,
        # Adapters compose their own label, layout and control chrome.
        class: (input_classes unless input_only),
        placeholder: placeholder,
        required: required,
        value: value
      }

      merge_html_attributes(base, html_attributes)
    end

    def field_id
      html_attributes[:id] || "field_#{field_name.to_s.parameterize(separator: '_')}"
    end
  end
end
