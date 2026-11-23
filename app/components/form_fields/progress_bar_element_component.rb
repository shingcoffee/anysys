# frozen_string_literal: true

module FormFields
  class ProgressBarElementComponent < BaseElementComponent
    COLORS = {
      "indigo" => "bg-indigo-600",
      "green"  => "bg-green-600",
      "blue"   => "bg-blue-600",
      "red"    => "bg-red-600"
    }.freeze

    attr_reader :label, :progress_value, :progress_color

    def initialize(label: "", progress_value: 0, progress_color: "indigo", theme: {})
      super(theme: theme)
      @label = label
      @progress_value = progress_value.to_i.clamp(0, 100)
      @progress_color = progress_color
    end

    def color_class
      COLORS[progress_color] || palette[:bg]
    end

    def label_present?
      label.present?
    end
  end
end
