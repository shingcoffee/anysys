# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::ProviderClient do
  let(:customer) { create(:customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer) }
  let(:settings) { create(:ai_assistant_provider_settings) }
  let(:client) { described_class.new(settings: settings, conversation: conversation) }

  it "delegates chat to the configured provider" do
    provider = instance_double(AiAssistant::Providers::OpenaiWhisper)
    allow(AiAssistant::Providers::OpenaiWhisper).to receive(:new).with(settings: settings).and_return(provider)
    allow(provider).to receive(:chat)
      .with(hash_including(messages: [{ role: "user", content: "Hi" }], tools: nil, on_chunk: nil))
      .and_return(outcome: :success, text: "{}", raw: {})

    expect(client.chat([{ role: "user", content: "Hi" }])).to include(outcome: :success)
  end

  # Streaming is the vendor's own declaration, so a token sink handed to a
  # vendor that cannot stream is dropped rather than passed on and ignored.
  it "forwards the token sink only to a vendor that streams" do
    sink = ->(_chunk) { }
    provider = instance_double(AiAssistant::Providers::OpenaiWhisper)
    allow(AiAssistant::Providers::OpenaiWhisper).to receive(:new).with(settings: settings).and_return(provider)
    allow(provider).to receive(:chat).and_return(outcome: :success, text: "{}", raw: {})

    client.chat([{ role: "user", content: "Hi" }], on_chunk: sink)

    expect(provider).to have_received(:chat).with(hash_including(on_chunk: sink))
  end

  it "drops the token sink for a vendor that does not stream" do
    cursor = create(:ai_assistant_provider_settings, provider: "cursor", api_key: "cur-test",
                    transcribe_active: false, generation_active: true)
    provider = instance_double(AiAssistant::Providers::Cursor)
    allow(AiAssistant::Providers::Cursor).to receive(:new).with(settings: cursor).and_return(provider)
    allow(provider).to receive(:chat).and_return(outcome: :success, text: "{}", raw: {})

    described_class.new(settings: cursor, conversation: conversation)
                   .chat([{ role: "user", content: "Hi" }], on_chunk: ->(_c) { })

    expect(provider).to have_received(:chat).with(hash_including(on_chunk: nil))
  end

  # A turn fans out into a tool loop, an entity pass, a flowchart pass and
  # their repairs — each a billed call. Limits::MAX_TURNS caps how many turns a
  # user gets; this caps what one turn may spend.
  it "refuses to call the vendor once the per-turn budget is spent" do
    provider = instance_double(AiAssistant::Providers::OpenaiWhisper)
    allow(AiAssistant::Providers::OpenaiWhisper).to receive(:new).with(settings: settings).and_return(provider)
    allow(provider).to receive(:chat) do |**options|
      options.fetch(:before_request).call
      { outcome: :success, text: "{}", raw: {} }
    end
    allow(Rails.logger).to receive(:warn)

    budgeted = described_class.new(settings: settings, conversation: conversation, budget: 2)
    2.times { budgeted.chat([{ role: "user", content: "Hi" }]) }
    result = budgeted.chat([{ role: "user", content: "Hi" }])

    expect(result).to include(outcome: :budget_exceeded, text: nil)
    expect(provider).to have_received(:chat).twice
    expect(budgeted.calls).to eq(2)
  end

  it "shares the same budget across native follow-ups and later repair calls" do
    provider = instance_double(AiAssistant::Providers::OpenaiWhisper)
    allow(AiAssistant::Providers::OpenaiWhisper).to receive(:new).and_return(provider)
    allow(provider).to receive(:chat) do |**options|
      2.times { options.fetch(:before_request).call }
      { outcome: :success, text: "{}", raw: {} }
    end
    budgeted = described_class.new(settings: settings, conversation: conversation, budget: 2)
    expect(budgeted.chat([])).to include(outcome: :success)
    expect(budgeted.chat([])).to include(outcome: :budget_exceeded)
    expect(budgeted.calls).to eq(2)
    expect(provider).to have_received(:chat).once
  end

  it "rejects a cancelled generation before calling any provider" do
    turn = create(:ai_assistant_message, customer: customer, conversation: conversation)
    generation = AiAssistant::Assistant::GenerationLifecycle.start!(conversation: conversation, user_message: turn)
    AiAssistant::Assistant::GenerationLifecycle.claim!(generation)
    AiAssistant::Assistant::GenerationLifecycle.cancel!(conversation: conversation)
    guarded = described_class.new(
      settings: settings, conversation: conversation,
      write_guard: AiAssistant::Assistant::GenerationWriteGuard.new(generation: generation)
    )
    expect(AiAssistant::Providers::OpenaiWhisper).not_to receive(:new)
    expect { guarded.chat([]) }.to raise_error(AiAssistant::Assistant::GenerationWriteGuard::Rejected)
    expect(guarded.calls).to eq(0)
  end

  it "maps an escaped provider transport error to an unreachable outcome" do
    provider = instance_double(AiAssistant::Providers::OpenaiWhisper)
    allow(AiAssistant::Providers::OpenaiWhisper).to receive(:new)
      .with(settings: settings)
      .and_return(provider)
    allow(provider).to receive(:chat).and_raise(Faraday::TimeoutError, "provider timed out")
    allow(Rails.logger).to receive(:error)

    result = client.chat([{ role: "user", content: "Hi" }])

    expect(result).to include(outcome: :unreachable, text: nil)
    expect(Rails.logger).to have_received(:error).with(
      /provider call failed.*Faraday::TimeoutError: provider timed out/
    )
  end

  it "does not hide an application failure raised while the provider executes a native tool" do
    provider = instance_double(AiAssistant::Providers::OpenaiWhisper)
    allow(AiAssistant::Providers::OpenaiWhisper).to receive(:new)
      .with(settings: settings)
      .and_return(provider)
    allow(provider).to receive(:chat)
      .and_raise(ActiveRecord::StatementInvalid, "tool write failed")

    expect {
      client.chat([{ role: "user", content: "Generate a page" }])
    }.to raise_error(ActiveRecord::StatementInvalid, "tool write failed")
  end

  it "exposes native tools for OpenAI Whisper" do
    expect(client.native_tools.map(&:name)).to contain_exactly(
      "list_catalog",
      "generate_page",
      "verify_artifact",
      "create_domain",
      "create_entity",
      "update_entity",
      "get_entity",
      "set_page_processing",
      "start_subsystem_build"
    )
  end

  it "exposes native tools for AWS Bedrock" do
    bedrock = create(:ai_assistant_provider_settings,
                     provider: "aws_bedrock",
                     api_key: "secret",
                     transcribe_active: false,
                     generation_active: true,
                     config: { access_key_id: "AKID" }.to_json)
    bedrock_client = described_class.new(settings: bedrock, conversation: conversation)
    expect(bedrock_client.native_tools.map(&:name)).to contain_exactly(
      "list_catalog",
      "generate_page",
      "verify_artifact",
      "create_domain",
      "create_entity",
      "update_entity",
      "get_entity",
      "set_page_processing",
      "start_subsystem_build"
    )
  end

  it "exposes native tools for DeepSeek" do
    deepseek = create(:ai_assistant_provider_settings, provider: "deepseek", api_key: "sk-deep",
                      transcribe_active: false, generation_active: true)
    deepseek_client = described_class.new(settings: deepseek, conversation: conversation)
    expect(deepseek_client.native_tools.map(&:name)).to contain_exactly(
      "list_catalog",
      "generate_page",
      "verify_artifact",
      "create_domain",
      "create_entity",
      "update_entity",
      "get_entity",
      "set_page_processing",
      "start_subsystem_build"
    )
  end

  it "exposes native tools for Qwen" do
    qwen = create(:ai_assistant_provider_settings, provider: "qwen", api_key: "sk-qwen",
                  transcribe_active: false, generation_active: true)
    qwen_client = described_class.new(settings: qwen, conversation: conversation)
    expect(qwen_client.native_tools.map(&:name)).to contain_exactly(
      "list_catalog",
      "generate_page",
      "verify_artifact",
      "create_domain",
      "create_entity",
      "update_entity",
      "get_entity",
      "set_page_processing",
      "start_subsystem_build"
    )
  end

  it "does not expose native tools for Cursor" do
    cursor = create(:ai_assistant_provider_settings, provider: "cursor", api_key: "cur-test",
                    transcribe_active: false, generation_active: true)
    cursor_client = described_class.new(settings: cursor, conversation: conversation)
    expect(cursor_client.native_tools).to eq([])
  end

  # Tool support is the vendor's own declaration, so a new generation vendor
  # stays a single-file addition instead of editing an allowlist here.
  it "asks the vendor class whether it takes native tools" do
    klass = settings.provider_class
    allow(klass).to receive(:supports_native_tools?).and_return(false)

    expect(described_class.new(settings: settings, conversation: conversation).native_tools).to eq([])
    expect(klass).to have_received(:supports_native_tools?)
  end
end
