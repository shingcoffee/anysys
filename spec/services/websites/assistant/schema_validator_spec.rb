# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Assistant::SchemaValidator do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }
  let(:website) { create(:website, customer: customer) }
  let!(:home) { create(:website_page, :home, website: website, customer: customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer) }
  let(:uploads) { Websites::Assistant::Uploads.new(conversation: conversation) }

  def validate(pages)
    extraction = Websites::Assistant::Extraction.parse({ intent: "apply_website", reply: "Done.", pages: pages }.to_json)
    described_class.call(extraction: extraction, website: website, uploads: uploads)
  end

  def error(key, **options)
    I18n.t("ai_assistant.assistant.website.errors.#{key}", **options)
  end

  def statement(headline = "We bake bread")
    { "type" => "statement", "props" => { "headline" => headline } }
  end

  def page(title = "About", sections: [ statement ], **extra)
    { "title" => title, "sections" => sections }.merge(extra.stringify_keys)
  end

  def attach_upload(filename = "shop.png", to: conversation)
    message = create(:ai_assistant_message, conversation: to, customer: to.customer)
    Current.set(customer: to.customer) do
      message.images.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/test.png")),
        filename: filename,
        content_type: "image/png"
      )
    end
    "upload:#{message.images.attachments.max_by(&:id).id}"
  end

  describe "page normalization" do
    it "keeps only the contract keys and casts them" do
      result = validate([
        page(" About us ", slug: "about", nav_visible: "false", published: true, layout_key: "x", position: 9,
             sections: [ { "type" => "statement", "id" => "sec_x", "props" => { "headline" => 2026, "bogus" => "drop" } } ])
      ])

      expect(result.errors).to eq([])
      expect(result.pages).to eq([
        {
          "page_id" => nil,
          "title" => "About us",
          "slug" => "about",
          "nav_visible" => false,
          "home" => false,
          "sections" => [ { "type" => "statement", "props" => { "headline" => "2026" } } ]
        }
      ])
    end

    it "defaults nav_visible to true and leaves slug nil when omitted" do
      normalized = validate([ page ]).pages.first

      expect(normalized).to include("nav_visible" => true, "slug" => nil)
    end

    it "drops blank string props" do
      props = validate([ page(sections: [ { "type" => "cta_band", "props" => { "headline" => "Visit", "body" => "  " } } ]) ])
              .pages.first.dig("sections", 0, "props")

      expect(props).to eq("headline" => "Visit")
    end

    it "keeps valid design styles and strips injected or unknown ones" do
      styles = {
        "headline" => { "color" => "#12ab34", "size" => "xl", "weight" => "red;}body{display:none" },
        "section" => { "background" => "url(javascript:alert(1))" },
        "bogus" => { "color" => "accent" }
      }
      result = validate([ page(sections: [ { "type" => "statement", "props" => { "headline" => "Hi", "styles" => styles } } ]) ])

      expect(result.errors).to eq([])
      expect(result.pages.first.dig("sections", 0, "props", "styles")).to eq("headline" => { "color" => "#12ab34", "size" => "xl" })
    end

    it "omits styles entirely when nothing valid remains" do
      props = validate([ page(sections: [ { "type" => "statement", "props" => { "headline" => "Hi", "styles" => { "headline" => { "color" => "#zzz" } } } } ]) ])
              .pages.first.dig("sections", 0, "props")

      expect(props).to eq("headline" => "Hi")
    end

    it "joins a list sent for a textarea with newlines and stringifies numbers" do
      tiers = [ { "name" => "Loaf club", "price" => 12, "features" => [ "Weekly loaf", "Free delivery" ] } ]

      result = validate([ page(sections: [ { "type" => "pricing", "props" => { "tiers" => tiers } } ]) ])

      expect(result.errors).to eq([])
      expect(result.pages.first.dig("sections", 0, "props", "tiers")).to eq(
        [ { "name" => "Loaf club", "price" => "12", "features" => "Weekly loaf\nFree delivery" } ]
      )
    end
  end

  describe "home rule" do
    it "never makes a new page home while the site already has one" do
      expect(validate([ page, page("Menu") ]).pages.map { |row| row["home"] }).to eq([ false, false ])
    end

    it "makes only the first new page home when the site has no home page, and drops its slug" do
      home.destroy!

      result = validate([ page("Welcome", slug: "welcome"), page("Menu", slug: "menu") ])

      expect(result.errors).to eq([])
      expect(result.pages.map { |row| [ row["home"], row["slug"] ] }).to eq([ [ true, nil ], [ false, "menu" ] ])
    end

    it "keeps a revised draft home page home and ignores its slug" do
      result = validate([ page("Home", page_id: home.id, slug: "not allowed!") ])

      expect(result.errors).to eq([])
      expect(result.pages.first).to include("page_id" => home.id, "home" => true, "slug" => nil)
    end
  end

  describe "page_id" do
    it "accepts a draft page of this website" do
      draft = create(:website_page, website: website, customer: customer, title: "Old about")

      expect(validate([ page(page_id: draft.id) ]).pages.first["page_id"]).to eq(draft.id)
    end

    it "refuses a published page" do
      published = create(:website_page, :published, website: website, customer: customer, title: "Pricing")

      expect(validate([ page(page_id: published.id) ]).errors).to eq([ error(:page_published, title: "Pricing") ])
    end

    it "refuses another tenant's page" do
      foreign = create(:website_page, website: create(:website, customer: other_customer), customer: other_customer)

      result = validate([ page(page_id: foreign.id) ])

      expect(result.errors).to eq([ error(:page_not_found, id: foreign.id) ])
      expect(result.pages.first["page_id"]).to be_nil
    end

    it "refuses a page_id that is not a number" do
      expect(validate([ page(page_id: "about") ]).errors).to eq([ error(:page_not_found, id: "about") ])
    end

    it "refuses the same page twice" do
      draft = create(:website_page, website: website, customer: customer)

      expect(validate([ page(page_id: draft.id), page("Again", page_id: draft.id) ]).errors)
        .to eq([ error(:duplicate_page, id: draft.id) ])
    end
  end

  describe "slug" do
    it "refuses a slug that is not lowercase-hyphen" do
      expect(validate([ page(slug: "About Us") ]).errors).to eq([ error(:invalid_slug, title: "About", slug: "About Us") ])
    end

    it "refuses a slug used twice in the document" do
      expect(validate([ page(slug: "about"), page("Story", slug: "about") ]).errors)
        .to eq([ error(:duplicate_slug, slug: "about") ])
    end

    it "refuses a slug another page of the site already uses" do
      create(:website_page, website: website, customer: customer, slug: "about")

      expect(validate([ page("About us", slug: "about") ]).errors)
        .to eq([ error(:slug_taken, title: "About us", slug: "about") ])
    end

    it "lets a revised page keep its own slug" do
      draft = create(:website_page, website: website, customer: customer, slug: "about")

      expect(validate([ page(page_id: draft.id, slug: "about") ]).errors).to eq([])
    end

    it "ignores slugs of another tenant's site" do
      create(:website_page, website: create(:website, customer: create(:customer)), slug: "about")

      expect(validate([ page(slug: "about") ]).errors).to eq([])
    end
  end

  describe "page structure" do
    it "requires at least one page" do
      expect(validate([]).errors).to eq([ error(:pages_blank) ])
    end

    it "caps the page count" do
      pages = Array.new(Websites::Assistant::Extraction::MAX_PAGES + 1) { |index| page("Page #{index}") }

      expect(validate(pages).errors).to eq([ error(:too_many_pages, count: Websites::Assistant::Extraction::MAX_PAGES) ])
    end

    it "requires a title" do
      expect(validate([ page(" ") ]).errors).to eq([ error(:title_blank, index: 1) ])
    end

    it "requires sections and caps their number" do
      too_many = Array.new(Websites::Assistant::Extraction::MAX_SECTIONS + 1) { statement }

      expect(validate([ page(sections: []), page("Long", sections: too_many) ]).errors).to eq([
        error(:sections_blank, title: "About"),
        error(:too_many_sections, title: "Long", count: Websites::Assistant::Extraction::MAX_SECTIONS)
      ])
    end

    it "refuses non-object sections and unknown section types" do
      result = validate([ page(sections: [ "hero", { "type" => "carousel", "props" => {} }, statement ]) ])

      expect(result.errors).to eq([
        error(:section_not_object, title: "About", index: 1),
        error(:unknown_section, title: "About", index: 2, type: "carousel")
      ])
      expect(result.pages.first["sections"].map { |row| row["type"] }).to eq([ "statement" ])
    end

    it "refuses a page that is not an object when handed one directly" do
      extraction = Struct.new(:pages).new([ "Home" ])

      result = described_class.call(extraction: extraction, website: website, uploads: uploads)

      expect(result.errors).to eq([ error(:page_not_object, index: 1) ])
    end
  end

  describe "section props" do
    it "refuses a select value outside its options" do
      result = validate([ page(sections: [ { "type" => "hero_cinematic", "props" => { "headline" => "Hi", "tone" => "neon" } } ]) ])

      expect(result.errors).to eq([
        error(:invalid_option, title: "About", type: "hero_cinematic", field: "tone", options: "light, dark")
      ])
      expect(result.pages.first.dig("sections", 0, "props")).to eq("headline" => "Hi")
    end

    it "checks selects inside array items" do
      cells = [ { "span" => "giant", "title" => "Ovens" } ]

      expect(validate([ page(sections: [ { "type" => "bento_grid", "props" => { "cells" => cells } } ]) ]).errors).to eq([
        error(:invalid_option, title: "About", type: "bento_grid", field: "cells[1].span", options: "hero, wide, unit")
      ])
    end

    it "enforces array bounds" do
      items = Array.new(7) { |index| { "question" => "Q#{index}", "answer" => "A" } }
      faq = { "type" => "faq", "props" => { "items" => items * 3 } }

      expect(validate([ page(sections: [ faq ]) ]).errors).to eq([
        error(:array_count, title: "About", type: "faq", field: "items", min: 0, max: 20)
      ])
    end

    it "requires a minimum-bounded array to be present" do
      proof = { "type" => "proof_strip", "props" => {} }

      expect(validate([ page(sections: [ proof ]) ]).errors).to eq([
        error(:array_count, title: "About", type: "proof_strip", field: "items", min: 4, max: 6)
      ])
    end

    it "accepts a minimum-bounded array with enough items" do
      items = Array.new(4) { |index| { "label" => "Years", "value" => index } }

      expect(validate([ page(sections: [ { "type" => "proof_strip", "props" => { "items" => items } } ]) ]).errors).to eq([])
    end

    it "refuses array items that are not objects" do
      gallery = { "type" => "gallery", "props" => { "items" => [ "photo.jpg" ] } }

      expect(validate([ page(sections: [ gallery ]) ]).errors).to eq([
        error(:item_not_object, title: "About", type: "gallery", field: "items")
      ])
    end
  end

  describe "hrefs" do
    def cta(href)
      { "type" => "cta_band", "props" => { "headline" => "Visit", "button_label" => "Go", "button_href" => href } }
    end

    it "accepts https, existing slugs and slugs of pages in the same document" do
      create(:website_page, website: website, customer: customer, slug: "contact")

      result = validate([
        page("Our Menu", sections: [ cta("contact"), cta("story"), cta("https://example.com/book") ]),
        page("Story", sections: [ cta("our-menu") ], slug: "story")
      ])

      expect(result.errors).to eq([])
    end

    it "refuses an internal link to a page that does not exist" do
      result = validate([ page(sections: [ cta("careers") ]) ])

      expect(result.errors).to eq([
        error(:unknown_link, title: "About", type: "cta_band", field: "button_href", slug: "careers")
      ])
      expect(result.pages.first.dig("sections", 0, "props")).not_to have_key("button_href")
    end

    it "refuses an href the site cannot render" do
      expect(validate([ page(sections: [ cta("javascript:alert(1)") ]) ]).errors).to eq([
        error(:invalid_href, title: "About", type: "cta_band", field: "button_href",
                             message: I18n.t("website.errors.javascript_href"))
      ])
    end
  end

  describe "images" do
    def hero(visual)
      { "type" => "hero_split", "props" => { "headline" => "Fresh bread", "visual_url" => visual } }
    end

    it "accepts an upload token from this conversation" do
      token = attach_upload

      result = validate([ page(sections: [ hero(token) ]) ])

      expect(result.errors).to eq([])
      expect(result.pages.first.dig("sections", 0, "props", "visual_url")).to eq(token)
      expect(result.unplaced).to eq([])
    end

    it "refuses a token from another conversation" do
      token = attach_upload(to: create(:ai_assistant_conversation, customer: customer))

      expect(validate([ page(sections: [ hero(token) ]) ]).errors).to eq([
        error(:unknown_upload, title: "About", type: "hero_split", field: "visual_url", token: token)
      ])
    end

    it "refuses a token from another tenant" do
      token = attach_upload(to: create(:ai_assistant_conversation, customer: other_customer))

      expect(validate([ page(sections: [ hero(token) ]) ]).errors).to eq([
        error(:unknown_upload, title: "About", type: "hero_split", field: "visual_url", token: token)
      ])
    end

    it "refuses an image URL the model invented" do
      result = validate([ page(sections: [ hero("https://images.example.com/bakery.jpg") ]) ])

      expect(result.errors).to eq([ error(:invalid_image, title: "About", type: "hero_split", field: "visual_url") ])
    end

    it "accepts an image already used on the site, at any depth" do
      existing = "https://images.unsplash.com/photo-1?w=800"
      create(:website_page, website: website, customer: customer,
                            sections: [ { "type" => "team_grid", "props" => { "people" => [ { "image_url" => existing } ] } } ])

      expect(validate([ page(sections: [ hero(existing) ]) ]).errors).to eq([])
    end

    it "checks images inside array items and allows blanks" do
      token = attach_upload
      cards = [ { "title" => "Rye", "image_url" => token }, { "title" => "Spelt", "image_url" => "" },
                { "title" => "Sourdough", "image_url" => "https://example.com/x.jpg" } ]

      result = validate([ page(sections: [ { "type" => "card_grid", "props" => { "cards" => cards } } ]) ])

      expect(result.errors).to eq([ error(:invalid_image, title: "About", type: "card_grid", field: "cards[3].image_url") ])
      expect(result.pages.first.dig("sections", 0, "props", "cards")).to eq(
        [ { "title" => "Rye", "image_url" => token }, { "title" => "Spelt" }, { "title" => "Sourdough" } ]
      )
    end

    it "reports pending uploads the document does not place" do
      placed = attach_upload("storefront.jpg")
      left_out = attach_upload("chef.png")

      result = validate([ page(sections: [ hero(placed) ]) ])

      expect(result.errors).to eq([])
      expect(result.unplaced.map(&:token)).to eq([ left_out ])
    end
  end

  it "collects every error but caps the list" do
    sections = Array.new(Websites::Assistant::Extraction::MAX_SECTIONS) { { "type" => "carousel" } }
    pages = Array.new(3) { |index| page("Page #{index}", sections: sections) }

    expect(validate(pages).errors.size).to eq(described_class::MAX_ERRORS)
  end

  describe ".map_images and .image_values" do
    it "walks only image keys at any depth" do
      tree = [ { "props" => { "visual_url" => "a", "headline" => "a", "cards" => [ { "image_url" => "b" } ] } } ]

      expect(described_class.image_values(tree)).to eq(%w[a b])
      expect(described_class.map_images(tree) { |value| value.upcase })
        .to eq([ { "props" => { "visual_url" => "A", "headline" => "a", "cards" => [ { "image_url" => "B" } ] } } ])
    end
  end
end
