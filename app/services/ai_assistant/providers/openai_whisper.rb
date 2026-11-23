# frozen_string_literal: true

require "openai"

# AiAssistant::Providers (registry) is referenced by `register!` / `default!`
# at class-body load time. Force-load it so this file is safe to require in
# isolation (eager load may hit openai_whisper.rb before providers.rb).
require_relative "../providers"

module AiAssistant
  module Providers
    # OpenAI Whisper via the ruby-openai gem. All Whisper HTTP stays in this
    # file — controllers and Puma request threads must never construct
    # OpenAI::Client, except the platform-owner "Test connection" probe
    # (#health_check), which runs live.
    class OpenaiWhisper < Base
      DEFAULT_MODEL = "whisper-1"
      DEFAULT_CHAT_MODEL = "gpt-4o-mini"

      # ruby-openai only sets Faraday's read timeout, and defaults it to 120s
      # from its global configuration — long enough for one hung vendor call to
      # hold a Solid Queue worker for two minutes, with no connect timeout at
      # all. Both are pinned explicitly here, in line with the open/read
      # timeouts the Aliyun provider sets.
      OPEN_TIMEOUT    = 5
      REQUEST_TIMEOUT = 60

      # A 429 is transient; every other 4xx is this app's request or credentials.
      RETRYABLE_CLIENT_STATUS = 429

      class << self
        def key                  = "openai_whisper"
        def default_display_name = "OpenAI Whisper"

        def config_fields
          [
            { name: :model, label: "Model", type: :string, default: DEFAULT_MODEL },
            { name: :chat_model, label: "Chat model", type: :string, default: DEFAULT_CHAT_MODEL },
            { name: :organization, label: "Organization", type: :string }
          ]
        end

        def configured?(settings)
          settings.api_key.present?
        end

        def supports_generation? = true
        def supports_native_tools? = true
        def supports_streaming?  = true
      end

      register!
      default!

      def transcribe(io:, filename:, content_type:, language: nil)
        return { outcome: :configuration_error, text: nil, raw: nil } unless self.class.configured?(settings)

        parameters = {
          model: settings.config_value(:model, DEFAULT_MODEL).presence || DEFAULT_MODEL,
          file: io
        }
        mapped = mapped_language(language)
        parameters[:language] = mapped if mapped

        response = client.audio.transcribe(parameters: parameters)
        text = extract_text(response)
        if text.blank?
          { outcome: :empty, text: nil, raw: response }
        else
          { outcome: :success, text: text, raw: response }
        end
      rescue Faraday::Error => e
        map_faraday(e)
      end

      def chat(messages:, tools: nil, on_chunk: nil, before_request: nil, before_tool_call: nil)
        return { outcome: :configuration_error, text: nil, raw: nil } unless self.class.configured?(settings)
        return AiAssistant::ScriptedCompletion.call(messages: messages) if AiAssistant::ScriptedCompletion.enabled?

        native = Array(tools).compact
        Llm.complete(
          provider: :openai,
          model: settings.config_value(:chat_model, DEFAULT_CHAT_MODEL).presence || DEFAULT_CHAT_MODEL,
          messages: messages,
          api_key: settings.api_key,
          organization: settings.config_value(:organization).presence,
          json: native.empty?,
          tools: native.presence,
          request_timeout: REQUEST_TIMEOUT,
          on_chunk: on_chunk, before_request: before_request, before_tool_call: before_tool_call
        )
      end

      private

      def client
        opts = { access_token: settings.api_key, request_timeout: REQUEST_TIMEOUT }
        org = settings.config_value(:organization).presence
        opts[:organization_id] = org if org
        # The gem exposes no connect-timeout option, so reach the Faraday
        # connection through its documented middleware hook.
        OpenAI::Client.new(opts) { |connection| connection.options.open_timeout = OPEN_TIMEOUT }
      end

      def mapped_language(language)
        code = language.to_s.strip
        return nil if code.blank? || code == "auto"
        return "zh" if code == "zh-CN"

        code
      end

      def extract_text(response)
        case response
        when Hash then (response["text"] || response[:text]).to_s.strip
        else response.to_s.strip
        end
      end

      # ruby-openai installs Faraday's `raise_error` middleware, so every HTTP
      # failure surfaces as a Faraday::Error subclass carrying #response_status,
      # and connect/read timeouts surface as Faraday::TimeoutError with none.
      # Any 4xx other than 429 is the caller's own request or credentials — a
      # bad model name (404) is a configuration problem, not vendor downtime.
      # 429 and 5xx are transient, so they stay :unreachable and the widget
      # tells the user to retry.
      def map_faraday(error)
        status = faraday_status(error)
        raw = { "error" => error.message, "status" => status }
        if status != RETRYABLE_CLIENT_STATUS && (400..499).cover?(status)
          { outcome: :configuration_error, text: nil, raw: raw }
        else
          { outcome: :unreachable, text: nil, raw: raw }
        end
      end

      def faraday_status(error)
        if error.respond_to?(:response_status) && error.response_status
          error.response_status.to_i
        elsif error.respond_to?(:response) && error.response.is_a?(Hash)
          error.response[:status].to_i
        else
          0
        end
      end
    end
  end
end
