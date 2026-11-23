# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Providers::Qwen do
  let(:settings) do
    build_stubbed(:ai_assistant_provider_settings,
                  provider: "qwen",
                  api_key: "sk-qwen",
                  transcribe_active: false,
                  generation_active: true,
                  config: { chat_model: "qwen-plus" }.to_json)
  end
  let(:adapter) { described_class.new(settings: settings) }

  it_behaves_like "an AI Assistant generation-only Llm provider",
                  key: "qwen",
                  display_name: "Qwen",
                  llm_provider: :qwen,
                  chat_model: "qwen-plus",
                  api_key: "sk-qwen"
end
