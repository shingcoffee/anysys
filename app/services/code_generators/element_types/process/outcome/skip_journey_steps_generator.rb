# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Outcome
        class SkipJourneyStepsGenerator < BaseGenerator
          generator_metadata do
            description "Leaves later steps of the visitor's current journey out by parking their keys on ctx[:submission_outcome] journey skip, which Journeys::Advance applies after a successful submit. Put this after save_model behind a decision (for example skip catering when the booking is not catering). Only steps the journey marks as skippable are left out, and so are steps that need their records. Use set_submission_outcome for flash copy and hand_off_to_module or request_payment for a destination. Reads the steps list. Does nothing when ctx[:journey] is missing. Invalid keys are rejected at design time."
            category :outcome
            version "1.1.0"
            presentation icon: "M13 5l7 7-7 7M5 5l7 7-7 7",
                        color: "teal", single_use: false, privileged: false
          end

          config_schema do
            list :steps, item: :literal, example: %w[catering],
                 description: "Keys of later journey steps to leave out, such as catering. Each key is lowercase letters, numbers, and underscores matching Journeys::Definition::KEY. Only steps the journey lets processing skip are actually skipped."
            validate do |cfg, errors|
              keys = Array(cfg["steps"]).map { |key| key.to_s.strip }
              if keys.empty?
                errors.add(:steps, :required)
              elsif keys.any? { |key| !Journeys::Definition::KEY.match?(key) }
                errors.add(:steps, :invalid_step_key)
              end
            end
          end

          def generate_body
            keys = Array(value(:steps)).map { |key| key.to_s.strip }.grep(Journeys::Definition::KEY)
            body("FlowchartRuntime::JourneySkips.request(ctx, steps: #{keys.inspect})")
          end
        end
      end
    end
  end
end
