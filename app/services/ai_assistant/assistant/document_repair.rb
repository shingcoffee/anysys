# frozen_string_literal: true

module AiAssistant
  module Assistant
    # One repair round-trip: hands a rejected document back to the model
    # together with the errors it has to fix, and returns the replacement the
    # model produced.
    #
    # The artifact processors (flowchart, website) validate and persist
    # differently, so each owns its own attempt loop and decides what an error
    # is. What they do NOT need to own twice is this exchange — replay the
    # conversation in the right mode, show the model its own rejected JSON,
    # append the repair instructions, and re-parse the reply.
    #
    # `parser` is any object answering `parse(text)` with an extraction that
    # responds to `valid?` and `persistable?` (every processor's Extraction
    # does). A reply
    # that is unusable — vendor failure, unparsable text, or a document that no
    # longer writes anything — comes back as nil, which the caller treats the
    # same as "could not be repaired".
    class DocumentRepair
      def initialize(conversation:, chat:, mode:, instructions:, parser:)
        @conversation = conversation
        @chat = chat
        @mode = mode
        @instructions = instructions
        @parser = parser
      end

      def call(document:, errors:)
        text = complete(messages(document, errors))
        return nil if text.nil?

        repaired = @parser.parse(text)
        repaired if repaired.valid? && repaired.persistable?
      end

      private

      def messages(document, errors)
        prompt_messages + [
          { role: "assistant", content: document.to_json },
          { role: "user", content: [ Prompt::Document.read(@instructions), joined(errors) ].join("\n") }
        ]
      end

      def prompt_messages
        PromptBuilder.call(conversation: @conversation, mode: @mode)
      end

      def complete(messages)
        result = @chat.call(messages)
        return nil unless result.is_a?(Hash) && result[:outcome] == :success

        result[:text].to_s.strip.presence
      end

      def joined(errors)
        Array(errors).map(&:to_s).reject(&:blank?).join("\n")
      end
    end
  end
end
