# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Providers::Cursor do
  let(:settings) do
    build_stubbed(:ai_assistant_provider_settings,
                  provider: "cursor",
                  api_key: "cur-test",
                  transcribe_active: false,
                  generation_active: true,
                  config: { chat_model: "gpt-5" }.to_json)
  end
  let(:adapter) { described_class.new(settings: settings) }

  def http_response(status:, body:)
    payload = body.is_a?(String) ? body : body.to_json
    OutboundHttp::Response.new(status: status, headers: {}, body: payload)
  end

  it_behaves_like "an AI Assistant registered provider",
                  key: "cursor",
                  display_name: "Cursor",
                  supports_transcribe: false,
                  supports_generation: true,
                  config_fields: [ :chat_model ]

  describe "#transcribe" do
    it "fail-closes with :configuration_error and never hits the network" do
      expect(OutboundHttp).not_to receive(:request)
      result = adapter.transcribe(io: StringIO.new("x"), filename: "clip.webm", content_type: "audio/webm")
      expect(result).to eq(outcome: :configuration_error, text: nil, raw: nil)
    end
  end

  describe "#chat" do
    let(:messages) { [ { role: "user", content: "Hello" } ] }

    it "returns :configuration_error when api_key is missing without calling Cursor" do
      settings.api_key = nil
      expect(OutboundHttp).not_to receive(:request)
      expect(adapter.chat(messages: messages)[:outcome]).to eq(:configuration_error)
    end

    it "delegates to ScriptedCompletion when the E2E stub is enabled" do
      expect(OutboundHttp).not_to receive(:request)
      result = nil
      with_e2e_assistant_stub do
        result = adapter.chat(messages: [ { role: "user", content: "Create a FooBar entity" } ])
      end
      document = JSON.parse(result[:text])
      expect(result[:outcome]).to eq(:success)
      expect(document["tool"]).to eq("create_entity")
    end

    it "uses the documented agent/run create envelope and polls the initial run" do
      expect(adapter).not_to receive(:poll_wait)
      expect(OutboundHttp).to receive(:request).with(
        :post,
        "https://api.cursor.com/v1/agents",
        hash_including(
          headers: hash_including(
            "Authorization" => "Bearer cur-test",
            "Content-Type" => "application/json"
          ),
          open_timeout: 5,
          read_timeout: 60
        )
      ) do |_method, _url, **kwargs|
        body = kwargs[:body]
        expect(body[:prompt][:text]).to include("USER: Hello")
        expect(body[:model]).to eq({ id: "gpt-5" })
        expect(body).not_to have_key(:repos)
        http_response(status: 201, body: { agent: { id: "bc_1" }, run: { id: "run_1" } })
      end
      expect(OutboundHttp).to receive(:request).with(
        :get,
        "https://api.cursor.com/v1/agents/bc_1/runs/run_1",
        hash_including(headers: hash_including("Authorization" => "Bearer cur-test"))
      ).and_return(http_response(status: 200, body: { status: "FINISHED", result: '{"intent":"chat"}' }))

      result = adapter.chat(messages: messages)
      expect(result[:outcome]).to eq(:success)
      expect(result[:text]).to eq('{"intent":"chat"}')
    end

    it "sends attached images as base64 prompt.images" do
      blob = instance_double(
        ActiveStorage::Blob,
        content_type: "image/png",
        download: "\x89PNG"
      )
      allow(OutboundHttp).to receive(:request) do |method, url, **kwargs|
        if method == :post && url == "https://api.cursor.com/v1/agents"
          expect(kwargs[:body][:prompt][:images]).to eq(
            [ { data: Base64.strict_encode64("\x89PNG"), mimeType: "image/png" } ]
          )
          http_response(status: 201, body: { agent: { id: "bc_1" }, run: { id: "run_1" } })
        else
          http_response(status: 200, body: { status: "FINISHED", result: "ok" })
        end
      end

      result = adapter.chat(
        messages: [ { role: "user", content: "see this", images: [ blob ] } ]
      )
      expect(result[:outcome]).to eq(:success)
    end

    it "omits model when chat_model is blank" do
      settings.write_config(chat_model: "")
      allow(OutboundHttp).to receive(:request) do |method, url, **kwargs|
        expect(kwargs[:body]).not_to have_key(:model) if method == :post
        case [ method, url ]
        when [ :post, "https://api.cursor.com/v1/agents" ]
          http_response(status: 201, body: { agent: { id: "bc_1" }, run: { id: "run_1" } })
        else
          http_response(status: 200, body: { status: "FINISHED", result: "ok" })
        end
      end

      expect(adapter.chat(messages: messages)[:outcome]).to eq(:success)
    end

    it "maps OutboundHttp::TransportError to :unreachable" do
      allow(OutboundHttp).to receive(:request).and_raise(OutboundHttp::TransportError, "timeout")
      expect(adapter.chat(messages: messages)[:outcome]).to eq(:unreachable)
    end

    it "maps 401 to :configuration_error" do
      allow(OutboundHttp).to receive(:request)
        .and_return(http_response(status: 401, body: { error: "bad key" }))
      expect(adapter.chat(messages: messages)[:outcome]).to eq(:configuration_error)
    end

    it "maps 403 to :configuration_error" do
      allow(OutboundHttp).to receive(:request)
        .and_return(http_response(status: 403, body: { error: "forbidden" }))
      expect(adapter.chat(messages: messages)[:outcome]).to eq(:configuration_error)
    end

    it "maps other 4xx except 429 to :configuration_error" do
      allow(OutboundHttp).to receive(:request)
        .and_return(http_response(status: 404, body: { error: "missing" }))
      expect(adapter.chat(messages: messages)[:outcome]).to eq(:configuration_error)
    end

    it "maps 429 to :unreachable" do
      allow(OutboundHttp).to receive(:request)
        .and_return(http_response(status: 429, body: { error: "slow down" }))
      expect(adapter.chat(messages: messages)[:outcome]).to eq(:unreachable)
    end

    it "maps 5xx to :unreachable" do
      allow(OutboundHttp).to receive(:request)
        .and_return(http_response(status: 503, body: { error: "boom" }))
      expect(adapter.chat(messages: messages)[:outcome]).to eq(:unreachable)
    end

    it "maps a blank run result to :empty" do
      allow(OutboundHttp).to receive(:request).and_return(
        http_response(status: 201, body: { agent: { id: "bc_1" }, run: { id: "run_1" } }),
        http_response(status: 200, body: { status: "FINISHED", result: "  " })
      )
      expect(adapter.chat(messages: messages)[:outcome]).to eq(:empty)
    end

    it "returns :unreachable when create-agent omits an id" do
      allow(OutboundHttp).to receive(:request)
        .and_return(http_response(status: 201, body: {}))
      expect(adapter.chat(messages: messages)[:outcome]).to eq(:unreachable)
    end

    it "returns :unreachable when create-agent returns invalid JSON" do
      allow(OutboundHttp).to receive(:request)
        .and_return(http_response(status: 201, body: "not-json"))
      expect(adapter.chat(messages: messages)[:outcome]).to eq(:unreachable)
    end

    it "returns :unreachable when the initial run never terminates before the deadline" do
      allow(adapter).to receive(:poll_wait)
      allow(Process).to receive(:clock_gettime).and_return(0.0, described_class::AGENT_TIMEOUT + 1.0)
      allow(OutboundHttp).to receive(:request).and_return(
        http_response(status: 201, body: { agent: { id: "bc_1" }, run: { id: "run_1" } }),
        http_response(status: 200, body: { status: "RUNNING" })
      )
      expect(adapter.chat(messages: messages)[:outcome]).to eq(:unreachable)
    end

    it "keeps polling a run writing a large tool document that is still RUNNING after seven minutes" do
      allow(adapter).to receive(:poll_wait)
      allow(Process).to receive(:clock_gettime).and_return(0.0, 420.0, 430.0)
      allow(OutboundHttp).to receive(:request).and_return(
        http_response(status: 201, body: { agent: { id: "bc_1" }, run: { id: "run_1" } }),
        http_response(status: 200, body: { status: "RUNNING" }),
        http_response(status: 200, body: { status: "FINISHED", result: "ok" })
      )
      expect(adapter.chat(messages: messages)).to include(outcome: :success, text: "ok")
    end

    it "bounds the run deadline so a turn's worst case stays inside the generation lease" do
      per_call = described_class::OPEN_TIMEOUT + described_class::CHAT_READ_TIMEOUT + described_class::AGENT_TIMEOUT
      worst_case = AiAssistant::Limits::MAX_VENDOR_CALLS * per_call
      expect(worst_case.seconds).to be < AiAssistant::Generation::MAX_RUNNING_AGE
    end

    it "waits for RUNNING and does not confuse the agent's lifecycle with execution state" do
      allow(adapter).to receive(:poll_wait)
      allow(OutboundHttp).to receive(:request).and_return(
        http_response(status: 201, body: { agent: { id: "bc_1", latestRunId: "later" }, run: { id: "run_1" } }),
        http_response(status: 200, body: { status: "RUNNING" }),
        http_response(status: 200, body: { status: "FINISHED", result: "ok" })
      )
      expect(adapter.chat(messages: messages)).to include(outcome: :success, text: "ok")
      expect(OutboundHttp).to have_received(:request).with(
        :get, "https://api.cursor.com/v1/agents/bc_1/runs/run_1", anything
      ).twice
    end

    it "does not treat an ERROR run's result as a successful completion" do
      allow(OutboundHttp).to receive(:request).and_return(
        http_response(status: 201, body: { agent: { id: "bc_1" }, run: { id: "run_1" } }),
        http_response(status: 200, body: { status: "ERROR", result: "partial answer" })
      )
      expect(adapter.chat(messages: messages)).to include(outcome: :unreachable, text: nil)
    end
  end

  describe "#health_check" do
    it "lists models on the result and does not persist the settings row" do
      persisted = create(:ai_assistant_provider_settings, provider: "cursor", api_key: "cur-test",
                         transcribe_active: false, generation_active: true, config: { organization: "keep-me" }.to_json)
      live = described_class.new(settings: persisted)
      allow(OutboundHttp).to receive(:request).with(
        :get,
        "https://api.cursor.com/v1/models",
        hash_including(
          headers: hash_including("Authorization" => "Bearer cur-test"),
          read_timeout: 30
        )
      ).and_return(http_response(status: 200, body: { items: [ { id: "gpt-5", displayName: "GPT-5" } ] }))

      result = live.health_check
      expect(result[:outcome]).to eq(:success)
      expect(result[:text]).to be_nil
      expect(result[:models]).to eq([ { "id" => "gpt-5", "display_name" => "GPT-5" } ])
      expect(persisted.reload.config_value(:generation_models)).to be_nil
      expect(persisted.config_value(:organization)).to eq("keep-me")
    end

    it "treats an empty items list as :success with an empty models array" do
      persisted = create(:ai_assistant_provider_settings, provider: "cursor", api_key: "cur-test",
                         transcribe_active: false, generation_active: true)
      live = described_class.new(settings: persisted)
      allow(OutboundHttp).to receive(:request)
        .and_return(http_response(status: 200, body: { items: [] }))

      result = live.health_check
      expect(result[:outcome]).to eq(:success)
      expect(result[:models]).to eq([])
      expect(persisted.reload.config_value(:generation_models)).to be_nil
    end

    it "maps 401 to :configuration_error" do
      persisted = create(:ai_assistant_provider_settings, provider: "cursor", api_key: "cur-test",
                         transcribe_active: false, generation_active: true)
      live = described_class.new(settings: persisted)
      allow(OutboundHttp).to receive(:request)
        .and_return(http_response(status: 401, body: { error: "bad key" }))
      expect(live.health_check).to include(outcome: :configuration_error, http_status: 401)
    end

    it "maps TransportError to :unreachable" do
      persisted = create(:ai_assistant_provider_settings, provider: "cursor", api_key: "cur-test",
                         transcribe_active: false, generation_active: true)
      live = described_class.new(settings: persisted)
      allow(OutboundHttp).to receive(:request).and_raise(OutboundHttp::TransportError, "timeout")
      expect(live.health_check[:outcome]).to eq(:unreachable)
    end
  end
end
