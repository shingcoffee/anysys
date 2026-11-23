# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Activities::TestConnection do
  let(:settings) { create(:ai_assistant_provider_settings) }

  describe "not configured" do
    it "returns configuration_error without calling the provider" do
      settings.update!(api_key: nil)
      expect(AiAssistant::Providers::OpenaiWhisper).not_to receive(:new)
      result = described_class.call(settings: settings)
      expect(result.status).to eq("configuration_error")
      expect(result.ok?).to eq(false)
    end

    it "persists and returns the not-configured message" do
      settings.update!(api_key: nil)
      result = described_class.call(settings: settings)
      expected = I18n.t("ai_assistant.platform_settings.errors.unconfigured_assignee")
      expect(result.message).to eq(expected)
      expect(settings.reload.last_health_check_message).to eq(expected)
    end
  end

  describe "error message" do
    def stub_health(result)
      allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper).to receive(:health_check).and_return(result)
    end

    it "returns the vendor's error string verbatim" do
      stub_health(outcome: :configuration_error, text: nil, raw: { "error" => "Incorrect API key provided" })
      result = described_class.call(settings: settings)
      expect(result.message).to eq("Incorrect API key provided")
      expect(settings.reload.last_health_check_message).to eq("Incorrect API key provided")
    end

    it "reads the message out of a nested error object" do
      stub_health(outcome: :configuration_error, text: nil,
                  raw: { "error" => { "message" => "Invalid key", "type" => "auth" } })
      expect(described_class.call(settings: settings).message).to eq("Invalid key")
    end

    it "reads a top-level message (Cursor) or Message (Aliyun)" do
      stub_health(outcome: :configuration_error, text: nil, raw: { "code" => "error", "message" => "Invalid User API Key" })
      expect(described_class.call(settings: settings).message).to eq("Invalid User API Key")

      stub_health(outcome: :configuration_error, text: nil, raw: { "Message" => "Specified access key is not found." })
      expect(described_class.call(settings: settings).message).to eq("Specified access key is not found.")
    end

    it "falls back to the HTTP status when the vendor sent no message" do
      stub_health(outcome: :unreachable, text: nil, raw: {}, http_status: 502)
      expect(described_class.call(settings: settings).message)
        .to eq(I18n.t("ai_assistant.platform_settings.test.http_status", status: 502))
    end

    it "returns nil when there is nothing to report" do
      stub_health(outcome: :unreachable, text: nil, raw: nil)
      expect(described_class.call(settings: settings).message).to be_nil
    end

    it "clears a previous error message on success" do
      settings.update_columns(last_health_check_status: "unreachable", last_health_check_message: "old failure")
      stub_health(outcome: :success, text: "hi", raw: { "message" => "ignored on success" })
      result = described_class.call(settings: settings)
      expect(result.message).to be_nil
      expect(settings.reload.last_health_check_message).to be_nil
    end

    it "truncates very long vendor messages" do
      stub_health(outcome: :configuration_error, text: nil, raw: { "error" => "x" * 2_000 })
      expect(described_class.call(settings: settings).message.length).to eq(described_class::MESSAGE_LIMIT)
    end

    it "reports an unexpected adapter exception as unreachable with its message" do
      allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper)
        .to receive(:health_check).and_raise(RuntimeError, "ffmpeg missing")
      result = described_class.call(settings: settings)
      expect(result).to have_attributes(status: "unreachable", message: "ffmpeg missing")
      expect(settings.reload.last_health_check_status).to eq("unreachable")
    end
  end

  describe "outcome mapping" do
    it "maps :success to ok" do
      allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper)
        .to receive(:health_check).and_return(outcome: :success, text: "hi", raw: {})
      expect(described_class.call(settings: settings).status).to eq("ok")
    end

    it "maps :empty to ok (silent probe is expected to yield no speech)" do
      allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper)
        .to receive(:health_check).and_return(outcome: :empty, text: nil, raw: {})
      expect(described_class.call(settings: settings).status).to eq("ok")
    end

    it "maps :configuration_error to configuration_error" do
      allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper)
        .to receive(:health_check).and_return(outcome: :configuration_error, text: nil, raw: { "error" => "bad key" })
      expect(described_class.call(settings: settings).status).to eq("configuration_error")
    end

    it "maps :unreachable to unreachable" do
      allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper)
        .to receive(:health_check).and_return(outcome: :unreachable, text: nil, raw: nil)
      expect(described_class.call(settings: settings).status).to eq("unreachable")
    end
  end

  describe "OpenAI WAV probe via health_check" do
    it "sends a silent WAV through #transcribe" do
      expect_any_instance_of(AiAssistant::Providers::OpenaiWhisper)
        .to receive(:transcribe) do |**kwargs|
          expect(kwargs[:filename]).to eq("probe.wav")
          expect(kwargs[:content_type]).to eq("audio/wav")
          { outcome: :empty, text: nil, raw: {} }
        end
      expect(described_class.call(settings: settings).status).to eq("ok")
    end
  end

  describe "Cursor health_check path" do
    let(:cursor_settings) do
      create(:ai_assistant_provider_settings, provider: "cursor", api_key: "cur-test",
             transcribe_active: false, generation_active: true,
             config: { organization: "keep-me" }.to_json)
    end

    it "calls health_check instead of transcribe and treats :success as ok" do
      expect_any_instance_of(AiAssistant::Providers::Cursor).not_to receive(:transcribe)
      allow_any_instance_of(AiAssistant::Providers::Cursor)
        .to receive(:health_check).and_return(outcome: :success, text: nil, raw: { "items" => [] })
      expect(described_class.call(settings: cursor_settings).status).to eq("ok")
    end

    it "persists generation_models from health_check without clobbering other config" do
      allow_any_instance_of(AiAssistant::Providers::Cursor).to receive(:health_check).and_return(
        outcome: :success, text: nil, raw: { "items" => [] },
        models: [ { "id" => "gpt-5", "display_name" => "GPT-5" } ]
      )
      described_class.call(settings: cursor_settings)
      cursor_settings.reload
      expect(cursor_settings.config_value(:generation_models)).to eq(
        [ { "id" => "gpt-5", "display_name" => "GPT-5" } ]
      )
      expect(cursor_settings.config_value(:organization)).to eq("keep-me")
      expect(cursor_settings.last_health_check_status).to eq("ok")
    end
  end

  describe "persistence" do
    it "writes last_health_check_at, _status, and _message on the settings row" do
      allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper)
        .to receive(:health_check).and_return(outcome: :success, text: "hi", raw: {})
      described_class.call(settings: settings)
      expect(settings.reload).to have_attributes(
        last_health_check_status: "ok",
        last_health_check_at: be_present
      )
    end
  end
end
