# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Admin::ThemeOptionComponent, type: :component do
  def render_option(token, value, **opts)
    render_inline(described_class.new(token: token, value: value, **opts))
  end

  it "keeps the radio a website-theme-picker token behind the visual" do
    render_option("appearance", "dark", checked: true, described_by: "website-theme-error")

    expect(page).to have_css(
      "label[for='website_theme_appearance_dark'] input#website_theme_appearance_dark.peer.sr-only[type='radio'][name='website[theme][appearance]'][value='dark'][checked]" \
      "[data-token='appearance'][data-website-theme-picker-target='token'][aria-describedby='website-theme-error']"
    )
    expect(page).to have_css("label .bg-neutral-950")
    expect(page).to have_text(I18n.t("website.admin.settings.theme.dark"))
  end

  it "draws accents as named swatches" do
    render_option("accent", "forest")

    expect(page).to have_css("label.group\\/swatch input:not([checked]) + span.bg-emerald-600")
    expect(page).to have_text(I18n.t("website.admin.settings.theme.forest"))
    expect(page).not_to have_css("input[aria-describedby]")
  end

  it "previews each font style as a specimen in that face" do
    render_option("type", "serif")

    specimen = page.find("span", exact_text: I18n.t("website.admin.settings.theme.specimen"))
    expect(specimen[:style]).to include("--font-site-heading: 'Newsreader'")
    expect(specimen[:class]).to include(Websites::Theme.new("type" => "serif").type_headline_class)
  end

  it "labels neutral tones apart from the tone token and sketches corners" do
    render_option("neutral", "warm")
    expect(page).to have_text(I18n.t("website.admin.settings.theme.neutrals.warm"))
    expect(page).to have_css("span.bg-stone-300")

    render_option("corners", "sharp")
    expect(page).to have_css("span.rounded-\\[2px\\]")
  end

  it "shows tighter bars for compact spacing than for spacious spacing" do
    render_option("density", "compact")
    expect(page).to have_css("span.gap-1 > span.bg-border", count: 4)

    render_option("density", "spacious")
    expect(page).to have_css("span.gap-2\\.5 > span.bg-border", count: 2)
  end
end
