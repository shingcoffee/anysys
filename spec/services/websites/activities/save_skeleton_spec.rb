# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Activities::SaveSkeleton do
  let!(:layout) { create(:website_layout) }
  let(:home) do
    {
      "title" => "Home", "slug" => "", "home" => true, "nav_visible" => true,
      "layout_key" => layout.key,
      "sections" => [{ "type" => "rich_text", "props" => { "heading" => "Welcome", "body" => "Copy" } }]
    }
  end
  let(:inner) { home.deep_dup.merge("title" => "About", "slug" => "about", "home" => false) }
  let(:skeleton) { create(:website_skeleton, pages: [home]) }

  it "accepts indexed form pages, boolean flags and valid section JSON" do
    draft = home.except("sections").merge("home" => "1", "nav_visible" => "0", "sections_json" => home.fetch("sections").to_json)
    result = described_class.call(skeleton: skeleton, params: { pages: { "0" => draft, "1" => inner } })

    expect(result).to be_success
    expect(skeleton.reload.pages.map { |page| page["slug"] }).to eq(["", "about"])
    expect(skeleton.pages.first).to include("home" => true, "nav_visible" => false)
    expect(skeleton.pages.first.fetch("sections").first.fetch("id")).to start_with("sec_")
  end

  it "does not discard a blank-title page to conceal an invalid submitted structure" do
    result = described_class.call(skeleton: skeleton, params: { pages: [home, inner.merge("title" => " ")] })

    expect(result).not_to be_success
    expect(skeleton.reload.pages).to eq([home])
  end

  it "requires exactly one home" do
    [[inner], [home, home.merge("title" => "Second home")]].each do |pages|
      result = described_class.call(skeleton: skeleton, params: { pages: pages })
      expect(result).not_to be_success
      expect(result.errors.join).to include(I18n.t("website.errors.home_required"))
      expect(skeleton.reload.pages).to eq([home])
    end
  end

  it "rejects invalid, reserved, duplicate and non-string slugs" do
    ["About Us", "preview", "x" * 65, nil, 3].each do |slug|
      expect(described_class.call(skeleton: skeleton, params: { pages: [home, inner.merge("slug" => slug)] })).not_to be_success
      expect(skeleton.reload.pages).to eq([home])
    end
    expect(described_class.call(skeleton: skeleton, params: { pages: [home, inner, inner.merge("title" => "Duplicate")] })).not_to be_success
  end

  it "rejects an unknown or archived layout" do
    expect(described_class.call(skeleton: skeleton, params: { pages: [home.merge("layout_key" => "missing_layout")] })).not_to be_success
    skeleton.reload
    layout.update!(archived: true)
    expect(described_class.call(skeleton: skeleton, params: { pages: [home] })).not_to be_success
  end

  ["{bad", "null", "{}", "[1]", "[]"].each do |json|
    it "rejects malformed or unusable section JSON #{json.inspect}" do
      result = described_class.call(skeleton: skeleton, params: { pages: [home.merge("sections_json" => json)] })

      expect(result).not_to be_success
      expect(skeleton.reload.pages).to eq([home])
    end
  end

  it "rejects malformed pages JSON and objects that are not indexed form collections" do
    ["{bad", "null", "{}", { "page" => home }, ["not an object"]].each do |pages|
      expect(described_class.call(skeleton: skeleton, params: { pages: pages })).not_to be_success
      expect(skeleton.reload.pages).to eq([home])
    end
  end

  it "enforces section and prop structure on direct model saves" do
    skeleton.pages = [home.merge("sections" => [{ "type" => "rich_text", "props" => ["invalid"] }])]

    expect(skeleton.save).to be(false)
    expect(skeleton.errors[:pages]).to be_present
  end

  it "does not silently coerce an invalid home flag into a home page" do
    expect(described_class.call(skeleton: skeleton, params: { pages: [home.merge("home" => "garbage")] })).not_to be_success
  end

  it "pins, clears and validates the paired theme" do
    expect(described_class.call(skeleton: skeleton, params: { theme_key: "aurora" })).to be_success
    expect(skeleton.reload.theme_preset_key).to eq("aurora")

    expect(described_class.call(skeleton: skeleton, params: { theme_key: "" })).to be_success
    expect(skeleton.reload.theme_key).to be_nil
    expect(skeleton.theme_preset_key).to eq(Websites::ThemePairing.for_skeleton(skeleton.key))

    expect(described_class.call(skeleton: skeleton, params: { theme_key: "neon" })).not_to be_success
  end
end
