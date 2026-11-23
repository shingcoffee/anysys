# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Dashboard::RecentListComponent, type: :component do
  def render_list(items:, kind: :pages)
    render_inline(
      described_class.new(
        title: I18n.t("admin_misc.dashboard.recents.pages_title"),
        view_all_href: "/pages",
        view_all_label: I18n.t("admin_misc.dashboard.recents.view_all"),
        items: items,
        empty_title: I18n.t("admin_misc.dashboard.recents.pages_empty_title"),
        empty_description: I18n.t("admin_misc.dashboard.recents.pages_empty_description"),
        empty_cta_label: I18n.t("admin_misc.pages.empty_action"),
        empty_cta_href: "/pages/new",
        kind: kind
      )
    )
  end

  it "renders rows with live and draft badges and a view-all header link" do
    render_list(
      items: [
        OpenStruct.new(name: "Contact form", href: "/pages/1", badge: "live"),
        OpenStruct.new(name: "Welcome page", href: "/pages/2", badge: "draft")
      ]
    )

    expect(page).to have_css("h2#dashboard-recents-pages-title", text: I18n.t("admin_misc.dashboard.recents.pages_title"))
    expect(page).to have_css("section[aria-labelledby='dashboard-recents-pages-title'][data-recent-kind='pages']")
    expect(page).to have_link(I18n.t("admin_misc.dashboard.recents.view_all"), href: "/pages")
    expect(page).to have_link("Contact form", href: "/pages/1")
    expect(page).to have_link("Welcome page", href: "/pages/2")
    expect(page).to have_css("ul > li", count: 2)
    expect(page).to have_css(".badge-success", text: I18n.t("common.status.live"))
    expect(page).to have_css(".badge-default", text: I18n.t("common.status.draft"))
    expect(page).to have_css("a.min-h-14 svg path[d='#{Dashboard::Home::METRIC_ICONS.fetch('pages')}']")
    expect(page).not_to have_text(I18n.t("admin_misc.dashboard.recents.pages_empty_title"))
    expect(page).not_to have_css("[data-controller]")
  end

  it "shows a relative updated label when the item carries updated_at" do
    travel_to(Time.zone.local(2026, 10, 16, 12, 0, 0)) do
      render_list(
        items: [Dashboard::RecentItem.new(name: "Contact form", href: "/pages/1", badge: "live", updated_at: 3.hours.ago)]
      )
    end

    expect(page).to have_text(
      I18n.t(
        "admin_misc.domains.directory.updated",
        time: I18n.t("chrome.admin_table.time_ago", time: "about 3 hours")
      )
    )
  end

  it "omits the updated label when the item has no updated_at" do
    render_list(items: [OpenStruct.new(name: "Contact form", href: "/pages/1", badge: "live")])

    expect(page).to have_link("Contact form", href: "/pages/1")
    expect(page).not_to have_text(/ago/)
  end

  it "renders a compact empty state and keeps view all in the header" do
    render_list(items: [])

    expect(page).to have_link(I18n.t("admin_misc.dashboard.recents.view_all"), href: "/pages")
    expect(page).to have_text(I18n.t("admin_misc.dashboard.recents.pages_empty_title"))
    expect(page).to have_text(I18n.t("admin_misc.dashboard.recents.pages_empty_description"))
    expect(page).to have_link(I18n.t("admin_misc.pages.empty_action"), href: "/pages/new")
    expect(page).to have_css(".px-5.py-10")
    expect(page).not_to have_css(".py-16")
    expect(page).not_to have_css("ul")
    expect(page).to have_css("a.btn-secondary", text: I18n.t("admin_misc.pages.empty_action"))
  end

  it "omits badges and uses the entity icon when the item has no live or draft state" do
    render_list(
      kind: :entities,
      items: [OpenStruct.new(name: "Members", href: "/entities/1", badge: nil)]
    )

    expect(page).to have_css("[data-recent-kind='entities']")
    expect(page).to have_link("Members", href: "/entities/1")
    expect(page).to have_css("svg path[d='#{Dashboard::Home::METRIC_ICONS.fetch('entities')}']")
    expect(page).not_to have_css(".badge")
  end
end
