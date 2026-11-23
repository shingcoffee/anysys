# frozen_string_literal: true

module AiAssistant
  module Assistant
    # Turns a conversation into the message array sent to the vendor: one
    # composed system prompt (see Prompt::Composer) followed by the recent
    # turns. Prompt *content* lives in Prompt::Sections; this class only owns
    # the transport shape and the history window.
    class PromptBuilder
      HISTORY_LIMIT = 20
      # Claude on Bedrock rejects a request carrying more than 20 images.
      MAX_REPLAYED_IMAGES = 16
      MAX_REPLAYED_BYTES = Attachments::MAX_TOTAL_BYTES
      # The reply's own text still says what it built.
      UNDONE_NOTE = "(The admin has since undone this reply's website changes; the website catalog shows the " \
                    "pages as they are now.)"
      APPLIED_NOTE = "(The admin approved this proposal and it was applied.)"
      PENDING_NOTE = "(This proposal is waiting for the admin's approval. Nothing from it is saved yet.)"
      DECLINED_NOTE = "(The admin discarded this proposal. Nothing from it was saved.)"
      SUPERSEDED_NOTE = "(This proposal was replaced or could no longer apply. Nothing from it was saved.)"
      MODES = Prompt::Composer::MODES

      def self.call(conversation:, mode:)
        new(conversation: conversation, mode: mode).call
      end

      def initialize(conversation:, mode:)
        @context = Prompt::Context.new(conversation: conversation, mode: mode)
      end

      def call
        [{ role: "system", content: Prompt::Composer.call(context: @context) }, *history]
      end

      private

      def conversation = @context.conversation

      # Only complete turns are replayed: a failed row's body is the localized
      # "the assistant could not reply" string, so including it would feed the
      # model its own error text as context.
      def history
        turns = conversation.messages
                            .with_attached_images
                            .where(status: "complete")
                            .order(id: :desc)
                            .limit(HISTORY_LIMIT)
                            .reverse
                            .map { |message| [message, image_attachments(message)] }
        replayed = replayed_image_turns(turns)
        turns.map { |message, attachments| history_message(message, attachments, replay: replayed.include?(message.id)) }
      end

      def history_message(message, attachments, replay:)
        entry = { role: message.role, content: content_for(message, attachments) }
        entry[:images] = attachments.map(&:blob) if replay
        entry
      end

      # The manifest names each image's token, so a turn whose pictures fall
      # outside the replay window can still be placed on a website by token.
      def content_for(message, attachments)
        body = message.body
        body = "#{body}\n\n#{UNDONE_NOTE}" if message.assistant? && Websites::Assistant::Undo.state(message) == :undone
        body = with_assistant_notes(body, message) if message.assistant?
        return body if attachments.empty? || !@context.website_enabled?

        "#{body}\n\n#{Websites::Assistant::Uploads.manifest_line(attachments)}"
      end

      def with_assistant_notes(body, message)
        notes = assistant_notes(message)
        return body if notes.empty?

        [body, *notes].join("\n\n")
      end

      def assistant_notes(message)
        metadata = message.metadata_json
        notes = []
        questions = Questions.sanitize(metadata["questions"]).map { |question| question.except("id") }
        notes << "(You asked these questions; the admin's next message answers them: #{JSON.generate(questions)})" if questions.any?
        assumptions = Questions.sanitize_assumptions(metadata["assumptions"])
        notes << "(Assumptions you stated: #{JSON.generate(assumptions)})" if assumptions.any?
        note = proposal_state_note(metadata)
        notes << note if note
        notes
      end

      def proposal_state_note(metadata)
        if metadata["applied_proposal"].present?
          APPLIED_NOTE
        elsif metadata["pending_confirmation"].present?
          PENDING_NOTE
        elsif metadata["declined_proposal"].present?
          DECLINED_NOTE
        elsif metadata["superseded_proposal"].present?
          SUPERSEDED_NOTE
        end
      end

      def image_attachments(message)
        return [] unless message.user? && message.images.attached?

        Websites::Assistant::Uploads.ordered(message)
      end

      # Newest turns first, whole turns only: a turn's pictures are replayed
      # all together or not at all, so they keep lining up with its manifest.
      def replayed_image_turns(turns)
        images = MAX_REPLAYED_IMAGES
        bytes = MAX_REPLAYED_BYTES
        replayed = Set.new
        turns.reverse_each do |message, attachments|
          next if attachments.empty?

          size = attachments.sum { |attachment| attachment.blob.byte_size.to_i }
          break if attachments.size > images || size > bytes

          images -= attachments.size
          bytes -= size
          replayed << message.id
        end
        replayed
      end
    end
  end
end
