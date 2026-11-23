# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Ai do
  let(:ctx) { { customer_id: 49, errors: [], text: "Ada" } }
  let(:settings) do
    create(:ai_assistant_provider_settings, provider: "deepseek", generation_active: true,
                                            transcribe_active: false, api_key: "sk-test",
                                            config: { chat_model: "deepseek-chat" }.to_json)
  end

  before do
    AiAssistant::ProviderSettings.update_all(generation_active: false)
    settings
  end

  it "completes through the platform generation provider" do
    allow(Llm).to receive(:complete).and_return(outcome: :success, text: "ok", raw: {})

    expect(described_class.complete(ctx, prompt_template: "Hi {{ text }}")).to eq("ok")
    expect(Llm).to have_received(:complete).with(hash_including(
      provider: :deepseek, model: "deepseek-chat", api_key: "sk-test"
    ))
  end

  it "repairs fenced JSON" do
    allow(Llm).to receive(:complete).and_return(outcome: :success, text: "```json\n{\"n\":1}\n```", raw: {})

    expect(described_class.complete(ctx, prompt_template: "Hi", output_format: "json", json_repair: true))
      .to eq("n" => 1)
  end

  it "fails when no generation provider is active" do
    settings.update!(generation_active: false)
    expect(described_class.complete(ctx, prompt_template: "Hi")).to be(false)
    expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.ai_inference.not_configured"))
  end

  it "fails for a Cursor generation provider" do
    settings.update!(generation_active: false)
    create(:ai_assistant_provider_settings, provider: "cursor", generation_active: true,
                                            transcribe_active: false, api_key: "sk-cursor")
    expect(described_class.complete(ctx, prompt_template: "Hi")).to be(false)
    expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.ai_inference.unsupported_provider"))
  end

  it "uses an explicit model override" do
    allow(Llm).to receive(:complete).and_return(outcome: :success, text: "ok", raw: {})
    described_class.complete(ctx, prompt_template: "Hi", model: "deepseek-reasoner")
    expect(Llm).to have_received(:complete).with(hash_including(model: "deepseek-reasoner"))
  end
end
