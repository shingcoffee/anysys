# frozen_string_literal: true

# Identity + readiness shared by every AI Assistant vendor spec.
# Host must define `settings` (a configured row for this provider).
#
#   it_behaves_like "an AI Assistant registered provider",
#     key: "cursor", display_name: "Cursor",
#     supports_transcribe: false, supports_generation: true,
#     config_fields: [ :chat_model ]
RSpec.shared_examples "an AI Assistant registered provider" do |key:, display_name:,
                                                                supports_transcribe:,
                                                                supports_generation:,
                                                                supports_images: nil,
                                                                config_fields: nil,
                                                                configured_on_api_key: true|
  it "registers without stealing the default transcribe vendor" do
    expect(AiAssistant::Providers.keys).to include(key.to_sym)
    expect(AiAssistant::Providers.default_key).to eq(:openai_whisper)
    expect(described_class.key).to eq(key.to_s)
    expect(described_class.default_display_name).to eq(display_name)
    expect(described_class.supports_transcribe?).to eq(supports_transcribe)
    expect(described_class.supports_generation?).to eq(supports_generation)
    expect(described_class.supports_images?).to eq(supports_images) unless supports_images.nil?
    if config_fields
      expect(described_class.config_fields.map { |field| field[:name] }).to eq(config_fields)
    end
  end

  if configured_on_api_key
    describe ".configured?" do
      it "is false when api_key is blank" do
        bare = build(:ai_assistant_provider_settings, provider: key, api_key: nil,
                     transcribe_active: false, generation_active: false)
        expect(described_class.configured?(bare)).to eq(false)
      end

      it "is true when api_key is present" do
        expect(described_class.configured?(settings)).to eq(true)
      end
    end
  end
end

# Chat-via-Llm coverage shared by Qwen/DeepSeek (generation-only) and Bedrock.
# Host must define `settings` and `adapter`.
RSpec.shared_examples "an AI Assistant Llm-backed chat" do |llm_provider:, chat_model:, api_key:,
                                                            extra_complete: {}|
  describe "#chat" do
    it "returns :success with the assistant text via Llm" do
      expect(Llm).to receive(:complete).with(
        hash_including({
          provider: llm_provider,
          model: chat_model,
          messages: [ { role: "user", content: "hi" } ],
          api_key: api_key,
          json: true,
          tools: nil
        }.merge(extra_complete))
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

    it "returns :configuration_error when api_key is missing without calling Llm" do
      settings.api_key = nil
      expect(Llm).not_to receive(:complete)
      expect(adapter.chat(messages: [])[:outcome]).to eq(:configuration_error)
    end

    it "delegates to ScriptedCompletion when the E2E stub is enabled" do
      expect(Llm).not_to receive(:complete)
      result = nil
      with_e2e_assistant_stub do
        result = adapter.chat(messages: [ { role: "user", content: "Create a FooBar entity" } ])
      end
      document = JSON.parse(result[:text])
      expect(result[:outcome]).to eq(:success)
      expect(document["tool"]).to eq("create_entity")
    end
  end
end
