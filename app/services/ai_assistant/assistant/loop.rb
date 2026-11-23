# frozen_string_literal: true

module AiAssistant
  module Assistant
    # Optional tool round-trips before the existing JSON intent processors.
    # Documents without a "tool" key pass through unchanged.
    class Loop
      MAX_STEPS = 8
      Result = Struct.new(:text, :outcome, keyword_init: true)

      def self.call(text:, conversation:, customer:, chat:, tool_session: nil)
        new(
          text: text,
          conversation: conversation,
          customer: customer,
          chat: chat,
          tool_session: tool_session
        ).call
      end

      def initialize(text:, conversation:, customer:, chat:, tool_session:)
        @text = text
        @conversation = conversation
        @customer = customer
        @chat = chat
        @tool_session = tool_session || Tools::Session.new(
          customer: customer,
          viewer: conversation.user,
          conversation: conversation
        )
      end

      def call
        current = parse(@text)
        return success(@text) unless tool?(current)

        messages = nil
        MAX_STEPS.times do
          messages ||= PromptBuilder.call(conversation: @conversation, mode: :entity)
          result = @tool_session.call(current["tool"], current["arguments"])
          messages += [
            { role: "assistant", content: current.to_json },
            { role: "user", content: { "tool_result" => result }.to_json }
          ]
          reply = @chat.call(messages)
          return Result.new(outcome: :provider_failure) unless reply.is_a?(Hash) &&
                                                                reply[:outcome] == :success

          text = reply[:text].to_s
          current = parse(text) || { "intent" => "chat", "reply" => text }
          return success(current.to_json) unless tool?(current)
        end
        Result.new(outcome: :max_steps)
      end

      private

      def success(text)
        Result.new(text: text, outcome: :success)
      end

      def parse(text)
        value = JSON.parse(text.to_s)
        value.is_a?(Hash) ? value : nil
      rescue JSON::ParserError
        nil
      end

      def tool?(document)
        document.is_a?(Hash) && document["tool"].present?
      end
    end
  end
end
