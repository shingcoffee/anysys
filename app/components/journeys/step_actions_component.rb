# frozen_string_literal: true

module Journeys
  # Extra submits beside a journey step's save button: Skip when the step is
  # optional, then "Save and add another" when it repeats.
  class StepActionsComponent < ApplicationComponent
    def self.for(step) = (new(step: step) if step && (step.optional || step.repeat))

    def initialize(step:)
      @step = step
    end

    def render? = @step && (@step.optional || @step.repeat)
    def skip? = @step&.optional == true
    def repeat? = @step&.repeat == true
  end
end
