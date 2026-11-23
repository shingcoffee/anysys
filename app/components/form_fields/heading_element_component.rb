# frozen_string_literal: true

module FormFields
  class HeadingElementComponent < BaseElementComponent
    LEVELS = {
      1 => "text-3xl font-bold tracking-tight",
      2 => "text-2xl font-bold tracking-tight",
      3 => "text-xl font-semibold",
      4 => "text-lg font-semibold",
      5 => "text-base font-semibold",
      6 => "text-sm font-semibold uppercase tracking-wide"
    }.freeze

    attr_reader :text, :level, :alignment

    def initialize(text:, level: 2, alignment: "left", theme: {})
      super(theme: theme)
      @text = text
      @level = level.to_i.clamp(1, 6)
      @alignment = alignment
    end

    def heading_tag
      "h#{level}"
    end

    def heading_classes
      base = LEVELS[level] || LEVELS[2]
      "#{base} #{alignment_class(alignment)} #{neutral(:strong_text)}"
    end

    def wrapper_margin
      resolve_heading_top_margin(@theme)
    end
  end
end
