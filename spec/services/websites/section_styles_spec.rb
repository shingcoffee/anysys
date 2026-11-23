# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::SectionStyles do
  it "lists section, text element, button, list and list-field targets" do
    keys = described_class.targets_for("hero_split").map { |target| target[:key] }
    pricing = described_class.target_kinds("pricing")

    expect(keys).to eq(%w[section eyebrow headline subhead buttons])
    expect(pricing).to include("tiers" => :items, "tiers.price" => :element, "heading" => :element)
    expect(pricing.keys).not_to include("tiers.button_href")
    expect(described_class.targets_for("nope")).to eq([])
  end

  it "validates values per target kind" do
    expect(described_class.valid_value?(:element, "color", "accent")).to be(true)
    expect(described_class.valid_value?(:element, "color", "#be123c")).to be(true)
    expect(described_class.valid_value?(:element, "color", "red; background:url(x)")).to be(false)
    expect(described_class.valid_value?(:section, "background", "band")).to be(false)
    expect(described_class.valid_value?(:items, "background", "band")).to be(true)
    expect(described_class.valid_value?(:element, "font", "playfair")).to be(true)
    expect(described_class.valid_value?(:element, "background", "#ffffff")).to be(false)
    expect(described_class.valid_value?(:buttons, "shape", "square")).to be(true)
  end

  it "sanitizes unknown targets, attributes and values away" do
    raw = { "headline" => { "color" => "accent", "size" => "huge", "nope" => "x" }, "ghost" => { "color" => "ink" }, "subhead" => "x" }

    expect(described_class.sanitize("hero_split", raw)).to eq("headline" => { "color" => "accent" })
  end

  it "collects override font families across sections" do
    sections = [
      { "type" => "hero_split", "props" => { "styles" => { "headline" => { "font" => "playfair" }, "section" => { "body_font" => "jost" } } } },
      { "type" => "faq", "props" => { "styles" => { "heading" => { "font" => "evil" } } } },
      { "type" => "faq", "props" => {} }
    ]

    expect(described_class.font_keys(sections)).to contain_exactly("playfair", "jost")
  end

  it "plugs a type-specific styles schema into PropSchema" do
    ok = { "headline" => "Hi", "styles" => { "headline" => { "color" => "accent" } } }
    unknown_target = { "styles" => { "ghost" => { "color" => "accent" } } }
    unknown_attribute = { "styles" => { "headline" => { "background" => "#ffffff" } } }

    expect(Websites::PropSchema.valid?("hero_split", ok)).to be(true)
    expect(Websites::PropSchema.valid?("hero_split", unknown_target)).to be(false)
    expect(Websites::PropSchema.valid?("hero_split", unknown_attribute)).to be(false)
  end
end
