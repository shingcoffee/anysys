# frozen_string_literal: true

module FlowchartRuntime
  # Thread/fiber-local deadline for one flowchart run.
  class RunContext < ActiveSupport::CurrentAttributes
    class Error < StandardError; end

    attribute :deadline

    class << self
      def with_deadline(seconds)
        budget = Float(seconds, exception: false)
        raise Error, "deadline must be positive" unless budget&.positive?

        previous = deadline
        self.deadline = monotonic_now + budget
        yield
      ensure
        self.deadline = previous
      end

      def remaining
        return ActivityTracer::EXECUTION_TIMEOUT_SECONDS unless deadline

        left = deadline - monotonic_now
        left.positive? ? left : 0.0
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
