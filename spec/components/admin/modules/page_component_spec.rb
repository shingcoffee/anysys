# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Modules::PageComponent, type: :component do
  it "renders the title with a tinted module icon" do
    render_inline(
      described_class.new(
        module_key: "authentication",
        breadcrumbs: [{ label: "Modules" }],
        title: "Users",
        description: "Manage users"
      )
    ) { "body" }

    expect(page).to have_css("h1", text: "Users")
    expect(page).to have_text("Manage users")
    expect(page).to have_css("span.size-10.bg-danger-subtle")
    expect(page).to have_text("body")
  end

  it "uses the default cube well when no module key is given" do
    render_inline(
      described_class.new(
        breadcrumbs: [{ label: "Modules" }],
        title: "Modules"
      )
    )

    expect(page).to have_css("span.size-10.bg-surface-active")
  end

  it "lets a record page replace the module tile with its own icon" do
    render_inline(described_class.new(module_key: "authentication", breadcrumbs: [{ label: "Modules" }], title: "Ada",
                                      icon_path: "M1 1h2", icon_class: "bg-indigo-500 text-white"))

    expect(page).to have_css("span.size-10.bg-indigo-500.text-white path[d='M1 1h2']")
    expect(page).not_to have_css("span.size-10.bg-danger-subtle")
  end

  it "keeps the module tint when only a custom icon is given" do
    render_inline(described_class.new(module_key: "authentication", breadcrumbs: [{ label: "Modules" }], title: "Ada",
                                      icon_path: "M1 1h2"))

    expect(page).to have_css("span.size-10.bg-danger-subtle path[d='M1 1h2']")
  end

  it "links the Modules crumb back to the hub on nested pages" do
    with_request_url("/81721200/admin/modules/authentication/users") do
      render_inline(
        described_class.new(
          module_key: "authentication",
          breadcrumbs: [
            { label: I18n.t("admin_modules.nav.modules") },
            { label: "Users" }
          ],
          title: "Users"
        )
      )
    end

    expect(page).to have_link(I18n.t("admin_modules.nav.modules"), href: "/81721200/admin/modules")
  end

  it "does not link the Modules crumb on the hub itself" do
    with_request_url("/81721200/admin/modules") do
      render_inline(
        described_class.new(
          breadcrumbs: [{ label: I18n.t("admin_modules.nav.modules") }],
          title: I18n.t("admin_modules.nav.modules")
        )
      )
    end

    expect(page).to have_css("h1", text: I18n.t("admin_modules.nav.modules"))
    expect(page).not_to have_link(I18n.t("admin_modules.nav.modules"), href: "/81721200/admin/modules")
  end

  it "prepends a hub crumb when the first crumb is not Modules" do
    with_request_url("/81721200/admin/modules/authentication/users") do
      render_inline(
        described_class.new(
          module_key: "authentication",
          breadcrumbs: [
            { label: "Entries" },
            { label: "Widgets" }
          ],
          title: "Widgets"
        )
      )
    end

    expect(page).to have_link(I18n.t("admin_modules.nav.modules"), href: "/81721200/admin/modules")
    expect(page).to have_text("Entries")
  end

  it "keeps nested module headers focused on record actions" do
    with_request_url("/81721200/admin/modules/authentication/users") do
      render_inline(
        described_class.new(
          module_key: "authentication",
          breadcrumbs: [{ label: "Modules" }],
          title: "Users",
          actions: [{ label: "New user", path: "/81721200/admin/modules/authentication/users/new" }]
        )
      )
    end

    expect(page).to have_link("New user", href: "/81721200/admin/modules/authentication/users/new")
    expect(page).not_to have_link(I18n.t("admin_modules.index.configure"))
    expect(page).not_to have_css('a[href*="/admin/settings/modules/"]')
  end

  it "passes wrapping title/actions and status badges through to the shared page shell" do
    render_inline(described_class.new(
      module_key: "authentication", breadcrumbs: [{ label: "Modules" }], title: "A long account name",
      wrap_title: true, wrap_actions: true,
      badges: [{ label: I18n.t("common.status.active"), variant: :success }],
      actions: [{ label: I18n.t("common.actions.edit"), path: "/edit", class: "min-h-11 w-full sm:w-auto" }]
    ))

    expect(page.find("h1")[:class]).to include("whitespace-normal", "[overflow-wrap:anywhere]")
    expect(page.find("h1")[:class]).not_to include("truncate")
    expect(page).to have_css("h1 + .badge-success.text-xs", text: I18n.t("common.status.active"))
    expect(page.find("a[href='/edit']").find(:xpath, "..")[:class]).to include("flex-col", "sm:flex-wrap", "lg:w-auto")
  end

  it "retains the compact default title and actions for other module pages" do
    render_inline(described_class.new(breadcrumbs: [{ label: "Modules" }], title: "Users",
      actions: [{ label: I18n.t("common.actions.edit"), path: "/edit" }]))

    expect(page.find("h1")[:class]).to include("truncate")
    expect(page.find("a[href='/edit']").find(:xpath, "..")[:class]).to include("sm:flex-nowrap")
  end
end
