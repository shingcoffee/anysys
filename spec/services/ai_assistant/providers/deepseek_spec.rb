# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Providers::Deepseek do
  let(:settings) do
    build_stubbed(:ai_assistant_provider_settings,
                  provider: "deepseek",
                  api_key: "sk-deep",
                  transcribe_active: false,
                  generation_active: true,
                  config: { chat_model: "deepseek-chat" }.to_json)
  end
  let(:adapter) { described_class.new(settings: settings) }

  it_behaves_like "an AI Assistant generation-only Llm provider",
                  key: "deepseek",
                  display_name: "DeepSeek",
                  llm_provider: :deepseek,
                  chat_model: "deepseek-chat",
                  api_key: "sk-deep",
                  supports_images: false
end
