# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Admin::CatalogThemeDotsComponent, type: :component do
  it "renders appearance and accent swatches for a light gold theme" do
    theme = Websites::Theme.for_catalog("presence")
    render_inline(described_class.new(theme: theme))

    expect(page).to have_css("[data-catalog-theme-dots='true']")
    expect(page).to have_css(".sr-only", text: /#{I18n.t("website.admin.settings.theme.light")}/)
    expect(page).to have_css(".sr-only", text: /#{I18n.t("website.admin.settings.theme.gold")}/)
    expect(page).to have_css("[class*='bg-amber-500']")
  end

  it "renders a dark appearance swatch" do
    theme = Websites::Theme.for_catalog("lumen")
    render_inline(described_class.new(theme: theme))

    expect(page).to have_css("[class*='bg-neutral-900']")
    expect(page).to have_text(I18n.t("website.admin.settings.theme.dark"))
  end
end
