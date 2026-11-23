# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Admin::StudioStatusStripComponent, type: :component do
  let(:website) { build_stubbed(:website, published: true) }

  it "renders live status, public path, and page count" do
    render_inline(
      described_class.new(website: website, customer_id: "81721200", page_count: 5)
    )

    expect(page).to have_css("[data-studio-status-strip='true']")
    expect(page).to have_text(I18n.t("website.admin.pages.index.site_live"))
    expect(page).to have_text(I18n.t("website.admin.pages.index.public_url"))
    expect(page).to have_link("/", href: "/")
    expect(page).to have_text(I18n.t("website.admin.pages.index.page_count", count: 5))
    expect(page).not_to have_link(I18n.t("website.admin.pages.index.open_settings"))
  end

  it "shows an unpublished path without a live link" do
    website.published = false
    render_inline(
      described_class.new(website: website, customer_id: "81721200", page_count: 1)
    )

    expect(page).to have_text(I18n.t("website.admin.pages.index.site_unpublished"))
    expect(page).to have_css("span.font-mono", text: "/")
    expect(page).not_to have_link("/")
    expect(page).to have_text(I18n.t("website.admin.pages.index.page_count", count: 1))
  end
end
