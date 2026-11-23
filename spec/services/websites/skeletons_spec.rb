# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Skeletons do
  it "registers the starter keys" do
    expect(described_class.keys).to contain_exactly(
      "presence", "saas_landing", "cinematic", "editorial", "studio", "product",
      "ledger", "signal", "atelier", "campus", "gazette",
      "lumen", "monograph", "terrain", "supper", "clinic", "folio", "voyage", "kinetic",
      "voltage", "wellspring", "summit", "manor", "bloom", "roast", "atrium",
      "canvas", "harbor", "calm", "marque", "tempo", "quarterly"
    )
  end

  it "files every skeleton under a known category" do
    expect(described_class.keys.map { |key| described_class.category_for(key) }).to all(be_in(described_class::CATEGORIES))
    expect(described_class.categories).to include("wellness", "hospitality")
  end

  it "seeds every page section as a valid, known section" do
    described_class.keys.each do |key|
      described_class.seed_pages_for(key).each do |page|
        page["sections"].each do |section|
          form = Websites::Contracts::Section.new(OpenStruct.new)
          expect(form.validate(section.merge("id" => "sec_1"))).to be(true), "#{key}/#{page["slug"]} #{section["type"]}: #{form.errors.full_messages}"
        end
      end
    end
  end

  it "links internal hrefs only to pages of the same skeleton" do
    collect_hrefs = lambda do |node|
      case node
      when Hash
        node.flat_map do |key, value|
          Websites::SectionKit::HREF_KEYS.include?(key.to_s) && value.is_a?(String) ? [value] : collect_hrefs.call(value)
        end
      when Array then node.flat_map { |value| collect_hrefs.call(value) }
      else []
      end
    end

    described_class.keys.each do |key|
      pages = described_class.seed_pages_for(key)
      slugs = pages.map { |page| page["slug"].to_s }
      links = collect_hrefs.call(pages.map { |page| page["sections"] }).grep(Websites::Href::SLUG)
      expect(links - slugs).to be_empty, "#{key} links to missing pages: #{(links - slugs).uniq}"
    end
  end

  it "has English and Chinese names for every skeleton and layout key" do
    layout_keys = described_class.keys.flat_map { |key| described_class.seed_pages_for(key).map { |page| page["layout_key"] } }

    %i[en zh-CN].each do |locale|
      described_class.keys.each { |key| expect(I18n.exists?("website.skeletons.#{key}.name", locale)).to be(true), "#{locale} #{key}" }
      layout_keys.each { |key| expect(I18n.exists?("website.layouts.#{key}.name", locale)).to be(true), "#{locale} #{key}" }
    end
  end

  it "seeds presence home copy from the locked design" do
    home = described_class.pages_for("presence").find { |page| page["home"] }
    hero = home["sections"].find { |section| section["type"] == "hero_split" }
    expect(hero["props"]).to include(
      "eyebrow" => "Introduction",
      "headline" => "A place for the work that lasts",
      "subhead" => "We design programs, spaces, and stories for people who care about craft.",
      "primary_label" => "See our work",
      "primary_href" => "services",
      "secondary_label" => "About us",
      "secondary_href" => "about"
    )
  end

  it "fills blank photography when decorating sections" do
    sections = described_class.decorate_sections([
      { "type" => "hero_split", "props" => { "headline" => "Hello" } }
    ])

    expect(sections.first["id"]).to start_with("sec_")
    expect(sections.first["props"]["headline"]).to eq("Hello")
    expect(sections.first["props"]["visual_url"]).to start_with("https://images.unsplash.com/")
  end

  it "gives every skeleton exactly one home page" do
    described_class.keys.each do |key|
      homes = described_class.pages_for(key).select { |page| page["home"] }
      expect(homes.size).to eq(1), "#{key} should have exactly one home"
    end
  end

  describe ".home_sections" do
    it "returns the home page's decorated sections, optionally limited" do
      home = described_class.pages_for("presence").find { |page| page["home"] }
      sections = described_class.home_sections("presence")

      expect(sections.map { |section| section["type"] }).to eq(home["sections"].map { |section| section["type"] })
      expect(sections).to all(include("id"))
      expect(described_class.home_sections("presence", limit: 2).size).to eq(2)
    end

    it "reads supplied page specs with any key style and falls back to the first page" do
      pages = [
        { title: "About", sections: [{ type: "quote", props: { quote: "Hi" } }] },
        { "title" => "Home", "home" => "true", "sections" => [{ "type" => "hero_split", "props" => {} }] }
      ]

      expect(described_class.home_sections("presence", pages).map { |section| section["type"] }).to eq(%w[hero_split])
      expect(described_class.home_sections("presence", pages.first(1)).map { |section| section["type"] }).to eq(%w[quote])
      expect(described_class.home_sections("presence", ["not a page"])).to eq([])
    end

    it "is empty for an unknown starter" do
      expect(described_class.home_sections("nope")).to eq([])
    end
  end
end
