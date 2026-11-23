# frozen_string_literal: true

module Journeys
  # "Save and add another" beside a repeatable journey step's submit button:
  # it submits the form with `_intent=add_another`, so the run stays on the
  # step (Journeys::Advance).
  class RepeatButtonComponent < ApplicationComponent
    # The button for a form's extra action slot, or nil when the step doesn't repeat.
    def self.for(step) = (new(step: step) if step&.repeat)

    def initialize(step:)
      @step = step
    end

    def render? = @step&.repeat == true
  end
end
