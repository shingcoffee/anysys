# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::ThemePreviewSwatchComponent, type: :component do
  def render_swatch(tokens = {})
    render_inline(described_class.new(theme: tokens))
  end

  it "renders the mini hero with default light azure tokens" do
    render_swatch

    expect(page).to have_css("[data-theme-preview-swatch][data-appearance='light'][data-accent='azure']")
    expect(page).to have_css("[aria-hidden='true']")
    expect(page).to have_css("[data-website-theme-picker-target='preview']")
    expect(page).to have_css(".bg-sky-600")
    expect(page).to have_css(".bg-white")
    expect(page).to have_text(I18n.t("website.admin.settings.theme.preview.kicker"))
    expect(page).to have_text(I18n.t("website.admin.settings.theme.preview.headline"))
    expect(page).to have_text(I18n.t("website.admin.settings.theme.preview.body"))
    expect(page).to have_text(I18n.t("website.admin.settings.theme.preview.action"))
    expect(page).to have_text(I18n.t("website.admin.settings.theme.preview.brand"))
    expect(page).to have_text(I18n.t("website.admin.settings.theme.preview.nav_home"))
    expect(page).to have_css("[data-website-theme-picker-target='stage']")
  end

  it "uses the supplied site name in the mini chrome" do
    render_inline(described_class.new(theme: {}, site_name: "Harbor"))

    expect(page).to have_text("Harbor")
    expect(page).not_to have_text(I18n.t("website.admin.settings.theme.preview.brand"))
  end

  it "renders a dark page chip and ink accent" do
    render_swatch("appearance" => "dark", "accent" => "ink")

    expect(page).to have_css("[data-appearance='dark'][data-accent='ink']")
    expect(page).to have_css(".bg-neutral-950")
    expect(page).to have_css(".bg-white")
  end

  it "accepts a Theme instance" do
    render_inline(described_class.new(theme: Websites::Theme.new("accent" => "rose")))

    expect(page).to have_css("[data-accent='rose']")
    expect(page).to have_css(".bg-rose-600")
  end

  it "tightens padding for compact density" do
    render_swatch("density" => "compact", "type" => "serif")

    expect(page).to have_css("[data-density='compact'][data-type='serif']")
    expect(page).to have_css(".p-4")
  end

  it "scopes the theme's fonts, radii and neutral ramp to the preview root" do
    render_swatch("type" => "classic", "corners" => "sharp", "neutral" => "cool")

    preview = page.find("[data-theme-preview-swatch]")
    expect(preview[:style]).to include("--font-site-heading: 'Playfair Display'", "--radius-lg: 0.25rem", "--color-neutral-500:")
    expect(preview[:class].split).to include("font-site-body")
    expect(preview["data-corners"]).to eq("sharp")
    expect(preview["data-neutral"]).to eq("cool")
    expect(preview.find("[data-website-theme-picker-target='headline']")[:class]).to include("font-site-heading")
    expect(preview.find("[data-website-theme-picker-target='button']")[:class].split).to include("rounded-md")
  end
end
