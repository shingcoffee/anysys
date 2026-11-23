# frozen_string_literal: true

module FlowchartRuntime
  # Thin, bounded facade over the Active Job enqueue APIs used by the
  # flowchart `enqueue_job` and `schedule_job` steps.
  #
  # It exists so generated code never calls `set(...).perform_later` directly:
  #
  #   - every scheduling option (queue, priority, wait, wait_until) is
  #     validated and clamped, so a flowchart cannot schedule a job years into
  #     the future or push an arbitrary string into the queue name
  #   - an enqueue that Active Job refuses (an aborted `before_enqueue`
  #     callback makes `perform_later` return false) raises instead of being
  #     reported as success
  module JobSchedule
    class Error < StandardError; end

    MAX_WAIT_SECONDS = 30 * 86_400
    MAX_PRIORITY     = 1_000
    MAX_INTERVAL     = 86_400
    MAX_RECURRENCES  = 100
    QUEUE_RE         = /\A[a-zA-Z0-9_.:-]{1,64}\z/
    WHEN_MODES       = %w[now at after recurring].freeze

    module_function

    # Enqueue now, at a time, after a delay, or as a bounded recurrence.
    # Returns a job id string, an array of ids (recurring interval), or nil.
    def run(job_class, schedule_when:, args: [], queue: nil, priority: nil, run_at: nil,
            wait_seconds: nil, cron_expression: nil, timezone: nil,
            interval_seconds: nil, recurrence_limit: nil)
      mode = schedule_when.to_s
      raise Error, "unknown when" unless WHEN_MODES.include?(mode)

      case mode
      when "now"
        job_id(enqueue!(job_class, args: args, queue: queue, priority: priority))
      when "at"
        job_id(enqueue!(job_class, args: args, queue: queue, priority: priority, wait_until: run_at))
      when "after"
        job_id(enqueue!(job_class, args: args, queue: queue, priority: priority, wait: wait_seconds))
      else
        run_recurring(
          job_class,
          args: args, queue: queue, priority: priority,
          cron_expression: cron_expression, timezone: timezone,
          interval_seconds: interval_seconds, recurrence_limit: recurrence_limit
        )
      end
    end

    def run_recurring(job_class, args:, queue:, priority:, cron_expression:, timezone:,
                      interval_seconds:, recurrence_limit:)
      if cron_expression.to_s.present?
        next_time = Schedule.next_cron_time(cron_expression, timezone: timezone)
        return job_id(enqueue!(job_class, args: args, queue: queue, priority: priority, wait_until: next_time))
      end

      limit = Integer(recurrence_limit, exception: false) || 1
      interval = Integer(interval_seconds, exception: false) || 3_600
      raise Error, "recurrenceLimit must be between 1 and #{MAX_RECURRENCES}" unless (1..MAX_RECURRENCES).cover?(limit)
      raise Error, "intervalSeconds must be between 1 and #{MAX_INTERVAL}" unless (1..MAX_INTERVAL).cover?(interval)
      raise Error, "recurring horizon exceeds #{MAX_WAIT_SECONDS / 86_400} days" if (limit * interval) > MAX_WAIT_SECONDS

      # Pre-book N delayed jobs (first wait is one interval, not now). This is
      # not a persistent repeating schedule; cron books only the next tick.
      limit.times.map do |index|
        job_id(enqueue!(job_class, args: args, queue: queue, priority: priority, wait: (index + 1) * interval))
      end
    end
    module_function :run_recurring
    private_class_method :run_recurring

    # @return [ActiveJob::Base] the enqueued job instance
    def enqueue!(job_class, args: [], queue: nil, priority: nil, wait: nil, wait_until: nil)
      klass = cast_job_class(job_class)
      options = build_options(queue: queue, priority: priority, wait: wait, wait_until: wait_until)

      target = options.empty? ? klass : klass.set(**options)
      job = target.perform_later(*Array(args))
      raise Error, "job was not enqueued" unless enqueued?(job)

      job
    end

    def build_options(queue: nil, priority: nil, wait: nil, wait_until: nil)
      options = {}
      options[:queue]      = cast_queue(queue)           unless queue.nil?
      options[:priority]   = cast_priority(priority)     unless priority.nil?
      options[:wait]       = bounded_wait(wait)          unless wait.nil?
      options[:wait_until] = bounded_wait_until(wait_until) unless wait_until.nil?
      options
    end

    # Clamps a relative delay into 0..MAX_WAIT_SECONDS.
    def bounded_wait(seconds)
      value = Float(seconds, exception: false)
      raise Error, "wait must be a non-negative number of seconds" unless value && !value.negative?

      [value, MAX_WAIT_SECONDS.to_f].min.seconds
    end

    # Clamps an absolute run time into now..now + MAX_WAIT_SECONDS.
    def bounded_wait_until(value)
      time = cast_time(value)
      now  = Time.current
      return now if time < now

      [time, now + MAX_WAIT_SECONDS.seconds].min
    end

    def enqueued?(job)
      return false if job == false || job.nil?
      return job.successfully_enqueued? if job.respond_to?(:successfully_enqueued?)

      true
    end

    # Active Job returns the job instance from perform_later, but an adapter
    # (or a test double) may return a bare truthy value. Callers still need a
    # single, safe way to record the id, so the duck-typing lives here rather
    # than in every generated step body.
    def job_id(job)
      job.job_id if job.respond_to?(:job_id)
    end

    def cast_job_class(job_class)
      unless job_class.respond_to?(:perform_later) && job_class.respond_to?(:set)
        raise Error, "job class must be an Active Job class"
      end

      job_class
    end

    def cast_queue(queue)
      name = queue.to_s
      raise Error, "invalid queue name" unless QUEUE_RE.match?(name)

      name
    end

    def cast_priority(priority)
      value = Integer(priority, exception: false)
      raise Error, "priority must be an integer" if value.nil?
      raise Error, "priority must be between 0 and #{MAX_PRIORITY}" if value.negative? || value > MAX_PRIORITY

      value
    end

    def cast_time(value)
      return value.to_time if value.respond_to?(:to_time) && !value.is_a?(String)

      parsed = value.is_a?(String) ? Time.zone.parse(value) : nil
      raise Error, "wait_until must be a time" if parsed.nil?

      parsed
    end
  end
end
