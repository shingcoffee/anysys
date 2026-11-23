# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::ModuleSettings::ShellComponent, type: :component do
  let(:feature_module) do
    find_or_create_feature_module!("email", name: "Email")
      .tap { |mod| mod.update!(description: "Platform email delivery.", version: "2.1") }
  end

  it "renders the admin page identity, health badge, navigation, actions, and content" do
    with_request_url("/81721200/admin/maintenance/platform/module_settings/email/credentials") do
      render_inline(described_class.new(
        feature_module: feature_module,
        customer_id: 81_721_200,
        current: :providers,
        health: { label: "Configured", status: :success },
        actions: [{ label: "Add credential", path: "#", variant: :primary }]
      )) { "Workspace content" }
    end

    expect(page).to have_css("[data-module-settings-shell='true']")
    expect(page).not_to have_css("[data-module-settings-shell='true'].max-w-6xl")
    expect(page).not_to have_css("[data-module-settings-shell='true'].px-4")
    expect(page).to have_css("nav[aria-label='Breadcrumb']")
    expect(page).to have_css("h1.text-subtitle", text: feature_module.display_name)
    expect(page).to have_text(feature_module.description)
    expect(page).not_to have_text(I18n.t("maint_platform.module_settings.workspace.platform_scope"))
    expect(page).to have_css("[data-module-settings-health='success']", text: "Configured")
    expect(page).to have_css("[aria-current='page'][data-section-nav-tab='providers']",
                             text: I18n.t("maint_platform.module_settings.show.nav.providers"))
    expect(page).to have_link("Add credential")
    expect(page).to have_text("Workspace content")
  end
end
