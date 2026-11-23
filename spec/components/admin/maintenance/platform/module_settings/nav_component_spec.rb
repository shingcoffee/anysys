# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::ModuleSettings::NavComponent, type: :component do
  def render_nav(module_key:, current:, customer_id: 81_721_200)
    with_request_url("/#{customer_id}/admin/maintenance/platform/module_settings") do
      render_inline(described_class.new(module_key: module_key, current: current, customer_id: customer_id))
    end
  end

  def ensure_module(key, name: key.humanize, schema: nil)
    fm = find_or_create_feature_module!(key, name: name)
    fm.update!(configuration_schema: schema.to_json) if schema
    fm
  end

  it "renders the stable email sections with Providers current and a Configuration tab" do
    email = ensure_module("email", name: "Email", schema: { "daily_send_cap" => { "type" => "number", "default" => 100 } })
    if email.configuration_schema_json.blank?
      email.update!(configuration_schema: { "daily_send_cap" => { "type" => "number", "default" => 100 } }.to_json)
    end
    render_nav(module_key: "email", current: :providers)

    expect(page).to have_css("nav[data-module-settings-nav='true']")
    expect(page).to have_css("[data-section-nav-tab='overview']")
    expect(page).to have_link(I18n.t("maint_platform.module_settings.show.nav.overview"),
                              href: "/81721200/admin/maintenance/platform/module_settings/email")
    expect(page).to have_link(I18n.t("maint_platform.module_settings.show.nav.configuration"),
                              href: "/81721200/admin/maintenance/platform/module_settings/email/configuration")
    expect(page).to have_link(I18n.t("maint_platform.module_settings.show.nav.developer"),
                              href: "/81721200/admin/maintenance/platform/module_settings/email/developer")
    expect(page).to have_css("a[aria-current='page'][data-section-nav-tab='providers']",
                             text: I18n.t("maint_platform.module_settings.show.nav.providers"))
    expect(page).not_to have_css("[data-controller='tabs']")
    expect(page).to have_link(I18n.t("maint_platform.module_settings.show.nav.providers"),
                              href: "/81721200/admin/maintenance/platform/module_settings/email/credentials")
    expect(page).not_to have_link(I18n.t("maint_platform.module_settings.show.nav.resources"))
    expect(page).not_to have_link(I18n.t("maint_platform.module_settings.show.nav.operations"))
  end

  it "renders Overview, Configuration, and Developer for authentication" do
    ensure_module("authentication", name: "User Authentication")
    render_nav(module_key: "authentication", current: :overview)

    expect(page).to have_css("a[aria-current='page'][data-section-nav-tab='overview']",
                             text: I18n.t("maint_platform.module_settings.show.nav.overview"))
    expect(page).to have_link(I18n.t("maint_platform.module_settings.show.nav.configuration"),
                              href: "/81721200/admin/maintenance/platform/module_settings/authentication/configuration")
    expect(page).to have_link(I18n.t("maint_platform.module_settings.show.nav.developer"),
                              href: "/81721200/admin/maintenance/platform/module_settings/authentication/developer")
  end

  it "renders SMS Overview, Configuration, Providers, Resources, and Developer" do
    sms = ensure_module("sms", name: "SMS", schema: { "daily_cap" => { "type" => "integer", "default" => 10 } })
    if sms.configuration_schema_json.blank?
      sms.update!(configuration_schema: { "daily_cap" => { "type" => "integer", "default" => 10 } }.to_json)
    end
    render_nav(module_key: "sms", current: :resources)

    expect(page).to have_link(I18n.t("maint_platform.module_settings.show.nav.overview"))
    expect(page).to have_link(I18n.t("maint_platform.module_settings.show.nav.configuration"),
                              href: "/81721200/admin/maintenance/platform/module_settings/sms/configuration")
    expect(page).to have_link(I18n.t("maint_platform.module_settings.show.nav.providers"),
                              href: "/81721200/admin/maintenance/platform/module_settings/sms/credentials")
    expect(page).to have_css("a[aria-current='page'][data-section-nav-tab='resources']",
                             text: I18n.t("maint_platform.module_settings.show.nav.resources"))
    expect(page).to have_link(I18n.t("maint_platform.module_settings.show.nav.resources"),
                              href: "/81721200/admin/maintenance/platform/module_settings/sms/templates")
    expect(page).to have_link(I18n.t("maint_platform.module_settings.show.nav.developer"))
  end

  it "renders captcha Overview, Providers, Resources, and Developer" do
    ensure_module("captcha", name: "Captcha")
    render_nav(module_key: "captcha", current: :providers)

    expect(page).to have_link(I18n.t("maint_platform.module_settings.show.nav.overview"))
    expect(page).to have_css("a[aria-current='page'][data-section-nav-tab='providers']",
                             text: I18n.t("maint_platform.module_settings.show.nav.providers"))
    expect(page).to have_link(I18n.t("maint_platform.module_settings.show.nav.resources"),
                              href: "/81721200/admin/maintenance/platform/module_settings/captcha/pages")
    expect(page).to have_link(I18n.t("maint_platform.module_settings.show.nav.developer"))
    expect(page).not_to have_link(I18n.t("maint_platform.module_settings.show.nav.operations"))
  end

  it "renders payment Operations with the existing webhook route" do
    ensure_module("payment", name: "Payments")
    render_nav(module_key: "payment", current: :operations)

    expect(page).to have_css("a[aria-current='page'][data-section-nav-tab='operations']",
                             text: I18n.t("maint_platform.module_settings.show.nav.operations"))
    expect(page).to have_link(I18n.t("maint_platform.module_settings.show.nav.operations"),
                              href: "/81721200/admin/maintenance/platform/module_settings/payment/webhook_events")
    expect(page).to have_link(I18n.t("maint_platform.module_settings.show.nav.providers"),
                              href: "/81721200/admin/maintenance/platform/module_settings/payment/gateways")
    expect(page).not_to have_link(I18n.t("maint_platform.module_settings.show.nav.resources"))
  end

  it "renders website Skeletons as a module section tab" do
    ensure_module("website", name: "Website", schema: { "default_skeleton_key" => { "type" => "string", "default" => "presence" } })
    render_nav(module_key: "website", current: :skeletons)

    expect(page).to have_css("a[aria-current='page'][data-section-nav-tab='skeletons']",
                             text: I18n.t("maint_platform.module_settings.show.nav.skeletons"))
    expect(page).to have_link(I18n.t("maint_platform.module_settings.show.nav.skeletons"),
                              href: "/81721200/admin/maintenance/platform/module_settings/website/skeletons")
    expect(page).to have_link(I18n.t("maint_platform.module_settings.show.nav.layouts"),
                              href: "/81721200/admin/maintenance/platform/module_settings/website/layouts")
  end

  [
    ["email", :vendor, :providers],
    ["captcha", :vendor, :providers],
    ["ai_assistant", :providers, :providers],
    ["sms", :templates, :resources],
    ["payment", :webhooks, :operations],
    ["authentication", :advanced, :developer]
  ].each do |module_key, existing_current, stable_section|
    it "normalizes #{module_key} current #{existing_current} to #{stable_section}" do
      ensure_module(module_key)

      render_nav(module_key: module_key, current: existing_current)

      expect(page).to have_css("a[aria-current='page']", count: 1)
      expect(page).to have_css(
        "a[aria-current='page'][data-section-nav-tab='#{stable_section}']",
        text: I18n.t("maint_platform.module_settings.show.nav.#{stable_section}")
      )
    end
  end
end
