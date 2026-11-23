# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module SchedulingTime
        class DeadlineCheckGenerator < BaseGenerator
          FORMATS = FlowchartRuntime::Deadline::FORMATS
          BEHAVIORS = %w[mark fail].freeze

          generator_metadata do
            description "Compares a deadline in ctx against a clock for SLA handling (due dates, booking cutoffs). Use business_hours_check for weekly opening hours. Reads deadlineVariable (Time or string; deadlineFormat iso8601/rfc2822/auto). Optional referenceTime (blank = now), gracePeriodSeconds, and warningSeconds. Writes {passed, remaining_seconds, overdue_seconds} to resultVar, a boolean to breachedVar, and a boolean to atRiskVar. behaviorOnBreach 'mark' (default) always succeeds; 'fail' fails with deadline_check.breached when the grace window has passed. Fails with deadline_check.failed when the deadline cannot be parsed."
            category :scheduling_time
            version "3.0.0"
            presentation icon: "M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z",
                          color: "red", single_use: false, privileged: false
          end

          config_schema do
            input :deadlineVariable, default: "deadline",
              description: "ctx path holding the deadline as a Time, Date, or string, e.g. 'due_at'. Default 'deadline'."
            enum :deadlineFormat, FORMATS, default: "auto",
              description: "'auto' (default) uses Time.parse. 'iso8601' and 'rfc2822' require that string shape. Ignored when the value is already a Time."
            input :referenceTime,
              description: "ctx path for the clock, e.g. 'now'. Blank uses Time.current."
            integer :gracePeriodSeconds, min: 0, max: FlowchartRuntime::Deadline::MAX_GRACE_PERIOD_SECONDS, default: 0,
              description: "Seconds added to the deadline before breachedVar is true (0-31536000). Default 0."
            integer :warningSeconds, min: 0, max: FlowchartRuntime::Deadline::MAX_GRACE_PERIOD_SECONDS, default: 0,
              description: "When remaining seconds are at or below this (and not breached), atRiskVar is true. 0 disables. Default 0."
            enum :behaviorOnBreach, BEHAVIORS, default: "mark",
              description: "'mark' (default) writes flags and succeeds. 'fail' also fails the step with deadline_check.breached when the grace window has passed."
            output :resultVar, default: "deadline_status",
              description: "ctx variable that receives {passed, remaining_seconds, overdue_seconds}. Default 'deadline_status'."
            output :breachedVar, default: "deadline_breached",
              description: "ctx variable set to true when now is after deadline + grace. Default 'deadline_breached'."
            output :atRiskVar, default: "deadline_at_risk", group: :advanced,
              description: "ctx variable set to true when remaining time is within warningSeconds. Default 'deadline_at_risk'."
          end

          def generate_body
            lines = [
              "check = FlowchartRuntime::Deadline.check(#{check_args})",
              assign(:resultVar, "check[:status]"),
              assign(:breachedVar, "check[:breached]"),
              assign(:atRiskVar, "check[:at_risk]")
            ]
            if value(:behaviorOnBreach) == "fail"
              lines << 'return FlowchartRuntime::Step.fail(ctx, :"deadline_check.breached") if check[:breached]'
            end
            lines << "true"

            attempt('"deadline_check.failed"', FlowchartRuntime::Deadline::Error) { lines }
          end

          private

          def check_args
            [
              "deadline: #{read(:deadlineVariable)}",
              ("format: #{read(:deadlineFormat)}" unless value(:deadlineFormat).to_s == "auto"),
              ("reference: #{read(:referenceTime)}" if value(:referenceTime).to_s.strip.present?),
              ("grace_seconds: #{read(:gracePeriodSeconds)}" unless value(:gracePeriodSeconds) == 0),
              ("warning_seconds: #{read(:warningSeconds)}" unless value(:warningSeconds) == 0)
            ].compact.join(", ")
          end
        end
      end
    end
  end
end
