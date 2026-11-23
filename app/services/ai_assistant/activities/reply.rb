# frozen_string_literal: true

module AiAssistant
  module Activities
    # Job-only chat completion. Reads recent turns, calls the vendor wrap,
    # persists the assistant message, and broadcasts it. Never invoked from a
    # Puma request thread.
    #
    # Everything the reader sees while the turn runs is published from here:
    # a live draft bubble carrying the progress trace and, on a vendor that
    # streams, the reply as it is written.
    class Reply
      LOG_TAG = "[ai_assistant.reply]"

      def self.call(generation:)
        new(generation: generation).call
      end

      def initialize(generation:)
        @generation = generation
      end

      def call
        @write_guard = AiAssistant::Assistant::GenerationWriteGuard.new(
          generation: generation
        )
        claim = AiAssistant::Assistant::GenerationLifecycle.claim!(generation)
        return if claim == :stale
        return complete_cancelled if claim == :cancelled

        policy = AiAssistant::Assistant::ExecutionPolicy.call(generation: generation)
        return complete_failure(policy.error_code) unless policy.allowed?

        @settings = AiAssistant::ProviderSettings.active_for(:generation)
        @tool_session = AiAssistant::Assistant::Tools::Session.new(
          customer: conversation.customer,
          write_guard: @write_guard,
          progress: progress,
          viewer: conversation.user,
          conversation: conversation,
          generation: generation
        )
        @provider = AiAssistant::Assistant::ProviderClient.new(
          settings: @settings,
          conversation: conversation,
          tool_session: @tool_session,
          write_guard: @write_guard
        )
        open_draft

        build_turn = AiAssistant::Subsystems::Answer.consume(conversation: conversation, user_message: user_message)
        return complete_turn(build_turn) if build_turn

        confirmation_turn = consume_confirmation
        return complete_turn(confirmation_turn) if confirmation_turn

        progress.start(:thinking)
        result = vendor_chat(prompt_messages, tools: native_tools)
        return if superseded?
        return complete_cancelled if cancelled?

        text = result[:text].to_s.strip
        if result[:outcome] == :success && text.present?
          handle_success(text)
        else
          complete_failure(failure_code_for(result))
        end
      rescue AiAssistant::Assistant::GenerationWriteGuard::Rejected => e
        handle_rejected_write(e)
      rescue ActiveRecord::RecordNotFound => e
        # The thread was reset (or the tenant removed) while this turn was in
        # flight. There is nothing left to write to, so stop quietly.
        report(e, "generation no longer exists")
      rescue StandardError => e
        report(e, "unexpected failure")
        terminalize_unexpected_failure
        raise
      end

      private

      attr_reader :generation

      def user_message
        generation.user_message
      end

      def conversation
        user_message.conversation
      end

      def progress
        @progress ||= AiAssistant::Assistant::Progress.new(conversation: conversation)
      end

      # The pump is told how to see a cancellation because the vendor request
      # already in flight is not aborted: without this the preview keeps
      # streaming for the rest of the provider timeout after Stop lands.
      def pump
        @pump ||= AiAssistant::Assistant::DeltaPump.new(
          conversation: conversation,
          cancelled: -> { %w[cancelled superseded].include?(generation.reload.status) }
        )
      end

      # The draft is the node every in-flight update writes into: progress
      # steps always, streamed prose when the vendor supports it.
      def open_draft
        AiAssistant::Stream.broadcast_draft_open(conversation)
        AiAssistant::Stream.broadcast_status(conversation, I18n.t("ai_assistant.assistant.status.thinking"))
      end

      def close_draft
        AiAssistant::Stream.broadcast_draft_close(conversation)
      end

      # Only complete turns are sent to the model. A failed assistant row's body
      # is the localized "the assistant could not reply" string, so including it
      # would feed the model its own error text as context.
      def prompt_messages
        AiAssistant::Assistant::PromptBuilder.call(
          conversation: conversation,
          mode: :entity
        )
      end

      def handle_success(text)
        return if superseded?
        return complete_cancelled if cancelled?

        turn = AiAssistant::Assistant::TurnProcessor.call(
          text: text,
          conversation: conversation,
          customer: conversation.customer,
          chat: method(:vendor_chat),
          tool_session: @tool_session,
          write_guard: @write_guard,
          progress: progress
        )
        @website_result = turn.website_result
        return preserve_committed_effects if superseded?
        return complete_cancelled if cancelled?

        complete_turn(turn)
      end

      def consume_confirmation
        AiAssistant::Assistant::PendingConfirmation.consume(
          conversation: conversation,
          user_message: user_message,
          generation: generation
        ) do |proposal|
          progress.start(:entity)
          AiAssistant::Assistant::TurnProcessor.call(
            proposal: proposal,
            conversation: conversation,
            customer: conversation.customer,
            chat: method(:vendor_chat),
            tool_session: @tool_session,
            write_guard: nil,
            progress: progress
          )
        end
      end

      def vendor_chat(messages, tools: nil)
        pump.begin_call
        result = @provider.chat(messages, tools: tools, on_chunk: pump)
        pump.flush
        result
      end

      def native_tools
        @provider.native_tools.presence
      end

      # A spent call budget is an operational condition, not a vendor outage,
      # so it gets its own code rather than hiding inside the generic failure.
      def failure_code_for(result)
        return "vendor_call_budget" if result[:outcome] == :budget_exceeded

        nil
      end

      def complete_failure(failure_code = nil)
        progress.fail!
        complete(
          failure_body(failure_code),
          "failed",
          failure_code: failure_code.to_s.presence
        )
      end

      # "Try again" is the wrong advice for a turn that ran out of vendor calls
      # rather than hitting an outage — repeating the same request spends the
      # same budget. The budget case says what would actually help instead.
      def failure_body(failure_code)
        return I18n.t("ai_assistant.assistant.budget_exceeded") if failure_code == "vendor_call_budget"

        I18n.t("ai_assistant.assistant.reply_failed")
      end

      def complete_cancelled
        complete(
          I18n.t("ai_assistant.assistant.cancelled"),
          "cancelled",
          required_status: "cancelled"
        )
      end

      def cancelled?
        generation.reload.status == "cancelled"
      end

      def superseded?
        generation.reload.status == "superseded"
      end

      def finish_generation(status:, failure_code: nil)
        pointer_cleared = AiAssistant::Assistant::GenerationLifecycle.finish!(
          generation,
          status: status,
          failure_code: failure_code
        )
        publish_idle if pointer_cleared
      end

      def publish_idle
        AiAssistant::Stream.broadcast_running(conversation, false)
        AiAssistant::Stream.broadcast_status(conversation, "")
      end

      # Website pages commit before the reply is written. A turn that is then
      # stopped or fails still records them, so the reply lists them and can
      # undo them.
      def complete(text, status, required_status: "running", failure_code: nil)
        complete_turn(
          AiAssistant::Assistant::TurnProcessor::Result.new(
            body: text,
            status: status,
            effects: [],
            website_result: @website_result
          ),
          required_status: required_status,
          failure_code: failure_code
        )
      end

      def complete_turn(turn, required_status: "running", failure_code: nil)
        finalized = AiAssistant::Assistant::Finalizer.call(
          turn: turn,
          conversation: conversation,
          write_guard: @write_guard
        )
        progress.finish
        # The draft goes before the real bubble is appended, so the reader never
        # sees the reply twice on the same stream.
        close_draft
        message = AiAssistant::Assistant::ReplyWriter.call(
          conversation: conversation,
          finalized: finalized,
          write_guard: @write_guard,
          required_status: required_status
        )
        finish_generation(
          status: generation_status(finalized.status),
          failure_code: failure_code
        )
        message
      end

      def handle_rejected_write(error)
        return preserve_committed_effects if error.state == :superseded
        return unless error.state == :cancelled

        complete_cancelled
      rescue AiAssistant::Assistant::GenerationWriteGuard::Rejected
        nil
      end

      # A replacement turn invalidates new writes, not effects that have
      # already committed. Keep their undo/provenance receipt without touching
      # the replacement generation's pointer, draft, or selected artifact.
      def preserve_committed_effects
        return unless @website_result&.applied

        message = conversation.with_lock do
          existing = conversation.messages.find_by(
            "role = 'assistant' AND json_extract(metadata, '$.generation_id') = ?", generation.id
          )
          next existing if existing

          finalized = AiAssistant::Assistant::Finalizer.call(
            conversation: conversation,
            turn: AiAssistant::Assistant::TurnProcessor::Result.new(
              body: @website_result.body, status: "cancelled", effects: [], website_result: @website_result
            )
          )
          conversation.messages.create!(
            customer_id: conversation.customer_id, role: "assistant", status: "cancelled",
            body: finalized.body,
            metadata: finalized.metadata.merge("generation_id" => generation.id, "superseded" => true)
          )
        end
        AiAssistant::Stream.broadcast_message(message)
        message
      end

      # An unexpected exception has to leave the same visible failure an
      # expected one does, or the draft bubble vanishes and the prompt sits
      # unanswered for good. The bubble is best-effort: a second exception here
      # would mask the one the caller is about to re-raise, and the generation
      # still has to reach a terminal state either way.
      def terminalize_unexpected_failure
        complete_failure("unexpected_error")
      rescue StandardError => e
        report(e, "failure message not written")
        close_draft
        finish_generation(status: :failed, failure_code: "unexpected_error")
      end

      def generation_status(message_status)
        case message_status
        when "complete" then "completed"
        when "cancelled" then "cancelled"
        else "failed"
        end
      end

      def report(error, context)
        Rails.logger.error(
          "#{LOG_TAG} #{context} generation=#{generation&.id} message=#{user_message&.id}: " \
          "#{error.class}: #{error.message}"
        )
      end
    end
  end
end
