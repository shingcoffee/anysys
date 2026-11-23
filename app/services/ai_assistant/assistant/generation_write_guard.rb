# frozen_string_literal: true

module AiAssistant
  module Assistant
    # Serializes one assistant write against generation replacement. The
    # conversation row lock keeps start! from superseding the generation while
    # the guarded database mutation is in progress.
    class GenerationWriteGuard
      class Rejected < StandardError
        attr_reader :state

        def initialize(state)
          @state = state
          super(state.to_s)
        end
      end

      # Runs a write under `guard` when the caller has one. The model's own turn
      # always passes a guard; a confirmation replay deliberately passes none,
      # because it already runs inside the conversation lock.
      def self.wrap(guard, &operation)
        return operation.call if guard.nil?

        guard.call(&operation)
      end

      def initialize(generation:)
        @generation = generation
      end

      def call(required_status: "running")
        conversation.with_lock do
          @generation.reload
          raise Rejected, rejection_state unless current_with_status?(required_status)

          yield
        end
      end

      def check!
        call { true }
      end

      private

      def conversation
        @conversation ||= @generation.conversation
      end

      def current_with_status?(required_status)
        conversation.current_generation_id == @generation.id &&
          @generation.status == required_status.to_s
      end

      def rejection_state
        if conversation.current_generation_id != @generation.id &&
           @generation.status == "cancelled"
          return :stale
        end
        return :cancelled if @generation.status == "cancelled"
        return :superseded if @generation.status == "superseded"
        return :stale unless conversation.current_generation_id == @generation.id

        :stale
      end
    end
  end
end
