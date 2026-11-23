# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe AiAssistant::Contracts::ProviderSettings do
  subject(:form) do
    described_class.new(
      OpenStruct.new(
        provider: "openai_whisper",
        api_key: "sk-test",
        transcribe_active: true,
        generation_active: true,
        config: { model: "whisper-1" }.to_json
      )
    )
  end

  let(:valid_params) do
    {
      provider: "openai_whisper", api_key: "sk-test",
      transcribe_active: true, generation_active: true,
      config: { model: "whisper-1" }.to_json
    }
  end

  def validate_with(params)
    form.validate(params)
    form
  end

  it "is valid with an api_key" do
    expect(validate_with(valid_params).errors[:base]).to be_empty
  end

  it "adds a localized error when api_key is blank" do
    f = validate_with(valid_params.merge(api_key: ""))
    expect(f.errors[:base]).to include(I18n.t("ai_assistant.platform_settings.errors.api_key_blank"))
  end

  it "adds the unknown-provider error when the provider is unregistered" do
    f = validate_with(valid_params.merge(provider: "unknown_vendor_xyz", config: "{}"))
    expect(f.errors[:base]).to include(I18n.t("ai_assistant.platform_settings.errors.unknown_provider"))
  end

  it "accepts blank model because the field declares a default" do
    f = validate_with(valid_params.merge(config: {}.to_json))
    expect(f.errors[:base]).to be_empty
  end

  it "requires Aliyun access_key_id and app_key" do
    f = described_class.new(
      OpenStruct.new(provider: "aliyun", api_key: "secret", transcribe_active: false,
                     generation_active: false, config: {}.to_json)
    )
    f.validate({})
    expect(f.errors[:base]).to include(
      I18n.t("ai_assistant.platform_settings.errors.field_blank",
             field: I18n.t("ai_assistant.providers.aliyun.fields.access_key_id"))
    )
    expect(f.errors[:base]).to include(
      I18n.t("ai_assistant.platform_settings.errors.field_blank",
             field: I18n.t("ai_assistant.providers.aliyun.fields.app_key"))
    )
  end

  it "rejects transcribe_active on a provider that does not support transcribe" do
    f = described_class.new(
      OpenStruct.new(provider: "cursor", api_key: "secret", transcribe_active: true,
                     generation_active: false, config: {}.to_json)
    )
    f.validate({})
    expect(f.errors[:base]).to include(I18n.t("ai_assistant.platform_settings.errors.transcribe_unsupported"))
    expect(I18n.t("ai_assistant.platform_settings.errors.transcribe_unsupported"))
      .to eq("This provider does not support Audio Transcribe.")
  end

  it "rejects generation_active on a provider that does not support generation" do
    f = described_class.new(
      OpenStruct.new(provider: "aliyun", api_key: "secret", transcribe_active: false,
                     generation_active: true, config: { access_key_id: "AKID", app_key: "app-1" }.to_json)
    )
    f.validate({})
    expect(f.errors[:base]).to include(I18n.t("ai_assistant.platform_settings.errors.generation_unsupported"))
    expect(I18n.t("ai_assistant.platform_settings.errors.generation_unsupported"))
      .to eq("This provider does not support Entity/Flowchart generation.")
  end
end
