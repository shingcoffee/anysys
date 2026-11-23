# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::Captcha::SettingsComponent, type: :component do
  # Build a full-featured double for Captcha::ProviderSettings so the spec
  # does not require a real DB row or encrypted-column support.
  let(:settings) do
    dbl = instance_double(
      Captcha::ProviderSettings,
      provider: "aliyun",
      last_health_check_status: "ok",
      access_key_id: "AK123",
      access_key_secret: "secret",
      enabled?: true,
      fail_policy: "open",
      score_threshold: nil
    )
    allow(dbl).to receive(:config_value).and_return(nil)
    dbl
  end

  def build_component(last_health_check_status: "ok", mode: :edit_vendor, errors: [],
                      providers: [], active_key: "aliyun")
    allow(settings).to receive(:last_health_check_status).and_return(last_health_check_status)
    described_class.new(
      settings: settings, mode: mode, customer_id: 81721200,
      providers: providers, active_key: active_key, errors: errors
    )
  end

  # The template calls captcha settings path helpers that require :customer_id.
  # Wrap render calls in with_request_url to supply the route params.
  def render_settings(component)
    with_request_url("/81721200/admin/maintenance/platform/module_settings/captcha/settings") do
      render_inline(component)
    end
  end

  it "exposes the provider display name via #provider_name" do
    expect(build_component.provider_name).to eq("Aliyun Captcha")
  end

  it "renders the provider selector with each registered provider's display name" do
    component = described_class.new(settings: settings, mode: :edit_vendor, customer_id: 81721200,
                                     providers: [Captcha::Providers::Aliyun], active_key: "aliyun")
    render_settings(component)
    expect(page).to have_text("Aliyun Captcha")
  end

  it "renders config field labels from the provider" do
    render_settings(build_component)
    expect(page).to have_text("Scene ID")
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
      expect(build_component(last_health_check_status: "unreachable").health_status_key)
        .to eq("unreachable")
    end

    it "returns 'unknown' for nil status" do
      expect(build_component(last_health_check_status: nil).health_status_key).to eq("unknown")
    end

    it "returns 'unknown' for unrecognized status string" do
      expect(build_component(last_health_check_status: "pending").health_status_key).to eq("unknown")
    end
  end

  describe "#health_badge_variant" do
    it "maps health keys to badge variants" do
      expect(build_component(last_health_check_status: "ok").health_badge_variant).to eq(:success)
      expect(build_component(last_health_check_status: "configuration_error").health_badge_variant).to eq(:danger)
      expect(build_component(last_health_check_status: "unreachable").health_badge_variant).to eq(:warning)
      expect(build_component(last_health_check_status: nil).health_badge_variant).to eq(:default)
    end
  end

  describe "#field_value" do
    let(:component) { build_component }

    it "returns config value from settings when present" do
      allow(settings).to receive(:config_value).with(:endpoint).and_return("my.endpoint.com")
      field = { name: :endpoint, label: "Endpoint", type: :string, default: "default.endpoint.com" }
      expect(component.field_value(field)).to eq("my.endpoint.com")
    end

    it "falls back to field default when config_value is blank" do
      allow(settings).to receive(:config_value).with(:endpoint).and_return(nil)
      field = { name: :endpoint, label: "Endpoint", type: :string, default: "default.endpoint.com" }
      expect(component.field_value(field)).to eq("default.endpoint.com")
    end

    it "returns nil when both config_value and default are absent" do
      allow(settings).to receive(:config_value).with(:scene_id).and_return(nil)
      field = { name: :scene_id, label: "Scene ID", type: :string }
      expect(component.field_value(field)).to be_nil
    end
  end

  describe "password-type config field (secret never echoed)" do
    let(:secret_field) { { name: :api_secret, label: "API Secret", type: :password } }

    before do
      allow(Captcha::Providers::Aliyun).to receive(:config_fields).and_return([secret_field])
      allow(settings).to receive(:config_value).with(:api_secret).and_return("STORED-SECRET-VALUE")
    end

    it "never emits the stored secret into the edit form and shows the mask placeholder" do
      render_settings(build_component(mode: :edit_vendor))
      expect(page.native.to_html).not_to include("STORED-SECRET-VALUE")
      expect(page).to have_css("input[type='password'][name='captcha_provider_settings[api_secret]']")
      expect(page).to have_css(
        "input[name='captcha_provider_settings[api_secret]'][placeholder='#{I18n.t("comp_admin.captcha_platform_settings.secret_placeholder")}']"
      )
    end

    it "masks the stored secret in the show view instead of echoing it" do
      render_settings(build_component(mode: :show))
      expect(page.native.to_html).not_to include("STORED-SECRET-VALUE")
      expect(page).to have_text("••••••")
    end
  end

  describe "with errors" do
    it "renders error messages in an error block" do
      render_settings(build_component(errors: ["Scene ID can't be blank"]))
      expect(page).to have_text("Scene ID can't be blank")
    end
  end

  describe "mode: :show" do
    it "renders the show view with access_key_id and health status" do
      render_settings(build_component(mode: :show, providers: [ Captcha::Providers::Aliyun ], active_key: "aliyun"))
      expect(page).to have_css("[data-provider-workspace='true']")
      expect(page).to have_css("[data-provider-workspace-section='health'] form[action*='test_connection']")
      expect(page).to have_css("[data-credential-panel='true']")
      expect(page).to have_css("[data-provider-workspace-section='advanced-options']")
      credentials = page.find("[data-provider-workspace-section='credentials']")
      advanced = page.find("[data-provider-workspace-section='advanced-options']")
      expect(credentials).to have_text(I18n.t("captcha.platform_settings.credentials_section"))
      expect(credentials).not_to have_text(I18n.t("captcha.platform_settings.fail_policy"))
      expect(advanced).to have_text(I18n.t("captcha.platform_settings.fail_policy"))
      expect(page).to have_text("AK123")
      expect(page).to have_text("Last verification: OK")
      expect(page).to have_link(I18n.t("captcha.platform_settings.edit_active"))
      expect(page).to have_link(I18n.t("captcha.platform_settings.edit_credentials"))
      expect(page).to have_text(I18n.t("captcha.platform_settings.active_section"))
    end
  end

  describe "mode: :edit_vendor" do
    before { render_settings(build_component(mode: :edit_vendor)) }

    it "renders every Aliyun configuration field plus fail policy" do
      expect(page).to have_field("captcha_provider_settings[scene_id]")
      expect(page).to have_field("captcha_provider_settings[endpoint]")
      expect(page).to have_field("captcha_provider_settings[region]")
      expect(page).to have_css("select#captcha_provider_settings_fail_policy")
      expect(page).not_to have_css("select[name='captcha_provider_settings[active_assignee]']")
      expect(page).not_to have_text("Make this the active provider")
      expect(page).to have_button(I18n.t("captcha.platform_settings.save"))
      expect(page).to have_link(I18n.t("captcha.platform_settings.cancel"))
    end

    it "constrains edit inputs so short keys are not full-bleed" do
      expect(page).to have_css("form.w-full div.max-w-xl input#captcha_provider_settings_scene_id")
      expect(page).not_to have_css("form.max-w-3xl")
    end
  end

  describe "mode: :edit_active" do
    it "lets the owner pick the live vendor without credential fields" do
      render_settings(build_component(
        mode: :edit_active,
        providers: [ Captcha::Providers::Aliyun, Captcha::Providers::Turnstile ],
        active_key: "aliyun"
      ))
      expect(page).to have_css("select[name='captcha_provider_settings[active_assignee]']")
      expect(page).not_to have_css("input[name='captcha_provider_settings[access_key_secret]']")
      expect(page).not_to have_text("Vendor")
      expect(page).to have_button(I18n.t("captcha.platform_settings.save"))
    end
  end
end
