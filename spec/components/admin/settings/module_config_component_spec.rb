# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Settings::ModuleConfigComponent, type: :component do
  let(:customer_id) { "81721200" }
  let(:assignment) { double("assignment", active?: true, configuration_json: { "daily_send_cap" => 42 }) }

  def render_config(key: "email", schema: FeatureModules::Email::Registration.configuration_schema, assignment: self.assignment, handoff_enabled: true, **options)
    feature_module = double("module", key: key, display_name: "Example module",
                                      configuration_schema_json: schema, handoff_enabled?: handoff_enabled,
                                      registration_class: "FeatureModules::#{key.camelize}::Registration".safe_constantize || FeatureModules::BaseModule)
    render_inline(described_class.new(customer_id: customer_id, feature_module: feature_module,
      assignment: assignment, default_exit: { kind: "route", name: "customer_home" }, **options))
  end

  it "uses the same single task heading on the root and daily-cap aliases" do
    [nil, "daily_cap"].each do |entry|
      render_config(entry_key: entry)
      expect(page).to have_css("h1", text: "Email limit", count: 1)
      expect(page).not_to have_css("h1", text: "Example module")
      expect(page).to have_link("Settings", href: "/81721200/admin/settings")
    end
  end

  it "retains SMS identity and labels on its generic root and aliases" do
    [nil, "daily_cap"].each do |entry|
      render_config(key: "sms", schema: FeatureModules::Sms::Registration.configuration_schema, entry_key: entry)
      expect(page).to have_css("h1", text: "Text message limit")
      expect(page).to have_text("Text messages per day")
      expect(page).not_to have_field("configuration[daily_send_cap]")
    end
  end

  it "preserves independent PATCH forms and the existing hidden return kind" do
    render_config(exit_override: { "url" => "https://example.com/thanks" })
    forms = page.all("form", visible: :all)
    expect(forms.size).to eq(1)
    expect(forms.first[:action]).to eq("/81721200/admin/settings/modules/emails")
    expect(page).to have_text("42")
    expect(page).not_to have_field("configuration[daily_send_cap]")
    expect(forms.first).not_to have_css("input[name='configuration[daily_send_cap]']", visible: :all)
    expect(forms.first).to have_css("input[name='configuration[exit_landing_page][kind]'][value='url']", visible: :all)
    expect(forms.first).to have_css("input[type='url'][value='https://example.com/thanks']", visible: :all)
    expect(page).to have_css("h2", text: "After finishing")
    expect(page).to have_text("Default: Organization home")
    expect(page).not_to have_css("code, pre")
    expect(rendered_content).not_to include("customer_home")
  end

  it "hides the return preference when handoff is disabled while displaying owner-managed limits" do
    render_config(handoff_enabled: false, exit_override: { "url" => "https://example.com/thanks" })

    expect(page).to have_text("42")
    expect(page).to have_text("The platform owner manages this limit for your organization.")
    expect(page).not_to have_text("This module isn't enabled")
    expect(page).not_to have_field("configuration[daily_send_cap]")
    expect(page).not_to have_css("form")
    expect(page).not_to have_text("After finishing")
    expect(page).not_to have_css("input[name*='exit_landing_page']", visible: :all)
    expect(page).not_to have_text("https://example.com/thanks")
  end

  it "does not offer an empty return form for a module with no settings or handoff" do
    render_config(schema: {}, handoff_enabled: false)

    expect(page).to have_text("This module has no configurable settings.")
    expect(page).not_to have_css("form")
  end

  it "explains which module actions use the return destination" do
    {
      "authentication" => "Regular sign-in, sign-up, and password recovery",
      "email" => "Sending or scheduling an email does not currently complete a handoff",
      "sms" => "Sending a message or checking delivery does not currently complete a handoff",
      "payment" => "The Return button on a standalone payment result also uses this URL",
      "ai_assistant" => "Chat replies and dictation do not currently complete a handoff",
      "captcha" => "Challenges, verification, and rate limits do not currently redirect here",
      "website" => "Publishing a site or page does not currently redirect here"
    }.each do |key, explanation|
      render_config(key: key, schema: {})
      expect(page).to have_text(explanation)
      expect(page).to have_text("A page-specific return destination takes priority.")
      expect(page).to have_text("Default: Organization home")
    end
  end

  it "translates the return destination explanation for the current locale" do
    I18n.with_locale(:"zh-CN") do
      render_config(key: "payment", schema: {})
      expect(page).to have_text("独立付款结果页的「返回」按钮也使用此网址。")
      expect(page).to have_text("页面单独指定的返回位置优先生效。")
    end
  end

  it "uses field defaults without overwriting stored false values" do
    allow(assignment).to receive(:configuration_json).and_return("mfa_enabled" => false)
    render_config(key: "authentication", schema: FeatureModules::Authentication::Registration.configuration_schema)
    expect(page).to have_css("h1", text: "Account security")
    expect(page).to have_select("Require two-factor authentication", selected: "No")
    expect(page).to have_field("Session timeout (minutes)", with: "30")
  end

  it "localizes schema descriptions and option labels at render time" do
    I18n.with_locale(:"zh-CN") do
      render_config(key: "authentication", schema: FeatureModules::Authentication::Registration.configuration_schema)
      expect(page).to have_text("会话闲置超过此分钟数后失效。")
      expect(page).not_to have_text("Session timeout in minutes")
      render_config(key: "ai_assistant", schema: FeatureModules::AiAssistant::Registration.configuration_schema)
      expect(page).to have_select("语言", selected: I18n.t("admin_misc.module_config.options.ai_assistant.language.auto"))
      expect(page).not_to have_text("translation missing")
    end
  end

  it "keeps unknown fields available with translated fallbacks instead of schema internals" do
    schema = { "internal_setting" => { "type" => "select", "description" => "Raw internal description", "options" => ["opaque_choice"] } }
    render_config(key: "future_module", entry_key: "internal_entry", schema: schema)
    expect(page).to have_select("Setting 1", options: ["Select...", "Option 1"])
    expect(page).to have_css("option[value='opaque_choice']")
    expect(page).not_to have_text("internal_setting")
    expect(page).not_to have_text("Raw internal description")
    expect(page).not_to have_text("internal_entry")
  end

  it "shows the unavailable state when assignment is suspended" do
    allow(assignment).to receive(:active?).and_return(false)
    render_config
    expect(page).to have_text("Suspended")
    expect(page).not_to have_css("form")
  end

  it "does not show enabled or editable controls when assignment is missing" do
    render_config(assignment: nil)
    expect(page).to have_text("Not enabled")
    expect(page).not_to have_css("form")
  end

  it "shows only the Return URL form when handoff is the module's sole setting" do
    render_config(schema: {})
    expect(page).not_to have_text("This module has no configurable settings.")
    expect(page).to have_css("form", count: 1, visible: :all)
    expect(page).to have_field("configuration[exit_landing_page][url]")
  end
end
