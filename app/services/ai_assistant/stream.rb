# frozen_string_literal: true

module AiAssistant
  # Signed Turbo Streams for the assistant workspace.
  #
  # Two scopes, because two different things change at two different rates:
  #
  #   * user_name(customer, user) — things that outlive one thread: the mic
  #     transcript inbox and the conversation sidebar.
  #   * name(customer, user, conversation) — one thread's bubbles, live draft,
  #     progress steps, status pill and artifact.
  #
  # Both names carry customer_id and user_id, so a subscription can never
  # receive another tenant's or another user's traffic. The conversation id is
  # additionally scoped by the resolver that hands it out, so subscribing to a
  # thread you do not own is not reachable from the panel.
  module Stream
    THREAD_ID = "ai_assistant_thread"
    EMPTY_ID = "ai_assistant_empty"
    ARTIFACT_ID = "ai_assistant_artifact"
    STATUS_ID = "ai_assistant_status"
    RUNNING_ID = "ai_assistant_running"
    DRAFT_ID = "ai_assistant_draft"
    DRAFT_BODY_ID = "ai_assistant_draft_body"
    DRAFT_STEPS_ID = "ai_assistant_draft_steps"
    CONVERSATIONS_ID = "ai_assistant_conversations"

    class << self
      def user_name(customer_id:, user_id:)
        [ :ai_assistant, customer_id, user_id ]
      end

      def name(customer_id:, user_id:, conversation_id:)
        [ :ai_assistant, customer_id, user_id, conversation_id ]
      end

      def for_conversation(conversation)
        name(
          customer_id: conversation.customer_id,
          user_id: conversation.user_id,
          conversation_id: conversation.id
        )
      end

      # @param remove_empty_state [Boolean] true only for the first turn of a
      #   thread, where the panel's empty-state placeholder is still on the
      #   page. The caller already knows this, so no per-broadcast COUNT is needed.
      def broadcast_message(message, remove_empty_state: false)
        conversation = message.conversation
        stream = for_conversation(conversation)
        Turbo::StreamsChannel.broadcast_remove_to(stream, target: EMPTY_ID) if remove_empty_state
        Turbo::StreamsChannel.broadcast_append_to(
          stream,
          target: THREAD_ID,
          html: render(AiAssistant::MessageComponent.new(message: message))
        )
      end

      # Re-renders one bubble that is already on the page, in place. Used when
      # a message's metadata changes after it was delivered — applying a
      # parked proposal, for instance, which retires the panel's buttons.
      # Replacing by the message's own node id is what keeps the thread from
      # ending up with two copies of the same bubble.
      def broadcast_message_replace(message)
        replace(
          message.conversation,
          ActionView::RecordIdentifier.dom_id(message),
          render(AiAssistant::MessageComponent.new(message: message))
        )
      rescue StandardError => e
        # The write this re-renders has already committed. A failed render is
        # a stale panel until reload, not a failed turn.
        log_failure("message_replace", e)
      end

      # Opens the live bubble the reply streams into. Replacing (not appending)
      # keeps the turn idempotent: a retried job reuses the same node instead of
      # stacking a second draft.
      def broadcast_draft_open(conversation)
        replace(conversation, DRAFT_ID, render(AiAssistant::DraftMessageComponent.new))
      end

      def broadcast_draft_close(conversation)
        replace(conversation, DRAFT_ID, empty_draft_html)
      end

      # The accumulated reply so far, not the newest chunk. Re-rendering the
      # whole body keeps Markdown coherent mid-stream and makes a dropped or
      # reordered frame self-healing.
      def broadcast_delta(conversation, text)
        update(conversation, DRAFT_BODY_ID, AiAssistant::Assistant::Markdown.render(text))
      end

      # Replace, not update: ProgressComponent's own root carries
      # DRAFT_STEPS_ID, so updating the slot's inner HTML would nest a second
      # node with the same id inside it.
      #
      # @param steps [Array<AiAssistant::Assistant::Progress::Step>]
      def broadcast_progress(conversation, steps)
        replace(
          conversation,
          DRAFT_STEPS_ID,
          render(AiAssistant::ProgressComponent.new(steps: steps))
        )
      end

      def broadcast_artifact(conversation)
        replace(
          conversation,
          ARTIFACT_ID,
          render(
            AiAssistant::ArtifactPaneComponent.new(
              conversation: conversation,
              customer: conversation.customer,
              viewer: conversation.user
            )
          )
        )
      end

      def broadcast_status(conversation, text)
        update(conversation, STATUS_ID, status_html(text))
      end

      # A blank status clears the header slot; a present one renders a live pill.
      def status_html(text)
        return "" if text.to_s.blank?

        helpers.tag.span(
          class: "inline-flex items-center gap-1.5 rounded-full bg-accent-subtle px-2.5 py-1 " \
                 "text-xs font-medium text-accent-text"
        ) do
          helpers.tag.span(class: "size-1.5 animate-pulse rounded-full bg-accent motion-reduce:animate-none") +
            helpers.tag.span(text.to_s)
        end
      end

      def broadcast_running(conversation, running)
        replace(conversation, RUNNING_ID, running_html(running))
      end

      def running_html(running)
        helpers.tag.div(
          "",
          id: RUNNING_ID,
          data: { running: running, ai_assistant_target: "runningFlag" },
          hidden: true
        )
      end

      # Sidebar refresh. Lives on the user stream because a thread's own stream
      # is gone the moment it is deleted, and the list has to survive that.
      def broadcast_conversations(customer:, user:, current_id: nil)
        Turbo::StreamsChannel.broadcast_replace_to(
          user_name(customer_id: customer.id, user_id: user.id),
          target: CONVERSATIONS_ID,
          html: render(
            AiAssistant::ConversationListComponent.new(
              customer: customer,
              user: user,
              current_id: current_id
            )
          )
        )
      rescue StandardError => e
        log_failure("conversations", e)
      end

      private

      def replace(conversation, target, html)
        Turbo::StreamsChannel.broadcast_replace_to(for_conversation(conversation), target: target, html: html)
      rescue StandardError => e
        log_failure(target, e)
      end

      def update(conversation, target, html)
        Turbo::StreamsChannel.broadcast_update_to(for_conversation(conversation), target: target, html: html)
      rescue StandardError => e
        log_failure(target, e)
      end

      def empty_draft_html
        helpers.tag.div("", id: DRAFT_ID)
      end

      def render(component)
        ApplicationController.render(component, layout: false)
      end

      def helpers
        ApplicationController.helpers
      end

      def log_failure(target, error)
        Rails.logger.error("[ai_assistant.stream] #{target} broadcast failed: #{error.class}: #{error.message}")
      end
    end
  end
end
