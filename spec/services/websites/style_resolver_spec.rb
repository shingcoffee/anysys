# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::StyleResolver do
  let(:linen) { Websites::ThemePresets.theme("linen") }

  def resolver(styles, type: "hero_split", with_theme: linen)
    described_class.new(styles, theme: with_theme, type: type)
  end

  it "renders element overrides as inline declarations" do
    css = resolver({ "headline" => { "color" => "accent", "font" => "jost", "size" => "xl", "weight" => "bold",
                                     "italic" => "italic", "align" => "center" } }).element_css("headline")

    expect(css).to include("color: var(--color-amber-800);", "font-family: 'Jost'", "--text-site-5xl: calc(3.25rem * 1.25);",
                           "font-weight: 700;", "font-style: italic;", "text-align: center; margin-inline: auto;")
  end

  it "ignores invalid or unknown values" do
    styles = { "headline" => { "color" => "red;}" }, "ghost" => { "color" => "accent" } }

    expect(resolver(styles).element_css("headline")).to be_nil
    expect(resolver(styles).element_css("ghost")).to be_nil
    expect(resolver(nil).section_css).to be_nil
  end

  it "applies section background, fonts and scale" do
    css = resolver({ "section" => { "background" => "#0f172a", "heading_font" => "playfair", "body_font" => "jost", "scale" => "sm" } }).section_css

    expect(css).to include("background-color: #0f172a;", "--font-site-heading: 'Playfair Display'", "--font-site-body: 'Jost'",
                           "--text-site-base: calc(1rem * 0.875);")
  end

  it "flips section appearance by background luminance" do
    expect(described_class.section_appearance("section" => { "background" => "#0f172a" })).to eq("dark")
    expect(described_class.section_appearance("section" => { "background" => "#f5efe6" })).to eq("light")
    expect(described_class.section_appearance({})).to be_nil
  end

  it "fills list items with readable text and a frame when unframed" do
    hex = resolver({ "items" => { "background" => "#1e3a8a" } }, type: "feature_grid")
    token = resolver({ "items" => { "background" => "accent" } }, type: "feature_grid")
    soft = resolver({ "items" => { "background" => "accent_soft" } }, type: "feature_grid")
    text_only = resolver({ "items" => { "text" => "muted" } }, type: "feature_grid")

    expect(hex.item_css("items")).to eq("background-color: #1e3a8a; color: #fff;")
    expect(hex.item_class("items")).to include(described_class::ITEM_TEXT_INHERIT, described_class::ITEM_FRAME)
    expect(hex.item_class("items", framed: true)).not_to include(described_class::ITEM_FRAME)
    expect(token.item_css("items")).to eq("background-color: var(--color-amber-700); color: #fff;")
    expect(soft.item_css("items")).to eq("background-color: var(--color-amber-50);")
    expect(soft.item_class("items", framed: true)).to be_nil
    expect(text_only.item_css("items")).to eq("color: var(--color-neutral-500);")
  end

  it "shapes both buttons and fills only the primary one" do
    styles = { "buttons" => { "shape" => "square", "fill" => "#fdf6e3" } }

    expect(resolver(styles).button_css(:primary)).to eq("border-radius: 0; background-color: #fdf6e3; color: #0a0a0a;")
    expect(resolver(styles).button_css(:secondary)).to eq("border-radius: 0;")
    expect(resolver({ "buttons" => { "fill" => "ink" } }).button_css(:primary)).to include("color: #fff;")
    expect(resolver({ "buttons" => { "fill" => "inverse", "text" => "accent" } }).button_css(:primary))
      .to eq("background-color: #fff; color: var(--color-amber-800);")
  end
end
