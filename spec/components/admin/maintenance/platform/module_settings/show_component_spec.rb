# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::ModuleSettings::ShowComponent, type: :component do
  let(:feature_module) do
    create(:feature_module, key: "test_show_layout_#{SecureRandom.hex(3)}",
                            name: "Layout Module", status: :active, required: false,
                            version: "2.1")
  end

  def render_show(mod: feature_module, models: [], pane: :overview, **extras)
    url = case pane.to_sym
          when :configuration
            "/81721200/admin/maintenance/platform/module_settings/#{mod.id}/configuration"
          when :developer
            "/81721200/admin/maintenance/platform/module_settings/#{mod.id}/developer"
          else
            "/81721200/admin/maintenance/platform/module_settings/#{mod.id}"
          end
    with_request_url(url) do
      render_inline(described_class.new(
        feature_module: mod,
        module_models: models,
        customer_id: 81_721_200,
        pane: pane,
        **extras
      ))
    end
  end

  it "renders Availability and details on Overview and omits Developer content" do
    render_show

    expect(page).to have_css("[data-module-settings-pane='overview']")
    expect(page).to have_css("[data-module-settings-section='availability']")
    expect(page).to have_css("[data-module-settings-section='details']")
    expect(page).to have_css("[data-module-settings-section='details'] dl")
    expect(page).to have_text(feature_module.key)
    expect(page).to have_text("2.1")
    expect(page).not_to have_css("[data-developer-reference]", visible: true)
    expect(page).not_to have_text(I18n.t("maint_platform.module_settings.show.handoff_target"))
    expect(page).not_to have_css("[data-module-settings-section='next-actions']")
    expect(page).not_to have_css("[data-controller='tabs']")
  end

  it "keeps availability control titles free of status badges" do
    render_show

    headings = page.all("[data-module-settings-section='availability'] h3").map(&:text)
    expect(headings).to eq([
      I18n.t("maint_platform.module_settings.show.module_status"),
      I18n.t("maint_platform.module_settings.show.required_module")
    ])
  end

  it "associates mandatory availability switches with accessible names and disabled explanations" do
    mandatory = FeatureModules::Module.find_by!(key: "authentication")
    render_show(mod: mandatory)

    section = page.find("[data-module-settings-section='availability']")
    switches = section.all("button[role='switch']")
    expect(switches.map { |button| button["aria-label"] }).to eq([
      I18n.t("maint_platform.module_settings.show.module_status"),
      I18n.t("maint_platform.module_settings.show.required_module")
    ])

    switches.each do |button|
      described_by_ids = button["aria-describedby"].to_s.split
      row = button.find(:xpath, "ancestor::*[@data-module-settings-setting-row]")
      expect(described_by_ids.size).to eq(2)
      expect(described_by_ids).to all(satisfy { |id| section.has_css?("##{id}") })
      expect(described_by_ids).to include(
        row.find("[role='note']", text: I18n.t("maint_platform.module_settings.show.locked_hint"))[:id]
      )
    end
  end

  it "renders Availability before details" do
    render_show

    html = page.native.to_html
    availability_at = html.index('data-module-settings-section="availability"')
    details_at = html.index('data-module-settings-section="details"')

    expect(availability_at).to be_present
    expect(details_at).to be_present
    expect(availability_at).to be < details_at
  end

  it "renders the Developer pane with the contract inside handoff, and models" do
    render_show(pane: :developer)

    expect(page).to have_css("[data-module-settings-pane='developer'][data-developer-reference='true']")
    expect(page).to have_css("[data-module-settings-section='handoff'] [data-module-settings-section='contract']")
    expect(page).to have_css("[data-module-settings-section='models']")
    expect(page).to have_text(I18n.t("maint_platform.module_settings.show.handoff_target"))
    expect(page).to have_text(I18n.t("maint_platform.module_settings.show.models.empty"))
    expect(page).not_to have_css("[data-module-settings-section='availability']")
  end

  describe "Developer models browser" do
    let(:models) do
      [
        { name: "Demo::Order", table_name: "demo_orders", columns_count: 2, associations_count: 1,
          columns: [{ name: "amount", label: "Amount", type: "integer" }, { name: "currency", label: "Currency", type: "string" }] },
        { name: "Demo::Refund", table_name: "demo_refunds", columns_count: 1, associations_count: 0,
          columns: [{ name: "reason", label: "Reason", type: "string" }] }
      ]
    end

    it "lists every model once and shows the first model's attributes by default" do
      render_show(pane: :developer, models: models)

      expect(page).to have_css("[data-module-settings-model-link]", count: 2)
      expect(page).to have_css("[data-module-settings-model-link='Demo::Order'][aria-current='page']")
      expect(page).to have_css("[data-module-settings-model='Demo::Order']")
      expect(page).to have_css("tr[data-list-filter-target='item']", count: 2)
      expect(page).to have_css("[data-controller='template-token-checkbox']", count: 2)
      expect(page).to have_text("2 columns · 1 association")
    end

    it "opens the requested model and returns toggles to it" do
      render_show(pane: :developer, models: models, selected_model: "Demo::Refund")

      expect(page).to have_css("[data-module-settings-model-link='Demo::Refund'][aria-current='page']")
      expect(page).to have_css("[data-module-settings-model='Demo::Refund'] tr[data-list-filter-target='item']", count: 1)
      toggle_form = page.find("input[name='extendable_model'][value='Demo::Refund']", visible: :all)
                        .find(:xpath, "ancestor::form")
      expect(toggle_form[:action]).to include("model=Demo%3A%3ARefund")
    end

    it "falls back to the first model for an unknown selection and keeps the default URL clean" do
      render_show(pane: :developer, models: models, selected_model: "Evil::Klass")

      expect(page).to have_css("[data-module-settings-model='Demo::Order']")
      expect(page.find("[data-module-settings-model-link='Demo::Order']")[:href]).not_to include("model=")
      expect(page.find("[data-module-settings-model-link='Demo::Refund']")[:href]).to include("model=Demo%3A%3ARefund")
    end

    it "shows the extendable attribute column only while the model is extendable" do
      render_show(pane: :developer, models: models)
      expect(page).not_to have_css("#extendable_attribute_demo_order_amount")
      expect(page).to have_text(I18n.t("maint_platform.module_settings.show.models.extendable_off_hint"))

      feature_module.set_extendable_model!("Demo::Order", true)
      render_show(pane: :developer, models: models)
      expect(page).to have_css("#extendable_attribute_demo_order_amount")
      expect(page).to have_css("[data-module-settings-model-link='Demo::Order'] .sr-only",
                               text: I18n.t("maint_platform.module_settings.show.models.extendable"))
    end
  end

  it "renders schema defaults only in Configuration as labeled rows without type badges" do
    feature_module.update!(configuration_schema: {
      "daily_cap" => { "type" => "integer", "default" => 100, "description" => "Max per day" },
      "enabled" => { "type" => "boolean", "default" => true, "description" => "Enabled by default" },
      "sender_name" => { "type" => "string", "default" => "Platform", "description" => "Default sender" },
      "language" => { "type" => "select", "default" => "auto", "options" => %w[auto en zh-CN], "description" => "Default language" }
    }.to_json)
    render_show

    expect(page).not_to have_text(I18n.t("maint_platform.module_settings.show.schema.title"))

    render_show(pane: :configuration)

    expect(page).to have_css("[data-module-settings-pane='configuration']")
    expect(page).to have_css("[data-module-settings-section='defaults']")
    expect(page).not_to have_css("[data-developer-reference]", visible: true)
    expect(page).to have_text(I18n.t("maint_platform.module_settings.show.schema.title"))
    expect(page).not_to have_css("table th", text: I18n.t("maint_platform.module_settings.show.schema.setting"))
    expect(page).not_to have_text("integer")
    expect(page).to have_text("daily_cap")
    expect(page).to have_field("config_defaults[daily_cap]", with: "100")
    expect(page).to have_css("label[for='config_defaults_daily_cap']", text: "daily_cap")
    expect(page).to have_css("label[for='config_defaults_enabled']", text: "enabled")
    expect(page).to have_css("label[for='config_defaults_sender_name']", text: "sender_name")
    expect(page).to have_css("label[for='config_defaults_language']", text: "language")
    expect(page).to have_field("config_defaults[enabled]", checked: true)
    expect(page).to have_field("config_defaults[sender_name]", with: "Platform")
    expect(page).to have_select("config_defaults[language]", selected: "auto", options: %w[auto en zh-CN])
    {
      "config_defaults_daily_cap" => "config_defaults_daily_cap_description",
      "config_defaults_enabled" => "config_defaults_enabled_description",
      "config_defaults_sender_name" => "config_defaults_sender_name_description",
      "config_defaults_language" => "config_defaults_language_description"
    }.each do |control_id, description_id|
      expect(page).to have_css("##{description_id}")
      expect(page).to have_css("##{control_id}[aria-describedby='#{description_id}']")
    end
    html = page.native.to_html
    expect(html).not_to include('data-module-settings-section="availability"')
  end

  it "localizes known schema field labels and select options instead of humanizing keys" do
    mod = find_or_create_feature_module!("ai_assistant", name: "AI Assistant")
    mod.update!(configuration_schema: FeatureModules::AiAssistant::Registration.configuration_schema.to_json)

    render_show(mod: mod, pane: :configuration)

    expect(page).to have_css("label[for='config_defaults_language']", text: "Language")
    expect(page).to have_select("config_defaults[language]",
                                selected: "Auto",
                                options: ["Auto", "English", "Simplified Chinese"])
  end

  it "localizes known schema select options in zh-CN" do
    mod = find_or_create_feature_module!("ai_assistant", name: "AI Assistant")
    mod.update!(configuration_schema: FeatureModules::AiAssistant::Registration.configuration_schema.to_json)

    I18n.with_locale("zh-CN") do
      render_show(mod: mod, pane: :configuration)

      expect(page).to have_css("label[for='config_defaults_language']", text: "语言")
      expect(page).to have_select("config_defaults[language]",
                                  options: ["自动", "英语", "简体中文"])
      expect(page).not_to have_text("Zh cn")
    end
  end

  it "treats an unknown pane as Overview" do
    render_show(pane: :operations)

    expect(page).to have_css("[data-module-settings-pane='overview']")
    expect(page).to have_css("[data-module-settings-section='availability']")
    expect(page).not_to have_css("[data-module-settings-pane='operations']")
  end

  it "renders Authentication signup only in Configuration" do
    auth = find_or_create_feature_module!("authentication", name: "User Authentication")

    render_show(mod: auth, customer_signup_enabled: true)
    expect(page).not_to have_text(I18n.t("maint_platform.module_settings.show.authentication.customer_signup"))

    render_show(mod: auth, customer_signup_enabled: true, pane: :configuration)
    expect(page).to have_css("[data-module-settings-section='authentication']")
    expect(page).to have_text(I18n.t("maint_platform.module_settings.show.authentication.customer_signup"))
    expect(page).to have_css(
      "button[role='switch'][aria-label='#{I18n.t("maint_platform.module_settings.show.authentication.customer_signup")}']"
    )
  end

  it "omits the Version detail when the module version is blank" do
    feature_module.update!(version: nil)
    render_show

    expect(page).to have_css("[data-module-settings-section='details']")
    expect(page).not_to have_css(
      "[data-module-settings-section='details'] dt",
      text: I18n.t("maint_platform.module_settings.show.version")
    )
  end

  it "renders an empty configuration state when the module has neither auth nor a schema" do
    feature_module.update!(configuration_schema: nil)
    render_show(pane: :configuration)

    expect(page).to have_css("[data-module-settings-pane='configuration']")
    expect(page).to have_text(I18n.t("maint_platform.module_settings.show.tabs.no_settings"))
    expect(page).not_to have_css("[data-module-settings-section='defaults']")
    expect(page).not_to have_css("[data-module-settings-section='authentication']")
  end
end
