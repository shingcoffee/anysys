# frozen_string_literal: true

module FlowchartRuntime
  class QueryLogger
    class Error < StandardError; end

    # Wraps a block and captures all SQL queries executed within it.
    # Returns [block_result, queries_array].
    #
    # @yield the block to execute
    # @return [Array(Object, Array<Hash>)] [result, queries]
    def self.capture(&block)
      raise Error, "block is required" unless block

      queries = []
      # The subscription is process-global, but notifications are delivered on
      # the thread that emitted them. Capturing the owning thread and dropping
      # events from any other thread scopes the log to this traced run only —
      # without it, SQL from concurrent requests (other tenants) would leak in.
      owner = Thread.current
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        next if Thread.current != owner
        next if payload[:name] == "SCHEMA"

        queries << {
          sql: payload[:sql],
          duration_ms: payload[:duration]&.round(2),
          name: payload[:name]
        }
      end

      result = block.call
      [result, queries]
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    end
  end
end
