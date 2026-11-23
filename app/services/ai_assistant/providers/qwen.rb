# frozen_string_literal: true

# AiAssistant::Providers (registry) is referenced by `register!` at
# class-body load time. Force-load it so this file is safe to require in
# isolation (eager load may hit this file before providers.rb).
require_relative "../providers"

module AiAssistant
  module Providers
    # Qwen (DashScope OpenAI-compatible) via Llm / RubyLLM :openai with a
    # DashScope base URL. Generation only — #transcribe fail-closes.
    # #chat runs from jobs and must never run on a Puma request thread;
    # #health_check is a single bounded call that the platform-owner "Test
    # connection" button runs live.
    class Qwen < Base
      DEFAULT_CHAT_MODEL = "qwen-plus"
      REQUEST_TIMEOUT = 60
      HEALTH_TIMEOUT = 30

      class << self
        def key                  = "qwen"
        def default_display_name = "Qwen"

        def config_fields
          [
            { name: :chat_model, label: "Chat model", type: :string, default: DEFAULT_CHAT_MODEL }
          ]
        end

        def configured?(settings)
          settings.api_key.present?
        end

        def supports_transcribe? = false
        def supports_generation? = true
        def supports_native_tools? = true
        def supports_streaming?  = true
      end

      register!

      def transcribe(io:, filename:, content_type:, language: nil) # rubocop:disable Lint/UnusedMethodArgument
        { outcome: :configuration_error, text: nil, raw: nil }
      end

      def chat(messages:, tools: nil, on_chunk: nil, before_request: nil, before_tool_call: nil)
        return { outcome: :configuration_error, text: nil, raw: nil } unless self.class.configured?(settings)
        return AiAssistant::ScriptedCompletion.call(messages: messages) if AiAssistant::ScriptedCompletion.enabled?

        complete_chat(
          messages: messages, tools: tools, request_timeout: REQUEST_TIMEOUT, on_chunk: on_chunk,
          before_request: before_request, before_tool_call: before_tool_call
        )
      end

      def health_check
        return { outcome: :configuration_error, text: nil, raw: nil } unless self.class.configured?(settings)

        result = complete_chat(
          messages: [ { role: "user", content: "ping" } ],
          tools: nil,
          request_timeout: HEALTH_TIMEOUT,
          json: false
        )
        case result[:outcome]
        when :success, :empty then { outcome: :success, text: nil, raw: result[:raw] }
        else result
        end
      end

      private

      def complete_chat(messages:, tools:, request_timeout:, json: nil, on_chunk: nil,
                        before_request: nil, before_tool_call: nil)
        native = Array(tools).compact
        Llm.complete(
          provider: :qwen,
          model: settings.config_value(:chat_model, DEFAULT_CHAT_MODEL).presence || DEFAULT_CHAT_MODEL,
          messages: messages,
          api_key: settings.api_key,
          json: json.nil? ? native.empty? : json,
          tools: native.presence,
          request_timeout: request_timeout,
          on_chunk: on_chunk, before_request: before_request, before_tool_call: before_tool_call
        )
      end
    end
  end
end
