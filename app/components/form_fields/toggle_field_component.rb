# frozen_string_literal: true

module FormFields
  class ToggleFieldComponent < BaseFieldComponent
    attr_reader :description

    def initialize(description: nil, **args)
      super(**args)
      @description = description
    end

    def checked?
      value == true || value == "true" || value == "1" || value == 1
    end

    def toggle_track_classes
      palette = color_palette(theme)
      "w-11 h-6 bg-gray-200 rounded-full peer " \
        "peer-focus:ring-2 #{palette[:ring_color]} peer-focus:ring-offset-2 " \
        "peer-checked:after:translate-x-full peer-checked:after:border-white " \
        "after:content-[''] after:absolute after:top-0.5 after:left-[2px] " \
        "after:bg-white after:border-gray-300 after:border after:rounded-full " \
        "after:h-5 after:w-5 after:transition-all #{palette[:checked_track]} transition-colors duration-150"
    end

    private

    def field_type
      :checkbox
    end
  end
end
