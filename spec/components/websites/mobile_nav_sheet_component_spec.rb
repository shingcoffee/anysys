# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::MobileNavSheetComponent, type: :component do
  it "keeps the mobile sheet focused on page navigation with no duplicate language control" do
    I18n.with_locale(:"zh-CN") do
      render_inline(described_class.new(
        website: website_record,
        pages: [website_page_record(title: "About", slug: "about", home: false)],
        current_slug: "about",
        theme: website_theme,
        open_label: I18n.t("website.public.nav.open"),
        close_label: I18n.t("website.public.nav.close")
      ))
    end

    expect(page).to have_css("[role='dialog'][aria-modal='true'][aria-labelledby='website-nav-title']")
    expect(page).to have_css("a[aria-current='page'][href='/12345678/about?locale=zh-CN']", text: "About")
    expect(page).to have_css("button[data-action='click->website-nav#close']")
    expect(page).to have_no_css("[role='group'], [data-controller='user-menu'], form[action='/locale']")
  end
end
