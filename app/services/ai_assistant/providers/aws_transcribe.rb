# frozen_string_literal: true

require "open3"
require "timeout"
require "aws-sdk-transcribestreamingservice"

# AiAssistant::Providers (registry) is referenced by `register!` at
# class-body load time. Force-load it so this file is safe to require in
# isolation (eager load may hit this file before providers.rb).
require_relative "../providers"

module AiAssistant
  module Providers
    # AWS Transcribe Streaming (StartStreamTranscription over HTTP/2).
    # MediaRecorder webm/opus (and the other families the upload contract
    # accepts) are transcoded to 16 kHz mono signed-LE PCM with ffmpeg and
    # piped into StartStreamTranscription as they are produced. Chunks are
    # ~100ms and sent at 8× realtime so a dictation is not replayed at 1×.
    # Dumping the buffer with no pace closes the HTTP/2 window; if that
    # still happens, one retry at 2×. No S3 and no batch poll.
    #
    # Transcription only — #chat stays on Base (fail closed).
    class AwsTranscribe < Base
      DEFAULT_REGION     = "us-east-1"
      SAMPLE_RATE_HZ     = 16_000
      # 100ms of s16le mono — AWS streaming wants 50–200ms chunks so the
      # HTTP/2 window stays bidirectional.
      CHUNK_BYTES        = SAMPLE_RATE_HZ * 2 / 10
      PACE_MULTIPLIER    = 8
      RETRY_PACE_MULTIPLIER = 2
      # After the last real audio, pad 1s of PCM silence and wait before
      # closing so AWS endpointing can emit a final (short dashboard clips
      # otherwise leave only partials).
      TRAILING_SILENCE_SECONDS = 1
      FLUSH_SLEEP        = 1.0
      # 8× send can still trail AWS finals; cover the slow-retry pace plus slack.
      STREAM_TIMEOUT     = SpeechToText::DurationPolicy::ABSOLUTE_MAX_DURATION / 2 + 30
      # Streaming IdentifyLanguage requires two or more codes. These are the
      # locales the rest of the module already maps (`en` / `zh-CN`).
      LANGUAGE_OPTIONS   = "en-US,zh-CN"
      FFMPEG = [
        "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error",
        "-i", "pipe:0",
        "-f", "s16le", "-acodec", "pcm_s16le",
        "-ac", "1", "-ar", SAMPLE_RATE_HZ.to_s,
        "pipe:1"
      ].freeze

      STREAM_ERROR_EVENTS = {
        on_bad_request_exception_event:          :configuration_error,
        on_limit_exceeded_exception_event:       :configuration_error,
        on_conflict_exception_event:             :configuration_error,
        on_internal_failure_exception_event:     :unreachable,
        on_service_unavailable_exception_event:  :unreachable,
        on_error_event:                          :unreachable
      }.freeze

      class << self
        def key                  = "aws_transcribe"
        def default_display_name = "AWS Transcribe"

        def config_fields
          [
            { name: :access_key_id, label: "Access Key ID", type: :string, required: true },
            { name: :region,        label: "Region",        type: :string, default: DEFAULT_REGION }
          ]
        end

        def configured?(settings)
          settings.api_key.present? && settings.config_value(:access_key_id).present?
        end
      end

      register!

      def transcribe(io:, filename:, content_type:, language: nil) # rubocop:disable Lint/UnusedMethodArgument
        return { outcome: :configuration_error, text: nil, raw: nil } unless self.class.configured?(settings)

        bytes = io.respond_to?(:read) ? io.read : io.to_s
        paced_transcribe(bytes, language)
      rescue StreamFailed => e
        { outcome: e.payload[:outcome], text: nil, raw: { "error" => e.payload[:message] } }
      rescue Timeout::Error => e
        { outcome: :unreachable, text: nil, raw: { "error" => e.message } }
      rescue Aws::Errors::MissingCredentialsError => e
        { outcome: :configuration_error, text: nil, raw: { "error" => e.message } }
      rescue Aws::Errors::ServiceError => e
        map_aws_error(e)
      rescue Seahorse::Client::Http2ConnectionClosedError => e
        { outcome: :unreachable, text: nil, raw: http2_closed_raw(e) }
      rescue Seahorse::Client::NetworkingError, Aws::Errors::NoSuchEndpointError => e
        { outcome: :unreachable, text: nil, raw: { "error" => e.message } }
      rescue Errno::ECONNRESET, Errno::EPIPE => e
        { outcome: :unreachable, text: nil, raw: { "error" => e.message } }
      rescue Errno::ENOENT => e
        { outcome: :configuration_error, text: nil, raw: { "error" => e.message } }
      end

      private

      def client_options
        {
          access_key_id:     settings.config_value(:access_key_id).to_s,
          secret_access_key: settings.api_key.to_s,
          region:            settings.config_value(:region, DEFAULT_REGION).presence || DEFAULT_REGION
        }
      end

      def stream_client
        @stream_client ||= Aws::TranscribeStreamingService::AsyncClient.new(**client_options)
      end

      def paced_transcribe(bytes, language)
        transcode_and_stream(bytes, language, PACE_MULTIPLIER)
      rescue Seahorse::Client::Http2ConnectionClosedError
        transcode_and_stream(bytes, language, RETRY_PACE_MULTIPLIER)
      end

      def transcode_and_stream(bytes, language, pace)
        Timeout.timeout(STREAM_TIMEOUT) do
          Open3.popen3(*FFMPEG) do |stdin, stdout, stderr, wait_thr|
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

            begin
              first = stdout.read(CHUNK_BYTES)
              if first.nil? || first.empty?
                join_ffmpeg(writer, err_reader)
                return ffmpeg_exit(wait_thr.value, err_reader.value)
              end

              text, raw = stream_pcm(stdout, language, pace, first_chunk: first)
              join_ffmpeg(writer, err_reader)
              err = err_reader.value.to_s
              status = wait_thr.value
              unless status&.success?
                return { outcome: :configuration_error, text: nil, raw: { "error" => err.presence || "ffmpeg failed" } }
              end

              if text.blank?
                { outcome: :empty, text: nil, raw: raw }
              else
                { outcome: :success, text: text, raw: raw }
              end
            ensure
              join_ffmpeg(writer, err_reader)
            end
          end
        end
      end

      def join_ffmpeg(writer, err_reader)
        writer.join(2) if writer&.alive?
        err_reader.join(2) if err_reader&.alive?
      end

      def ffmpeg_exit(status, stderr)
        err = stderr.to_s
        unless status&.success?
          return { outcome: :configuration_error, text: nil, raw: { "error" => err.presence || "ffmpeg failed" } }
        end

        { outcome: :empty, text: nil, raw: nil }
      end

      def stream_pcm(pcm_io, language, pace, first_chunk:)
        finals = []
        last_partial = { "text" => nil }
        stream_error = nil
        async_resp = nil
        finished = false

        input_stream = Aws::TranscribeStreamingService::EventStreams::AudioStream.new
        output_stream = Aws::TranscribeStreamingService::EventStreams::TranscriptResultStream.new

        output_stream.on_transcript_event_event do |event|
          collect_transcripts(event, finals, last_partial)
        end
        STREAM_ERROR_EVENTS.each do |hook, outcome|
          output_stream.public_send(hook) do |event|
            stream_error ||= { outcome: outcome, message: event_message(event) }
          end
        end

        async_resp = stream_client.start_stream_transcription(
          stream_params(language).merge(
            input_event_stream_handler: input_stream,
            output_event_stream_handler: output_stream
          )
        )
        send_pcm(input_stream, pcm_io, pace, first_chunk: first_chunk)
        async_resp.wait
        finished = true

        raise StreamFailed, stream_error if stream_error

        text = finals.join(" ").strip
        text = last_partial["text"].to_s.strip if text.blank?
        [ text, { "transcripts" => finals } ]
      ensure
        close_hung_stream(async_resp) unless finished
      end

      # Dumping the whole buffer closes the HTTP/2 connection before finals
      # arrive. Pace faster than realtime (clips are ≤ 120s, so AWS's 5-minute
      # signing window is not a concern) with small chunks so the return path
      # still has window.
      def send_pcm(input_stream, pcm_io, pace, first_chunk:)
        pending = first_chunk
        loop do
          nxt = pcm_io.read(CHUNK_BYTES)
          input_stream.signal_audio_event_event(audio_chunk: pending)
          break if nxt.nil? || nxt.empty?

          sleep(chunk_sleep(pending.bytesize, pace))
          pending = nxt
        end
        send_trailing_silence(input_stream, pace)
        sleep(FLUSH_SLEEP)
        input_stream.signal_end_stream
      end

      def send_trailing_silence(input_stream, pace)
        remaining = SAMPLE_RATE_HZ * 2 * TRAILING_SILENCE_SECONDS
        while remaining.positive?
          size = [ CHUNK_BYTES, remaining ].min
          input_stream.signal_audio_event_event(audio_chunk: ("\x00".b * size))
          remaining -= size
          sleep(chunk_sleep(size, pace))
        end
      end

      def chunk_sleep(bytes, pace)
        bytes.to_f / (SAMPLE_RATE_HZ * 2 * pace)
      end

      def close_hung_stream(async_resp)
        async_resp.join! if async_resp.respond_to?(:join!)
      rescue Seahorse::Client::Http2ConnectionClosedError
        nil
      end

      def http2_closed_raw(error)
        extras = []
        if @stream_client.respond_to?(:connection_errors)
          extras = Array(@stream_client.connection_errors).map { |err| "#{err.class}: #{err.message}" }
        end
        { "error" => error.message, "connection_errors" => extras }
      end

      def collect_transcripts(event, finals, last_partial)
        Array(event.transcript&.results).each do |result|
          text = Array(result.alternatives).first&.transcript.to_s.strip
          next if text.empty?

          if result.is_partial
            last_partial["text"] = text
          else
            finals << text
          end
        end
      end

      def stream_params(language)
        mapped = mapped_language(language)
        params = {
          media_encoding: "pcm",
          media_sample_rate_hertz: SAMPLE_RATE_HZ
        }
        if mapped
          params[:language_code] = mapped
        else
          params[:identify_language] = true
          params[:language_options] = LANGUAGE_OPTIONS
        end
        params
      end

      def mapped_language(language)
        code = language.to_s.strip
        return nil if code.blank? || code == "auto"
        return "en-US" if code == "en"
        return "zh-CN" if code == "zh-CN"

        code
      end

      def event_message(event)
        return event.message.to_s if event.respond_to?(:message)
        return event.error_message.to_s if event.respond_to?(:error_message)

        event.to_s
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
        return true if status.between?(400, 499)
        return true if error.is_a?(Aws::Errors::MissingCredentialsError)

        codes = %w[
          AccessDenied AccessDeniedException InvalidAccessKeyId InvalidClientTokenId
          SignatureDoesNotMatch UnrecognizedClient UnrecognizedClientException BadRequestException
        ]
        code = error.respond_to?(:code) ? error.code.to_s : ""
        codes.include?(code) || codes.include?(error.class.name.split("::").last)
      end

      # Raised when the HTTP/2 output stream delivers an exception event after
      # start_stream_transcription has already returned. Mapped in #transcribe.
      class StreamFailed < StandardError
        attr_reader :payload

        def initialize(payload)
          @payload = payload
          super(payload[:message].to_s)
        end
      end
    end
  end
end
