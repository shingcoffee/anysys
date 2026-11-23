# frozen_string_literal: true

require "rails_helper"

RSpec.describe Llm do
  let(:config) { RubyLLM.config.dup }
  let(:response) { instance_double(RubyLLM::Message, content: "hello", raw: { "ok" => true }) }
  let(:chat) { instance_double(RubyLLM::Chat) }
  let(:context) { instance_double(RubyLLM::Context) }

  def complete(**overrides)
    described_class.complete(
      **{
        provider: :openai,
        model: "gpt-4o-mini",
        messages: [ { role: "user", content: "hi" } ],
        api_key: "sk-test"
      }.merge(overrides)
    )
  end

  before do
    allow(RubyLLM).to receive(:context) do |&block|
      block&.call(config)
      context
    end
    allow(context).to receive(:chat).and_return(chat)
    allow(chat).to receive(:with_instructions).and_return(chat)
    allow(chat).to receive(:with_params).and_return(chat)
    allow(chat).to receive(:with_temperature).and_return(chat)
    allow(chat).to receive(:with_tools).and_return(chat)
    allow(chat).to receive(:add_message)
    allow(chat).to receive(:before_tool_call).and_return(chat)
    allow(chat).to receive(:complete).and_return(response)
  end

  it "returns :success with the assistant text" do
    expect(complete[:outcome]).to eq(:success)
    expect(complete[:text]).to eq("hello")
  end

  it "seeds system instructions and history then completes" do
    expect(chat).to receive(:with_instructions).with("sys").and_return(chat)
    expect(chat).to receive(:add_message).with(role: :user, content: "hi")
    expect(chat).to receive(:complete).and_return(response)
    complete(messages: [ { role: "system", content: "sys" }, { role: "user", content: "hi" } ])
  end

  it "seeds image attachments as RubyLLM::Content for vision providers" do
    expect(chat).to receive(:add_message) do |role:, content:|
      expect(role).to eq(:user)
      expect(content).to be_a(RubyLLM::Content)
      expect(content.text).to eq("see this")
      expect(content.attachments.size).to eq(1)
    end
    complete(messages: [ { role: "user", content: "see this", images: [ Rails.root.join("spec/fixtures/files/shot.png").to_s ] } ])
  end

  it "does not attach images for DeepSeek" do
    expect(chat).to receive(:add_message).with(role: :user, content: "see this")
    complete(
      provider: :deepseek,
      model: "deepseek-chat",
      api_key: "sk-deep",
      messages: [ { role: "user", content: "see this", images: [ Rails.root.join("spec/fixtures/files/shot.png").to_s ] } ]
    )
  end

  it "requests JSON object mode when json: true and tools are absent" do
    expect(chat).to receive(:with_params).with(response_format: { type: "json_object" }).and_return(chat)
    complete(json: true)
  end

  it "does not request JSON mode when tools are present" do
    tool = instance_double(RubyLLM::Tool)
    expect(chat).to receive(:with_tools).with(tool).and_return(chat)
    expect(chat).to receive(:before_tool_call)
    expect(chat).not_to receive(:with_params).with(hash_including(response_format: { type: "json_object" }))
    complete(json: true, tools: [ tool ])
  end

  it "sets the per-call OpenAI key on the context" do
    complete
    expect(config.openai_api_key).to eq("sk-test")
  end

  it "returns :empty when the model returns blank content" do
    allow(response).to receive(:content).and_return("  ")
    expect(complete[:outcome]).to eq(:empty)
  end

  it "returns :configuration_error when api_key is blank" do
    expect(RubyLLM).not_to receive(:context)
    result = complete(api_key: "")
    expect(result[:outcome]).to eq(:configuration_error)
  end

  it "allows a blank api_key for ollama" do
    expect(context).to receive(:chat).with(model: "llama3", provider: :ollama, assume_model_exists: true)
                                     .and_return(chat)
    result = complete(provider: :ollama, model: "llama3", api_key: "")
    expect(result[:outcome]).to eq(:success)
    expect(config.ollama_api_base).to eq(Llm::OLLAMA_API_BASE)
  end

  it "returns :configuration_error for an unknown provider" do
    expect(RubyLLM).not_to receive(:context)
    expect(complete(provider: :cohere)[:outcome]).to eq(:configuration_error)
  end

  it "sets the per-call Bedrock keys on the context" do
    expect(context).to receive(:chat).with(
      model: "amazon.nova-lite-v1:0", provider: :bedrock, assume_model_exists: true
    ).and_return(chat)
    result = complete(
      provider: :bedrock,
      model: "amazon.nova-lite-v1:0",
      api_key: "secret",
      access_key_id: "AKID",
      region: "us-west-2"
    )
    expect(result[:outcome]).to eq(:success)
    expect(config.bedrock_api_key).to eq("AKID")
    expect(config.bedrock_secret_key).to eq("secret")
    expect(config.bedrock_region).to eq("us-west-2")
  end

  it "returns :configuration_error when Bedrock access_key_id is blank" do
    expect(RubyLLM).not_to receive(:context)
    result = complete(provider: :bedrock, api_key: "secret", access_key_id: "", region: "us-east-1")
    expect(result[:outcome]).to eq(:configuration_error)
  end

  it "sets the per-call DeepSeek key on the context" do
    expect(context).to receive(:chat).with(
      model: "deepseek-chat", provider: :deepseek, assume_model_exists: true
    ).and_return(chat)
    result = complete(provider: :deepseek, model: "deepseek-chat", api_key: "sk-deep")
    expect(result[:outcome]).to eq(:success)
    expect(config.deepseek_api_key).to eq("sk-deep")
  end

  it "routes Qwen through RubyLLM OpenAI-compatible DashScope" do
    expect(context).to receive(:chat).with(
      model: "qwen-plus", provider: :openai, assume_model_exists: true
    ).and_return(chat)
    result = complete(provider: :qwen, model: "qwen-plus", api_key: "sk-qwen")
    expect(result[:outcome]).to eq(:success)
    expect(config.openai_api_key).to eq("sk-qwen")
    expect(config.openai_api_base).to eq(Llm::QWEN_API_BASE)
  end

  it "maps unauthorized errors to :configuration_error" do
    allow(chat).to receive(:complete).and_raise(RubyLLM::UnauthorizedError.new(nil, "bad key"))
    expect(complete[:outcome]).to eq(:configuration_error)
  end

  it "maps rate limits to :unreachable" do
    allow(chat).to receive(:complete).and_raise(RubyLLM::RateLimitError.new(nil, "slow down"))
    expect(complete[:outcome]).to eq(:unreachable)
  end

  it "maps Faraday timeouts to :unreachable" do
    allow(chat).to receive(:complete).and_raise(Faraday::TimeoutError.new("timeout"))
    expect(complete[:outcome]).to eq(:unreachable)
  end

  describe "actual native-tool completion boundaries" do
    let(:real_chat) do
      config.openai_api_key = "sk-test"
      RubyLLM::Context.new(config).chat(model: "gpt-4o-mini", provider: :openai, assume_model_exists: true)
    end
    let(:wire_provider) { real_chat.instance_variable_get(:@provider) }
    let(:terminal_response) { RubyLLM::Message.new(role: :assistant, content: "hello") }
    let(:tool) do
      Class.new(RubyLLM::Tool) do
        description "Return the fixture catalog"
        def name = "fixture_catalog"
        def execute = "catalog"
      end.new
    end
    let(:tool_response) do
      call = RubyLLM::ToolCall.new(id: "call_1", name: "fixture_catalog", arguments: {})
      RubyLLM::Message.new(role: :assistant, content: nil, tool_calls: { "call_1" => call })
    end

    before { allow(context).to receive(:chat).and_return(real_chat) }

    it "charges each real provider completion, including the native-tool follow-up" do
      allow(wire_provider).to receive(:complete).and_return(tool_response, terminal_response)
      requests = 0
      result = complete(tools: [tool], before_request: -> { requests += 1 })
      expect(result).to include(outcome: :success, text: "hello")
      expect(requests).to eq(2)
      expect(wire_provider).to have_received(:complete).twice
    end

    it "stops before a second network call when the actual-call budget is exhausted" do
      allow(wire_provider).to receive(:complete).and_return(tool_response)
      result = complete(tools: [tool], call_budget: 1)
      expect(result).to include(outcome: :budget_exceeded, text: nil)
      expect(wire_provider).to have_received(:complete).once
    end

    it "checks cancellation before invoking a tool from a just-completed request" do
      cancelled = false
      allow(wire_provider).to receive(:complete) do
        cancelled = true
        tool_response
      end
      expect(tool).not_to receive(:execute)
      guard = -> { raise AiAssistant::Assistant::GenerationWriteGuard::Rejected, :cancelled if cancelled }
      expect { complete(tools: [tool], before_tool_call: guard) }
        .to raise_error(AiAssistant::Assistant::GenerationWriteGuard::Rejected) { |error| expect(error.state).to eq(:cancelled) }
      expect(wire_provider).to have_received(:complete).once
    end

    it "checks generation state before a native follow-up even after the tool succeeded" do
      requests = 0
      allow(wire_provider).to receive(:complete).and_return(tool_response)
      guard = lambda do
        requests += 1
        raise AiAssistant::Assistant::GenerationWriteGuard::Rejected, :superseded if requests == 2
      end
      expect { complete(tools: [tool], before_request: guard) }
        .to raise_error(AiAssistant::Assistant::GenerationWriteGuard::Rejected)
      expect(wire_provider).to have_received(:complete).once
    end
  end

  # Supplying on_chunk switches the request to server-sent streaming; the
  # return value is unchanged either way, so a caller that cannot use partial
  # text simply omits it.
  describe "streaming" do
    let(:chunk_class) { Struct.new(:content) }

    def chunk(content)
      chunk_class.new(content)
    end

    def stream(*frames, &handler)
      allow(chat).to receive(:complete) do |&block|
        frames.each { |frame| block.call(frame) }
        response
      end
      complete(on_chunk: handler)
    end

    it "completes without a block when no handler is given" do
      expect(chat).to receive(:complete) do |&block|
        expect(block).to be_nil
        response
      end

      expect(complete[:outcome]).to eq(:success)
    end

    it "forwards each chunk's content to the handler" do
      seen = []

      result = stream(chunk("He"), chunk("llo")) { |text| seen << text }

      expect(seen).to eq(%w[He llo])
      expect(result).to include(outcome: :success, text: "hello")
    end

    it "forwards a bare string chunk that carries no content reader" do
      seen = []

      stream("raw") { |text| seen << text }

      expect(seen).to eq([ "raw" ])
    end

    # Tool-call and usage frames arrive on the same stream with no content.
    it "skips frames with no content" do
      seen = []

      stream(chunk(nil), chunk("Hi"), chunk("")) { |text| seen << text }

      expect(seen).to eq([ "Hi" ])
    end

    # A broken live preview must not take the reply down with it.
    it "swallows a raising handler and still returns the completion" do
      allow(Rails.logger).to receive(:error)

      result = stream(chunk("He"), chunk("llo")) { raise "preview exploded" }

      expect(result).to include(outcome: :success, text: "hello")
      expect(Rails.logger).to have_received(:error)
        .with(/stream subscriber failed: RuntimeError: preview exploded/).twice
    end
  end
end
