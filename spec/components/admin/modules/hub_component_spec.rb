# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Modules::HubComponent, type: :component do
  let(:customer) { build_stubbed(:customer, id: 81_721_200, name: "Acme") }

  def render_hub(modules:)
    with_request_url("/#{customer.id}/admin/modules") do
      render_inline(described_class.new(modules: modules))
    end
  end

  def module_card(key:, name:, section:, links: [])
    Dashboard::ModuleCard.new(
      key: key,
      name: name,
      description: I18n.t("admin_misc.dashboard.modules.blurbs.authentication"),
      primary: links.first,
      secondaries: links.drop(1).first(2),
      links: links,
      section: section
    )
  end

  it "renders enabled-module cards with destinations" do
    render_hub(
      modules: [
        OpenStruct.new(
          key: "authentication",
          name: "User Authentication",
          description: I18n.t("admin_misc.dashboard.modules.blurbs.authentication"),
          primary: OpenStruct.new(label: "Users", href: "/#{customer.id}/admin/modules/authentication/users"),
          secondaries: [
            OpenStruct.new(label: "Security Log", href: "/#{customer.id}/admin/modules/authentication/events")
          ]
        )
      ]
    )

    expect(page).to have_css("h1", text: I18n.t("admin_modules.nav.modules"))
    expect(page).to have_text(I18n.t("admin_modules.index.description"))
    expect(page).to have_text(I18n.t("admin_misc.dashboard.modules.blurbs.authentication"))
    expect(page).to have_text(I18n.t("admin_modules.index.quick_links"))
    expect(page).not_to have_text("1 modules enabled")
    expect(page).not_to have_text("2 pages")
    expect(page).not_to have_css(".tabular-nums")
    expect(page).not_to have_link(href: "/#{customer.id}/admin/maintenance/modules")
    expect(page).to have_css("h3", text: "User Authentication")
    expect(page).to have_link("Users", href: "/#{customer.id}/admin/modules/authentication/users")
    expect(page).to have_css("section[aria-labelledby^='modules-section-'] a", count: 2)
    expect(page).not_to have_text(I18n.t("admin_modules.index.empty_title"))
    expect(page).not_to have_text(/flowchart/i)
    expect(page).not_to have_css("[data-controller='ai-assistant']")
  end

  it "renders an empty state without maintenance actions" do
    render_hub(modules: [])

    expect(page).to have_text(I18n.t("admin_modules.index.empty_title"))
    expect(page).to have_text(I18n.t("admin_modules.index.empty_body"))
    expect(page).not_to have_link(href: "/#{customer.id}/admin/maintenance/modules")
  end

  it "groups cards into labelled sections without a search in the right content" do
    render_hub(
      modules: [
        module_card(
          key: "authentication", name: "User Authentication", section: :records,
          links: [Dashboard::Link.new(label: "Users", href: "/u")]
        ),
        module_card(
          key: "email", name: "Email", section: :communication,
          links: [Dashboard::Link.new(label: "Templates", href: "/t")]
        )
      ]
    )

    expect(page).to have_css("h2", text: I18n.t("admin_modules.index.sections.records"))
    expect(page).to have_css("h2", text: I18n.t("admin_modules.index.sections.communication"))
    expect(page).to have_css("article", count: 2)
    expect(page).not_to have_css("input[type='search'], [data-controller='list-filter']")
    expect(page).to have_css("section[aria-labelledby^='modules-section-']", count: 2)
    expect(page).not_to have_link(I18n.t("admin_modules.index.configure"))
  end

  it "puts unmapped modules into the other section" do
    render_hub(
      modules: [module_card(key: "custom_x", name: "Custom X", section: nil, links: [])]
    )

    expect(page).to have_css("h2", text: I18n.t("admin_modules.index.sections.other"))
  end

  it "has no Manage Modules affordance" do
    render_hub(
      modules: [module_card(key: "email", name: "Email", section: :communication, links: [])]
    )

    expect(page).to have_css("h3", text: "Email")
    expect(page).not_to have_link(I18n.t("admin_modules.index.manage_modules"))
    expect(page).not_to have_text(I18n.t("admin_modules.index.manage_hint"))
  end

  it "keeps guides in the sidebar rather than repeating them on cards" do
    render_hub(modules: [
      module_card(key: "email", name: "Email", section: :communication, links: []),
      module_card(key: "captcha", name: "Captcha", section: :growth, links: [])
    ])

    expect(page).not_to have_css("section[aria-labelledby^='modules-section-'] details")
    expect(page).not_to have_link(href: "/#{customer.id}/admin/settings/modules/captcha")
  end

end
