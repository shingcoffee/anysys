# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Theme do
  it "keeps azure light as the default" do
    theme = described_class.new

    expect(theme.appearance).to eq("light")
    expect(theme.accent).to eq("azure")
    expect(theme.corners).to eq("soft")
    expect(theme.neutral).to eq("neutral")
    expect(theme.filled_button_class).to include("bg-sky-600")
    expect(theme.cta_band_class).to include("bg-sky-950")
  end

  it "accepts violet and copper accents" do
    violet = described_class.new("accent" => "violet")
    copper = described_class.new("accent" => "copper", "appearance" => "dark")

    expect(violet.kicker_class).to include("text-violet-700")
    expect(copper.filled_button_class).to include("bg-orange-500")
    expect(violet.placeholder_class).to include("from-violet-50")
  end

  it "gives every accent a full class set in both appearances" do
    described_class::ACCENTS.each do |accent|
      %w[light dark].each do |appearance|
        theme = described_class.new("accent" => accent, "appearance" => appearance)

        expect([theme.kicker_class, theme.filled_button_class, theme.cta_band_class, theme.accent_soft_class]).to all(be_present)
        expect(theme.surface_class("accent")).to be_present
        expect(theme.color("accent_fill")).to be_present
      end
    end
  end

  it "maps catalog keys and prefixes onto their paired named themes" do
    presence = described_class.for_catalog("presence")
    home = described_class.for_catalog("presence_home")
    lumen = described_class.for_catalog("lumen")
    saas = described_class.for_catalog("saas_home")

    expect(presence.preset_key).to eq("linen")
    expect(presence.accent).to eq("gold")
    expect(presence.type).to eq("classic")
    expect(home.tokens).to eq(presence.tokens)
    expect(lumen.dark?).to be(true)
    expect(saas.preset_key).to eq("meridian")
    expect(saas.density).to eq("compact")
    expect(described_class.default_tokens?(Website::DEFAULT_THEME)).to be(true)
    expect(described_class.default_tokens?(presence.tokens)).to be(false)
  end

  it "honors a platform theme_key override on the catalog row" do
    layout = WebsiteLayout.find_by(key: "article") || create(:website_layout, key: "article")
    layout.update_columns(theme_key: "noir")

    expect(described_class.for_catalog("article").preset_key).to eq("noir")
  ensure
    layout&.update_columns(theme_key: nil)
  end

  it "resolves catalog themes from preloaded rows without querying" do
    row = WebsiteSkeleton.new(key: "presence", theme_key: "noir")

    expect(WebsiteSkeleton).not_to receive(:find_by)
    expect(WebsiteLayout).not_to receive(:find_by)
    expect(described_class.for_catalog("presence", records: { "presence" => row }).preset_key).to eq("noir")
    expect(described_class.for_catalog("presence", records: {}).preset_key).to eq("linen")
  end

  it "falls back to defaults for unknown tokens and presets" do
    theme = described_class.new("accent" => "neon", "corners" => "blob", "preset" => "nope")

    expect(theme.accent).to eq("azure")
    expect(theme.corners).to eq("soft")
    expect(theme.preset_key).to be_nil
    expect(theme.to_stored).not_to have_key("preset")
  end

  it "tracks drift from the starting preset" do
    linen = described_class.preset("linen")
    tweaked = described_class.new(linen.to_stored.merge("accent" => "rose"))

    expect(linen.customized?).to be(false)
    expect(tweaked.customized?).to be(true)
    expect(tweaked.to_stored).to include("preset" => "linen", "accent" => "rose")
  end

  it "resolves a page override before the site theme" do
    website = Website.new(theme: described_class.preset("meridian").to_stored)
    page = WebsitePage.new(theme_key: "gilded")

    expect(described_class.for_page(website: website, page: page).preset_key).to eq("gilded")
    expect(described_class.for_page(website: website, page: WebsitePage.new).preset_key).to eq("meridian")
  end

  it "exports font, radius and neutral CSS variables for the public layout" do
    classic = described_class.new("type" => "classic", "corners" => "sharp", "neutral" => "warm")
    sans = described_class.new

    expect(classic.root_style).to include("--font-site-heading: 'Playfair Display'")
    expect(classic.root_style).to include("--font-site-body: 'Source Sans 3'")
    expect(classic.root_style).to include("--radius-2xl: 0.375rem")
    expect(classic.root_style).to include("--color-neutral-500: oklch(55.3% 0.013 58.071)")
    expect(sans.root_style).to include("'Inter'")
    expect(sans.root_style).not_to include("--radius-")
    expect(sans.root_style).not_to include("--color-neutral-")
    expect(classic.font_keys).to contain_exactly("playfair", "source_sans")
  end

  it "uses the pairing's headline weight on the site heading family" do
    grotesk = described_class.new("type" => "grotesk")

    expect(grotesk.type_headline_class).to eq("font-site-heading font-bold tracking-[-0.045em]")
    expect(grotesk.type_body_class).to eq("font-site-body")
  end

  it "squares buttons only for sharp corners" do
    expect(described_class.new("corners" => "sharp").button_shape_class).to eq("rounded-md")
    expect(described_class.new("corners" => "round").button_shape_class).to eq("rounded-full")
  end

  it "resolves semantic colors for the appearance" do
    light = described_class.new("accent" => "teal")
    dark = light.with_appearance("dark")

    expect(light.color("ink")).to eq("var(--color-neutral-950)")
    expect(dark.color("ink")).to eq("#fff")
    expect(light.color("inverse")).to eq("#fff")
    expect(light.color("unknown")).to be_nil
    expect(dark.for_surface("contrast").dark?).to be(false)
  end
end
