# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Settings::CatalogComponent, type: :component do
  def node(**overrides)
    SidebarNode.new(**{ key: "settings.member", label: "Member", menu_item: :settings, path: "/1/admin/settings/member" }.merge(overrides))
  end

  def render_catalog(nodes)
    render_inline described_class.new(nodes: nodes)
  end

  it "renders grouped cards and skips Overview" do
    nodes = [
      node(key: "settings.overview", label: "Overview", path: "/1/admin/settings", description: "Hub"),
      node(key: "settings.section.organization", label: "Organization", path: nil, section_root: true, description: "Workspace settings"),
      node(key: "settings.member", label: "Member", path: "/1/admin/settings/member", description: "Member copy", icon: "M1 1"),
      node(key: "settings.section.billing", label: "Billing", path: nil, section_root: true),
      node(key: "settings.subscription", label: "Subscription Plan", path: "/1/admin/settings/billing/subscription", description: "Plans")
    ]
    render_catalog(nodes)
    expect(page).to have_text("Organization")
    expect(page).to have_text("Billing")
    expect(page).to have_link("Member", href: "/1/admin/settings/member")
    expect(page).to have_text("Member copy")
    expect(page).to have_text("Workspace settings")
    expect(page).to have_text("Plans")
    expect(page).to have_link("Subscription Plan", href: "/1/admin/settings/billing/subscription")
    expect(page).not_to have_link("Overview")
    expect(page).to have_css("section[aria-labelledby^='catalog-']", count: 2)
    expect(page).not_to have_css("input[type='search'], [data-controller='list-filter']")
  end

  it "links to each exact child destination instead of an arbitrary first child" do
    child = node(key: "settings.modules.authentication.sign_up", label: "Sign up",
                  path: "/1/admin/settings/modules/authentication/sign_up")
    password = node(key: "settings.authentication.forget_password", label: "Password reset",
                    path: "/1/admin/settings/modules/authentication/forget_password")
    parent = node(key: "settings.modules.authentication", label: "User Authentication",
                  path: nil, icon: "M9 12",
                  description: "Auth copy",
                   children: [child, password])
    render_catalog([
      node(key: "settings.section.modules", label: "Modules", path: nil, section_root: true),
      parent
    ])
    expect(page).not_to have_link("User Authentication")
    expect(page).to have_link("Sign up", href: child.path)
    expect(page).to have_link("Password reset", href: password.path)
    expect(page).to have_css("section[aria-labelledby='catalog-settings-section-modules'] a", count: 2)
  end

  it "renders the empty state when there are no navigable cards" do
    render_catalog([
      node(key: "settings.overview", label: "Overview", path: "/1/admin/settings")
    ])
    expect(page).to have_text("No settings yet")
    expect(page).to have_text("Settings appear here as you enable modules for this organization.")
  end

  it "retains unknown destinations in neutral link rows" do
    render_catalog([
      node(key: "settings.custom", label: "Custom", path: "/1/admin/settings/custom", icon: "M1 1")
    ])
    expect(page).not_to have_css(".bg-info-subtle, .bg-warning-subtle, .bg-success-subtle")
    expect(page).to have_link("Custom", href: "/1/admin/settings/custom")
  end

  it "uses shared typography and neutral rows for modules" do
    render_catalog([
      node(key: "settings.modules.email", label: "Email", path: "/1/admin/settings/modules/emails", icon: "M3 8")
    ])
    expect(page).not_to have_css(".bg-info-subtle")
    expect(page).to have_link("Email", href: "/1/admin/settings/modules/emails")
  end

  it "skips a node that has neither a path nor a child path" do
    orphan = node(key: "settings.orphan", label: "Orphan", path: nil, children: [])
    render_catalog([orphan])
    expect(page).to have_text("No settings yet")
    expect(page).not_to have_text("Orphan")
  end

  it "shares the Modules card styling and shows each setting once without right-side search" do
    render_catalog([
      node(key: "settings.section.email", label: "Email", path: nil, section_root: true,
           icon: Admin::Maintenance::Platform::ModuleSettingsHelper::MODULE_ICON_PATHS.fetch("email")),
      node(key: "settings.email.template_tokens", label: "Email personalization", path: "/1/admin/settings/modules/emails/template_tokens")
    ])
    expect(page).to have_css("section[aria-labelledby='catalog-settings-section-email'] .size-11.bg-info-subtle")
    expect(page).to have_css("a[href='/1/admin/settings/modules/emails/template_tokens']", count: 1)
    expect(page).not_to have_css("input[type='search'], [data-search-text], [data-list-filter-target]")
  end
end
