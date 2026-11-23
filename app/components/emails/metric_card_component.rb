# frozen_string_literal: true

module Emails
  class MetricCardComponent < ApplicationComponent
    TONE_BORDERS = {
      "sent"         => "border-l-accent",
      "delivered"    => "border-l-success",
      "bounced"      => "border-l-danger",
      "complained"   => "border-l-warning",
      "suppressed"   => "border-l-warning",
      "opened"       => "border-l-info",
      "clicked"      => "border-l-accent",
      "unsubscribed" => "border-l-border-strong",
      "failed"       => "border-l-danger",
      "accent"       => "border-l-accent",
      "success"      => "border-l-success",
      "danger"       => "border-l-danger",
      "warning"      => "border-l-warning",
      "info"         => "border-l-info"
    }.freeze

    attr_reader :label, :value, :border_class

    def initialize(label:, value:, tone: nil, border_class: nil)
      @label = label
      @value = value
      @border_class = border_class.presence || TONE_BORDERS.fetch(tone.to_s, "border-l-accent")
    end
  end
end
