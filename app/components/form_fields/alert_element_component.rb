# frozen_string_literal: true

module FormFields
  class AlertElementComponent < BaseElementComponent
    VARIANTS = {
      "info"    => { bg: "bg-blue-50", border: "border-blue-200", text: "text-blue-800", icon_color: "text-blue-400" },
      "warning" => { bg: "bg-yellow-50", border: "border-yellow-200", text: "text-yellow-800", icon_color: "text-yellow-400" },
      "success" => { bg: "bg-green-50", border: "border-green-200", text: "text-green-800", icon_color: "text-green-400" },
      "danger"  => { bg: "bg-red-50", border: "border-red-200", text: "text-red-800", icon_color: "text-red-400" }
    }.freeze

    ICONS = {
      "info"    => '<path stroke-linecap="round" stroke-linejoin="round" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />',
      "warning" => '<path stroke-linecap="round" stroke-linejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />',
      "success" => '<path stroke-linecap="round" stroke-linejoin="round" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />',
      "danger"  => '<path stroke-linecap="round" stroke-linejoin="round" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />'
    }.freeze

    attr_reader :content_text, :variant

    def initialize(content_text:, variant: "info", theme: {})
      super(theme: theme)
      @content_text = content_text
      @variant = variant
    end

    def variant_config
      VARIANTS[variant] || VARIANTS["info"]
    end

    def icon_svg
      ICONS[variant] || ICONS["info"]
    end
  end
end
