# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::ThemePairing do
  it "pairs every skeleton with a known preset" do
    Websites::Skeletons::KEYS.each do |key|
      expect(Websites::ThemePresets.known?(described_class.for_skeleton(key))).to be(true), key
    end
  end

  it "pairs every catalog layout with a known preset" do
    Websites::Catalog.layouts.each do |layout|
      expect(Websites::ThemePresets.known?(described_class.for_layout(layout.key))).to be(true), layout.key
    end
  end

  it "inherits a family layout's pairing from its skeleton" do
    expect(described_class.for_layout("presence_home")).to eq(described_class.for_skeleton("presence"))
    expect(described_class.for_layout("article")).to eq("broadsheet")
  end

  it "falls back to the default preset for unknown keys" do
    expect(described_class.for_catalog("unknown_thing")).to eq(Websites::ThemePresets::DEFAULT_KEY)
  end
end
