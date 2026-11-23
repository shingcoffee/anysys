# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Activities::UpdateProviderSettings do
  let!(:settings) do
    create(:ai_assistant_provider_settings, api_key: "OLD_SECRET",
           transcribe_active: false, generation_active: false)
  end

  def update(provider: "openai_whisper", **params)
    described_class.call(provider: provider, params: params)
  end

  it "fails validation when api_key is blank on a new unconfigured row" do
    AiAssistant::ProviderSettings.delete_all
    res = described_class.call(provider: "openai_whisper", params: { api_key: "" })
    expect(res.success?).to eq(false)
    expect(res.errors.join(" ")).to match(/api key/i)
  end

  it "updates non-secret fields and rotates the api_key on non-blank submission" do
    res = update(api_key: "NEW_SECRET", model: "whisper-1", organization: "org-2", transcribe_active: "1")
    expect(res.success?).to eq(true)
    expect(settings.reload).to have_attributes(api_key: "NEW_SECRET", transcribe_active: true)
    expect(settings.config_value(:organization)).to eq("org-2")
  end

  it "preserves the existing api_key when submitted blank" do
    update(api_key: "", model: "whisper-1")
    expect(settings.reload.api_key).to eq("OLD_SECRET")
  end

  it "deletes a config key back to its provider default when submitted blank" do
    settings.write_config(organization: "org-custom")
    settings.save!
    update(api_key: "k", organization: "")
    expect(settings.reload.config_value(:organization)).to be_nil
  end

  it "deletes a blank chat_model so the vendor default applies" do
    settings.write_config(chat_model: "gpt-4o")
    settings.save!
    update(api_key: "k", chat_model: "")
    expect(settings.reload.config_value(:chat_model)).to be_nil
  end

  it "activates transcribe independently of generation" do
    update(api_key: "K", transcribe_active: "1")
    expect(settings.reload).to have_attributes(transcribe_active: true, generation_active: false)
  end

  it "activates generation independently of transcribe" do
    update(api_key: "K", generation_active: "1")
    expect(settings.reload).to have_attributes(transcribe_active: false, generation_active: true)
  end

  it "deactivates a job when that flag is submitted as false" do
    settings.update!(transcribe_active: true, generation_active: true)
    update(api_key: "K", transcribe_active: "0")
    expect(settings.reload).to have_attributes(transcribe_active: false, generation_active: true)
  end

  it "leaves job flags unchanged when they are omitted" do
    settings.update!(transcribe_active: true, generation_active: false)
    update(api_key: "K")
    expect(settings.reload).to have_attributes(transcribe_active: true, generation_active: false)
  end

  it "rejects assigning transcribe to a generation-only provider" do
    res = update(provider: "cursor", api_key: "K", transcribe_active: "1")
    expect(res.success?).to eq(false)
    expect(res.errors).to include(I18n.t("ai_assistant.platform_settings.errors.transcribe_unsupported"))
    row = AiAssistant::ProviderSettings.find_by(provider: "cursor")
    expect(row.transcribe_active).to eq(false)
  end

  it "rejects assigning generation to a transcribe-only provider" do
    res = update(provider: "aliyun", api_key: "K", access_key_id: "AKID", app_key: "app-1",
                 generation_active: "1")
    expect(res.success?).to eq(false)
    expect(res.errors).to include(I18n.t("ai_assistant.platform_settings.errors.generation_unsupported"))
    row = AiAssistant::ProviderSettings.find_by(provider: "aliyun")
    expect(row.generation_active).to eq(false)
  end

  it "enqueues TestConnectionJob after a successful Cursor save" do
    expect {
      update(provider: "cursor", api_key: "K", generation_active: "1")
    }.to have_enqueued_job(AiAssistant::TestConnectionJob)
  end

  it "does not enqueue TestConnectionJob for a non-Cursor save" do
    expect {
      update(api_key: "K", transcribe_active: "1")
    }.not_to have_enqueued_job(AiAssistant::TestConnectionJob)
  end

  it "assigns jobs from transcribe_assignee and generation_assignee across vendors" do
    aliyun = create(:ai_assistant_provider_settings,
                    provider: "aliyun",
                    api_key: "AKS",
                    transcribe_active: true,
                    generation_active: false,
                    config: { access_key_id: "AKID", app_key: "app-1" }.to_json)

    res = update(provider: "cursor", api_key: "K",
                 transcribe_assignee: "openai_whisper", generation_assignee: "cursor")

    expect(res.success?).to eq(true)
    expect(settings.reload).to have_attributes(transcribe_active: true, generation_active: false)
    expect(aliyun.reload.transcribe_active).to eq(false)
    cursor = AiAssistant::ProviderSettings.find_by!(provider: "cursor")
    expect(cursor).to have_attributes(generation_active: true, transcribe_active: false)
  end

  it "clears a job when the assignee select is blank" do
    settings.update!(transcribe_active: true, generation_active: true)
    update(api_key: "K", transcribe_assignee: "", generation_assignee: "openai_whisper")
    expect(settings.reload).to have_attributes(transcribe_active: false, generation_active: true)
  end

  it "assigns jobs without requiring the current tab's credentials" do
    AiAssistant::ProviderSettings.for_provider("cursor").update!(api_key: nil)
    res = described_class.call(
      provider: "cursor",
      params: { transcribe_assignee: "openai_whisper", generation_assignee: "" }
    )
    expect(res.success?).to eq(true)
    expect(settings.reload.transcribe_active).to eq(true)
    expect(AiAssistant::ProviderSettings.find_by(provider: "cursor").generation_active).to eq(false)
  end

  it "rejects assigning a job to a provider that is not configured" do
    res = update(api_key: "K", generation_assignee: "cursor")
    expect(res.success?).to eq(false)
    expect(res.errors).to include(I18n.t("ai_assistant.platform_settings.errors.unconfigured_assignee"))
    expect(AiAssistant::ProviderSettings.find_by(provider: "cursor")&.generation_active).not_to eq(true)
  end

  it "rejects transcribe_assignee pointing at a generation-only provider" do
    res = update(api_key: "K", transcribe_assignee: "cursor")
    expect(res.success?).to eq(false)
    expect(res.errors).to include(I18n.t("ai_assistant.platform_settings.errors.transcribe_unsupported"))
    expect(settings.reload.transcribe_active).to eq(false)
  end

  it "does not persist a failed update" do
    AiAssistant::ProviderSettings.delete_all
    described_class.call(provider: "openai_whisper", params: { api_key: "" })
    row = AiAssistant::ProviderSettings.find_by(provider: "openai_whisper")
    expect(row.api_key).to be_blank
  end
end
