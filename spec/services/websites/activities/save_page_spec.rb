# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Activities::SavePage do
  let_it_be(:customer) { create(:customer) }
  let(:site) { create(:website, customer: customer) }
  let!(:home) { create(:website_page, :home, website: site, customer: customer) }
  let(:page) { create(:website_page, website: site, customer: customer, slug: "about", title: "About") }

  before { Current.customer = customer }
  after  { Current.customer = nil }

  it "saves title, slug, and sections when structure is editable" do
    result = described_class.call(
      page: page,
      structure_editable: true,
      params: {
        title: "Our story",
        slug: "story",
        published: true,
        nav_visible: false,
        sections: [
          { type: "rich_text", props: { heading: "Hello", body: "A finished sentence." } }
        ]
      }
    )

    expect(result.success?).to be(true)
    page.reload
    expect(page.title).to eq("Our story")
    expect(page.slug).to eq("story")
    expect(page.published).to be(true)
    expect(page.nav_visible).to be(false)
    expect(page.sections.first["type"]).to eq("rich_text")
    expect(page.sections.first["id"]).to start_with("sec_")
    expect(page.sections.first["props"]).to be_a(Hash)
  end

  it "parses sections from a JSON string" do
    result = described_class.call(
      page: page,
      structure_editable: true,
      params: {
        title: "About",
        slug: "about",
        sections: [
          { type: "quote", props: { quote: "Stay hungry.", attribution: "Jobs" } }
        ].to_json
      }
    )

    expect(result.success?).to be(true)
    expect(page.reload.sections.first["type"]).to eq("quote")
    expect(page.sections.first["props"]["quote"]).to eq("Stay hungry.")
  end

  it "rejects malformed sections JSON" do
    result = described_class.call(
      page: page,
      params: { title: "About", slug: "about", sections: "{not-json" }
    )
    expect(result.success?).to be(false)
    expect(result.errors.join).to include(I18n.t("website.errors.invalid_sections"))
  end

  it "makes this page home and unsets home on siblings" do
    result = described_class.call(page: page, params: { title: "About", slug: "about", home: true })
    expect(result.success?).to be(true)
    expect(page.reload).to have_attributes(home: true, slug: "")
    expect(home.reload).to have_attributes(home: false, slug: "home")
    expect(site.pages.where(home: true).count).to eq(1)
  end

  it "refuses to unset the home page" do
    result = described_class.call(page: home, params: { title: "Home", home: false, slug: "home-now" })
    expect(result.success?).to be(false)
    expect(result.errors.join).to include(I18n.t("website.errors.home_required"))
    expect(home.reload.home).to be(true)
  end

  it "rejects an unknown section type" do
    result = described_class.call(
      page: page,
      structure_editable: true,
      params: { title: "About", slug: "about", sections: [ { type: "raw_html", props: {} } ] }
    )
    expect(result.success?).to be(false)
    expect(result.errors.join).to include(I18n.t("website.errors.unknown_section"))
  end

  it "generates a unique slug from the title when the slug is blank" do
    fresh = WebsitePage.new(website: site, customer: customer)
    result = described_class.call(
      page: fresh,
      params: { title: "Our Journal", slug: "", nav_visible: "1", published: "0", sections: "[]" }
    )

    expect(result.success?).to be(true)
    expect(fresh).to have_attributes(persisted?: true, slug: "our-journal", title: "Our Journal", home: false)
  end

  it "returns a taken-slug failure instead of raising" do
    page
    fresh = WebsitePage.new(website: site, customer: customer)
    result = nil
    expect {
      result = described_class.call(
        page: fresh,
        params: { title: "About", slug: "about", sections: "[]" }
      )
    }.not_to raise_error

    expect(result.success?).to be(false)
    expect(result.errors.join).to include(I18n.t("website.errors.slug_taken"))
    expect(fresh).not_to be_persisted
    expect(fresh.errors[:slug]).to be_present
  end

  it "overlays section props by id and ignores type or order changes" do
    page.update!(
      sections: [
        { "id" => "sec_keep", "type" => "quote", "props" => { "quote" => "Old", "attribution" => "A" } }
      ]
    )

    result = described_class.call(
      page: page,
      params: {
        title: "About",
        slug: "about",
        layout_key: "article",
        sections: [
          { "id" => "sec_keep", "type" => "hero_split", "props" => { "quote" => "New", "attribution" => "B" } },
          { "id" => "sec_extra", "type" => "cta_band", "props" => { "headline" => "Nope" } }
        ]
      }
    )

    expect(result.success?).to be(true)
    page.reload
    expect(page.layout_key).not_to eq("article")
    expect(page.sections.size).to eq(1)
    expect(page.sections.first).to include("id" => "sec_keep", "type" => "quote")
    expect(page.sections.first["props"]["quote"]).to eq("New")
  end

  it "backfills a blank layout_key from the page's section types" do
    create(:website_layout, key: "presence_about_match", sections: [
      { "type" => "split_image_text", "props" => {} },
      { "type" => "rich_text", "props" => {} },
      { "type" => "quote", "props" => {} }
    ])

    page.update!(
      layout_key: "",
      sections: [
        { "id" => "sec_split", "type" => "split_image_text", "props" => { "heading" => "Studio" } },
        { "id" => "sec_copy", "type" => "rich_text", "props" => { "heading" => "How" } },
        { "id" => "sec_quote", "type" => "quote", "props" => { "quote" => "Old" } }
      ]
    )

    result = described_class.call(
      page: page,
      params: {
        title: "About",
        slug: "about",
        layout_key: "article",
        sections: page.sections
      }
    )

    expect(result.success?).to be(true)
    expect(page.reload.layout_key).to eq("presence_about_match")
  end

  it "rejects a slug taking a shortcut and chooses a noncolliding generated slug" do
    target = create(:page, :for_member, :for_public, customer: customer, launched: true)
    PageShortcut.create!(customer_id: customer.id, path: "/journal", target: target)
    result = described_class.call(page: page, params: { title: "Journal", slug: "journal" })
    expect(result.success?).to be(false)
    expect(result.errors.join).to include(I18n.t("page_shortcuts.errors.shortcut_slug_taken"))
    expect(page.reload.slug).to eq("about")

    fresh = WebsitePage.new(website: site, customer: customer)
    result = described_class.call(page: fresh, params: { title: "Journal", slug: "" })
    expect(result.success?).to be(true)
    expect(fresh.slug).to eq("journal-2")
  end

  it "keeps demoted home slugs from taking a shortcut" do
    target = create(:page, :for_member, :for_public, customer: customer, launched: true)
    PageShortcut.create!(customer_id: customer.id, path: "/home", target: target)
    result = described_class.call(page: page, params: { home: true })
    expect(result.success?).to be(true)
    expect(home.reload.slug).to eq("home-2")
  end

  it "validates an existing page's explicit slug after obtaining the shared customer lock" do
    target = create(:page, :for_member, :for_public, customer: customer, launched: true)
    page
    allow(PageShortcuts::Collisions).to receive(:with_customer_lock).with(customer_id: customer.id).and_wrap_original do |original, **args, &write|
      original.call(**args) do
        PageShortcut.create!(customer_id: customer.id, path: "/late-path", target: target)
        write.call
      end
    end

    result = described_class.call(page: page, params: { title: "Updated", slug: "late-path" })

    expect(result.success?).to be(false)
    expect(result.errors.join).to include(I18n.t("page_shortcuts.errors.shortcut_slug_taken"))
    expect(page.reload).to have_attributes(title: "About", slug: "about")
  end

  it "generates slugs inside the shared customer write boundary" do
    target = create(:page, :for_member, :for_public, customer: customer, launched: true)
    fresh = WebsitePage.new(website: site, customer: customer)
    allow(PageShortcuts::Collisions).to receive(:with_customer_lock).with(customer_id: customer.id).and_wrap_original do |original, **args, &write|
      original.call(**args) do
        PageShortcut.create!(customer_id: customer.id, path: "/journal", target: target)
        write.call
      end
    end

    result = described_class.call(page: fresh, params: { title: "Journal", slug: "" })

    expect(result.success?).to be(true)
    expect(fresh.reload.slug).to eq("journal-2")
  end

  it "rolls back sibling home demotion when page persistence hits a unique index" do
    page
    allow(page).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique)

    result = described_class.call(page: page, params: { home: true, title: "Updated" })

    expect(result.success?).to be(false)
    expect(result.errors.join).to include(I18n.t("website.errors.slug_taken"))
    expect(home.reload).to have_attributes(home: true, slug: "")
    expect(page.reload).to have_attributes(home: false, title: "About", slug: "about")
  end

  it "does not demote the current home for a failed submission" do
    result = described_class.call(page: page, params: { home: true, title: "" })

    expect(result.success?).to be(false)
    expect(home.reload).to have_attributes(home: true, slug: "")
    expect(page.reload).to have_attributes(home: false, title: "About", slug: "about")
  end

  it "reloads inside the customer boundary so an explicit stale unpublish is persisted" do
    stale = WebsitePage.find(page.id)
    expect(stale).not_to be_published
    page.update!(published: true)

    result = described_class.call(page: stale, params: { published: false })

    expect(result).to be_success
    expect(page.reload).not_to be_published
  end

  it "merges locked section updates onto current persisted structure rather than a stale template" do
    page.update!(sections: [{ "id" => "keep", "type" => "quote", "props" => { "quote" => "Original" } }])
    stale = WebsitePage.find(page.id)
    page.update!(sections: [
      *page.sections,
      { "id" => "added", "type" => "rich_text", "props" => { "body" => "Keep newer work" } }
    ])

    result = described_class.call(page: stale, params: {
      sections: [{ "id" => "keep", "type" => "quote", "props" => { "quote" => "Updated" } }]
    })

    expect(result).to be_success
    expect(page.reload.sections.map { |section| section["id"] }).to eq(%w[keep added])
    expect(page.sections.last.dig("props", "body")).to eq("Keep newer work")
  end

  it "does not decorate an ignored incoming type before applying its props to the saved type" do
    page.update!(sections: [{ "id" => "keep", "type" => "quote", "props" => { "quote" => "Old" } }])

    result = described_class.call(page: page, params: {
      sections: [{ "id" => "keep", "type" => "hero_split", "props" => { "quote" => "New" } }]
    })

    expect(result).to be_success
    expect(page.reload.sections).to eq([{ "id" => "keep", "type" => "quote", "props" => { "quote" => "New" } }])
  end

  it "unpublishes stale stored invalid content without rewriting it, but refuses to republish it" do
    invalid = [{ "id" => "keep", "type" => "faq", "props" => { "items" => Array.new(21) { { "question" => "Q", "answer" => "A" } } } }]
    page.update!(published: true, sections: invalid)

    expect(described_class.call(page: page, params: { published: false })).to be_success
    expect(page.reload).not_to be_published
    expect(page.sections).to eq(invalid)
    expect(described_class.call(page: page, params: { published: true })).not_to be_success
    expect(page.reload).not_to be_published
    expect(page.sections).to eq(invalid)
  end

  it "does not refill media or template content on a publication-only save" do
    layout = create(:website_layout)
    page.update!(layout_key: layout.key, sections: [], published: true)

    expect(described_class.call(page: page, params: { published: false, sections: [] })).to be_success
    expect(page.reload.sections).to eq([])
  end

  describe "page theme override" do
    it "stores a preset key and clears it back to the site theme with a blank value" do
      expect(described_class.call(page: page, params: { theme_key: "midnight" })).to be_success
      expect(page.reload.theme_key).to eq("midnight")

      expect(described_class.call(page: page, params: { theme_key: "" })).to be_success
      expect(page.reload.theme_key).to be_nil
    end

    it "rejects an unknown preset" do
      result = described_class.call(page: page, params: { theme_key: "neon" })

      expect(result).not_to be_success
      expect(page.reload.theme_key).to be_nil
    end

    it "resolves the layout sentinel to the layout's paired preset" do
      layout = create(:website_layout)
      result = described_class.call(page: site.pages.new(customer: customer), params: { title: "Visit", layout_key: layout.key, theme_key: "layout" })

      expect(result).to be_success
      expect(result.model.reload.theme_key).to eq(layout.theme_preset_key)
    end

    it "prefers a layout's explicit theme over its catalog pairing" do
      layout = create(:website_layout, theme_key: "obsidian")
      result = described_class.call(page: site.pages.new(customer: customer), params: { title: "Visit", layout_key: layout.key, theme_key: "layout" })

      expect(result.model.reload.theme_key).to eq("obsidian")
    end

    it "drops the layout sentinel when the page has no layout" do
      expect(described_class.call(page: page, params: { theme_key: "layout" })).to be_success
      expect(page.reload.theme_key).to be_nil
    end
  end

  it "persists validated section styles and rejects unknown style values" do
    styles = { "headline" => { "color" => "accent", "size" => "xl" }, "section" => { "background" => "#0f172a" } }
    ok = described_class.call(page: page, structure_editable: true, params: {
      sections: [{ type: "hero_split", props: { headline: "Hi", styles: styles } }]
    })
    expect(ok).to be_success
    expect(page.reload.sections.first.dig("props", "styles")).to eq(styles)

    bad = described_class.call(page: page, structure_editable: true, params: {
      sections: [{ type: "hero_split", props: { headline: "Hi", styles: { "headline" => { "color" => "url(evil)" } } } }]
    })
    expect(bad).not_to be_success
    expect(page.reload.sections.first.dig("props", "styles")).to eq(styles)
  end
end
