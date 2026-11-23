# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::ModuleCatalogComponent, type: :component do
  let(:customer_id) { 81_721_200 }
  let(:email) { build_stubbed(:feature_module, key: "email", name: "Email", required: false) }
  let(:auth) { build_stubbed(:feature_module, key: "authentication", name: "User Authentication", required: true) }
  let(:captcha) { build_stubbed(:feature_module, key: "captcha", name: "Captcha", required: false) }
  let(:open_link) { Dashboard::Link.new(label: "Templates", href: "/81721200/admin/modules/emails/templates") }

  def render_catalog(modules: [email, auth, captcha], enabled_ids: [email.id, auth.id], **opts)
    render_inline(described_class.new(customer_id: customer_id, modules: modules, enabled_ids: enabled_ids, **opts))
  end

  it "summarises enabled, not-enabled and required counts" do
    render_catalog

    { enabled: 2, disabled: 1, required: 1 }.each do |key, value|
      expect(page).to have_css("[data-module-stat='#{key}'] dt", text: I18n.t("maint_core.modules.index.stats.#{key}"))
      expect(page).to have_css("[data-module-stat='#{key}'] dd", text: value.to_s)
    end
    expect(page).to have_text(I18n.t("maint_core.modules.index.enabled_count", enabled: 2, total: 3))
  end

  it "groups modules into navigation sections in navigation order" do
    render_catalog

    sections = page.all("section[data-module-section]").map { |s| s["data-module-section"] }
    expect(sections).to eq(%w[records communication growth])
    expect(page).to have_css("section[data-module-section='records'] h2", text: I18n.t("admin_modules.index.sections.records"))
    expect(page).to have_css("section[data-module-section='communication'] li[data-module-key='email']")
    expect(page).to have_css("section[data-module-section='growth'] li[data-module-key='captcha'][data-module-enabled='false']")
  end

  it "wires the client-side search and its no-match state" do
    render_catalog

    expect(page).to have_css("[data-controller='list-filter'] input[type='search'][data-list-filter-target='search']")
    expect(page).to have_css("li[data-list-filter-target='item']", count: 3)
    expect(page).to have_css("[data-list-filter-target='empty'].hidden", text: I18n.t("maint_core.modules.index.no_matches_title"))
  end

  it "passes open links only through to the matching module" do
    render_catalog(open_links: { "email" => open_link })

    expect(page).to have_link(I18n.t("maint_core.modules.index.open_module"), href: open_link.href, count: 1)
  end

  it "renders owner limit forms only for enabled modules with an owner assignment" do
    assignment = build_stubbed(:customer_feature_module, feature_module: email)
    allow(email.registration_class).to receive(:owner_managed_configuration_keys).and_return(%w[daily_send_cap])
    allow(email).to receive(:configuration_schema_json).and_return("daily_send_cap" => { "type" => "integer", "default" => 100 })

    render_catalog(owner_assignments: { email.id => assignment, captcha.id => assignment })

    expect(page).to have_css("form[data-module-owner-configuration='email']")
    expect(page).to have_css("form[data-module-owner-configuration]", count: 1)
  end

  it "renders an empty state when no modules are available" do
    render_catalog(modules: [], enabled_ids: [])

    expect(page).to have_text(I18n.t("maint_core.modules.index.empty"))
    expect(page).to have_text(I18n.t("maint_core.modules.index.empty_hint"))
    expect(page).not_to have_css("[data-controller='list-filter']")
  end
end
