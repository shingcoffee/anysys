# frozen_string_literal: true

module AiAssistant
  module Activities
    # Request-path (and transcribe-job) handoff: persist the user turn and
    # enqueue ReplyJob. NEVER calls the chat vendor.
    class SendMessage
      include AiAssistant::Activities::ConversationScoped

      class Result < Preflight::Result
        alias_method :message, :record
      end

      def self.call(customer:, user:, body:, images: [], conversation_id: nil, idempotency_key: nil,
                    proposal_message_id: nil)
        new(
          customer: customer, user: user, body: body,
          images: images, conversation_id: conversation_id, idempotency_key: idempotency_key,
          proposal_message_id: proposal_message_id
        ).call
      end

      def initialize(customer:, user:, body:, images: [], conversation_id: nil, idempotency_key: nil,
                     proposal_message_id: nil)
        @customer = customer
        @user = user
        @body = body
        @images = images
        @conversation_id = conversation_id
        @idempotency_key = idempotency_key.to_s.presence
        @proposal_message_id = proposal_message_id
      end

      def call
        # STT retries carry a stable clip key. The conversation lock below is
        # the authoritative deduplication guard; this precheck avoids spending
        # the paid request throttle for an already installed turn.
        existing = target_conversation&.messages&.find_by(idempotency_conditions) if idempotency_key
        return success_result(existing) if existing

        failure = preflight_failure
        return failure if failure

        # May create the thread when the composer sent no id — that is what
        # opens a first conversation. A named id that resolves to nothing
        # belongs to someone else (or is gone), so it is a 404, never a send
        # into a thread of our choosing.
        conversation = resolve_conversation(conversation_id)
        return not_found_failure if conversation.nil?

        claimed = claim_turn(conversation)
        return conversation_limit_failure if claimed.nil?

        message, first_turn, generation = claimed
        return success_result(message) unless generation

        safely_publish { broadcast_conversations(current_id: conversation.id) }
        broadcast_message(message, remove_empty_state: first_turn)
        safely_publish do
          AiAssistant::Stream.broadcast_running(conversation, true)
          AiAssistant::Stream.broadcast_status(conversation, I18n.t("ai_assistant.assistant.status.thinking"))
        end
        generation_handoff_result(generation: generation, record: message)
      end

      private

      attr_reader :customer, :user, :body, :images, :conversation_id, :idempotency_key,
                  :proposal_message_id

      # The contract and the tenant gate come from ConversationScoped; the
      # vendor throttle and the provider-configured check do not, and a send
      # needs both. #activity_guard keeps its slot in the chain.
      def preflight_failure
        return fail_result(422, contract_errors) unless contract_valid?

        activity_guard ||
          disabled_failure ||
          unconfigured_failure ||
          rate_limited_failure
      end

      # Names the thread after its opening prompt and bumps the sidebar
      # ordering. #adopt_title_from is a no-op once a title exists, so a
      # thread the user renamed keeps its name.
      #
      # The sidebar links an archived row straight into the workspace, so
      # sending into one is reachable and is not refused. It does mean the
      # thread has to come back to the open list: a reload without an id only
      # ever opens an active thread, so the conversation the admin was just
      # having would otherwise disappear from view.
      def record_activity(conversation, message, first_turn:)
        conversation.adopt_title_from(message.body) if first_turn
        conversation.unarchive! if conversation.archived?
        conversation.touch_activity!
      end

      def rate_scope = "chat"

      def provider_job = :generation

      # Rejects a spent thread before anything is written; #claim_turn is what
      # actually enforces the cap. The predicate itself is ConversationScoped's.
      def activity_guard
        return nil unless exhausted?(target_conversation)

        conversation_limit_failure
      end

      # Takes one round, or nil when the cap closed. Counting and inserting
      # under the row lock is what stops two concurrent sends from both taking
      # the last round; the same lock serializes against DeleteConversation and
      # the reply job's write guard.
      def claim_turn(conversation)
        conversation.with_lock do
          if idempotency_key && (existing = conversation.messages.find_by(idempotency_conditions))
            next [existing, false, nil]
          end
          next nil if exhausted?(conversation)

          # Resolved before the insert: the dashboard's empty-state node only
          # exists while the thread has no turns, so the broadcast can be told
          # whether to remove it instead of counting rows on every message.
          first_turn = conversation.messages.empty?
          message = create_message!(conversation)
          record_activity(conversation, message, first_turn: first_turn)
          generation = AiAssistant::Assistant::GenerationLifecycle.start!(
            conversation: conversation, user_message: message
          )
          [message, first_turn, generation]
        end
      end

      # The cap precheck runs before the module, provider and rate gates have
      # passed, so it reads the thread without creating one — otherwise a
      # refused request would still leave a row behind.
      def target_conversation
        return @target_conversation if defined?(@target_conversation)

        @target_conversation = existing_conversation(conversation_id)
      end

      def contract_valid?
        contract.validate(body: body, images: images)
      end

      def contract
        @contract ||= AiAssistant::Contracts::Message.new(
          AiAssistant::Contracts::Message::Input.new
        )
      end

      def contract_errors
        contract.errors.full_messages
      end

      def create_message!(conversation)
        message = conversation.messages.create!(
          customer: customer,
          role: "user",
          body: persisted_body,
          status: "complete",
          metadata: message_metadata
        )
        AiAssistant::Assistant::Attachments.attach!(message, images)
        message
      end

      def broadcast_message(message, remove_empty_state:)
        AiAssistant::Stream.broadcast_message(
          message,
          remove_empty_state: remove_empty_state
        )
      rescue StandardError => e
        Rails.logger.error(
          "[ai_assistant.send_message] message broadcast failed " \
          "message=#{message.id}: #{e.class}: #{e.message}"
        )
      end

      def message_metadata
        metadata = {}
        metadata["idempotency_key"] = idempotency_key if idempotency_key
        pin_id = parsed_proposal_message_id
        metadata["confirms_message_id"] = pin_id if pin_id
        metadata
      end

      def parsed_proposal_message_id
        id = case proposal_message_id
             when Integer then proposal_message_id
             when String then Integer(proposal_message_id, 10, exception: false)
             end
        id if id&.positive?
      end

      def persisted_body
        stripped = body.to_s.strip
        return stripped if stripped.present?

        I18n.t("ai_assistant.assistant.attached_images")
      end

      def idempotency_conditions
        ["role = ? AND json_extract(metadata, '$.idempotency_key') = ?", "user", idempotency_key]
      end

      def safely_publish
        yield
      rescue StandardError => e
        Rails.logger.error("[ai_assistant.send_message] broadcast failed: #{e.class}: #{e.message}")
      end
    end
  end
end
