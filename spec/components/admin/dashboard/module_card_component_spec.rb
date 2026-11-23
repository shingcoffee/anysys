# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Dashboard::ModuleCardComponent, type: :component do
  def render_card(**overrides)
    render_inline(
      described_class.new(
        **{
          key: "authentication",
          name: "User Authentication",
          description: "Manage users and sign-in for this organization.",
          primary: OpenStruct.new(label: "Users", href: "/users"),
          secondaries: [
            OpenStruct.new(label: "Security Log", href: "/events"),
            OpenStruct.new(label: "Sign up", href: "/sign-up")
          ]
        }.merge(overrides)
      )
    )
  end

  it "renders the title, description, primary, and secondaries without linking the card" do
    render_card

    expect(page).to have_css("h3", text: "User Authentication")
    expect(page).to have_text("Manage users and sign-in for this organization.")
    expect(page).not_to have_link("User Authentication")
    expect(page).to have_link("Users", href: "/users")
    expect(page).to have_css("a[data-module-link='primary']", text: "Users")
    expect(page).to have_link("Security Log", href: "/events")
    expect(page).to have_link("Sign up", href: "/sign-up")
    expect(page).to have_css("a[data-module-link='secondary']", text: "Security Log")
    expect(page).to have_css("a[data-module-link='secondary']", count: 2)
    expect(page).not_to have_css("a.btn-primary, a.btn-secondary")
    expect(page).to have_css("article.h-full")
    expect(page).to have_css("span.size-9.bg-danger-subtle")
    expect(page).not_to have_css("details")
    expect(page).not_to have_css("[data-controller]")
    expect(page).not_to have_css("[data-action]")
  end

  it "omits the primary link when primary is nil and still renders secondaries" do
    render_card(primary: nil)

    expect(page).not_to have_link("Users")
    expect(page).to have_link("Security Log", href: "/events")
    expect(page).to have_css("a[data-module-link='secondary']")
    expect(page).not_to have_css("a[data-module-link='primary']")
  end

  it "omits the footer when there are no primary or secondary links" do
    render_card(primary: nil, secondaries: [])

    expect(page).to have_css("h3", text: "User Authentication")
    expect(page).not_to have_css("a")
    expect(page).not_to have_css(".border-t")
  end

  it "tints only the icon well for an unknown module key" do
    render_card(key: "custom_future", name: "Future", description: "On.", primary: nil, secondaries: [])

    expect(page).to have_css("span.size-9.bg-surface-active")
    expect(page).not_to have_css(".card.bg-surface-active")
  end

  context "rich variant" do
    def render_rich(**overrides)
      render_inline(
        described_class.new(
          **{
            key: "email",
            name: "Email",
            description: "Templates, lists, and send activity.",
            primary: Dashboard::Link.new(label: "Email Templates", href: "/t"),
            secondaries: [
              Dashboard::Link.new(label: "Send Activity", href: "/s"),
              Dashboard::Link.new(label: "Audience", href: "/a")
            ],
            links: [
              Dashboard::Link.new(label: "Email Templates", href: "/t"),
              Dashboard::Link.new(label: "Send Activity", href: "/s"),
              Dashboard::Link.new(label: "Audience", href: "/a")
            ],
             variant: :rich
          }.merge(overrides)
        )
      )
    end

    it "renders the module description and each record link once without duplicate footer actions" do
      render_rich

      expect(page).to have_css("h3", text: "Email")
      expect(page).to have_css("span.size-11.bg-info-subtle")
      expect(page).to have_link("Email Templates", href: "/t")
      expect(page).to have_link("Send Activity", href: "/s")
      expect(page).to have_link("Audience", href: "/a")
      expect(page).not_to have_link("Configure")
      expect(page).to have_text("Templates, lists, and send activity.")
      expect(page).to have_text(I18n.t("admin_modules.index.quick_links"))
      expect(page).not_to have_css("[data-search-text], [data-list-filter-target]")
      expect(page).not_to have_css("a.btn-primary, a.btn-secondary")
      expect(page).to have_css("a[href='/t']", count: 1)
    end

    it "falls back to primary/secondaries when no links are given" do
      render_rich(links: nil)

      expect(page).to have_link("Send Activity", href: "/s")
      expect(page).not_to have_link("Configure")
    end

    it "dedupes quick links by href" do
      render_rich(links: [
        Dashboard::Link.new(label: "Templates", href: "/t"),
        Dashboard::Link.new(label: "Templates again", href: "/t")
      ])

      expect(page.all("a[href='/t']").size).to eq(1)
    end

    it "leaves the guides in the Modules sidebar instead of duplicating them on hub cards" do
      render_rich

      expect(page).not_to have_css("details")
      expect(page).not_to have_text(I18n.t("admin_modules.index.howto.title"))
    end
  end
end
