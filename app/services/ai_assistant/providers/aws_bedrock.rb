# frozen_string_literal: true

require "open3"
require "timeout"
require "aws-sdk-bedrockruntime"

# AiAssistant::Providers (registry) is referenced by `register!` at
# class-body load time. Force-load it so this file is safe to require in
# isolation (eager load may hit this file before providers.rb).
require_relative "../providers"

module AiAssistant
  module Providers
    # AWS Bedrock Converse. Transcription sends the clip as an audio content
    # block (Nova understands wav/mp3/ogg/aac/flac/mp4; other containers are
    # ffmpeg'd to wav). Generation goes through Llm / RubyLLM :bedrock.
    # Controllers and Puma request threads must never construct this client,
    # except the platform-owner "Test connection" probe (#health_check), which
    # runs live.
    class AwsBedrock < Base
      DEFAULT_REGION = "us-east-1"
      DEFAULT_MODEL = "amazon.nova-lite-v1:0"
      DEFAULT_CHAT_MODEL = "amazon.nova-lite-v1:0"
      OPEN_TIMEOUT = 5
      REQUEST_TIMEOUT = 60
      SAMPLE_RATE_HZ = 16_000
      RETRYABLE_CLIENT_STATUS = 429
      TRANSCRIBE_PROMPT =
        "Transcribe the spoken audio. Return only the transcript text with no quotes or commentary."
      PASS_THROUGH_FORMATS = %w[wav mp3 ogg opus aac flac mp4].freeze
      FFMPEG_WAV = [
        "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error",
        "-i", "pipe:0",
        "-f", "wav", "-acodec", "pcm_s16le",
        "-ac", "1", "-ar", SAMPLE_RATE_HZ.to_s,
        "pipe:1"
      ].freeze

      class << self
        def key                  = "aws_bedrock"
        def default_display_name = "AWS Bedrock"

        def config_fields
          [
            { name: :access_key_id, label: "Access Key ID", type: :string, required: true },
            { name: :region,        label: "Region",        type: :string, default: DEFAULT_REGION },
            { name: :model,         label: "Model",         type: :string, default: DEFAULT_MODEL },
            { name: :chat_model,    label: "Chat model",    type: :string, default: DEFAULT_CHAT_MODEL }
          ]
        end

        def configured?(settings)
          settings.api_key.present? && settings.config_value(:access_key_id).present?
        end

        def supports_generation? = true
        def supports_native_tools? = true
        def supports_streaming?  = true
      end

      register!

      def transcribe(io:, filename:, content_type:, language: nil)
        return { outcome: :configuration_error, text: nil, raw: nil } unless self.class.configured?(settings)

        bytes, format = audio_payload(io, filename, content_type)
        response = runtime_client.converse(converse_params(bytes, format, language))
        text = extract_text(response)
        if text.blank?
          { outcome: :empty, text: nil, raw: raw_of(response) }
        else
          { outcome: :success, text: text, raw: raw_of(response) }
        end
      rescue TranscodeFailed => e
        { outcome: :configuration_error, text: nil, raw: { "error" => e.message } }
      rescue Timeout::Error => e
        { outcome: :unreachable, text: nil, raw: { "error" => e.message } }
      rescue Aws::Errors::MissingCredentialsError => e
        { outcome: :configuration_error, text: nil, raw: { "error" => e.message } }
      rescue Aws::BedrockRuntime::Errors::ServiceError, Aws::Errors::ServiceError => e
        map_aws_error(e)
      rescue Seahorse::Client::NetworkingError, Aws::Errors::NoSuchEndpointError => e
        { outcome: :unreachable, text: nil, raw: { "error" => e.message } }
      rescue Errno::ENOENT => e
        { outcome: :configuration_error, text: nil, raw: { "error" => e.message } }
      end

      def chat(messages:, tools: nil, on_chunk: nil, before_request: nil, before_tool_call: nil)
        return { outcome: :configuration_error, text: nil, raw: nil } unless self.class.configured?(settings)
        return AiAssistant::ScriptedCompletion.call(messages: messages) if AiAssistant::ScriptedCompletion.enabled?

        native = Array(tools).compact
        Llm.complete(
          provider: :bedrock,
          model: settings.config_value(:chat_model, DEFAULT_CHAT_MODEL).presence || DEFAULT_CHAT_MODEL,
          messages: messages,
          api_key: settings.api_key,
          access_key_id: settings.config_value(:access_key_id),
          region: settings.config_value(:region, DEFAULT_REGION).presence || DEFAULT_REGION,
          json: native.empty?,
          tools: native.presence,
          request_timeout: REQUEST_TIMEOUT,
          on_chunk: on_chunk, before_request: before_request, before_tool_call: before_tool_call
        )
      end

      # Nova Lite/Pro v1 reject Converse `audio` blocks (Sonic / Nova 2 Omni
      # only). A silent-WAV #transcribe therefore always 4xx's on the default
      # model, which Test connection would misread as bad credentials. Ping
      # with text instead — same keys, modality the chat model accepts.
      def health_check
        return { outcome: :configuration_error, text: nil, raw: nil } unless self.class.configured?(settings)

        response = runtime_client.converse(health_converse_params)
        { outcome: :success, text: nil, raw: raw_of(response) }
      rescue Timeout::Error => e
        { outcome: :unreachable, text: nil, raw: { "error" => e.message } }
      rescue Aws::Errors::MissingCredentialsError => e
        { outcome: :configuration_error, text: nil, raw: { "error" => e.message } }
      rescue Aws::BedrockRuntime::Errors::ServiceError, Aws::Errors::ServiceError => e
        map_aws_error(e)
      rescue Seahorse::Client::NetworkingError, Aws::Errors::NoSuchEndpointError => e
        { outcome: :unreachable, text: nil, raw: { "error" => e.message } }
      end

      private

      def runtime_client
        @runtime_client ||= Aws::BedrockRuntime::Client.new(
          access_key_id: settings.config_value(:access_key_id).to_s,
          secret_access_key: settings.api_key.to_s,
          region: settings.config_value(:region, DEFAULT_REGION).presence || DEFAULT_REGION,
          http_open_timeout: OPEN_TIMEOUT,
          http_read_timeout: REQUEST_TIMEOUT
        )
      end

      def audio_payload(io, filename, content_type)
        bytes = io.respond_to?(:read) ? io.read : io.to_s
        format = SpeechToText::AudioFormats.vendor_format(
          :bedrock, filename: filename, content_type: content_type
        )
        return [ bytes, format ] if PASS_THROUGH_FORMATS.include?(format)

        [ transcode_wav(bytes), "wav" ]
      end

      def transcode_wav(bytes)
        Timeout.timeout(REQUEST_TIMEOUT) do
          Open3.popen3(*FFMPEG_WAV) do |stdin, stdout, stderr, wait_thr|
            stdin.binmode
            stdout.binmode
            stderr.binmode
            writer = Thread.new do
              stdin.write(bytes)
            rescue Errno::EPIPE
              nil
            ensure
              stdin.close
            end
            err_reader = Thread.new { stderr.read }
            wav = stdout.read
            writer.join(2) if writer.alive?
            err_reader.join(2) if err_reader.alive?
            status = wait_thr.value
            err = err_reader.value.to_s
            unless status&.success?
              raise TranscodeFailed, err.presence || "ffmpeg failed"
            end
            raise TranscodeFailed, "ffmpeg produced no audio" if wav.blank?

            wav
          end
        end
      end

      def converse_params(bytes, format, language)
        {
          model_id: settings.config_value(:model, DEFAULT_MODEL).presence || DEFAULT_MODEL,
          messages: [
            {
              role: "user",
              content: [
                { audio: { format: format, source: { bytes: bytes } } },
                { text: transcribe_prompt(language) }
              ]
            }
          ]
        }
      end

      def health_converse_params
        {
          model_id: settings.config_value(:chat_model, DEFAULT_CHAT_MODEL).presence || DEFAULT_CHAT_MODEL,
          messages: [ { role: "user", content: [ { text: "ping" } ] } ]
        }
      end

      def transcribe_prompt(language)
        mapped = mapped_language(language)
        return TRANSCRIBE_PROMPT unless mapped

        "#{TRANSCRIBE_PROMPT} The speech is in #{mapped}."
      end

      def mapped_language(language)
        code = language.to_s.strip
        return nil if code.blank? || code == "auto"
        return "English" if code == "en"
        return "Chinese" if code == "zh-CN"

        code
      end

      def extract_text(response)
        payload = response.respond_to?(:to_h) ? response.to_h : {}
        payload = payload.deep_symbolize_keys if payload.respond_to?(:deep_symbolize_keys)
        Array(payload.dig(:output, :message, :content)).filter_map do |block|
          next unless block.is_a?(Hash)

          block[:text].to_s
        end.join.strip
      end

      def raw_of(response)
        response.respond_to?(:to_h) ? response.to_h : response
      end

      def map_aws_error(error)
        status = error.respond_to?(:context) ? error.context&.http_response&.status_code.to_i : 0
        raw = { "error" => error.message, "status" => status }
        if client_error?(error, status)
          { outcome: :configuration_error, text: nil, raw: raw }
        else
          { outcome: :unreachable, text: nil, raw: raw }
        end
      end

      def client_error?(error, status)
        return false if status == RETRYABLE_CLIENT_STATUS
        return true if status.between?(400, 499)
        return true if error.is_a?(Aws::Errors::MissingCredentialsError)

        codes = %w[
          AccessDenied AccessDeniedException InvalidAccessKeyId InvalidClientTokenId
          SignatureDoesNotMatch UnrecognizedClient UnrecognizedClientException
          ValidationException ResourceNotFoundException
        ]
        code = error.respond_to?(:code) ? error.code.to_s : ""
        codes.include?(code) || codes.include?(error.class.name.split("::").last)
      end

      class TranscodeFailed < StandardError; end
    end
  end
end
