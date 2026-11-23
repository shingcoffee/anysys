# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::ModuleCatalogComponent, type: :component do
  def fake_module(display_name:, description:, key:, id:, active:, required:, mandatory: false, schema: {})
    dbl = instance_double(
      FeatureModules::Module,
      display_name: display_name,
      description: description,
      registration_class: key == "sms" ? FeatureModules::Sms::Registration : FeatureModules::Module::NullRegistration,
      key: key,
      id: id,
      active?: active,
      required?: required,
      mandatory?: mandatory,
      configuration_schema_json: schema
    )
    allow(dbl).to receive(:to_param).and_return(id.to_s)
    dbl
  end

  let(:sms) do
    fake_module(display_name: "SMS", description: "Send texts", key: "sms",
                id: 11, active: true, required: false)
  end
  let(:captcha) do
    fake_module(display_name: "Captcha", description: "Bot check", key: "captcha",
                id: 12, active: false, required: true)
  end

  def render_catalog(mods)
    with_request_url("/81721200/admin/maintenance/platform/module_settings") do
      render_inline(described_class.new(modules: mods, customer_id: 81721200))
    end
  end

  it "renders searchable module cards with status, configuration context, and a full-card workspace link" do
    render_catalog([sms, captcha])

    expect(page).to have_css("[data-module-card]", count: 2)
    expect(page).to have_css("p.sr-only", text: I18n.t("maint_platform.module_settings.index.stats_summary",
                                                       total: 2, active: 1, required: 1))
    expect(page).not_to have_text(I18n.t("maint_platform.module_settings.index.stats.total"))
    expect(page).to have_text(I18n.t("maint_platform.module_settings.index.search_placeholder"))
    expect(page).to have_button(I18n.t("maint_platform.module_settings.index.filter_all"))
    expect(page).to have_css("[data-module-card] a[href='/81721200/admin/maintenance/platform/module_settings/11']")
    expect(page).to have_css("[data-module-card] a[href='/81721200/admin/maintenance/platform/module_settings/12']")
    expect(page).not_to have_text(I18n.t("maint_platform.module_settings.index.configure"))
    expect(page).to have_text("sms")
    expect(page).to have_text(I18n.t("maint_platform.module_settings.workspace.status.required"))
    expect(page).to have_text(I18n.t("maint_platform.module_settings.index.configuration_context.provider"))
    expect(page).not_to have_css("[data-configuration-health]")
    expect(page).not_to have_text(I18n.t("maint_platform.module_settings.index.health.unknown"))
    expect(page).to have_css("[data-controller='module-settings-catalog']")
  end

  it "renders the empty state without the catalog controller when there are no modules" do
    render_catalog([])

    expect(page).to have_text(I18n.t("maint_platform.module_settings.index.empty"))
    expect(page).to have_text(I18n.t("maint_platform.module_settings.index.empty_description"))
    expect(page).to have_css("p.sr-only", text: I18n.t("maint_platform.module_settings.index.stats_summary",
                                                       total: 0, active: 0, required: 0))
    expect(page).not_to have_css("[data-controller='module-settings-catalog']")
  end

  it "reads the SMS registration description at render time instead of a stored boot-locale value" do
    %w[en zh-CN en].each do |locale|
      I18n.with_locale(locale) do
        render_catalog([sms])
        expected = I18n.t("sms_campaign_http.registration.description")
        expect(page).to have_text(expected)
        expect(page.find("[data-module-card]")["data-description"]).to eq(expected)
        expect(rendered_content).not_to include("Send texts")
      end
    end
    expect(sms.description).to eq("Send texts")
  end

  it "distinguishes provider assignment, platform defaults, and no additional configuration" do
    defaults = fake_module(
      display_name: "Defaults",
      description: "Schema defaults",
      key: "custom_defaults",
      id: 13,
      active: true,
      required: false,
      schema: { "limit" => { "type" => "integer" } }
    )
    none = fake_module(
      display_name: "Simple",
      description: "No settings",
      key: "simple",
      id: 14,
      active: true,
      required: false,
      schema: nil
    )

    render_catalog([sms, defaults, none])

    expect(page).to have_text(I18n.t("maint_platform.module_settings.index.configuration_context.provider"))
    expect(page).to have_text(I18n.t("maint_platform.module_settings.index.configuration_context.defaults"))
    expect(page).to have_text(I18n.t("maint_platform.module_settings.index.configuration_context.none"))
  end
end
