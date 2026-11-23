# frozen_string_literal: true

module Journeys
  # Launch checks beside the builder's details. `issues: nil` hides the card;
  # an empty list is ready; strings are the blockers to fix first.
  class ReadinessComponent < ApplicationComponent
    CHECK = "M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
    WARNING = "M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"

    def initialize(issues:)
      @issues = issues
    end

    def render? = !@issues.nil?
    def ready? = @issues.empty?
  end
end
