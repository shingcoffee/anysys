# frozen_string_literal: true

module Journeys
  # Records what the current step produced (an update step, the record it
  # edited) and decides where the run goes. Skip leaves no record; later
  # steps that needed one, to fill from or to edit, are passed over. The
  # step's processing may also leave out later conditional steps (+skip+, the
  # keys skip_journey_steps parked on the outcome); the run remembers them
  # and passes over them, and over the steps that need their records.
  class Advance
    INTENTS = %w[continue add_another skip].freeze
    SKIP = "skip"
    Next = Data.define(:kind, :step)

    def self.call(...) = new(...).call

    # Whether submitting +step+ with +intent+ ends the journey, before the run
    # (nil on the first step) records it: what the step's processing reads as
    # ctx[:journey]["finishing"]. Steps this submit's own processing leaves
    # out are not known yet.
    def self.finishing?(journey:, step:, run:, intent:)
      return false if step.repeat && intent.to_s == "add_another"

      next_reachable(journey.steps_definition, step, (run&.records || {}).merge(step.key => [true]), run&.skipped).nil?
    end

    def self.next_reachable(definition, current, records, skipped = nil)
      left_out = Array(skipped)
      definition.steps.drop_while { |step| step.key != current.key }.drop(1)
                .find { |step| !step.finish? && left_out.exclude?(step.key) && step.needs.all? { |from| Array(records[from]).any? } }
    end

    def initialize(run:, entry:, intent: nil, skip: [])
      @run = run
      @entry = entry
      @intent = INTENTS.include?(intent.to_s) ? intent.to_s : "continue"
      @skip = Array(skip).map(&:to_s)
    end

    def call
      definition = @run.journey.steps_definition
      step = definition.step(@run.current_step)

      if @intent == SKIP
        return unless step&.optional
      else
        return finish(definition) unless step

        @run.record!(step.key, @entry.id) if @entry
        @run.skip!(left_out(definition, step))
        return Next.new(kind: :step, step: step) if step.repeat && @intent == "add_another"
      end

      upcoming = self.class.next_reachable(definition, step, @run.records, @run.skipped)
      return finish(definition) unless upcoming

      @run.update!(current_step: upcoming.key)
      Next.new(kind: :step, step: upcoming)
    end

    private

    # Only later steps the journey marks conditional can be left out.
    def left_out(definition, step)
      later = definition.steps.drop_while { |candidate| candidate.key != step.key }.drop(1)
      later.select(&:conditional?).map(&:key) & @skip
    end

    def finish(definition)
      @run.update!(status: :completed, current_step: definition.finish&.key)
      Next.new(kind: :finish, step: definition.finish)
    end
  end
end
