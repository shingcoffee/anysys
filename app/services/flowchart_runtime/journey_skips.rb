# frozen_string_literal: true

module FlowchartRuntime
  # Leaves later steps of the visitor's journey out: parks their keys on
  # ctx[:submission_outcome]["journey"]["skip"], which Journeys::Advance
  # applies once the submit succeeds, to the steps the journey marks as ones
  # processing may skip. Outside a journey it does nothing.
  module JourneySkips
    module_function

    def request(ctx, steps:)
      return true unless ctx[:journey].is_a?(Hash)

      keys = Array(steps).map { |key| key.to_s.strip }.grep(Journeys::Definition::KEY)
      return true if keys.empty?

      outcome = (ctx[:submission_outcome] || {}).to_h.stringify_keys
      journey = outcome["journey"].is_a?(Hash) ? outcome["journey"] : {}
      outcome["journey"] = journey.merge("skip" => (Array(journey["skip"]) | keys))
      ctx[:submission_outcome] = outcome
      true
    end
  end
end
