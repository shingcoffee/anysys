# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::HomeSiteLocalization do
  let(:en) { Websites::HomeSite.definition(locale: :en) }
  let(:zh) { Websites::HomeSite.definition(locale: :"zh-CN") }
  let(:localization) { described_class.new(locale: :"zh-CN") }

  def site(source = en, customer_id: Websites::HomeSite::CUSTOMER_ID)
    Website.new(source.except("pages").merge("id" => 123, "customer_id" => customer_id))
  end

  def page(source = en.fetch("pages").first)
    WebsitePage.new(source.merge("id" => 456, "website_id" => 123,
                                "customer_id" => Websites::HomeSite::CUSTOMER_ID))
  end

  it "translates every source section, page title and site text in both directions" do
    [[en, zh, :"zh-CN"], [zh, en, :en]].each do |base, target, locale|
      presenter = described_class.new(locale: locale)
      original_site = site(base)
      original_attributes = original_site.attributes.deep_dup
      copy = presenter.website(original_site)
      expect(copy).to be_readonly
      expect(copy.id).to eq(original_site.id)
      expect(copy.attributes.slice("name", "tagline", "seo", "footer")).to eq(target.slice("name", "tagline", "seo", "footer"))
      expect(original_site.attributes).to eq(original_attributes)

      base.fetch("pages").zip(target.fetch("pages")).each do |source_page, target_page|
        original = page(source_page)
        attributes = original.attributes.deep_dup
        translated = presenter.page(original)
        expect(translated.title).to eq(target_page.fetch("title"))
        expect(translated.sections).to eq(target_page.fetch("sections"))
        expect(translated).to be_readonly
        expect(translated.id).to eq(original.id)
        expect(translated.website_id).to eq(original.website_id)
        translated.sections.first["props"].clear
        expect(original.attributes).to eq(attributes)
      end
      copy.footer["columns"].clear
      expect(original_site.attributes).to eq(original_attributes)
    end
  end

  it "preserves owner edits, reordered sections and lists, legacy ids, additions and control values" do
    original = page
    original.title = "Owner title"
    original.published = false
    original.nav_visible = false
    original.position = 99
    original.sections = original.sections.reverse
    original.sections.each_with_index { |section, index| section["id"] = "sec_#{index}" }
    grid = original.sections.find { |section| section["type"] == "feature_grid" }
    grid["props"]["items"].reverse!
    grid["props"]["items"].first["body"] = "Owner's body\nSecond line"
    cards = original.sections.find { |section| section["type"] == "card_grid" }
    cards["props"]["cards"].reverse!
    cards["props"]["cards"].first["image_url"] = "https://cdn.example.com/owner-card.webp"
    cards["props"]["cards"].first["href"] = "Home"
    hero = original.sections.find { |section| section["type"] == "hero_centered" }
    hero["props"]["headline"] = "Owner headline\nOwner second line"
    hero["props"]["primary_href"] = en.dig("pages", 0, "title")
    hero["props"]["media_mode"] = "image"
    hero["props"]["image_url"] = "/81721200/site/media/owner--signed"
    added = { "id" => "owner", "type" => "rich_text", "props" => { "body" => "Owner section" } }
    original.sections << added
    attributes = original.attributes.deep_dup

    translated = localization.page(original)
    expect(translated.attributes.except("sections")).to eq(attributes.except("sections"))
    expect(translated.sections.pluck("id", "type")).to eq(original.sections.pluck("id", "type"))
    expect(translated.sections.last).to eq(added)
    translated_hero = translated.sections.find { |section| section["type"] == "hero_centered" }
    expect(translated_hero["props"]).to include("headline" => "Owner headline\nOwner second line", "primary_href" => "Home", "media_mode" => "image", "image_url" => "/81721200/site/media/owner--signed")
    translated_grid = translated.sections.find { |section| section["type"] == "feature_grid" }
    expected_grid = zh.fetch("pages").first.fetch("sections").reverse.find { |section| section["type"] == "feature_grid" }
    expect(translated_grid.dig("props", "heading")).to eq(expected_grid.dig("props", "heading"))
    expect(translated_grid.dig("props", "items").pluck("title")).to eq(expected_grid.dig("props", "items").reverse.pluck("title"))
    expect(translated_grid.dig("props", "items", 0, "body")).to eq("Owner's body\nSecond line")
    translated_cards = translated.sections.find { |section| section["type"] == "card_grid" }
    expected_cards = zh.fetch("pages").first.fetch("sections").find { |section| section["type"] == "card_grid" }
    expect(translated_cards.dig("props", "cards").pluck("title")).to eq(expected_cards.dig("props", "cards").reverse.pluck("title"))
    expect(translated_cards.dig("props", "cards", 0)).to include("image_url" => "https://cdn.example.com/owner-card.webp", "href" => "Home")
    expect(original.attributes).to eq(attributes)
    expect(described_class.new(locale: :en).page(translated).attributes).to eq(attributes)
  end

  it "round-trips multiline heroes, reordered draft outlines and plan feature lists without normalizing newlines" do
    en.fetch("pages").each do |source_page|
      original = page(source_page)
      original.sections.each do |section|
        section.dig("props", "items")&.reverse!
        section.dig("props", "tiers")&.reverse!
      end
      attributes = original.attributes.deep_dup
      translated = localization.page(original)
      target_sections = zh.fetch("pages").find { |item| item["slug"] == original.slug }.fetch("sections")
      translated.sections.zip(target_sections).each do |actual, target|
        expected = target.deep_dup
        expected.dig("props", "items")&.reverse!
        expected.dig("props", "tiers")&.reverse!
        expect(actual).to eq(expected)
      end
      expect(described_class.new(locale: :en).page(translated).attributes).to eq(attributes)
      expect(original.attributes).to eq(attributes)
    end
  end

  it "localizes polished source with legacy IDs while preserving moved About media and literal owner prose" do
    %w[pricing about contact].each do |slug|
      original = page(en.fetch("pages").find { |definition| definition["slug"] == slug })
      original.sections.each_with_index { |section, index| section["id"] = "sec_#{slug}_#{index}" }
      if slug == "about"
        original.sections.select { |section| section["type"] == "rich_text" }.last["props"]["body"] = "Owner's craft statement"
      end
      before = original.attributes.deep_dup
      translated = localization.page(original)
      expected = zh.fetch("pages").find { |definition| definition["slug"] == slug }.fetch("sections").deep_dup
      expected.each_with_index { |section, index| section["id"] = original.sections[index]["id"] }
      expected.select { |section| section["type"] == "rich_text" }.last["props"]["body"] = "Owner's craft statement" if slug == "about"
      expect(translated.sections).to eq(expected)
      expect(translated).to be_readonly
      expect(described_class.new(locale: :en).page(translated).attributes).to eq(before)
      expect(original.attributes).to eq(before)
    end
  end

  it "preserves edited metadata and footer routes while translating untouched copy" do
    original = site
    original.name = "Owner brand"
    original.seo["description"] = "Owner SEO"
    original.footer["columns"].reverse!
    original.footer["columns"].first["links"].first["url"] = "Home"
    copy = localization.website(original)
    expect(copy.name).to eq("Owner brand")
    expect(copy.seo).to include("description" => "Owner SEO", "title" => zh.dig("seo", "title"))
    expect(copy.footer["columns"].pluck("heading")).to eq(zh.dig("footer", "columns").reverse.pluck("heading"))
    expect(copy.footer.dig("columns", 0, "links", 0, "url")).to eq("Home")
  end

  it "leaves conflicting same-type translations literal rather than guessing" do
    source = en.deep_dup
    target = zh.deep_dup
    # Add a third genuine source grid to Home's two to exercise legacy-id ambiguity.
    [source, target].each do |definition|
      definition["pages"].first["sections"] << definition["pages"].find { |item| item["slug"] == "about" }.fetch("sections").find { |section| section["type"] == "feature_grid" }.deep_dup
    end
    grids = source["pages"].first["sections"].select { |section| section["type"] == "feature_grid" }
    grids.each { |section| section["props"]["heading"] = "Ambiguous heading" }
    allow(Websites::HomeSite).to receive(:definition).with(locale: :en).and_return(source)
    allow(Websites::HomeSite).to receive(:definition).with(locale: :"zh-CN").and_return(target)
    original = page(source["pages"].first)
    original.sections.each { |section| section["id"] = "sec_legacy_#{section['id']}" }
    translated = localization.page(original)
    expect(translated.sections.select { |section| section["type"] == "feature_grid" }.map { |section| section.dig("props", "heading") }).to eq(["Ambiguous heading"] * 3)
  end

  it "does not inspect definitions for another tenant or translate non-source slugs" do
    other_site = site(customer_id: 1234)
    other_page = page.tap { |record| record.customer_id = 1234 }
    expect(Websites::HomeSite).not_to receive(:definition)
    expect(localization.website(other_site)).to equal(other_site)
    expect(localization.page(other_page)).to equal(other_page)
  end

  it "leaves additional owner pages untouched" do
    original = page.tap { |record| record.slug = "campaign" }
    expect(localization.page(original)).to equal(original)
  end
end
