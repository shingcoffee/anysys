# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::EntryDisplay do
  let_it_be(:customer) { create(:customer) }
  let(:em_dash) { I18n.t("common.labels.em_dash") }
  let(:admin_only) { { "admin" => true, "member" => false, "public" => false } }

  let!(:instructor) do
    create(:entity, customer: customer, name: "Instructor", property_schema: [
      { "name" => "Name", "name_slug" => "name", "html_type" => "text" },
      { "name" => "Badge", "name_slug" => "badge", "html_type" => "text", "visibility" => admin_only }
    ].to_json)
  end
  let!(:jenny) { create(:entity_entry, customer: customer, entity: instructor, data: { name: "Jenny", badge: "J1" }.to_json) }
  let!(:unnamed) { create(:entity_entry, customer: customer, entity: instructor, data: {}.to_json) }

  def reference(slug, label_field: "name", html_type: "select")
    { "name" => slug.titleize, "name_slug" => slug, "html_type" => html_type,
      "config" => { "options_source" => "entity_entries", "entity_id" => instructor.id.to_s, "label_field" => label_field } }
  end

  let!(:course) do
    create(:entity, customer: customer, name: "Course", property_schema: [
      { "name" => "Title", "name_slug" => "title", "html_type" => "text" },
      { "name" => "Mode", "name_slug" => "mode", "html_type" => "select",
        "config" => { "options" => [{ "label" => "In person", "value" => "in_person" }] } },
      { "name" => "Tags", "name_slug" => "tags", "html_type" => "checkbox",
        "config" => { "options" => [{ "label" => "Lab", "value" => "lab" }, { "label" => "Field", "value" => "field" }] } },
      { "name" => "Active", "name_slug" => "active", "html_type" => "checkbox" },
      { "name" => "Starts", "name_slug" => "starts_on", "html_type" => "date" },
      { "name" => "Seats", "name_slug" => "seats", "html_type" => "number" },
      { "name" => "Double seats", "name_slug" => "double_seats", "type" => "Calculated", "html_type" => "number",
        "formula" => "seats * 2" },
      reference("instructor"),
      reference("assistant", label_field: "badge")
    ].to_json)
  end

  # Ruby 3.2 treats `build("k" => "v")` as keywords, not a positional hash.
  def build(data = nil, audience: EntityAttributeAudience::ADMIN, **fields)
    entry = create(:entity_entry, customer: customer, entity: course, data: (data || fields).to_json)
    [described_class.new(entity: course, entries: [entry], customer_id: customer.id, audience: audience), entry]
  end

  it "shows the em dash for blank values" do
    display, entry = build("title" => "", "tags" => [])
    expect(%w[title tags mode instructor].map { |slug| display.text(entry, slug) }).to all(eq(em_dash))
  end

  it "shows static option labels, joining several, and the value when no option matches" do
    display, entry = build("mode" => "in_person", "tags" => %w[lab field])
    expect(display.text(entry, "mode")).to eq("In person")
    expect(display.text(entry, "tags")).to eq("Lab, Field")

    display, entry = build("mode" => "remote")
    expect(display.text(entry, "mode")).to eq("remote")
  end

  it "labels references, names missing records and falls back to Untitled" do
    display, entry = build("instructor" => jenny.id.to_s)
    expect(display.text(entry, "instructor")).to eq("Jenny")

    display, entry = build("instructor" => unnamed.id.to_s)
    expect(display.text(entry, "instructor")).to eq("Untitled (##{unnamed.id})")

    display, entry = build("instructor" => "999999")
    expect(display.text(entry, "instructor")).to eq("Missing record (#999999)")
  end

  it "keeps the raw id when the display field is hidden from the audience" do
    display, entry = build({ "assistant" => jenny.id.to_s }, audience: EntityAttributeAudience::MEMBER)
    expect(display.text(entry, "assistant")).to eq(jenny.id.to_s)

    display, entry = build({ "assistant" => jenny.id.to_s })
    expect(display.text(entry, "assistant")).to eq("J1")
  end

  it "never numbers duplicate labels" do
    twin = create(:entity_entry, customer: customer, entity: instructor, data: { name: "Jenny" }.to_json)
    display, entry = build("instructor" => twin.id.to_s)
    expect(display.text(entry, "instructor")).to eq("Jenny")
  end

  it "shows derived values" do
    display, entry = build("seats" => 12)
    expect(display.text(entry, "double_seats")).to eq("24")
  end

  it "shows yes and no for a checkbox without options" do
    display, entry = build("active" => true)
    expect(display.text(entry, "active")).to eq(I18n.t("common.labels.yes"))

    display, entry = build("active" => "false")
    expect(display.text(entry, "active")).to eq(I18n.t("common.labels.no"))
  end

  it "shows dates, numbers and unknown slugs as stored" do
    display, entry = build("starts_on" => "2026-11-02", "seats" => 12)
    expect(display.text(entry, "starts_on")).to eq("2026-11-02")
    expect(display.text(entry, "seats")).to eq("12")

    # EntityEntry rejects keys outside the schema, so the unknown slug is stubbed in.
    allow(entry).to receive(:data_json).and_return(entry.data_json.merge("legacy" => "x"))
    expect(display.text(entry, "legacy")).to eq("x")
  end

  it "shows an in-scope person label to a member and the bare id for a peer's row" do
    person_model = EntityDefinitions::Capabilities::PERSON_MODEL
    enable_module!("authentication", customer).set_extendable_model!(person_model, true)
    member = create(:user, :member, customer: customer)
    peer = create(:user, :member, customer: customer)
    other_customer = create(:customer)
    foreign_member = create(:user, :member, customer: other_customer)
    learner = create(:entity, customer: customer, name: "Learner", extended_model: person_model,
                     property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    mine = create(:entity_entry, customer: customer, entity: learner, user: member, data: { name: "Ada" }.to_json)
    theirs = create(:entity_entry, customer: customer, entity: learner, user: peer, data: { name: "Grace" }.to_json)
    enable_module!("authentication", other_customer).set_extendable_model!(person_model, true)
    foreign_entity = create(:entity, customer: other_customer, name: "Learner", extended_model: person_model,
                            property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    foreign = create(:entity_entry, customer: other_customer, entity: foreign_entity, user: foreign_member,
                     data: { name: "Foreign" }.to_json)

    host = create(:entity, customer: customer, name: "Note", property_schema: [
      { "name" => "Who", "name_slug" => "who", "html_type" => "select",
        "config" => { "options_source" => "entity_entries", "entity_id" => learner.id.to_s, "label_field" => "name" } }
    ].to_json)

    show = lambda do |data, audience:, viewer:|
      entry = create(:entity_entry, customer: customer, entity: host, data: data.to_json)
      display = described_class.new(entity: host, entries: [entry], customer_id: customer.id,
                                    audience: audience, viewer: viewer)
      display.text(entry, "who")
    end

    expect(show.call({ "who" => mine.id.to_s }, audience: EntityAttributeAudience::MEMBER, viewer: member)).to eq("Ada")
    expect(show.call({ "who" => theirs.id.to_s }, audience: EntityAttributeAudience::MEMBER, viewer: member)).to eq(theirs.id.to_s)
    expect(show.call({ "who" => foreign.id.to_s }, audience: EntityAttributeAudience::MEMBER, viewer: member)).to eq(foreign.id.to_s)
    expect(show.call({ "who" => theirs.id.to_s }, audience: EntityAttributeAudience::ADMIN, viewer: nil)).to eq("Grace")
  end

  it "preloads a page: one label query per reference field, however many entries" do
    entries = Array.new(4) { create(:entity_entry, customer: customer, entity: course, data: { "instructor" => jenny.id.to_s }.to_json) }
    display = described_class.new(entity: course, entries: entries, customer_id: customer.id, audience: EntityAttributeAudience::ADMIN)
    queries = []
    subscriber = ->(*, payload) { queries << payload[:sql] if payload[:sql].to_s.include?("json_extract(entity_entries.data") }

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      entries.each { |entry| display.text(entry, "instructor") }
    end
    expect(queries.size).to eq(1)
  end

  describe ".prime! and EntityEntry#display_text" do
    it "attaches one display per entity to the tenant's entries" do
      entry = create(:entity_entry, customer: customer, entity: course, data: { "mode" => "in_person" }.to_json)
      foreign = create(:entity_entry, customer: create(:customer), entity: course, data: { "mode" => "in_person" }.to_json)

      described_class.prime!([entry, foreign, "skip"], customer_id: customer.id, audience: EntityAttributeAudience::ADMIN)

      expect(entry.display_text("mode")).to eq("In person")
      expect(foreign.display_text("mode")).to eq("in_person")
    end
  end

  describe "file fields" do
    let(:documents) do
      create(:entity, customer: customer, property_schema: [
        { "name" => "Contract", "name_slug" => "contract", "html_type" => "file" },
        { "name" => "Scans", "name_slug" => "scans", "html_type" => "file", "config" => { "multiple" => true } }
      ].to_json)
    end

    def file(name) = { io: StringIO.new("%PDF-1.4\n"), filename: name }

    it "shows each entry's filenames from one query, and the em dash for none" do
      model = EntityEntry.build_for(documents)
      filed = model.create!(customer_id: customer.id, contract: file("terms.pdf"), scans: [file("a.pdf"), file("b.pdf")])
      empty = model.create!(customer_id: customer.id)
      display = described_class.new(entity: documents, entries: [EntityEntry.find(filed.id), EntityEntry.find(empty.id)],
                                    customer_id: customer.id, audience: EntityAttributeAudience::ADMIN)

      queries = 0
      counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        expect(display.text(filed, "contract")).to eq("terms.pdf")
        expect(display.text(filed, "scans")).to eq("a.pdf, b.pdf")
        expect(display.text(empty, "scans")).to eq(em_dash)
        expect(display.files(filed, "scans").map { |scan| scan.filename.to_s }).to eq(%w[a.pdf b.pdf])
      end
      expect(queries).to be <= 2
      expect(display.files(filed, "title")).to eq([])
    end
  end
end
