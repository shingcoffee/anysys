# frozen_string_literal: true

module AiAssistant
  module Assistant
    # Final reply after tool calls. Website documents are routed before this
    # parser; any other intent (including the retired apply_entities) is invalid.
    class ReplyEnvelope
      module Intent
        CHAT = "chat"
        CLARIFY = "clarify"
        ALL = [CHAT, CLARIFY].freeze
      end

      attr_reader :intent, :reply, :error, :questions, :assumptions, :flowchart_requested

      def self.parse(text)
        new(text).tap(&:decode!)
      end

      def initialize(text)
        @text = text.to_s
        @questions = []
        @assumptions = []
        @flowchart_requested = false
      end

      def valid?
        error.nil?
      end

      def decode!
        document = JsonDocument.parse(@text)
        return decode_plain_text if document.nil?

        document = document.deep_stringify_keys if document.is_a?(Hash)
        return reject! unless document.is_a?(Hash)

        @questions = Questions.sanitize(document["questions"])
        @assumptions = Questions.sanitize_assumptions(document["assumptions"])
        @flowchart_requested = document["flowchart"] == true
        @intent = document["intent"].to_s
        @intent = Intent::CLARIFY if @questions.any?
        @reply = document["reply"]
        return reject! unless Intent::ALL.include?(@intent)
        return assign_reply! if @reply.is_a?(String) && @reply.strip.present?
        return fallback_reply! if @questions.any?

        reject!
      end

      private

      def decode_plain_text
        stripped = @text.strip
        return reject! if stripped.empty? || stripped.lstrip.start_with?("{")

        @intent = Intent::CHAT
        @reply = stripped
        self
      end

      def assign_reply!
        @reply = @reply.strip
        self
      end

      def fallback_reply!
        @reply = I18n.t("ai_assistant.assistant.questions.intro")
        self
      end

      def reject!
        @error = :invalid
        self
      end
    end
  end
end
