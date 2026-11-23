# frozen_string_literal: true

module FormFields
  class SpacerElementComponent < BaseElementComponent
    HEIGHTS = {
      "sm" => "h-4",
      "md" => "h-8",
      "lg" => "h-12",
      "xl" => "h-20"
    }.freeze

    attr_reader :height

    def initialize(height: "md", theme: {})
      super(theme: theme)
      @height = height
    end

    def height_class
      HEIGHTS[height] || HEIGHTS["md"]
    end
  end
end
