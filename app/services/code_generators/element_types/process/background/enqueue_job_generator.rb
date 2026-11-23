# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Background
        class EnqueueJobGenerator < BaseGenerator
          WHEN_MODES = %w[now at after recurring].freeze
          QUEUES = %w[default low high mailers].freeze
          MAX_PRIORITY = FlowchartRuntime::JobSchedule::MAX_PRIORITY
          MAX_WAIT_SECONDS = FlowchartRuntime::JobSchedule::MAX_WAIT_SECONDS
          MAX_INTERVAL = FlowchartRuntime::JobSchedule::MAX_INTERVAL
          MAX_RECURRENCES = FlowchartRuntime::JobSchedule::MAX_RECURRENCES

          generator_metadata do
            description "Enqueues an allow-listed Active Job via set(queue, priority, wait, wait_until).perform_later. " \
                        "Use now for immediate work, at for a timestamp, after for a delay in seconds, or recurring " \
                        "for the next cron tick (Fugit) or a bounded burst of delayed jobs. Recurring interval times " \
                        "limit pre-books N delayed jobs (first after one interval); it is not a persistent scheduler, " \
                        "so use cron for a repeating clock. Writes resultVar with the job id (or an array of ids). " \
                        "Fails with enqueue_job.failed when the class is not an ApplicationJob, enqueue is aborted, " \
                        "or the cron/horizon is invalid."
            category :background
            version "4.1.0"
            presentation icon: "M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10",
                         color: "indigo", single_use: false, privileged: false
          end

          config_schema do
            reference :jobClass, source: :job_classes, required: true, example: "ApplicationJob",
                      description: "Allow-listed ApplicationJob class to run, for example ProcessOrderJob. " \
                                   "Resolved through Invocable.job!; arbitrary constants are refused."
            enum :when, WHEN_MODES, default: "now",
                 description: "When to run. now enqueues immediately; at uses runAt; after waits waitSeconds; " \
                              "recurring uses cronExpression (next tick only) or intervalSeconds x recurrenceLimit (pre-booked delays)."
            expression :jobArgs, example: "ctx[:user_id]",
                       description: "Ruby expression for perform arguments, for example ctx[:order].id or " \
                                    "ctx[:user_id], ctx[:order_id]. Leave blank for no arguments."
            enum :queueName, QUEUES, default: "default",
                 description: "Active Job queue. default is the app queue; low and high are priority aliases; mailers is the mailer queue."
            integer :priority, min: 0, max: MAX_PRIORITY,
                    description: "Active Job priority from 0 to 1000. Leave blank for the adapter default."
            expression :runAt, example: "1.hour.from_now", visible: { when: "at" },
                       description: "Ruby time expression for when=at, for example 1.hour.from_now or Time.zone.parse(ctx[:due_at]). Clamped to the next 30 days."
            integer :waitSeconds, min: 0, max: MAX_WAIT_SECONDS, example: 3600, visible: { when: "after" },
                    description: "Delay in seconds for when=after, for example 3600 for one hour. Clamped to 30 days."
            literal :cronExpression, example: "0 * * * *", placeholder: true, visible: { when: "recurring" },
                    description: "Five-field cron for when=recurring, for example 0 9 * * 1-5 (weekdays at 09:00). " \
                                 "Only the next occurrence is enqueued. Takes precedence over intervalSeconds."
            literal :timezone, default: "UTC", placeholder: true, visible: { when: "recurring" },
                    description: "IANA timezone for the cron expression, for example UTC or America/New_York. Ignored for interval bursts."
            integer :intervalSeconds, min: 1, max: MAX_INTERVAL, default: 3_600, visible: { when: "recurring" },
                    description: "Seconds between pre-booked delayed jobs when cronExpression is blank (1-86400, default 3600). " \
                                 "First job waits one interval; this is not a persistent repeating schedule."
            integer :recurrenceLimit, min: 1, max: MAX_RECURRENCES, default: 1, visible: { when: "recurring" },
                    description: "How many delayed jobs to pre-book when cronExpression is blank (1-100, default 1). " \
                                 "intervalSeconds x this value must stay within 30 days."
            output :resultVar, default: "enqueued_job_id",
                   description: "Ctx variable that receives the Active Job id string, or an array of ids for an interval burst."
            requires :runAt, when: { when: "at" }
            requires :waitSeconds, when: { when: "after" }

            validate do |_cfg, errors|
              next unless value(:when) == "recurring"

              cron = value(:cronExpression).to_s
              if cron.present? && !FlowchartRuntime::Schedule.valid_cron?(cron)
                errors.add(:cronExpression, :invalid_cron)
              end
              zone = value(:timezone).to_s
              if zone.present? && ActiveSupport::TimeZone[zone].blank?
                errors.add(:timezone, :invalid_timezone)
              end
              limit = value(:recurrenceLimit).to_i
              interval = value(:intervalSeconds).to_i
              if cron.blank? && limit.positive? && interval.positive? && (limit * interval) > MAX_WAIT_SECONDS
                errors.add(:recurrenceLimit, :horizon_too_far, max_days: MAX_WAIT_SECONDS / 86_400)
              end
            end
          end

          def generate_body
            body(
              attempt(
                '"enqueue_job.failed"',
                FlowchartRuntime::JobSchedule::Error,
                FlowchartRuntime::Schedule::Error,
                FlowchartRuntime::Invocable::Error
              ) do
                [
                  assign(:resultVar, run_call),
                  "true"
                ]
              end
            )
          end

          private

          def run_call
            "FlowchartRuntime::JobSchedule.run(#{run_args})"
          end

          def run_args
            args = [
              "FlowchartRuntime::Invocable.job!(#{read(:jobClass)})",
              "schedule_when: #{read(:when)}"
            ]
            args << "args: [#{read(:jobArgs)}]" if value(:jobArgs).present?
            args << "queue: #{read(:queueName)}"
            args << "priority: #{read(:priority)}" unless value(:priority).nil?
            case value(:when)
            when "at"
              args << "run_at: #{read(:runAt)}" if value(:runAt).present?
            when "after"
              args << "wait_seconds: #{read(:waitSeconds)}" unless value(:waitSeconds).nil?
            when "recurring"
              if value(:cronExpression).to_s.present?
                args << "cron_expression: #{read(:cronExpression)}"
                args << "timezone: #{read(:timezone)}" if value(:timezone).present?
              else
                args << "timezone: #{read(:timezone)}" if value(:timezone).present?
                args << "interval_seconds: #{read(:intervalSeconds)}" unless value(:intervalSeconds).nil? || value(:intervalSeconds) == 3_600
                args << "recurrence_limit: #{read(:recurrenceLimit)}" unless value(:recurrenceLimit).nil? || value(:recurrenceLimit) == 1
              end
            end
            args.join(", ")
          end
        end
      end
    end
  end
end
