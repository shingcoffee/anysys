# frozen_string_literal: true

# Shared coverage for generation-only Llm-backed vendors (Qwen, DeepSeek).
# The host spec must define `settings` and `adapter`.
#
#   it_behaves_like "an AI Assistant generation-only Llm provider",
#     key: "qwen", display_name: "Qwen", llm_provider: :qwen,
#     chat_model: "qwen-plus", api_key: "sk-qwen"
RSpec.shared_examples "an AI Assistant generation-only Llm provider" do |key:, display_name:,
                                                                        llm_provider:, chat_model:,
                                                                        api_key:, supports_images: true|
  it_behaves_like "an AI Assistant registered provider",
                  key: key,
                  display_name: display_name,
                  supports_transcribe: false,
                  supports_generation: true,
                  supports_images: supports_images,
                  config_fields: [ :chat_model ]

  it_behaves_like "an AI Assistant Llm-backed chat",
                  llm_provider: llm_provider,
                  chat_model: chat_model,
                  api_key: api_key

  describe "#transcribe" do
    it "fail-closes with :configuration_error and never calls Llm" do
      expect(Llm).not_to receive(:complete)
      result = adapter.transcribe(io: StringIO.new("x"), filename: "clip.webm", content_type: "audio/webm")
      expect(result).to eq(outcome: :configuration_error, text: nil, raw: nil)
    end
  end

  describe "#health_check" do
    it "probes via Llm chat instead of transcribe" do
      expect(adapter).not_to receive(:transcribe)
      expect(Llm).to receive(:complete).with(
        hash_including(provider: llm_provider, model: chat_model, api_key: api_key, json: false)
      ).and_return({ outcome: :success, text: "pong", raw: {} })
      expect(adapter.health_check[:outcome]).to eq(:success)
    end

    it "treats a blank chat reply as credentials OK" do
      allow(Llm).to receive(:complete).and_return({ outcome: :empty, text: nil, raw: {} })
      expect(adapter.health_check[:outcome]).to eq(:success)
    end

    it "returns :configuration_error when api_key is missing without calling Llm" do
      settings.api_key = nil
      expect(Llm).not_to receive(:complete)
      expect(adapter.health_check[:outcome]).to eq(:configuration_error)
    end
  end
end
