# frozen_string_literal: true

module FormFields
  class RadioFieldComponent < BaseFieldComponent
    attr_reader :options, :layout

    def initialize(options: [], layout: "vertical", **args)
      super(**args)
      @options = options || []
      @layout = layout
    end

    private

    def field_type
      :radio
    end

    def container_classes
      layout == "inline" ? "flex flex-wrap gap-4" : "space-y-2"
    end

    def radio_input_classes
      palette = color_palette(theme)
      "w-4 h-4 #{palette[:text]} border-gray-300 #{palette[:ring]} focus:ring-2 " \
        "transition-colors cursor-pointer"
    end

    def radio_option_wrapper_classes
      "flex items-center gap-2 cursor-pointer group py-0.5 px-1 rounded " \
        "hover:bg-gray-50 transition-colors duration-100"
    end
  end
end
