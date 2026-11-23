# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Providers::OpenaiWhisper do
  let(:settings) do
    build_stubbed(:ai_assistant_provider_settings,
                  api_key: "sk-test",
                  config: { model: "whisper-1", organization: "org-1" }.to_json)
  end
  let(:adapter) { described_class.new(settings: settings) }
  let(:client) { instance_double(OpenAI::Client) }
  let(:audio_api) { instance_double(OpenAI::Audio) }
  let(:io) { StringIO.new("fake-audio") }

  def transcribe(language: "en")
    adapter.transcribe(io: io, filename: "clip.webm", content_type: "audio/webm", language: language)
  end

  before do
    allow(OpenAI::Client).to receive(:new).and_return(client)
    allow(client).to receive(:audio).and_return(audio_api)
  end

  it_behaves_like "an AI Assistant registered provider",
                  key: "openai_whisper",
                  display_name: "OpenAI Whisper",
                  supports_transcribe: true,
                  supports_generation: true,
                  supports_images: true

  describe "#transcribe" do
    it "returns :success with the transcript text and never hits the network" do
      expect(audio_api).to receive(:transcribe).and_return({ "text" => "hello world" })
      result = transcribe
      expect(result[:outcome]).to eq(:success)
      expect(result[:text]).to eq("hello world")
    end

    it "omits the language param when language is auto" do
      expect(audio_api).to receive(:transcribe) do |parameters:|
        expect(parameters).not_to have_key(:language)
        { "text" => "ok" }
      end
      transcribe(language: "auto")
    end

    it "omits the language param when language is blank" do
      expect(audio_api).to receive(:transcribe) do |parameters:|
        expect(parameters).not_to have_key(:language)
        { "text" => "ok" }
      end
      transcribe(language: "")
    end

    it "maps zh-CN to Whisper language zh" do
      expect(audio_api).to receive(:transcribe) do |parameters:|
        expect(parameters[:language]).to eq("zh")
        { "text" => "你好" }
      end
      transcribe(language: "zh-CN")
    end

    it "passes en through as en" do
      expect(audio_api).to receive(:transcribe) do |parameters:|
        expect(parameters[:language]).to eq("en")
        { "text" => "ok" }
      end
      transcribe(language: "en")
    end

    it "builds OpenAI::Client with the encrypted api_key, organization and an explicit read timeout" do
      expect(OpenAI::Client).to receive(:new).with(
        { access_token: "sk-test", organization_id: "org-1", request_timeout: described_class::REQUEST_TIMEOUT }
      ).and_return(client)
      allow(audio_api).to receive(:transcribe).and_return({ "text" => "ok" })
      transcribe
    end

    # ruby-openai only exposes a read timeout and defaults it to 120s from its
    # global config, with no connect timeout at all — one hung vendor call would
    # otherwise hold a Solid Queue worker for minutes.
    it "pins a connect timeout on the Faraday connection" do
      connection = Faraday::Connection.new
      allow(OpenAI::Client).to receive(:new) do |_opts, &middleware|
        middleware.call(connection)
        client
      end
      allow(audio_api).to receive(:transcribe).and_return({ "text" => "ok" })

      transcribe

      expect(connection.options.open_timeout).to eq(described_class::OPEN_TIMEOUT)
    end

    it "returns :empty when the vendor returns blank text" do
      allow(audio_api).to receive(:transcribe).and_return({ "text" => "  " })
      expect(transcribe[:outcome]).to eq(:empty)
    end

    it "returns :configuration_error when api_key is missing without calling OpenAI" do
      settings.api_key = nil
      expect(OpenAI::Client).not_to receive(:new)
      expect(transcribe[:outcome]).to eq(:configuration_error)
    end

    it "maps Faraday transport errors to :unreachable" do
      allow(audio_api).to receive(:transcribe).and_raise(Faraday::TimeoutError.new("timeout"))
      result = transcribe
      expect(result[:outcome]).to eq(:unreachable)
    end

    it "maps Faraday 401 to :configuration_error" do
      error = Faraday::UnauthorizedError.new("bad key")
      allow(error).to receive(:response_status).and_return(401)
      allow(audio_api).to receive(:transcribe).and_raise(error)
      expect(transcribe[:outcome]).to eq(:configuration_error)
    end

    # ruby-openai installs Faraday's raise_error middleware, so every HTTP
    # failure arrives as a Faraday::Error carrying #response_status.
    it "maps a 404 (e.g. a bad model name) to :configuration_error rather than vendor downtime" do
      error = Faraday::ResourceNotFound.new("no such model")
      allow(error).to receive(:response_status).and_return(404)
      allow(audio_api).to receive(:transcribe).and_raise(error)
      expect(transcribe[:outcome]).to eq(:configuration_error)
    end

    it "keeps a 429 as :unreachable because it is transient" do
      error = Faraday::TooManyRequestsError.new("slow down")
      allow(error).to receive(:response_status).and_return(429)
      allow(audio_api).to receive(:transcribe).and_raise(error)
      expect(transcribe[:outcome]).to eq(:unreachable)
    end

    it "maps a 5xx to :unreachable" do
      error = Faraday::ServerError.new("boom")
      allow(error).to receive(:response_status).and_return(503)
      allow(audio_api).to receive(:transcribe).and_raise(error)
      expect(transcribe[:outcome]).to eq(:unreachable)
    end
  end

  describe "#chat" do
    it "returns :success with the assistant text via Llm" do
      expect(Llm).to receive(:complete).with(
        hash_including(
          provider: :openai,
          model: "gpt-4o-mini",
          messages: [ { role: "user", content: "hi" } ],
          api_key: "sk-test",
          organization: "org-1",
          json: true,
          tools: nil
        )
      ).and_return({ outcome: :success, text: "hello", raw: {} })
      result = adapter.chat(messages: [ { role: "user", content: "hi" } ])
      expect(result[:outcome]).to eq(:success)
      expect(result[:text]).to eq("hello")
    end

    it "passes native tools through and turns JSON mode off" do
      tool = instance_double(AiAssistant::Assistant::Tools::ListCatalog)
      expect(Llm).to receive(:complete).with(hash_including(json: false, tools: [ tool ]))
                    .and_return({ outcome: :success, text: "{}", raw: {} })
      adapter.chat(messages: [ { role: "user", content: "hi" } ], tools: [ tool ])
    end

    it "returns :empty when Llm returns blank content" do
      allow(Llm).to receive(:complete).and_return({ outcome: :empty, text: nil, raw: {} })
      expect(adapter.chat(messages: [ { role: "user", content: "hi" } ])[:outcome]).to eq(:empty)
    end

    it "returns :configuration_error when api_key is missing without calling Llm" do
      settings.api_key = nil
      expect(Llm).not_to receive(:complete)
      expect(adapter.chat(messages: [])[:outcome]).to eq(:configuration_error)
    end

    it "maps Llm unreachable outcomes through" do
      allow(Llm).to receive(:complete).and_return({ outcome: :unreachable, text: nil, raw: { "error" => "timeout" } })
      expect(adapter.chat(messages: [])[:outcome]).to eq(:unreachable)
    end

    it "returns a create document when E2E_STUB_ASSISTANT is set in development" do
      expect(OpenAI::Client).not_to receive(:new)
      result = nil
      with_e2e_assistant_stub do
        result = adapter.chat(messages: [ { role: "user", content: "Create a FooBar entity" } ])
      end
      document = JSON.parse(result[:text])
      expect(result[:outcome]).to eq(:success)
      expect(document["tool"]).to eq("create_entity")
      expect(document.dig("arguments", "entities").first["name"]).to eq("FooBar")
    end

    it "emits the final envelope after a tool result" do
      result = nil
      with_e2e_assistant_stub do
        result = adapter.chat(messages: [
          { role: "user", content: "Create a FooBar entity" },
          { role: "user", content: { "tool_result" => { "status" => "succeeded" } }.to_json }
        ])
      end
      document = JSON.parse(result[:text])
      expect(document["intent"]).to eq("chat")
      expect(document["reply"]).to include("FooBar")
    end
  end
end
