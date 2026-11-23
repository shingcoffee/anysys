# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Activities::SaveLayout do
  let(:layout) { create(:website_layout) }
  let(:sections) { [{ "type" => "rich_text", "props" => { "heading" => "Original", "body" => "Copy" } }] }

  it "saves valid JSON sections and decorates only the validated structure" do
    result = described_class.call(layout: layout, params: { sections_json: sections.to_json })

    expect(result).to be_success
    expect(layout.reload.sections.first).to include("type" => "rich_text", "props" => sections.first["props"])
    expect(layout.sections.first.fetch("id")).to start_with("sec_")
  end

  ["{bad", "{}", "null", "[1]", "[]"].each do |json|
    it "rejects #{json.inspect} without replacing stored layout content" do
      original = layout.sections.deep_dup
      result = described_class.call(layout: layout, params: { sections_json: json })

      expect(result).not_to be_success
      expect(result.errors).to be_present
      expect(layout.reload.sections).to eq(original)
    end
  end

  [
    { "type" => "raw_html", "props" => {} },
    { "type" => "rich_text", "props" => "not an object" },
    { "type" => "rich_text", "props" => { "body" => { "html" => "data" } } },
    { "type" => "rich_text", "props" => { "unrecognized" => "value" } },
    { "type" => "card_grid", "props" => { "cards" => [{ "title" => "Card", "unrecognized" => "value" }] } },
    { "type" => "card_grid", "props" => { "cards" => "not a list" } },
    { "type" => "hero_cinematic", "props" => { "tone" => "neon" } },
    { "type" => "hero_split", "props" => { "visual_url" => "javascript:alert(1)" } }
  ].each do |section|
    it "rejects an invalid section before normalization: #{section.inspect}" do
      original = layout.sections.deep_dup
      result = described_class.call(layout: layout, params: { sections: [section] })

      expect(result).not_to be_success
      expect(layout.reload.sections).to eq(original)
    end
  end

  it "rejects duplicate section identities" do
    duplicated = Array.new(2) { sections.first.merge("id" => "same") }
    expect(described_class.call(layout: layout, params: { sections: duplicated })).not_to be_success
  end

  it "enforces nested array cardinality on direct model saves too" do
    layout.sections = [{ "type" => "proof_strip", "props" => { "items" => [{ "label" => "Only one", "value" => "1" }] } }]

    expect(layout.save).to be(false)
    expect(layout.errors[:sections]).to be_present
  end

  it "pins, clears and validates the paired theme" do
    expect(described_class.call(layout: layout, params: { theme_key: "glacier" })).to be_success
    expect(layout.reload.theme_preset_key).to eq("glacier")

    expect(described_class.call(layout: layout, params: { theme_key: "" })).to be_success
    expect(layout.reload.theme_key).to be_nil
    expect(layout.theme_preset_key).to eq(Websites::ThemePairing.for_layout(layout.key))

    expect(described_class.call(layout: layout, params: { theme_key: "neon" })).not_to be_success
    expect(layout.reload.theme_key).to be_nil
  end
end
