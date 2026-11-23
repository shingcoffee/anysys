# frozen_string_literal: true

require "fugit"

module FlowchartRuntime
  module Schedule
    class Error < StandardError; end

    module_function

    def valid_cron?(expression)
      !Fugit::Cron.parse(expression.to_s).nil?
    end

    def next_cron_time(expression, timezone: nil)
      raise Error, "cron expression is required" if expression.to_s.strip.empty?

      cron = parse_cron(expression, timezone: timezone)
      raise Error, "invalid cron expression" unless cron

      cron.next_time.to_t
    end

    def parse_cron(expression, timezone: nil)
      Fugit::Cron.parse([expression.to_s, timezone.to_s.presence].compact.join(" "))
    end
  end
end
