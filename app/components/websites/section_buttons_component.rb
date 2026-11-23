# frozen_string_literal: true

module Websites
  # Primary + secondary call-to-action pair read from `<key>_label` /
  # `<key>_href` props. A label without a resolvable href renders as a span.
  class SectionButtonsComponent < PublicComponent
    def initialize(section:, primary_key: "primary", secondary_key: "secondary", align: :start, secondary_class: nil)
      @section = section
      @theme = section.theme
      @customer_id = section.customer_id
      @primary_key = primary_key
      @secondary_key = secondary_key
      @align = align.to_sym
      @secondary_class = secondary_class
    end

    def buttons
      @buttons ||= [
        button(@primary_key, @section.primary_button_class, :primary),
        button(@secondary_key, @secondary_class || @section.secondary_button_class, :secondary)
      ].compact
    end

    def render?
      buttons.any?
    end

    def wrapper_class
      justify = @align == :center ? "sm:justify-center" : "sm:justify-start"
      "flex w-full flex-col items-stretch gap-3 sm:w-auto sm:flex-row sm:items-center #{justify}"
    end

    private

    def button(key, css_class, role)
      label = @section.prop("#{key}_label")
      return unless present_text?(label)

      { label: label, href: @section.resolved_href("#{key}_href"), css_class: css_class, style: @section.styler.button_css(role) }
    end
  end
end
