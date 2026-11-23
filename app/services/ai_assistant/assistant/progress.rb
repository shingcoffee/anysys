# frozen_string_literal: true

module AiAssistant
  module Assistant
    # The visible trace of one turn.
    #
    # A turn is not one vendor call: it can run a tool loop, an entity pass, a
    # flowchart pass and a repair round-trip, each of which can take tens of
    # seconds. Previously all of that sat behind a single static "Working…"
    # pill. Progress records each step as it starts and completes so the panel
    # can show what the assistant is actually doing.
    #
    # Steps are identified by a stable key; the label is resolved at render
    # time so it follows the reader's locale rather than the job's.
    class Progress
      KEYS = %i[thinking catalog entity flowchart page website verify repair].freeze

      Step = Struct.new(:key, :state, :detail, keyword_init: true) do
        def running? = state == :running
        def done? = state == :done
        def failed? = state == :failed

        def label
          I18n.t("ai_assistant.assistant.progress.#{key}")
        end
      end

      # Stand-in for the pipeline stages that can run outside a live turn
      # (confirmation replays, specs), so no caller has to nil-check.
      class Null
        def start(_key, detail: nil) = self
        def finish(_state = :done) = self
        def fail! = self
        def steps = []
        def running_key = nil
      end

      def self.null = Null.new

      def initialize(conversation:, publisher: AiAssistant::Stream)
        @conversation = conversation
        @publisher = publisher
        @steps = []
      end

      attr_reader :steps

      # Marks any still-running step done, opens `key`, and pushes the new
      # trace. Auto-closing the previous step keeps callers from having to pair
      # every begin with an end on every early return.
      def start(key, detail: nil)
        raise ArgumentError, "unknown progress key #{key}" unless KEYS.include?(key)

        close_running(:done)
        @steps << Step.new(key: key, state: :running, detail: detail)
        publish
        self
      end

      def finish(state = :done)
        close_running(state)
        publish
        self
      end

      # Terminal failure of the step in flight, leaving earlier steps intact so
      # the reader can see how far the turn got.
      def fail!
        finish(:failed)
      end

      def running_key
        @steps.find(&:running?)&.key
      end

      private

      def close_running(state)
        @steps.each { |step| step.state = state if step.running? }
      end

      def publish
        @publisher.broadcast_progress(@conversation, @steps)
      end
    end
  end
end
