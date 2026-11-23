# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Providers do
  describe ".ensure_loaded!" do
    it "loads every provider file under app/services/ai_assistant/providers/*.rb (except base)" do
      expect { described_class.ensure_loaded! }.not_to raise_error
      expect(described_class.keys).not_to be_empty
    end
  end

  describe ".keys" do
    it "returns the registered provider keys as symbols" do
      expect(described_class.keys).to all(be_a(Symbol))
      expect(described_class.keys).to include(
        :openai_whisper, :aws_transcribe, :aliyun, :cursor, :aws_bedrock, :deepseek, :qwen
      )
    end
  end

  describe ".default_key" do
    it "returns the provider that declared default! (openai_whisper)" do
      expect(described_class.default_key).to eq(:openai_whisper)
    end
  end
end
