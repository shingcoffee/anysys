# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Providers::AwsBedrock do
  let(:settings) do
    build_stubbed(:ai_assistant_provider_settings,
                  provider: "aws_bedrock",
                  api_key: "secret",
                  config: {
                    access_key_id: "AKID",
                    region: "us-west-2",
                    model: "amazon.nova-lite-v1:0",
                    chat_model: "amazon.nova-pro-v1:0"
                  }.to_json)
  end
  let(:adapter) { described_class.new(settings: settings) }
  let(:client) { instance_double(Aws::BedrockRuntime::Client) }
  let(:io) { StringIO.new("fake-wav") }

  def transcribe(filename: "clip.wav", content_type: "audio/wav", language: "en")
    adapter.transcribe(io: io, filename: filename, content_type: content_type, language: language)
  end

  def converse_response(text)
    double("ConverseResponse", to_h: {
      output: { message: { content: [ { text: text } ] } }
    })
  end

  def stub_ffmpeg(stdout_bytes: "RIFFWAV", stderr_bytes: "", success: true)
    status = instance_double(Process::Status, success?: success)
    wait_thr = instance_double(Process::Waiter, value: status)
    allow(Open3).to receive(:popen3) do |*_args, &block|
      stdin = StringIO.new
      stdout = StringIO.new(stdout_bytes)
      stderr = StringIO.new(stderr_bytes)
      block.call(stdin, stdout, stderr, wait_thr)
    end
  end

  before do
    allow(Aws::BedrockRuntime::Client).to receive(:new).and_return(client)
    allow(client).to receive(:converse).and_return(converse_response("hello world"))
  end

  it_behaves_like "an AI Assistant registered provider",
                  key: "aws_bedrock",
                  display_name: "AWS Bedrock",
                  supports_transcribe: true,
                  supports_generation: true,
                  config_fields: [ :access_key_id, :region, :model, :chat_model ],
                  configured_on_api_key: false

  describe ".configured?" do
    it "is false when the secret or access key id is blank" do
      bare = build(:ai_assistant_provider_settings, provider: "aws_bedrock", api_key: nil,
                   transcribe_active: false, generation_active: false, config: {}.to_json)
      expect(described_class.configured?(bare)).to eq(false)
    end

    it "is true when secret and access key id are present" do
      expect(described_class.configured?(settings)).to eq(true)
    end
  end

  describe "#transcribe" do
    it "returns :success from Converse text and never hits live AWS" do
      expect(client).to receive(:converse) do |params|
        expect(params[:model_id]).to eq("amazon.nova-lite-v1:0")
        content = params[:messages][0][:content]
        audio = content.find { |block| block[:audio] }
        text = content.find { |block| block[:text] }
        expect(audio[:audio][:format]).to eq("wav")
        expect(audio[:audio][:source][:bytes]).to eq("fake-wav")
        expect(text[:text]).to include("Transcribe the spoken audio")
        expect(text[:text]).to include("English")
        converse_response("hello world")
      end
      expect(Aws::BedrockRuntime::Client).to receive(:new).with(hash_including(
        access_key_id: "AKID",
        secret_access_key: "secret",
        region: "us-west-2"
      )).and_return(client)

      result = transcribe
      expect(result[:outcome]).to eq(:success)
      expect(result[:text]).to eq("hello world")
    end

    it "omits the language sentence when language is auto" do
      expect(client).to receive(:converse) do |params|
        text = params[:messages][0][:content].find { |block| block[:text] }[:text]
        expect(text).not_to include("English")
        expect(text).not_to include("Chinese")
        converse_response("ok")
      end
      transcribe(language: "auto")
    end

    it "names Chinese when language is zh-CN" do
      expect(client).to receive(:converse) do |params|
        text = params[:messages][0][:content].find { |block| block[:text] }[:text]
        expect(text).to include("Chinese")
        converse_response("你好")
      end
      expect(transcribe(language: "zh-CN")[:text]).to eq("你好")
    end

    it "does not invoke ffmpeg for a pass-through wav clip" do
      expect(Open3).not_to receive(:popen3)
      transcribe
    end

    it "transcodes webm to wav before Converse" do
      stub_ffmpeg(stdout_bytes: "PCM-WAV")
      expect(client).to receive(:converse) do |params|
        audio = params[:messages][0][:content].find { |block| block[:audio] }
        expect(audio[:audio][:format]).to eq("wav")
        expect(audio[:audio][:source][:bytes]).to eq("PCM-WAV")
        converse_response("ok")
      end
      adapter.transcribe(io: StringIO.new("webm-bytes"), filename: "clip.webm",
                         content_type: "audio/webm", language: "auto")
    end

    it "returns :empty when Converse returns blank text" do
      allow(client).to receive(:converse).and_return(converse_response("  "))
      expect(transcribe[:outcome]).to eq(:empty)
    end

    it "returns :configuration_error when credentials are missing without calling AWS" do
      settings.api_key = nil
      expect(Aws::BedrockRuntime::Client).not_to receive(:new)
      expect(transcribe[:outcome]).to eq(:configuration_error)
    end

    it "maps AccessDenied to :configuration_error" do
      error = Aws::BedrockRuntime::Errors::AccessDeniedException.new(nil, "denied")
      allow(error).to receive(:context).and_return(nil)
      allow(client).to receive(:converse).and_raise(error)
      expect(transcribe[:outcome]).to eq(:configuration_error)
    end

    it "maps networking failures to :unreachable" do
      allow(client).to receive(:converse).and_raise(Seahorse::Client::NetworkingError.new(StandardError.new("down")))
      result = transcribe
      expect(result[:outcome]).to eq(:unreachable)
    end

    it "maps a missing ffmpeg binary to :configuration_error" do
      allow(Open3).to receive(:popen3).and_raise(Errno::ENOENT, "ffmpeg")
      result = adapter.transcribe(io: StringIO.new("webm"), filename: "clip.webm",
                                  content_type: "audio/webm", language: "auto")
      expect(result[:outcome]).to eq(:configuration_error)
    end
  end

  it_behaves_like "an AI Assistant Llm-backed chat",
                  llm_provider: :bedrock,
                  chat_model: "amazon.nova-pro-v1:0",
                  api_key: "secret",
                  extra_complete: { access_key_id: "AKID", region: "us-west-2" }

  describe "#health_check" do
    it "probes via a text Converse ping instead of audio transcribe" do
      expect(adapter).not_to receive(:transcribe)
      expect(client).to receive(:converse) do |params|
        expect(params[:model_id]).to eq("amazon.nova-pro-v1:0")
        expect(params[:messages][0][:content]).to eq([ { text: "ping" } ])
        converse_response("pong")
      end

      expect(adapter.health_check[:outcome]).to eq(:success)
    end

    it "treats a blank Converse reply as credentials OK" do
      allow(client).to receive(:converse).and_return(converse_response("  "))
      expect(adapter).not_to receive(:transcribe)
      expect(adapter.health_check[:outcome]).to eq(:success)
    end

    it "returns :configuration_error when credentials are missing without calling AWS" do
      settings.api_key = nil
      expect(Aws::BedrockRuntime::Client).not_to receive(:new)
      expect(adapter.health_check[:outcome]).to eq(:configuration_error)
    end

    it "maps AccessDenied to :configuration_error" do
      error = Aws::BedrockRuntime::Errors::AccessDeniedException.new(nil, "denied")
      allow(error).to receive(:context).and_return(nil)
      allow(client).to receive(:converse).and_raise(error)
      expect(adapter.health_check[:outcome]).to eq(:configuration_error)
    end
  end
end
