# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Media do
  it "fills blank hero photography with an https Unsplash URL" do
    props = described_class.fill("hero_split", "headline" => "Hello")

    expect(props["headline"]).to eq("Hello")
    expect(props["visual_url"]).to start_with("https://images.unsplash.com/")
    expect(Websites::Href.media?(props["visual_url"])).to be(true)
  end

  it "does not overwrite an authored image URL" do
    kept = "https://cdn.example.com/mine.jpg"
    props = described_class.fill("hero_cinematic", "image_url" => kept, "headline" => "Stay")

    expect(props["image_url"]).to eq(kept)
    expect(props["headline"]).to eq("Stay")
  end

  it "leaves media-free centered hero props intact, including blank and previously saved images" do
    [{}, { "image_url" => "" }, { "image_url" => described_class::BENTO_WIDE }, { "image_url" => "https://cdn.example.com/mine.jpg" }].each do |image|
      props = { "headline" => "Build your workspace", "media_mode" => "none" }.merge(image)

      expect(described_class.fill("hero_centered", props, "lumen")).to eq(props)
    end
  end

  it "still fills centered hero images when media mode is absent, blank, or image" do
    [{}, { "media_mode" => "" }, { "media_mode" => "image" }].each do |mode|
      props = described_class.fill("hero_centered", mode, "lumen")

      expect(props["image_url"]).to eq(described_class.palette_for("lumen")[:bento_wide])
    end
  end

  it "honors media-free heroes when filling whole pages without affecting neighboring photo sections" do
    pages = [{ title: "Product", sections: [
      { id: "intro", type: "hero_centered", props: { headline: "Product", media_mode: "none" } },
      { id: "photo", type: "hero_split", props: {} }
    ] }]
    filled = described_class.fill_pages(pages, "lumen")
    sections = filled.first["sections"]

    expect(sections.first).to eq("id" => "intro", "type" => "hero_centered", "props" => { "headline" => "Product", "media_mode" => "none" })
    expect(sections.last["props"]["visual_url"]).to start_with("https://images.unsplash.com/")
    expect(pages.first[:sections].last[:props]).to eq({})
  end

  it "never repeats a single-image shot on the same page, falling back through the palette" do
    sections = [
      { type: "hero_split", props: {} },
      { type: "collection_rail", props: { items: [{ title: "A" }, { title: "B" }] } },
      { type: "cta_split", props: {} },
      { type: "cta_split", props: { image_url: "https://cdn.example.com/mine.jpg" } }
    ]
    filled = described_class.fill_sections(sections, "harbor_home").map { |section| section["props"] }
    hero = filled[0]["visual_url"]
    rail = filled[1]["items"].map { |item| item["image_url"] }
    cta = filled[2]["image_url"]

    expect(cta).to eq(described_class.palette_for("harbor")[:bento_wide])
    expect([hero, *rail, cta].map { |url| described_class.photo_id(url) }.uniq.size).to eq(4)
    expect(filled[3]["image_url"]).to eq("https://cdn.example.com/mine.jpg")
    expect(described_class.fill("cta_split", {}, "harbor")["image_url"]).to eq(described_class.palette_for("harbor")[:split])
  end

  it "moves page-used shots to the end of a list's cycle" do
    set = described_class.palette_for("tempo")
    hero = set[:hero]
    used = Set.new([described_class.photo_id(hero)])
    items = Array.new(3) { |index| { "title" => "Item #{index}" } }

    rail = described_class.fill("collection_rail", { "items" => items }, "tempo", used.dup)["items"]
    expect(rail.map { |item| described_class.photo_id(item["image_url"]) }).not_to include(described_class.photo_id(hero))

    full = Array.new(set[:listings].size) { |index| { "title" => "Item #{index}" } }
    full_rail = described_class.fill("collection_rail", { "items" => full }, "tempo", used.dup)["items"]
    expect(described_class.photo_id(full_rail.last["image_url"])).to eq(described_class.photo_id(hero))

    crowded = Set.new(set[:listings].map { |url| described_class.photo_id(url) })
    cycled = described_class.fill("collection_rail", { "items" => items }, "tempo", crowded)["items"]
    expect(cycled.map { |item| item["image_url"] }).to eq(set[:listings].first(3))
  end

  it "keeps the preferred shot when every palette shot is already on the page" do
    set = described_class.palette_for("harbor")
    used = Set.new(described_class::SHOT_FALLBACKS.flat_map { |name| Array(set[name]) }.map { |url| described_class.photo_id(url) })

    expect(described_class.fill("image_banner", {}, "harbor", used)["image_url"]).to eq(set[:bento_hero])
  end

  it "assigns distinct shots across bento spans and team portraits" do
    cells = described_class.fill("bento_grid", "cells" => [
      { "span" => "hero", "title" => "A" },
      { "span" => "wide", "title" => "B" },
      { "span" => "unit", "title" => "C" },
      { "span" => "unit", "title" => "D" }
    ])["cells"]

    urls = cells.map { |cell| cell["image_url"] }
    expect(urls).to all(start_with("https://images.unsplash.com/"))
    expect(urls.uniq.size).to eq(4)

    people = described_class.fill("team_grid", "people" => [
      { "name" => "Ada" }, { "name" => "Grace" }
    ])["people"]
    expect(people.map { |person| person["image_url"] }.uniq.size).to eq(2)
  end

  it "gives a named starter its own photography and keeps authored URLs" do
    stock = described_class::HERO_SPLIT
    props = described_class.fill("hero_split", { "visual_url" => stock }, "atelier_home")

    expect(props["visual_url"]).to include("photo-1556228720-195a672e8a03")
    expect(props["visual_url"]).not_to eq(stock)

    kept = described_class.fill("hero_split", { "visual_url" => "https://cdn.example.com/mine.jpg" }, "atelier")
    expect(kept["visual_url"]).to eq("https://cdn.example.com/mine.jpg")
  end

  it "replaces a known-dead Unsplash id without touching other authored URLs" do
    dead = "#{described_class::HOST}/photo-1497215728101-856f4ea42187?auto=format&fit=crop&w=900&q=80"
    kept = "https://cdn.example.com/mine.jpg"

    replaced = described_class.fill("bento_grid", "cells" => [
      { "span" => "unit", "image_url" => dead }
    ])
    expect(replaced["cells"].first["image_url"]).to start_with("https://images.unsplash.com/")
    expect(replaced["cells"].first["image_url"]).not_to include("photo-1497215728101-856f4ea42187")

    kept_props = described_class.fill("hero_split", "visual_url" => kept)
    expect(kept_props["visual_url"]).to eq(kept)
  end

  it "fills tiles, stories, listings and places from a palette's own shot lists" do
    tiles = described_class.fill("showcase_tiles", { "tiles" => [{ "title" => "Aero" }, { "title" => "Terra" }] }, "voltage_home")["tiles"]
    expect(tiles.first["image_url"]).to include("photo-1560958089-b8a1929cea89", "w=1800")
    expect(tiles.map { |tile| tile["image_url"] }.uniq.size).to eq(2)

    listings = described_class.fill("listing_grid", { "listings" => [{ "title" => "Villa" }] }, "manor_listings")["listings"]
    expect(listings.first["image_url"]).to include("photo-1613490493576-7fde63acd811")

    rails = described_class.fill("collection_rail", { "items" => [{ "title" => "File" }] }, "canvas_home")["items"]
    expect(rails.first["image_url"]).to include("photo-1558655146-9f40138edfeb")

    stories = described_class.fill("story_index", { "stories" => [{ "title" => "Lead" }] }, "gazette_home")["stories"]
    expect(stories.first["image_url"]).to include("photo-1494412574643-ff11b0a5c1c3")

    places = described_class.fill("locations", { "places" => [{ "name" => "Mercer" }] }, "atelier_visit")["places"]
    expect(places.first["image_url"]).to include("photo-1528698827591-e19ccd7bc23d")
  end

  it "falls back to a palette's scene shots for collections it does not define" do
    places = described_class.fill("locations", { "places" => [{ "name" => "Clinic" }, { "name" => "Annex" }] }, "clinic_contact")["places"]
    tiles = described_class.fill("showcase_tiles", { "tiles" => [{ "title" => "Default" }] })["tiles"]

    expect(places.map { |place| place["image_url"] }).to all(start_with("https://images.unsplash.com/"))
    expect(places.map { |place| place["image_url"] }.uniq.size).to eq(2)
    expect(tiles.first["image_url"]).to start_with("https://images.unsplash.com/")
  end
end
