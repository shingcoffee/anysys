# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Entities::AttributeGroupCardComponent, type: :component do
  let(:entry) { EntityEntry.new(id: 7) }
  let(:fields) do
    [{ "name_slug" => "code", "display_label" => "Code" },
     { "name_slug" => "bio", "name" => "bio", "html_type" => "textarea" },
     { "name_slug" => "intake" }]
  end
  let(:display) do
    instance_double(Entities::EntryDisplay).tap do |double|
      allow(double).to receive(:text) { |_entry, slug| { "code" => "042857", "bio" => "Line 1\nLine 2" }.fetch(slug, I18n.t("common.labels.em_dash")) }
      allow(double).to receive(:files).and_return([])
    end
  end

  def render_card(**options)
    render_inline(described_class.new(id: "group-1", heading: "Enrollment", icon: "book", color: "indigo",
                                      fields: fields, entry: entry, display: display, **options))
  end

  it "renders the group as a card with its icon tile and heading, without a field count" do
    render_card

    card = page.find("section#group-1.card[aria-labelledby='group-1-heading']")
    aggregate_failures do
      expect(card).to have_css("header span.bg-indigo-50.text-indigo-600 svg")
      expect(card).to have_css("header h2#group-1-heading", text: "Enrollment")
      expect(card).not_to have_text(I18n.t("admin_misc.entities.entry_detail.field_count", count: 3))
    end
  end

  it "labels fields by display label, name, then slug, stacking long-text fields and muting blanks" do
    render_card

    rows = page.all("dl > div")
    aggregate_failures do
      expect(page.all("dt").map(&:text)).to eq(%w[Code bio intake])
      expect(page).to have_css("dd.text-text-primary", text: "042857")
      expect(rows.map { |row| row[:class].include?("sm:grid") }).to eq([true, false, true])
      expect(rows[1]).to have_css("dd.whitespace-pre-line", text: "Line 1")
      expect(page).to have_css("dd.text-text-tertiary", text: I18n.t("common.labels.em_dash"))
    end
  end

  context "with contact values" do
    let(:values) do
      { "email" => "ada@example.com", "phone" => "+44 (20) 7946-0018", "site" => "https://example.com/a",
        "unsafe" => "javascript:alert(1)", "extension" => "ext." }
    end
    let(:fields) do
      [{ "name_slug" => "email", "html_type" => "email" }, { "name_slug" => "phone", "html_type" => "tel" },
       { "name_slug" => "site", "html_type" => "url" }, { "name_slug" => "unsafe", "html_type" => "url" },
       { "name_slug" => "extension", "html_type" => "tel" }, { "name_slug" => "blank", "html_type" => "email" }]
    end
    let(:display) do
      instance_double(Entities::EntryDisplay).tap do |double|
        allow(double).to receive(:text) { |_entry, slug| values.fetch(slug, I18n.t("common.labels.em_dash")) }
        allow(double).to receive(:files).and_return([])
      end
    end

    it "links email, phone and web-address values, leaving unusable values and blanks as text" do
      render_card

      aggregate_failures do
        expect(page).to have_css("dd a[href='mailto:ada@example.com']", text: "ada@example.com")
        expect(page).to have_css("dd a[href='tel:+442079460018']", text: "+44 (20) 7946-0018")
        expect(page).to have_css("dd a[href='https://example.com/a'][target='_blank'][rel='noopener noreferrer']")
        expect(page).to have_css("dd", text: "javascript:alert(1)")
        expect(page).to have_css("dd", text: "ext.")
        expect(page.all("dd a").size).to eq(3)
        expect(page).to have_css("dd.text-text-tertiary", text: I18n.t("common.labels.em_dash"))
      end
    end
  end

  context "with file values" do
    let(:customer) { create(:customer) }
    let(:entity) do
      create(:entity, customer: customer, property_schema: [
        { "name" => "Contract", "name_slug" => "contract", "type" => "Types::String", "html_type" => "file" },
        { "name" => "Photo", "name_slug" => "photo", "type" => "Types::String", "html_type" => "image" },
        { "name" => "Scans", "name_slug" => "scans", "type" => "Types::String", "html_type" => "file" }
      ].to_json)
    end
    let(:entry) do
      png = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/test.png"), "image/png")
      EntityEntry.build_for(entity).create!(customer_id: customer.id, photo: png,
                                            contract: { io: StringIO.new("%PDF-1.4\n"), filename: "terms.pdf" })
    end
    let(:fields) { Array(entity.property_schema_json) }
    let(:display) { Entities::EntryDisplay.new(entity: entity, entries: [entry], customer_id: customer.id, audience: "admin") }

    it "links each file for download and previews images, muting a field without files" do
      render_card

      aggregate_failures do
        expect(page).to have_link("terms.pdf", href: %r{/rails/active_storage/blobs/.+/terms\.pdf\?disposition=attachment})
        expect(page).to have_css("dd a[target='_blank'][rel='noopener noreferrer'] img[alt='test.png']")
        expect(page).to have_css("dd.text-text-tertiary", text: I18n.t("common.labels.em_dash"))
      end
    end
  end

  it "drops its own card when unframed, for a caller that provides one" do
    render_card(framed: false)

    section = page.find("section#group-1")
    aggregate_failures do
      expect(section[:class].split).not_to include("card")
      expect(section).to have_css("header h2", text: "Enrollment")
    end
  end

  it "takes the heading level of its surroundings" do
    render_card(heading_tag: :h5)

    expect(page).to have_css("header h5#group-1-heading", text: "Enrollment")
    expect(page).not_to have_css("h2")
  end
end
