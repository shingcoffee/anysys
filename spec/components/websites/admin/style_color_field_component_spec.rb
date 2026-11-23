# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Admin::StyleColorFieldComponent, type: :component do
  let(:theme) { Websites::Theme.new("accent" => "forest") }

  def render_field(value: "", attribute: "color", tokens: Websites::SectionStyles::COLOR_TOKENS)
    render_inline(described_class.new(name: "website_style_s_headline_#{attribute}", attribute: attribute,
                                      label: "Color", value: value, tokens: tokens, theme: theme))
  end

  it "renders default, theme tokens in the theme's colors, the palette and a custom picker" do
    render_field

    expect(page).to have_css("legend", text: "Color")
    expect(page).to have_css("input#website_style_s_headline_color_default[value=''][checked][data-style-prop='color']")
    expect(page).to have_css("input#website_style_s_headline_color_accent[value='accent']")
    expect(page.find("label[for='website_style_s_headline_color_accent'] span[aria-hidden]")[:style]).to include(theme.color("accent"))
    Websites::SectionStyles::PALETTE.each do |hex|
      expect(page).to have_css("input[type='radio'][value='#{hex}']")
    end
    expect(page).to have_css("input[type='radio'][data-style-custom-radio][value='#000000']:not([checked])")
    expect(page).to have_css("input[type='color'][data-style-custom-input][data-action='input->website-builder#pickStyleColor']")
    expect(page).to have_css("input[data-action='change->website-builder#markDirty']", minimum: 2)
  end

  it "checks a stored token or palette color" do
    render_field(value: "muted")
    expect(page).to have_css("input[value='muted'][checked]")
    expect(page).not_to have_css("input[value=''][checked]")

    render_field(value: "#be123c")
    expect(page).to have_css("input[type='radio'][value='#be123c'][checked]")
    expect(page).not_to have_css("[data-style-custom-radio][checked]")
  end

  it "keeps an off-palette hex in the custom radio and paints the picker" do
    render_field(value: "#123abc")

    expect(page).to have_css("input[data-style-custom-radio][value='#123abc'][checked]")
    expect(page.find("input[type='color']")[:style]).to include("#123abc")
  end

  it "draws the accent background swatch with the theme's fill color" do
    render_field(attribute: "background", tokens: Websites::SectionStyles::BACKGROUND_TOKENS)

    swatch = page.find("label[for='website_style_s_headline_background_accent'] span[aria-hidden]")
    expect(swatch[:style]).to include(theme.color("accent_fill"))
  end
end
