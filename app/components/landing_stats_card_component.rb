# frozen_string_literal: true

class LandingStatsCardComponent < ApplicationComponent
  def initialize(label:, value:, sub_label: nil, icon: nil, compact: false)
    @label = label
    @value = value
    @sub_label = sub_label
    @icon = icon
    @compact = compact
  end
  attr_reader :label, :value, :sub_label, :icon

  def compact?
    @compact
  end
end
