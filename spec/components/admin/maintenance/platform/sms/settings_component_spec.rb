# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::Sms::SettingsComponent, type: :component do
  let(:aliyun) { Sms::Adapters.for("aliyun") }
  let(:twilio) { Sms::Adapters.for("twilio") }
  let(:providers) { [aliyun, twilio] }
  let(:sandbox) { build_stubbed(:sms_credential, provider: "aliyun", mode: "sandbox", status: "active") }

  def build_component(**overrides)
    described_class.new(**{
      provider_key: "aliyun",
      providers: providers,
      credentials_by_mode: { "sandbox" => sandbox },
      all_credentials: [sandbox],
      delivery_by_mode: { "sandbox" => "aliyun", "production" => nil },
      customer_id: 81_721_200,
      mode: :show
    }.merge(overrides))
  end

  def render_settings(component = build_component)
    with_request_url("/81721200/admin/maintenance/platform/module_settings/sms/credentials") do
      render_inline(component)
    end
  end

  it "renders delivery assignment and the provider switcher on show" do
    render_settings

    expect(page).to have_css("[data-provider-workspace='true']")
    expect(page).to have_css("[data-provider-workspace-section='assignment']")
    expect(page).to have_css("[data-provider-workspace-section='provider']")
    expect(page).to have_css("[data-provider-workspace-section='health']")
    expect(page).to have_css("[data-provider-workspace-section='credentials']")
    expect(page).to have_css("[data-credential-panel='true']")
    health = page.find("[data-provider-workspace-section='health']")
    expect(health).to have_text(I18n.t("common.status.configured"))
    expect(health).to have_text(I18n.t("common.status.partial"))
    expect(page).to have_text(I18n.t("maint_platform.sms.platform_settings.delivery_section"))
    expect(page).to have_text(I18n.t("maint_platform.sms.platform_settings.vendor_section"))
    expect(page).to have_link(aliyun.display_name)
    expect(page).to have_link(twilio.display_name)
    expect(page).to have_text(I18n.t("common.modes.sandbox"))
    expect(page).to have_text(sandbox.access_key_id)
    expect(page).not_to have_css("[data-controller='tabs']")
  end

  it "hides vendor cards while editing delivery assignment" do
    render_settings(build_component(mode: :edit_delivery))

    expect(page).to have_css("select#sms_delivery_sandbox")
    expect(page).not_to have_text(I18n.t("maint_platform.sms.platform_settings.vendor_section"))
  end

  it "renders the locked credential form for the environment being edited" do
    record = Sms::Credential.new(provider: "aliyun", mode: "sandbox", status: "disabled")
    render_settings(build_component(mode: :edit_vendor, edit_mode_key: "sandbox", credential: record,
                                    credentials_by_mode: {}))

    expect(page).to have_css("input[type='hidden'][name='sms_credential[provider]']", visible: :all)
    expect(page).to have_css("input[type='hidden'][name='sms_credential[mode]']", visible: :all)
    expect(page).not_to have_css("select#sms_credential_provider")
    expect(page).to have_field("sms_credential[access_key_id]")
  end

  it "marks the live delivery vendor as active in the switcher" do
    render_settings

    aliyun_tab = page.find("a", text: aliyun.display_name)
    expect(aliyun_tab).to have_text(I18n.t("common.status.active"))
    expect(page).to have_link(twilio.display_name)
    expect(page.find("a", text: twilio.display_name)).not_to have_text(I18n.t("common.status.active"))
  end
end
