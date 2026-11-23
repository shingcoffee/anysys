# frozen_string_literal: true

module Emails
  class SparklineComponent < ApplicationComponent
    WIDTH = 300
    HEIGHT = 40

    TONE_CLASSES = {
      "accent"  => "text-accent",
      "success" => "text-success",
      "danger"  => "text-danger",
      "info"    => "text-info",
      "warning" => "text-warning"
    }.freeze

    LEGACY_TONES = {
      "indigo"  => "accent",
      "emerald" => "success",
      "rose"    => "danger",
      "sky"     => "info",
      "pink"    => "accent"
    }.freeze

    attr_reader :values, :tone, :width, :height

    def initialize(values:, color: nil, tone: "accent", width: WIDTH, height: HEIGHT)
      @values = values
      resolved = LEGACY_TONES[color.to_s] || tone.to_s
      @tone = TONE_CLASSES.key?(resolved) ? resolved : "accent"
      @width = width
      @height = height
    end

    def tone_class
      TONE_CLASSES.fetch(tone)
    end

    def points
      return "" if values.empty?

      max = values.max || 0
      max = 1 if max.zero?

      values.map.with_index do |val, i|
        x = (i.to_f / [values.size - 1, 1].max) * width
        y = height - ((val.to_f / max) * height)
        y = [[y, 2].max, height - 2].min
        "#{x},#{y}"
      end.join(" ")
    end

    def fill_points
      "0,#{height} #{points} #{width},#{height}"
    end
  end
end
