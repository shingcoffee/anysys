# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::SettingsLinkCardComponent, type: :component do
  it "renders the title, subtitle, and each link's title/description/href" do
    render_inline(described_class.new(
      title: "Email Configuration",
      subtitle: "Platform-wide email gateway credentials and SMTP settings.",
      links: [
        { path: "/81721200/admin/maintenance/platform/module_settings/email/credentials",
          title: "Credentials",
          description: "SMTP server settings, API keys, and delivery gateway configuration.",
          icon: :envelope }
      ]
    ))

    expect(page).to have_text("Email Configuration")
    expect(page).to have_text("Platform-wide email gateway credentials and SMTP settings.")
    expect(page).to have_link("Credentials", href: "/81721200/admin/maintenance/platform/module_settings/email/credentials")
    expect(page).to have_text("SMTP server settings, API keys, and delivery gateway configuration.")
    expect(page).to have_css("ul.grid")
  end

  it "renders multiple links in order and falls back to the default icon for an unknown key" do
    render_inline(described_class.new(
      title: "SMS Configuration",
      subtitle: "Platform-wide gateway credentials and shared message templates.",
      links: [
        { path: "/x/credentials", title: "Credentials", description: "Creds", icon: :envelope },
        { path: "/x/templates", title: "Templates", description: "Tmpls", icon: :unknown_icon }
      ]
    ))

    expect(page).to have_link("Credentials", href: "/x/credentials")
    expect(page).to have_link("Templates", href: "/x/templates")
  end

  it "renders the list layout when requested" do
    render_inline(described_class.new(
      title: "List",
      subtitle: "Rows",
      layout: :list,
      links: [{ path: "/x", title: "One", description: "Desc", icon: :envelope }]
    ))

    expect(page).to have_css("ul.divide-y")
    expect(page).to have_link("One", href: "/x")
  end

  it "omits the heading block when show_heading is false" do
    render_inline(described_class.new(
      title: "Hidden heading",
      subtitle: "Hidden subtitle",
      show_heading: false,
      links: [{ path: "/x", title: "One", description: "Desc", icon: :envelope }]
    ))

    expect(page).not_to have_text("Hidden heading")
    expect(page).not_to have_text("Hidden subtitle")
    expect(page).to have_link("One", href: "/x")
  end

  it "falls back to the grid layout for an unknown layout key" do
    render_inline(described_class.new(
      title: "Grid",
      subtitle: "Tiles",
      layout: :unknown,
      links: [{ path: "/x", title: "One", description: "Desc", icon: :envelope }]
    ))

    expect(page).to have_css("ul.grid")
  end
end
