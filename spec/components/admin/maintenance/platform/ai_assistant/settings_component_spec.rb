# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::AiAssistant::SettingsComponent, type: :component do
  FakeWhisper = Class.new do
    def self.key = "openai_whisper"
    def self.display_name = "OpenAI Whisper"
    def self.config_fields
      [
        { name: :model, label: "Model", type: :string, default: "whisper-1" },
        { name: :chat_model, label: "Chat model", type: :string, default: "gpt-4o-mini" },
        { name: :organization, label: "Organization", type: :string }
      ]
    end
    def self.field_label(field) = field[:label].to_s
    def self.credential_label(name)
      I18n.t("ai_assistant.platform_settings.#{name}", default: name.to_s.humanize)
    end
    def self.supports_transcribe? = true
    def self.supports_generation? = true
  end

  FakeCursor = Class.new do
    def self.key = "cursor"
    def self.display_name = "Cursor"
    def self.config_fields
      [
        { name: :chat_model, label: "Chat model", type: :string }
      ]
    end
    def self.field_label(field) = field[:label].to_s
    def self.credential_label(name)
      I18n.t("ai_assistant.platform_settings.#{name}", default: name.to_s.humanize)
    end
    def self.supports_transcribe? = false
    def self.supports_generation? = true
  end

  FakeAws = Class.new do
    def self.key = "aws_transcribe"
    def self.display_name = "AWS Transcribe"
    def self.config_fields
      [
        { name: :region, label: "Region", type: :string, default: "us-east-1" }
      ]
    end
    def self.field_label(field) = field[:label].to_s
    def self.credential_label(name)
      I18n.t("ai_assistant.platform_settings.#{name}", default: name.to_s.humanize)
    end
    def self.supports_transcribe? = true
    def self.supports_generation? = false
  end

  let(:settings) do
    dbl = instance_double(
      "AiAssistant::ProviderSettings",
      provider: "openai_whisper",
      last_health_check_status: "ok",
      last_health_check_message: nil,
      api_key: "sk-secret-value",
      transcribe_active?: true,
      generation_active?: true
    )
    allow(dbl).to receive(:config_value).and_return(nil)
    dbl
  end

  def stub_providers(*klasses)
    allow(AiAssistant::Providers).to receive(:for) do |key|
      klasses.find { |pc| pc.key.to_s == key.to_s } ||
        raise(ArgumentError, "unknown provider #{key}")
    end
  end

  def build_component(last_health_check_status: "ok", mode: :show, errors: [],
                      providers: [ FakeWhisper ], transcribe_key: "openai_whisper",
                      generation_key: "openai_whisper", transcribe_settings: settings,
                      generation_settings: settings)
    allow(settings).to receive(:last_health_check_status).and_return(last_health_check_status)
    described_class.new(
      settings: settings, mode: mode, customer_id: 81721200,
      providers: providers, transcribe_key: transcribe_key,
      generation_key: generation_key, transcribe_settings: transcribe_settings,
      generation_settings: generation_settings, errors: errors
    )
  end

  def render_settings(component)
    with_request_url("/81721200/admin/maintenance/platform/module_settings/ai_assistant/settings") do
      render_inline(component)
    end
  end

  describe "rendering with default (show) state" do
    before { render_settings(build_component(mode: :show)) }

    it "renders the shared provider workspace with adjacent health testing" do
      expect(page).to have_css("[data-provider-workspace='true']")
      expect(page).to have_css("[data-provider-workspace-section='health'] form[action*='test_connection']")
      expect(page).to have_css("[data-credential-panel='true']")
      expect(page).to have_css("[data-provider-workspace-section='advanced-options']")
      expect(page.find("[data-provider-workspace-section='credentials']")).not_to have_text("Organization")
      expect(page.find("[data-provider-workspace-section='advanced-options']")).to have_text("Organization")
    end

    it "renders the masked API key and does not echo the secret" do
      expect(page).to have_text(I18n.t("ai_assistant.platform_settings.masked"))
      expect(page.native.to_html).not_to include("sk-secret-value")
    end

    it "puts platform jobs first with labeled providers, then vendor credentials" do
      html = page.native.to_html
      jobs_at = html.index("Platform jobs")
      vendor_at = html.index("Vendor")
      transcribe_at = html.index("Audio Transcribe")
      generation_at = html.index("Entity/Flowchart generation")
      credentials_at = html.index("Credentials")

      expect(jobs_at).to be_present
      expect(vendor_at).to be > jobs_at
      expect(transcribe_at).to be_between(jobs_at, vendor_at)
      expect(generation_at).to be_between(transcribe_at, vendor_at)
      expect(credentials_at).to be > vendor_at
      expect(page).to have_text(I18n.t("ai_assistant.platform_settings.jobs.transcribe_hint"))
      expect(page).to have_text(I18n.t("ai_assistant.platform_settings.jobs.generation_hint"))
      expect(page).to have_text("Organization")
    end

    it "does not duplicate assignment in a status strip or tab Active badges" do
      expect(page).not_to have_text("Assignees")
      expect(page).not_to have_text("This provider")
      expect(page).not_to have_text(I18n.t("common.status.active"))
      expect(page).to have_button(I18n.t("ai_assistant.platform_settings.test.button"))
      expect(page).to have_link(I18n.t("ai_assistant.platform_settings.edit_jobs"))
      expect(page).to have_link(I18n.t("ai_assistant.platform_settings.edit_credentials"))
    end

    it "marks the current provider tab as the current page" do
      expect(page).to have_css("nav[aria-label='#{I18n.t("ai_assistant.platform_settings.nav_label")}']")
      expect(page).to have_css("a[aria-current='page']", text: "OpenAI Whisper")
    end

    it "lists each job's provider by name instead of a joined assignee string" do
      expect(page).to have_text("Provider")
      expect(page).to have_text("OpenAI Whisper")
      expect(page.native.to_html).not_to include("OpenAI Whisper · OpenAI Whisper")
    end
  end

  describe "mode: :edit_vendor" do
    before { render_settings(build_component(mode: :edit_vendor, providers: [ FakeWhisper, FakeAws, FakeCursor ])) }

    it "renders a PATCH form with a blank password API key (keep-existing)" do
      expect(page).to have_css("form.w-full[method='post']")
      expect(page).not_to have_css("form.max-w-3xl")
      expect(page).to have_css("input[name='_method'][value='patch']", visible: :all)
      field = page.find("input#ai_assistant_provider_settings_api_key")
      expect(field[:type]).to eq("password")
      expect(field[:value]).to be_blank
      expect(field[:placeholder]).to eq(I18n.t("ai_assistant.platform_settings.secret_placeholder"))
      expect(page.native.to_html).not_to include("sk-secret-value")
    end

    it "does not include job assignee selects on the credentials form" do
      expect(page).not_to have_css("select[name='ai_assistant_provider_settings[transcribe_assignee]']")
      expect(page).not_to have_css("select[name='ai_assistant_provider_settings[generation_assignee]']")
      expect(page).to have_css("input[name='ai_assistant_provider_settings[organization]']")
      expect(page).to have_css("input[type='text'][name='ai_assistant_provider_settings[model]']")
      expect(page).to have_css("input[type='text'][name='ai_assistant_provider_settings[chat_model]']")
      expect(page).to have_button(I18n.t("ai_assistant.platform_settings.save"))
      expect(page).to have_link(I18n.t("ai_assistant.platform_settings.cancel"))
    end

    it "keeps vendor tab switches on the vendor edit path" do
      expect(page).to have_css("a[href*='section=vendor'][href*='provider=openai_whisper'][aria-current='page']")
    end

    it "does not render the retired enabled checkbox" do
      expect(page).not_to have_css("input[name='ai_assistant_provider_settings[enabled]']")
      expect(page).not_to have_text("Make this the active provider")
    end
  end

  describe "mode: :edit_jobs" do
    before { render_settings(build_component(mode: :edit_jobs, providers: [ FakeWhisper, FakeAws, FakeCursor ])) }

    it "assigns jobs with provider selects and does not prompt for credentials" do
      expect(page).to have_css("select[name='ai_assistant_provider_settings[transcribe_assignee]']")
      expect(page).to have_css("select[name='ai_assistant_provider_settings[generation_assignee]']")
      expect(page).to have_css("option[value='openai_whisper']", text: "OpenAI Whisper")
      expect(page).to have_css("select[name='ai_assistant_provider_settings[transcribe_assignee]'] option[value='aws_transcribe']")
      expect(page).not_to have_css("select[name='ai_assistant_provider_settings[transcribe_assignee]'] option[value='cursor']")
      expect(page).to have_css("select[name='ai_assistant_provider_settings[generation_assignee]'] option[value='cursor']")
      expect(page).not_to have_css("select[name='ai_assistant_provider_settings[generation_assignee]'] option[value='aws_transcribe']")
      expect(page).not_to have_css("input[name='ai_assistant_provider_settings[api_key]']")
      expect(page).not_to have_css("input[name='ai_assistant_provider_settings[organization]']")
      expect(page).not_to have_text("Vendor")
      expect(page).to have_button(I18n.t("ai_assistant.platform_settings.save"))
      expect(page).to have_link(I18n.t("ai_assistant.platform_settings.cancel"))
    end
  end

  describe "password-type config field (secret never echoed)" do
    let(:secret_field) { { name: :api_secret, label: "API Secret", type: :password } }

    before do
      allow(AiAssistant::Providers).to receive(:for).and_return(FakeWhisper)
      allow(FakeWhisper).to receive(:config_fields).and_return([ secret_field ])
      allow(settings).to receive(:config_value).with(:api_secret).and_return("STORED-SECRET-VALUE")
    end

    it "never emits the stored secret into the edit form and shows the mask placeholder" do
      render_settings(build_component(mode: :edit_vendor))
      expect(page.native.to_html).not_to include("STORED-SECRET-VALUE")
      expect(page).to have_css("input[type='password'][name='ai_assistant_provider_settings[api_secret]']")
      expect(page).to have_css(
        "input[name='ai_assistant_provider_settings[api_secret]'][placeholder='#{I18n.t("ai_assistant.platform_settings.secret_placeholder")}']"
      )
    end

    it "masks the stored secret in the show view instead of echoing it" do
      render_settings(build_component(mode: :show))
      expect(page.native.to_html).not_to include("STORED-SECRET-VALUE")
      expect(page).to have_text(I18n.t("ai_assistant.platform_settings.masked"))
    end
  end

  describe "with errors" do
    it "renders error messages" do
      render_settings(build_component(mode: :edit_vendor, errors: [ "API key can't be blank" ]))
      expect(page).to have_text("API key can't be blank")
    end
  end

  describe "#health_status_key" do
    it "returns 'ok' for last_health_check_status == 'ok'" do
      expect(build_component(last_health_check_status: "ok").health_status_key).to eq("ok")
    end

    it "returns 'configuration_error' for last_health_check_status == 'configuration_error'" do
      expect(build_component(last_health_check_status: "configuration_error").health_status_key)
        .to eq("configuration_error")
    end

    it "returns 'unreachable' for last_health_check_status == 'unreachable'" do
      expect(build_component(last_health_check_status: "unreachable").health_status_key).to eq("unreachable")
    end

    it "returns 'unknown' for nil status" do
      expect(build_component(last_health_check_status: nil).health_status_key).to eq("unknown")
    end
  end

  describe "health check error" do
    it "shows the last vendor error under a failed status" do
      allow(settings).to receive(:last_health_check_message).and_return("Invalid User API Key")
      render_settings(build_component(last_health_check_status: "configuration_error"))
      expect(page).to have_css("[data-provider-workspace-section='health'] [data-health-error]",
                               text: "Invalid User API Key")
    end

    it "hides a stale message once the status is OK" do
      allow(settings).to receive(:last_health_check_message).and_return("old failure")
      render_settings(build_component(last_health_check_status: "ok"))
      expect(page).not_to have_css("[data-health-error]")
      expect(page).not_to have_text("old failure")
    end

    it "labels the button while the live test is running" do
      render_settings(build_component)
      expect(page).to have_css(
        "button[data-turbo-submits-with='#{I18n.t("comp_payments.test_connection.testing")}']",
        text: I18n.t("ai_assistant.platform_settings.test.button")
      )
    end
  end

  describe "#field_value" do
    let(:component) { build_component }

    it "returns config value from settings when present" do
      allow(settings).to receive(:config_value).with(:model).and_return("whisper-1")
      field = { name: :model, label: "Model", type: :string, default: "whisper-1" }
      expect(component.field_value(field)).to eq("whisper-1")
    end

    it "falls back to field default when config_value is blank" do
      allow(settings).to receive(:config_value).with(:model).and_return(nil)
      field = { name: :model, label: "Model", type: :string, default: "whisper-1" }
      expect(component.field_value(field)).to eq("whisper-1")
    end
  end

  describe "provider lookup" do
    it "still renders with providers passed in and does not raise" do
      expect { render_settings(build_component(mode: :show)) }.not_to raise_error
      expect(page).to have_text("OpenAI Whisper")
    end

    it "shows unassigned jobs when no assignee rows are passed" do
      component = described_class.new(
        settings: settings, mode: :show, customer_id: 81721200,
        providers: [ FakeWhisper ], transcribe_key: nil, generation_key: nil,
        transcribe_settings: nil, generation_settings: nil
      )
      render_settings(component)
      expect(page).to have_text("Platform jobs")
      expect(page).to have_text("Not assigned")
      expect(page.native.to_html).not_to include("— · —")
    end
  end

  describe "Cursor vendor" do
    let(:providers) { [ FakeWhisper, FakeCursor ] }
    let(:whisper_row) do
      dbl = instance_double("AiAssistant::ProviderSettings", provider: "openai_whisper")
      allow(dbl).to receive(:config_value).and_return(nil)
      dbl
    end

    before do
      stub_providers(FakeWhisper, FakeCursor)
      allow(settings).to receive(:provider).and_return("cursor")
      allow(settings).to receive(:transcribe_active?).and_return(false)
      allow(settings).to receive(:generation_active?).and_return(true)
    end

    it "keeps mixed assignees in the jobs card and does not mark tabs Active" do
      render_settings(build_component(
        mode: :show, providers: providers,
        transcribe_key: "openai_whisper", generation_key: "cursor",
        transcribe_settings: whisper_row, generation_settings: settings
      ))

      expect(page).to have_css("a[aria-current='page']", text: "Cursor")
      expect(page).not_to have_text(I18n.t("common.status.active"))
      expect(page).to have_text("OpenAI Whisper")
      expect(page).to have_text("Cursor")
      expect(page.native.to_html).not_to include("OpenAI Whisper · Cursor")
    end

    it "does not show Not supported and lists the cached generation model" do
      allow(settings).to receive(:config_value).with(:chat_model).and_return("composer")
      allow(settings).to receive(:config_value).with(:generation_models).and_return(
        [ { "id" => "composer", "display_name" => "Composer" } ]
      )
      render_settings(build_component(
        mode: :show, providers: providers,
        transcribe_key: "openai_whisper", generation_key: "cursor",
        transcribe_settings: whisper_row, generation_settings: settings
      ))

      expect(page).to have_text("Audio Transcribe")
      expect(page).not_to have_text("Not supported")
      expect(page).to have_text("Composer")
      expect(page).to have_text("Configuration")
    end

    it "renders a cached generation select on edit, including a stale stored id" do
      allow(settings).to receive(:config_value).with(:chat_model).and_return("stale-id")
      allow(settings).to receive(:config_value).with(:generation_models).and_return(
        [ { "id" => "composer", "display_name" => "Composer" } ]
      )
      render_settings(build_component(
        mode: :edit_vendor, providers: providers,
        transcribe_key: "openai_whisper", generation_key: "cursor",
        transcribe_settings: whisper_row, generation_settings: settings
      ))

      expect(page).not_to have_text("Not supported")
      expect(page).not_to have_css("select[name='ai_assistant_provider_settings[generation_assignee]']")
      expect(page).to have_css("select.input-field[name='ai_assistant_provider_settings[chat_model]']")
      expect(page).to have_css("option[value='']", text: "Cursor default")
      expect(page).to have_css("option[value='composer']", text: "Composer")
      expect(page).to have_css("option[value='stale-id'][selected]")
    end

    it "omits the select when the Cursor model cache is empty" do
      render_settings(build_component(
        mode: :edit_vendor, providers: providers,
        transcribe_key: "openai_whisper", generation_key: "cursor",
        transcribe_settings: whisper_row, generation_settings: settings
      ))

      expect(page).not_to have_css("select[name='ai_assistant_provider_settings[chat_model]']")
      expect(page).to have_text("Save credentials first. Models load after Test connection.")
    end
  end

  describe "AWS-like vendor" do
    before do
      stub_providers(FakeAws)
      allow(settings).to receive(:provider).and_return("aws_transcribe")
      allow(settings).to receive(:transcribe_active?).and_return(true)
      allow(settings).to receive(:generation_active?).and_return(false)
    end

    it "shows transcribe assignment without a model row and generation as not assigned" do
      render_settings(build_component(
        mode: :show, providers: [ FakeAws ],
        transcribe_key: "aws_transcribe", generation_key: nil,
        transcribe_settings: settings, generation_settings: nil
      ))

      expect(page).to have_text("Audio Transcribe")
      expect(page).to have_text("Entity/Flowchart generation")
      expect(page).to have_text("Not assigned")
      expect(page).not_to have_text("Not supported")
      expect(page).not_to have_text("Model")
      expect(page).to have_text("AWS Transcribe")
    end

    it "renders job selects without a model input on jobs edit" do
      render_settings(build_component(
        mode: :edit_jobs, providers: [ FakeAws ],
        transcribe_key: "aws_transcribe", generation_key: nil,
        transcribe_settings: settings, generation_settings: nil
      ))

      expect(page).to have_css("select[name='ai_assistant_provider_settings[transcribe_assignee]'] option[value='aws_transcribe'][selected]")
      expect(page).to have_css("select[name='ai_assistant_provider_settings[generation_assignee]'] option[value=''][selected]")
      expect(page).not_to have_css("input[name='ai_assistant_provider_settings[transcribe_active]']")
      expect(page).not_to have_css("input[name='ai_assistant_provider_settings[generation_active]']")
      expect(page).not_to have_css("input[name='ai_assistant_provider_settings[model]']")
      expect(page).not_to have_text("Not supported")
    end
  end
end
