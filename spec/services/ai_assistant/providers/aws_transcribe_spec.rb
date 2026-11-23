# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Providers::AwsTranscribe do
  let(:settings) do
    build_stubbed(:ai_assistant_provider_settings,
                  provider: "aws_transcribe",
                  api_key: "secret",
                  config: { access_key_id: "AKID", region: "us-east-1" }.to_json)
  end
  let(:adapter) { described_class.new(settings: settings) }
  let(:async_client) { instance_double(Aws::TranscribeStreamingService::AsyncClient) }
  let(:input_stream) do
    instance_double(Aws::TranscribeStreamingService::EventStreams::AudioStream,
                    signal_audio_event_event: nil, signal_end_stream: nil)
  end
  let(:output_stream) { instance_double(Aws::TranscribeStreamingService::EventStreams::TranscriptResultStream) }
  let(:async_resp) { instance_double("AsyncResponse") }
  let(:io) { StringIO.new("fake-webm") }
  let(:pcm) { "P" * (described_class::CHUNK_BYTES + 12) }

  def transcribe(language: "en")
    adapter.transcribe(io: io, filename: "clip.webm", content_type: "audio/webm", language: language)
  end

  def stub_ffmpeg(stdout_bytes: pcm, stderr_bytes: "", success: true)
    status = instance_double(Process::Status, success?: success)
    wait_thr = instance_double(Process::Waiter, value: status)
    allow(Open3).to receive(:popen3) do |*_args, &block|
      stdin = StringIO.new
      stdout = StringIO.new(stdout_bytes)
      stderr = StringIO.new(stderr_bytes)
      block.call(stdin, stdout, stderr, wait_thr)
    end
  end

  def stub_transcript_event(text:, partial: false)
    alt = instance_double("Alternative", transcript: text)
    result = instance_double("Result", is_partial: partial, alternatives: [ alt ])
    transcript = instance_double("Transcript", results: [ result ])
    instance_double("TranscriptEvent", transcript: transcript)
  end

  before do
    stub_ffmpeg
    allow(Aws::TranscribeStreamingService::AsyncClient).to receive(:new).and_return(async_client)
    allow(Aws::TranscribeStreamingService::EventStreams::AudioStream).to receive(:new).and_return(input_stream)
    allow(Aws::TranscribeStreamingService::EventStreams::TranscriptResultStream).to receive(:new).and_return(output_stream)
    allow(output_stream).to receive(:on_transcript_event_event) { |&block| @on_transcript = block }
    %i[
      on_bad_request_exception_event
      on_limit_exceeded_exception_event
      on_internal_failure_exception_event
      on_conflict_exception_event
      on_service_unavailable_exception_event
      on_error_event
    ].each { |name| allow(output_stream).to receive(name) }
    allow(async_client).to receive(:start_stream_transcription).and_return(async_resp)
    allow(async_client).to receive(:connection_errors).and_return([])
    allow(adapter).to receive(:sleep)
    allow(async_resp).to receive(:wait) do
      @on_transcript&.call(stub_transcript_event(text: "hello world"))
      true
    end
  end

  it_behaves_like "an AI Assistant registered provider",
                  key: "aws_transcribe",
                  display_name: "AWS Transcribe",
                  supports_transcribe: true,
                  supports_generation: false,
                  config_fields: %i[access_key_id region],
                  configured_on_api_key: false

  describe ".configured?" do
    it "is false when required credentials are blank" do
      bare = build(:ai_assistant_provider_settings, provider: "aws_transcribe", api_key: nil, config: {}.to_json)
      expect(described_class.configured?(bare)).to eq(false)
    end

    it "is true when secret and access key id are present" do
      expect(described_class.configured?(settings)).to eq(true)
    end
  end

  describe "#transcribe" do
    it "transcodes to PCM, streams it, and returns the final transcript without calling AWS" do
      result = transcribe
      expect(result[:outcome]).to eq(:success)
      expect(result[:text]).to eq("hello world")
      expect(Open3).to have_received(:popen3).with(*described_class::FFMPEG)
      expect(input_stream).to have_received(:signal_audio_event_event).at_least(2).times
      expect(input_stream).to have_received(:signal_end_stream)
      expect(async_resp).to have_received(:wait)
    end

    it "sends PCM in chunks of at most 100ms (3200 bytes at 16 kHz s16le)" do
      allow(input_stream).to receive(:signal_audio_event_event) do |audio_chunk:|
        expect(audio_chunk.bytesize).to be <= 3200
      end
      transcribe
    end

    it "appends one second of silent PCM after the clip so AWS can finalize the last utterance" do
      silent = []
      allow(input_stream).to receive(:signal_audio_event_event) do |audio_chunk:|
        silent << audio_chunk.dup if audio_chunk.present? && audio_chunk.bytes.uniq == [ 0 ]
      end
      transcribe
      expect(silent.sum(&:bytesize)).to eq(described_class::SAMPLE_RATE_HZ * 2)
      expect(input_stream).to have_received(:signal_end_stream)
    end

    it "sleeps one eighth of each chunk's audio duration between sends" do
      chunks = []
      allow(input_stream).to receive(:signal_audio_event_event) do |audio_chunk:|
        chunks << audio_chunk.dup
      end
      transcribe
      expect(chunks.size).to be >= 2
      expected = chunks.first.bytesize.to_f / (described_class::SAMPLE_RATE_HZ * 2 * 8)
      expect(adapter).to have_received(:sleep).with(a_value_within(1e-9).of(expected)).at_least(:once)
    end

    it "pipes ffmpeg stdout into the stream instead of buffering the whole PCM file" do
      transcribe
      expect(Open3).to have_received(:popen3).with(*described_class::FFMPEG)
    end

    it "retries once at half speed when the HTTP/2 window closes on the fast send" do
      calls = 0
      allow(async_client).to receive(:start_stream_transcription) do |*_args|
        calls += 1
        raise Seahorse::Client::Http2ConnectionClosedError, "closed" if calls == 1

        async_resp
      end
      result = transcribe
      expect(result[:outcome]).to eq(:success)
      expect(calls).to eq(2)
      expected = pcm.byteslice(0, described_class::CHUNK_BYTES).bytesize.to_f /
        (described_class::SAMPLE_RATE_HZ * 2 * 2)
      expect(adapter).to have_received(:sleep).with(a_value_within(1e-9).of(expected)).at_least(:once)
    end

    it "ignores partial results and concatenates finals" do
      allow(async_resp).to receive(:wait) do
        @on_transcript.call(stub_transcript_event(text: "ignore me", partial: true))
        @on_transcript.call(stub_transcript_event(text: "first"))
        @on_transcript.call(stub_transcript_event(text: "second"))
        true
      end
      expect(transcribe[:text]).to eq("first second")
    end

    it "falls back to the last non-empty partial when AWS never sends a final" do
      allow(async_resp).to receive(:wait) do
        @on_transcript.call(stub_transcript_event(text: "现在是", partial: true))
        @on_transcript.call(stub_transcript_event(text: "现在是北京时间几点了?", partial: true))
        true
      end
      result = transcribe
      expect(result[:outcome]).to eq(:success)
      expect(result[:text]).to eq("现在是北京时间几点了?")
    end

    it "identifies language when language is auto and sends the two app locales as options" do
      expect(async_client).to receive(:start_stream_transcription) do |params|
        expect(params).not_to have_key(:language_code)
        expect(params[:identify_language]).to eq(true)
        expect(params[:language_options]).to eq("en-US,zh-CN")
        expect(params).not_to have_key(:preferred_language)
        expect(params[:media_encoding]).to eq("pcm")
        expect(params[:media_sample_rate_hertz]).to eq(16_000)
        async_resp
      end
      transcribe(language: "auto")
    end

    it "maps en to en-US" do
      expect(async_client).to receive(:start_stream_transcription)
        .with(hash_including(language_code: "en-US", media_encoding: "pcm"))
        .and_return(async_resp)
      transcribe(language: "en")
    end

    it "maps zh-CN to zh-CN" do
      expect(async_client).to receive(:start_stream_transcription)
        .with(hash_including(language_code: "zh-CN"))
        .and_return(async_resp)
      transcribe(language: "zh-CN")
    end

    it "returns :empty when every final transcript is blank" do
      allow(async_resp).to receive(:wait) do
        @on_transcript.call(stub_transcript_event(text: "  "))
        true
      end
      expect(transcribe[:outcome]).to eq(:empty)
    end

    it "returns :empty when ffmpeg emits no PCM" do
      stub_ffmpeg(stdout_bytes: "")
      expect(async_client).not_to receive(:start_stream_transcription)
      expect(transcribe[:outcome]).to eq(:empty)
    end

    it "returns :configuration_error when credentials are missing without calling AWS or ffmpeg" do
      settings.api_key = nil
      expect(Open3).not_to receive(:popen3)
      expect(Aws::TranscribeStreamingService::AsyncClient).not_to receive(:new)
      expect(transcribe[:outcome]).to eq(:configuration_error)
    end

    it "returns :configuration_error when ffmpeg is not installed" do
      allow(Open3).to receive(:popen3).and_raise(Errno::ENOENT)
      expect(transcribe[:outcome]).to eq(:configuration_error)
    end

    it "returns :configuration_error when ffmpeg exits non-zero" do
      stub_ffmpeg(stdout_bytes: "", stderr_bytes: "Decoder failed", success: false)
      expect(transcribe[:outcome]).to eq(:configuration_error)
    end

    it "maps a streaming 4xx to :configuration_error" do
      error = Aws::TranscribeStreamingService::Errors::ServiceError.new(nil, "bad pcm")
      allow(error).to receive(:context).and_return(
        instance_double("RequestContext", http_response: instance_double("HttpResponse", status_code: 400))
      )
      allow(async_client).to receive(:start_stream_transcription).and_raise(error)
      expect(transcribe[:outcome]).to eq(:configuration_error)
    end

    it "maps a streaming 5xx to :unreachable" do
      error = Aws::TranscribeStreamingService::Errors::ServiceError.new(nil, "unavailable")
      allow(error).to receive(:context).and_return(
        instance_double("RequestContext", http_response: instance_double("HttpResponse", status_code: 503))
      )
      allow(async_client).to receive(:start_stream_transcription).and_raise(error)
      expect(transcribe[:outcome]).to eq(:unreachable)
    end

    it "maps a transcode timeout to :unreachable" do
      allow(Open3).to receive(:popen3).and_raise(Timeout::Error)
      expect(transcribe[:outcome]).to eq(:unreachable)
    end

    it "maps an in-stream BadRequestException event to :configuration_error" do
      allow(output_stream).to receive(:on_bad_request_exception_event) { |&block| @on_bad_request = block }
      allow(async_resp).to receive(:wait) do
        @on_bad_request.call(instance_double("BadRequestException", message: "unsupported"))
        true
      end
      expect(transcribe[:outcome]).to eq(:configuration_error)
    end

    it "maps an in-stream ServiceUnavailableException event to :unreachable" do
      allow(output_stream).to receive(:on_service_unavailable_exception_event) { |&block| @on_unavailable = block }
      allow(async_resp).to receive(:wait) do
        @on_unavailable.call(instance_double("ServiceUnavailableException", message: "throttled"))
        true
      end
      expect(transcribe[:outcome]).to eq(:unreachable)
    end

    it "maps an unmodeled stream error event to :unreachable" do
      allow(output_stream).to receive(:on_error_event) { |&block| @on_error = block }
      allow(async_resp).to receive(:wait) do
        @on_error.call(instance_double("EventError", error_message: "http/2 reset"))
        true
      end
      expect(transcribe[:outcome]).to eq(:unreachable)
    end

    it "maps a connection reset to :unreachable" do
      allow(async_client).to receive(:start_stream_transcription).and_raise(Errno::ECONNRESET)
      expect(transcribe[:outcome]).to eq(:unreachable)
    end

    it "maps an HTTP/2 connection close to :unreachable and records connection.errors" do
      allow(async_client).to receive(:connection_errors)
        .and_return([ StandardError.new("GOAWAY") ])
      allow(async_client).to receive(:start_stream_transcription)
        .and_raise(Seahorse::Client::Http2ConnectionClosedError.new("closed"))
      result = transcribe
      expect(result[:outcome]).to eq(:unreachable)
      expect(result[:raw]["connection_errors"].join).to include("GOAWAY")
    end

    it "times out a hung stream wait as :unreachable instead of blocking the worker" do
      stub_const("#{described_class}::STREAM_TIMEOUT", 0.01)
      allow(async_resp).to receive(:wait) { sleep 0.2; true }
      allow(async_resp).to receive(:join!)
      expect(transcribe[:outcome]).to eq(:unreachable)
      expect(async_resp).to have_received(:join!)
    end
  end

  describe "#chat" do
    it "fail-closes because this vendor is transcription-only" do
      expect(adapter.chat(messages: [])).to eq(outcome: :configuration_error, text: nil, raw: nil)
    end
  end
end
