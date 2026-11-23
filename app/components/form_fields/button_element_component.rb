# frozen_string_literal: true

module FormFields
  class ButtonElementComponent < BaseElementComponent
    STATIC_VARIANTS = {
      "secondary" => "text-gray-700 bg-white hover:bg-gray-50 border-gray-300",
      "outline"   => nil # resolved dynamically based on theme
    }.freeze

    SIZES = {
      "sm" => "px-3 py-1.5 text-xs",
      "md" => "px-5 py-2.5 text-sm",
      "lg" => "px-7 py-3 text-base"
    }.freeze

    attr_reader :content_text, :button_url, :button_variant, :button_size, :alignment

    def initialize(content_text:, button_url: "#", button_variant: "primary", button_size: "md", alignment: "left", theme: {})
      super(theme: theme)
      @content_text = content_text
      @button_url = button_url
      @button_variant = button_variant
      @button_size = button_size
      @alignment = alignment
    end

    def variant_classes
      case button_variant
      when "primary"
        pal = palette
        "text-white #{pal[:bg]} #{pal[:hover]} border-transparent"
      when "outline"
        pal = palette
        "#{pal[:text]} bg-transparent #{pal[:outline_hover]} border-current"
      else
        STATIC_VARIANTS["secondary"]
      end
    end

    def size_classes
      SIZES[button_size] || SIZES["md"]
    end

    def button_alignment_class
      alignment_class(alignment)
    end

    def radius_class
      resolve_radius_class(@theme)
    end
  end
end
