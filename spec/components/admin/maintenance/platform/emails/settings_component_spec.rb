# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::Emails::SettingsComponent, type: :component do
  let(:smtp) { Email::Providers.for("smtp") }
  let(:ses) { Email::Providers.for("ses") }
  let(:providers) { [smtp, ses] }
  let(:sandbox) { build_stubbed(:email_credential, provider: "smtp", mode: "sandbox", status: "active") }

  def build_component(**overrides)
    described_class.new(**{
      provider_key: "smtp",
      providers: providers,
      credentials_by_mode: { "sandbox" => sandbox },
      all_credentials: [sandbox],
      delivery_by_mode: { "sandbox" => "smtp", "production" => nil },
      customer_id: 81_721_200,
      mode: :show
    }.merge(overrides))
  end

  def render_settings(component = build_component)
    with_request_url("/81721200/admin/maintenance/platform/module_settings/email/credentials") do
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
    expect(page.find("[data-provider-workspace-section='credentials']")).to have_css("[data-credential-panel='true']")
    expect(page).to have_text(I18n.t("maint_platform.emails.platform_settings.delivery_section"))
    expect(page).to have_text(I18n.t("maint_platform.emails.platform_settings.vendor_section"))
    expect(page).to have_link(smtp.display_name)
    expect(page).to have_link(ses.display_name)
    expect(page).to have_text(I18n.t("maint_platform.emails.credentials.form.modes.sandbox"))
    expect(page).to have_text(sandbox.host)
    expect(page).not_to have_css("[data-controller='tabs']")
  end

  it "renders aggregate inactive health before credential panels" do
    inactive = build_stubbed(:email_credential, provider: "smtp", mode: "sandbox", status: "disabled")
    render_settings(build_component(credentials_by_mode: { "sandbox" => inactive }, all_credentials: [inactive]))

    html = page.native.to_html
    expect(page.find("[data-provider-workspace-section='health']")).to have_text(I18n.t("common.status.disabled"))
    expect(html.index("data-provider-workspace-section=\"health\""))
      .to be < html.index("data-provider-workspace-section=\"credentials\"")
  end

  it "hides vendor cards while editing delivery assignment" do
    render_settings(build_component(mode: :edit_delivery))

    expect(page).to have_css("select#email_delivery_sandbox")
    expect(page).not_to have_text(I18n.t("maint_platform.emails.platform_settings.vendor_section"))
  end

  it "renders the locked credential form for the environment being edited" do
    record = Emails::Credential.new(provider: "smtp", mode: "sandbox", status: "disabled")
    render_settings(build_component(mode: :edit_vendor, edit_mode_key: "sandbox", credential: record,
                                    credentials_by_mode: {}))

    expect(page).to have_css("input[type='hidden'][name='emails_credential[provider]']", visible: :all)
    expect(page).to have_css("input[type='hidden'][name='emails_credential[mode]']", visible: :all)
    expect(page).not_to have_css("select#emails_credential_provider")
    expect(page).to have_field("emails_credential[host]")
  end

  it "marks the live delivery vendor as active in the switcher" do
    render_settings

    smtp_tab = page.find("a", text: smtp.display_name)
    expect(smtp_tab).to have_text(I18n.t("common.status.active"))
    expect(page).to have_link(ses.display_name)
    expect(page.find("a", text: ses.display_name)).not_to have_text(I18n.t("common.status.active"))
  end
end
