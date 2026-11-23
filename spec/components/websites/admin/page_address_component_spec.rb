# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Admin::PageAddressComponent, type: :component do
  it "links to a live page in a new tab with a screen-reader hint" do
    render_inline(described_class.new(path: "/81721200/site/about", live: true))

    expect(page).to have_css("[data-page-address]", text: I18n.t("website.admin.pages.edit.address_label"))
    expect(page).to have_css("a[href='/81721200/site/about'][target='_blank'][rel='noopener']", text: "/81721200/site/about")
    expect(page).to have_css("a", text: I18n.t("website.admin.pages.edit.address_opens"))
    expect(page).not_to have_text(I18n.t("website.admin.pages.edit.address_hidden"))
  end

  it "shows the path as text while visitors cannot open it" do
    render_inline(described_class.new(path: "/81721200/site/about"))

    expect(page).not_to have_css("a")
    expect(page).to have_css("[data-page-address] .font-mono", text: "/81721200/site/about")
    expect(page).to have_text(I18n.t("website.admin.pages.edit.address_hidden"))
  end

  it "renders nothing without a path" do
    render_inline(described_class.new(path: nil, live: true))

    expect(page).not_to have_css("[data-page-address]")
  end
end
