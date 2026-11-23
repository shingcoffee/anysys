# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Entities::EntryDetailComponent, type: :component do
  let_it_be(:customer) { create(:customer) }

  let(:entity) do
    e = Entity.new(
      customer_id: customer.id,
      name: "Student",
      description: "Students"
    )
    e.attribute_groups_json = attribute_groups
    e.property_schema_json = property_schema
    e.save!
    e
  end

  let(:attribute_groups) do
    [
      { "id" => "g_contact", "name" => "Contact", "icon" => "mail", "color" => "indigo" },
      { "id" => "g_profile", "name" => "Profile", "label" => "Profile Info", "icon" => "user", "color" => "teal" }
    ]
  end

  let(:property_schema) do
    [
      { "name" => "first name", "name_slug" => "first_name", "display_label" => "First name", "group_id" => "g_contact" },
      { "name" => "email", "name_slug" => "email", "group_id" => "g_contact" },
      { "name" => "grade", "name_slug" => "grade", "group_id" => "g_profile" },
      { "name" => "notes", "name_slug" => "notes" }
    ]
  end

  let(:entry) do
    create(
      :entity_entry,
      :with_data,
      customer: customer,
      entity: entity,
      entry_data: {
        "first_name" => "Alice",
        "email" => "alice@example.com",
        "grade" => "",
        "notes" => nil
      }
    )
  end

  let(:display) do
    Entities::EntryDisplay.new(
      entity: entity,
      entries: [entry],
      customer_id: entry.customer_id,
      audience: EntityAttributeAudience::ADMIN
    )
  end

  subject(:component) do
    described_class.new(entity: entity, entry: entry, display: display)
  end

  before { render_inline(component) }

  it "renders inline page content, not a slide-over drawer" do
    aggregate_failures do
      expect(page).not_to have_css("[data-controller='slide-over']")
      expect(page).not_to have_css("[role='dialog']")
      expect(page).not_to have_css(".fixed")
    end
  end

  it "renders every attribute group in authored order, ungrouped last, within one record sheet" do
    headings = page.all("section[id^='entry-section-'] h2").map { |h| h.text.strip }
    sheet = page.find("div.card.divide-y")
    aggregate_failures do
      expect(headings).to eq(["Contact", "Profile", I18n.t("admin_misc.entities.entry_detail.ungrouped")])
      expect(sheet.all(:xpath, "./section").map { |node| node[:id] }).to eq(%w[entry-section-1 entry-section-2 entry-section-3])
      expect(page).not_to have_css("section.card[id^='entry-section-']")
      expect(page).not_to have_css("#entry-associations-heading")
    end
  end

  it "lists each group's fields inside its own section without a field count" do
    contact = page.find("section#entry-section-1")
    aggregate_failures do
      expect(contact["aria-labelledby"]).to eq("entry-section-1-heading")
      expect(contact).to have_css("dt", text: "First name")
      expect(contact).to have_css("dt", text: "email")
      expect(contact).not_to have_css("dt", text: "grade")
      expect(contact).not_to have_text(I18n.t("admin_misc.entities.entry_detail.field_count", count: 2))
      expect(page.find("section#entry-section-2")).not_to have_text(
        I18n.t("admin_misc.entities.entry_detail.field_count", count: 1)
      )
    end
  end

  it "styles each group header with the group's icon and a soft tile of its color" do
    aggregate_failures do
      expect(page.find("section#entry-section-1 header span.bg-indigo-50.text-indigo-600")).to have_css("svg")
      expect(page).to have_css("section#entry-section-2 header span.bg-teal-50")
      expect(page).to have_css("section#entry-section-3 header span.bg-slate-100")
    end
  end

  it "indexes the sections in the sidebar with anchor links" do
    nav = page.find("aside nav")
    links = nav.all("a").map { |a| [a[:href], a.text.squish] }
    expect(links).to eq([
      ["#entry-section-1", "Contact 2"],
      ["#entry-section-2", "Profile 1"],
      ["#entry-section-3", "#{I18n.t('admin_misc.entities.entry_detail.ungrouped')} 1"]
    ])
  end

  context "with an association" do
    let(:association) do
      Entities::EntryAssociations::Association.new(
        bridge: Entity.new(id: 77), target: Entity.new(name: "Course", display_label: "Course", color: "amber"),
        source_slug: "student", columns: []
      )
    end
    let(:section) do
      Entities::EntryAssociations::Section.new(association: association, rows: [entry, entry], display: display,
                                               existing_target_ids: {})
    end

    it "renders the association card after the groups and indexes it last" do
      render_inline(described_class.new(entity: entity, entry: entry, display: display, associations: [section], writable: true))

      expect(page.all("section[id^='entry-']").map { |node| node[:id] }.last).to eq("entry-association-77")
      expect(page.find("aside nav").all("a").last.text.squish).to eq("Course 2")
      expect(page).to have_css("section#entry-association-77 a[href$='/associations/77/entries/new'][data-action='association-dialog#open']")
      expect(page).to have_css("dialog#entity-quick-add-dialog-0", visible: :all)
    end

    it "groups the association cards under an Associated records heading, one level down" do
      render_inline(described_class.new(entity: entity, entry: entry, display: display, associations: [section]))

      block = page.find("section[aria-labelledby='entry-associations-heading']")
      aggregate_failures do
        expect(block).to have_css("h2#entry-associations-heading",
                                  text: I18n.t("admin_misc.entities.association_entries.section_hint"))
        expect(block).to have_css("section#entry-association-77 h3#entry-association-77-heading", text: "Course")
      end
    end

    it "renders neither the dialog nor its wiring when not writable" do
      render_inline(described_class.new(entity: entity, entry: entry, display: display, associations: [section], writable: false))

      expect(page).not_to have_css("dialog", visible: :all)
      expect(page).not_to have_css("section#entry-association-77[data-controller]")
    end

    it "wires the section scroll to a rendered section it is asked to reveal" do
      render_inline(described_class.new(entity: entity, entry: entry, display: display, associations: [section],
                                        reveal_section: "entry-association-77", writable: true))

      scroller = page.find("[data-controller='section-scroll']")
      aggregate_failures do
        expect(scroller["data-section-scroll-id-value"]).to eq("entry-association-77")
        expect(scroller["data-section-scroll-highlight-class"]).to eq(described_class::REVEAL_HIGHLIGHT_CLASSES)
        expect(scroller["data-section-scroll-cue-class"]).to eq(described_class::REVEAL_CUE_CLASSES)
        expect(scroller).to have_css("section#entry-association-77 a[href$='/associations/77/entries/new'][data-section-scroll-target='cue']")
      end
    end

    it "ignores a reveal target that is not one of its sections" do
      render_inline(described_class.new(entity: entity, entry: entry, display: display, associations: [section],
                                        reveal_section: "entry-association-78"))

      expect(page).not_to have_css("[data-controller='section-scroll']")
      expect(page).not_to have_css("[data-section-scroll-id-value]")
    end

    it "hands a writable card's Add to the journey that adds its rows" do
      journey = build(:journey, key: "student_courses", name: "Add courses")
      starts = instance_double(Journeys::RecordStarts)
      allow(starts).to receive(:for_association).with(association).and_return(Journeys::RecordStarts::Start.new(journey: journey, page: nil,
                                                                                                                field: "student"))

      render_inline(described_class.new(entity: entity, entry: entry, display: display, associations: [section], writable: true,
                                        journey_starts: starts))
      expect(page).to have_css("section#entry-association-77 form[action$='/journeys/student_courses'] button[data-journey-start]")
      expect(page).not_to have_css("section#entry-association-77 a[href$='/associations/77/entries/new']")

      render_inline(described_class.new(entity: entity, entry: entry, display: display, associations: [section], journey_starts: starts))
      expect(page).not_to have_css("[data-journey-start]")
    end
  end

  context "when only one group has fields" do
    let(:attribute_groups) { [] }
    let(:property_schema) { [{ "name" => "notes", "name_slug" => "notes" }] }
    let(:entry) { create(:entity_entry, :with_data, customer: customer, entity: entity, entry_data: { "notes" => "Hi" }) }

    it "omits the section index" do
      expect(page).not_to have_css("aside nav")
    end
  end

  context "when no attribute has fields to show" do
    let(:property_schema) { [] }
    let(:entry) { create(:entity_entry, customer: customer, entity: entity) }

    it "skips empty groups and explains that there is nothing to show" do
      aggregate_failures do
        expect(page).not_to have_css("section[id^='entry-section-']")
        expect(page).to have_text(I18n.t("admin_misc.entities.entry_detail.no_fields"))
      end
    end
  end

  context "with long-form attributes" do
    let(:attribute_groups) { [] }
    let(:property_schema) do
      [
        { "name" => "Bio", "name_slug" => "bio", "html_type" => "textarea" },
        { "name" => "City", "name_slug" => "city", "html_type" => "text" }
      ]
    end
    let(:entry) do
      create(:entity_entry, :with_data, customer: customer, entity: entity,
             entry_data: { "bio" => "Line one\nLine two", "city" => "Paris" })
    end

    it "stacks textareas under their label and keeps their line breaks, beside-label for short values" do
      bio = page.find("dt", text: "Bio").find(:xpath, "..")
      city = page.find("dt", text: "City").find(:xpath, "..")
      aggregate_failures do
        expect(bio[:class]).not_to include("sm:grid")
        expect(bio).to have_css("dd.whitespace-pre-line")
        expect(city[:class]).to include("sm:grid")
      end
    end
  end

  it "renders group headings from group name or label" do
    aggregate_failures do
      expect(page).to have_text("Contact")
      expect(page).to have_text("Profile")
      expect(page).to have_text(I18n.t("admin_misc.entities.entry_detail.ungrouped"))
    end
  end

  context "when a group has only a label" do
    before do
      allow(entity).to receive(:grouped_property_schema).and_return([
        { group: { "label" => "Profile Info" }, attributes: [{ "name" => "grade", "name_slug" => "grade" }] }
      ])
      render_inline(described_class.new(entity: entity, entry: entry, display: display))
    end

    it "falls back to the label for the group heading" do
      expect(page).to have_text("Profile Info")
    end
  end

  it "renders authored attribute labels" do
    aggregate_failures do
      expect(page).to have_text("First name")
      expect(page).to have_text("email")
      expect(page).to have_text("grade")
      expect(page).to have_text("notes")
    end
  end

  it "renders attribute values and em-dash for blank values" do
    aggregate_failures do
      expect(page).to have_text("Alice")
      expect(page).to have_text("alice@example.com")
      expect(page).to have_css("dd.text-text-tertiary", text: "—", count: 2)
    end
  end

  it "renders the record details card in the sidebar" do
    card = page.find("aside section[aria-labelledby='entry-record-heading']")
    aggregate_failures do
      expect(card).to have_css("h2", text: I18n.t("admin_misc.entities.entry_detail.record_heading"))
      expect(card).to have_css("dt", text: I18n.t("admin_misc.entities.columns.id"))
      expect(card).to have_css("dd", text: "##{entry.id}")
      expect(card).to have_css("dt", text: I18n.t("admin_misc.entities.entry_detail.entity"))
      expect(card).to have_css("dd", text: entity.display_label)
      expect(card).to have_css("dt", text: I18n.t("admin_misc.entities.columns.created_at"))
      expect(card).to have_css("dt", text: I18n.t("admin_misc.entities.columns.updated_at"))
      expect(card).to have_css("time[datetime='#{entry.created_at.iso8601}']")
      expect(card).to have_css("time[datetime='#{entry.updated_at.iso8601}']")
    end
  end

  it "renders the fields before the sidebar, without an Account card, for a non-person entity" do
    columns = page.find("div.grid").all(:xpath, "./*").map { |node| node.tag_name }
    aside = page.find("aside")
    aggregate_failures do
      expect(page).not_to have_css("#entry-account-heading")
      expect(columns).to eq(%w[div aside])
      expect(aside[:class]).not_to include("lg:row-start-2")
      expect(aside.all("section").first["aria-labelledby"]).to eq("entry-record-heading")
    end
  end

  context "when the entity is a person" do
    before do
      allow(entity).to receive(:person?).and_return(true)
      allow(entry).to receive(:user).and_return(nil)
      render_inline(described_class.new(entity: entity, entry: entry, display: display, writable: true))
    end

    it "leads with the Account card, then the fields, then the record details, sidebar-placed on desktop" do
      grid = page.find("div.grid")
      account, main, aside = grid.all(:xpath, "./*")
      aggregate_failures do
        expect(grid[:class]).to include("lg:grid-rows-[auto_1fr]")
        expect(account).to have_css("#entry-account-heading", text: I18n.t("comp_admin.person_link.heading"))
        expect(account[:class]).to include("lg:col-start-2", "lg:row-start-1")
        expect(main).to have_css("section#entry-section-1")
        expect(main[:class]).to include("lg:col-start-1", "lg:row-span-2")
        expect(aside.tag_name).to eq("aside")
        expect(aside[:class]).to include("lg:col-start-2", "lg:row-start-2")
        expect(aside).to have_css("section[aria-labelledby='entry-record-heading']")
        expect(aside).not_to have_css("#entry-account-heading")
      end
    end
  end

  it "does not render form controls" do
    aggregate_failures do
      expect(page).not_to have_css("form")
      expect(page).not_to have_css("input")
      expect(page).not_to have_css("textarea")
      expect(page).not_to have_css("select")
      expect(page).not_to have_css("button")
    end
  end

  context "when the entity has option and calculated attributes" do
    let(:attribute_groups) { [] }
    let(:property_schema) do
      [
        { "name" => "Mode", "name_slug" => "mode", "html_type" => "select",
          "config" => { "options" => [{ "label" => "In person", "value" => "in_person" }] } },
        { "name" => "Seats", "name_slug" => "seats", "html_type" => "number" },
        { "name" => "Double seats", "name_slug" => "double_seats", "type" => "Calculated", "html_type" => "number",
          "formula" => "seats * 2" }
      ]
    end
    let(:entry) do
      create(
        :entity_entry,
        :with_data,
        customer: customer,
        entity: entity,
        entry_data: { "mode" => "in_person", "seats" => 12 }
      )
    end

    it "shows option labels and calculated values, not raw option codes" do
      aggregate_failures do
        expect(page).to have_text("In person")
        expect(page).to have_text("24")
        expect(page).not_to have_text("in_person")
      end
    end
  end
end
