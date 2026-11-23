# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Modules::Authentication::UserProfileCardComponent, type: :component do
  let(:customer_id) { 12_345_678 }
  let(:fields) do
    [
      { "name_slug" => "name", "name" => "Name", "display_label" => "Preferred name", "html_type" => "text" },
      { "name_slug" => "mode", "name" => "Mode", "html_type" => "select", "config" => { "options" => [{ "value" => "in_person", "label" => "In person" }] } },
      { "name_slug" => "seats", "name" => "Seats", "html_type" => "number" },
      { "name_slug" => "active", "name" => "Participating", "html_type" => "switch" },
      { "name_slug" => "notes", "name" => "Notes", "html_type" => "textarea" },
      { "name_slug" => "interests", "name" => "Interests", "html_type" => "multi-select", "config" => { "options" => [{ "value" => "arts", "label" => "Arts" }] } },
      { "name_slug" => "blank", "name" => "", "html_type" => "text" }
    ]
  end
  let(:entity) do
    record = Entity.new(id: 93, name: "Student", display_label: "Student profile", icon: "user", color: "teal")
    record.property_schema_json = fields + [{ "name_slug" => "private_notes", "display_label" => "Private notes", "visibility" => ["member"] }]
    record
  end
  let(:entry) do
    EntityEntry.new(id: 55, entity: entity, customer_id: customer_id, updated_at: Time.zone.parse("2026-11-01 12:00"),
      data: { name: "Alice", mode: "in_person", seats: 0, active: false, notes: "Line one\nLine two", interests: ["arts"], blank: "", private_notes: "Secret value" }.to_json)
  end
  let(:display) { Entities::EntryDisplay.new(entity: entity, entries: [entry], customer_id: customer_id, audience: EntityAttributeAudience::ADMIN) }
  let(:groups) do
    [
      { key: "contact", heading: "Contact", icon: "mail", color: "indigo", fields: fields.first(4) },
      { key: "empty", heading: "Empty hidden group", icon: nil, color: nil, fields: [] },
      { key: "other", heading: nil, icon: nil, color: nil, fields: fields.drop(4) }
    ]
  end
  let(:user) { build_stubbed(:user, :member, id: 42, customer_id: customer_id, status: "active") }
  let(:profile) do
    Authentication::UserDomainProfiles::Profile.new(entity: entity, entry: entry, display: display, groups: groups,
                                                    associations: [], form: nil)
  end
  let(:missing) { profile.with(entry: nil, display: nil, groups: []) }

  def render_profile(target: profile, account: user)
    render_inline(described_class.new(profile: target, user: account, customer_id: customer_id, id_prefix: "user-42-domain-7"))
  end

  it "renders only projected groups in schema order as the entry page's flat group sections, without a separate link status" do
    render_profile

    expect(page).to have_css("article#user-42-domain-7-entity-93[aria-labelledby='user-42-domain-7-entity-93-heading']")
    expect(page).to have_css("h4", text: "Student profile")
    expect(page).not_to have_text(I18n.t("comp_admin.person_link.badge_linked"))
    expect(page).not_to have_text(I18n.t("admin_misc.entities.entry_detail.title", id: entry.id))
    expect(page.all("h5").map(&:text).map(&:strip)).to eq(["Contact", I18n.t("admin_misc.entities.entry_detail.ungrouped")])
    expect(page).to have_css("section#user-42-domain-7-entity-93-group-1 header h5#user-42-domain-7-entity-93-group-1-heading")
    expect(page).not_to have_css("section.card")
    expect(page).not_to have_css(".bg-canvas")
    expect(page).not_to have_css("details")
    expect(page).to have_css("dt", text: "Preferred name")
    expect(page).to have_css("dt", text: "Mode")
    expect(page).to have_css("dt", text: "blank", exact_text: true)
    expect(page).not_to have_text("Empty hidden group")
  end

  it "uses the prepared display for readable option and boolean values, preserving zero and blank styling" do
    render_profile

    expect(page).to have_css("dd", text: "In person", exact_text: true)
    expect(page).to have_css("dd", text: "Arts", exact_text: true)
    expect(page).to have_css("dd.text-text-primary", text: "0", exact_text: true)
    expect(page).to have_css("dd.text-text-primary", text: I18n.t("common.labels.no"), exact_text: true)
    expect(page).to have_css("dd.text-text-tertiary", text: I18n.t("common.labels.em_dash"), count: 1)
    expect(page).not_to have_text("in_person")
  end

  it "delegates reference and derived labels to the supplied display instead of reading raw JSON" do
    allow(display).to receive(:text).and_call_original
    allow(display).to receive(:text).with(entry, "mode").and_return("Referenced programme")
    allow(display).to receive(:text).with(entry, "seats").and_return("24")
    render_profile

    expect(page).to have_css("dd", text: "Referenced programme", exact_text: true)
    expect(page).to have_css("dd", text: "24", exact_text: true)
  end

  it "does not rediscover or evaluate fields omitted by the visibility-filtered projection" do
    expect(entity).not_to receive(:grouped_property_schema)
    expect(display).not_to receive(:text).with(entry, "private_notes")
    render_profile

    expect(page).not_to have_text("Private notes")
    expect(page).not_to have_text("Secret value")
  end

  it "stacks long-form fields under their label and preserves line breaks in wrapping values" do
    rendered = render_profile

    %w[Notes Interests].each do |label|
      field = page.find("dt", text: label).find(:xpath, "..")
      expect(field[:class]).not_to include("sm:grid")
      expect(field).to have_css("dd.whitespace-pre-line")
    end
    notes = rendered.css("dt").find { |node| node.text == "Notes" }.parent.at_css("dd")
    expect(notes.text).to eq("Line one\nLine two")
    expect(notes["class"]).to include("break-words", "[overflow-wrap:anywhere]")
    expect(page.find("dt", text: "Mode").find(:xpath, "..")[:class]).to include("sm:grid")
  end

  it "omits the entity-name row when the domain section is this profile alone" do
    render_inline(described_class.new(profile: profile, user: user, customer_id: customer_id,
                                      id_prefix: "user-42-domain-7", identity: false))

    heading = page.find("h4", visible: :all)
    expect(heading.text).to eq("Student profile")
    expect(heading[:class]).to eq("sr-only")
    expect(page).to have_css("h4.sr-only", count: 1, visible: :all)
    expect(page).not_to have_link(I18n.t("admin_modules.users.show.profiles.view_entry"))
    expect(page).not_to have_text(I18n.t("common.labels.updated_at"))
    expect(page).to have_css("dt", text: "Preferred name")
  end

  it "renders record metadata and a same-tab, explicitly tenant-scoped entry link with an informative accessible name" do
    render_profile

    label = I18n.t("admin_modules.users.show.profiles.view_entry_label", entity: entity.display_label, id: entry.id)
    expect(page).to have_link(I18n.t("admin_modules.users.show.profiles.view_entry"), href: "/12345678/admin/entities/93/entries/55")
    expect(page.find("a")["aria-label"]).to eq(label)
    expect(page.find("a")[:target]).to be_nil
    expect(page.find("a")[:class]).to include("min-h-11", "w-full", "sm:w-auto")
    expect(page).not_to have_text(I18n.t("admin_misc.entities.entry_detail.title", id: 55))
    expect(page).to have_text(I18n.t("common.labels.updated_at"))
    expect(page).to have_css("time[datetime='#{entry.updated_at.iso8601}']")
  end

  it "uses the URL tenant even for a shared entity and an entry carrying a different customer ID" do
    entity.customer_id = nil
    entry.customer_id = 9999
    render_profile

    expect(page).to have_css("a[href='/12345678/admin/entities/93/entries/55']")
    expect(page).not_to have_css("a[href^='/9999/']")
  end

  it "renders a missing profile without a create form neutrally, with no entry-list link and no record data" do
    render_profile(target: missing)

    expect(page).not_to have_text(I18n.t("comp_admin.person_link.badge_not_linked"))
    expect(page).to have_text(I18n.t("admin_modules.users.show.profiles.missing_description", entity: entity.display_label))
    expect(page).not_to have_css("a, form, dl, time")
    expect(page).not_to have_text("Alice")
  end

  it "asks to activate an inactive account instead of offering a profile it could not link" do
    render_profile(target: missing, account: build_stubbed(:user, :member, :inactive, id: 42, customer_id: customer_id))

    expect(page).to have_text(I18n.t("admin_modules.users.show.profiles.inactive_description", entity: entity.display_label))
    expect(page).not_to have_css("form")
  end

  context "with a create form" do
    let(:customer) { create(:customer) }
    let(:customer_id) { customer.id }
    let(:entity) do
      create(:entity, customer: customer, name: "Student", display_label: "Student profile", property_schema: [
        { name: "Student number", name_slug: "student_number", html_type: "text" },
        { name: "Major", name_slug: "major", html_type: "text" }
      ].to_json)
    end
    let(:form) { Entities::EntryForm.new(entity: entity, customer: customer) }

    it "opens the entry form from a Create profile button in a closed modal titled for the entity and user" do
      render_profile(target: missing.with(form: form))

      card_id = "user-42-domain-7-entity-#{entity.id}"
      row = page.find("##{card_id} > [data-controller='modal-dialog']")
      expect(row["data-modal-dialog-open-value"]).to eq("false")
      expect(page).not_to have_css("details, summary", visible: :all)
      trigger = row.find("button[data-action='modal-dialog#open']")
      expect(trigger.text.squish).to eq(I18n.t("admin_modules.users.show.profiles.create_profile"))
      expect(trigger["type"]).to eq("button")
      expect(trigger["aria-controls"]).to eq("#{card_id}-dialog")
      expect(trigger["aria-haspopup"]).to eq("dialog")
      dialog = row.find("dialog##{card_id}-dialog[data-modal-dialog-target='dialog']", visible: :all)
      expect(dialog[:open]).to be_nil
      expect(dialog).to have_css("h2##{card_id}-dialog-title",
                                 text: I18n.t("admin_modules.users.show.profiles.create_title", entity: "Student profile"), visible: :all)
      expect(dialog).to have_text(user.display_name)
      expect(dialog).to have_css("form", visible: :all)
    end

    it "renders the entity's entry form, posting to the user's profile endpoint, with a Cancel that closes the modal" do
      render_profile(target: missing.with(form: form))

      card_id = "user-42-domain-7-entity-#{entity.id}"
      expect(page).to have_text(I18n.t("admin_modules.users.show.profiles.create_description", entity: "Student profile"))
      form_node = page.find("##{card_id} form[action='/#{customer.id}/admin/modules/authentication/users/42/profiles?entity_id=#{entity.id}'][method='post']", visible: :all)
      expect(form_node).to have_field("#{card_id}-form_student_number", visible: :all)
      expect(form_node).to have_field("#{card_id}-form_major", visible: :all)
      expect(form_node.find("input#{"[name='entry[data][student_number]']"}", visible: :all)).to be_present
      expect(form_node.find("button[type='submit']", visible: :all).text.squish).to eq(I18n.t("admin_modules.users.show.profiles.create_profile"))
      expect(form_node.find("button[data-action='modal-dialog#close']", visible: :all).text.squish).to eq(I18n.t("common.actions.cancel"))
      expect(page).not_to have_css("a", visible: :all)
    end

    it "opens the modal on render and keeps submitted values and link errors after a failed submission" do
      failed = Entities::EntryForm.new(entity: entity, customer: customer, params: { "student_number" => "S-1" })
      failed.add_errors!("base" => [I18n.t("people.errors.user_unavailable")])
      render_profile(target: missing.with(form: failed))

      expect(page).to have_css("[data-controller='modal-dialog'][data-modal-dialog-open-value='true']")
      expect(page).to have_css("dialog [role='alert']", text: I18n.t("people.errors.user_unavailable"), visible: :all)
      expect(page).to have_field("user-42-domain-7-entity-#{entity.id}-form_student_number", with: "S-1", visible: :all)
    end

    it "localizes the create copy, modal title and buttons in Simplified Chinese" do
      I18n.with_locale(:"zh-CN") do
        render_profile(target: missing.with(form: form))
        expect(page).to have_text(I18n.t("admin_modules.users.show.profiles.create_description", entity: "Student profile"))
        expect(page).to have_button(I18n.t("admin_modules.users.show.profiles.create_profile"), count: 2, visible: :all)
        expect(page).to have_css("h2", text: I18n.t("admin_modules.users.show.profiles.create_title", entity: "Student profile"), visible: :all)
        expect(page).not_to have_css(".translation_missing", visible: :all)
      end
    end
  end

  describe "association rows" do
    let(:target) { Entity.new(id: 94, name: "Course", display_label: "Course", icon: "book", color: "teal") }
    let(:columns) do
      [
        { "name_slug" => "course", "display_label" => "Course", "type" => Entity::ENTITY_REFERENCE_TYPE,
          "config" => { "options_source" => Entities::ReferenceLabels::OPTIONS_SOURCE, "entity_id" => 94 } },
        { "name_slug" => "score", "display_label" => "Score", "html_type" => "number" },
        { "name_slug" => "notes", "display_label" => "Notes", "html_type" => "textarea" }
      ]
    end
    let(:association) do
      Entities::EntryAssociations::Association.new(bridge: Entity.new(id: 95, name: "Enrollment"), target: target,
                                                    source_slug: "student", columns: columns)
    end
    let(:rows) do
      [EntityEntry.new(id: 301, data: { course: "77", score: 91 }.to_json),
       EntityEntry.new(id: 302, data: { course: "78" }.to_json)]
    end
    let(:row_display) do
      instance_double(Entities::EntryDisplay).tap do |double|
        allow(double).to receive(:text) do |row, slug|
          { [301, "course"] => "Algebra", [301, "score"] => "91", [302, "course"] => "Deleted course" }
            .fetch([row.id, slug], I18n.t("common.labels.em_dash"))
        end
      end
    end
    let(:section) do
      Entities::EntryAssociations::Section.new(association: association, rows: rows, display: row_display,
                                               existing_target_ids: { "course" => Set["77"] })
    end

    it "lists each linked record read-only with its bridge attributes, linking only existing targets" do
      render_profile(target: profile.with(associations: [section]))

      block = page.find("section#user-42-domain-7-entity-93-association-95[aria-labelledby='user-42-domain-7-entity-93-association-95-heading']")
      expect(block[:class].split).not_to include("card")
      expect(block.find(:xpath, "preceding-sibling::p[1]")).to have_text(I18n.t("admin_misc.entities.association_entries.section_hint"))
      expect(block).to have_css("header h5", text: "Course")
      expect(block).to have_css("table thead th", text: "Score")
      expect(block).to have_css("table tbody td a[href='/12345678/admin/entities/94/entries/77']", text: "Algebra")
      expect(block).to have_text(I18n.t("admin_misc.entities.association_entries.entry_count", count: 2))
      expect(block).to have_link("Algebra", href: "/12345678/admin/entities/94/entries/77")
      expect(block).to have_css("p", text: "Deleted course")
      expect(block).not_to have_link("Deleted course")
      expect(block).to have_css("dt", text: "Score")
      expect(block).to have_css("dd.text-text-primary", text: "91")
      expect(block).to have_css("dd.text-text-tertiary", text: I18n.t("common.labels.em_dash"))
      expect(block).not_to have_css("form, [data-turbo-method], a[href*='/associations/']")
    end

    it "explains an empty association and does not report the profile as fieldless" do
      empty = Entities::EntryAssociations::Section.new(**section.to_h, rows: [])
      render_profile(target: profile.with(groups: [], associations: [empty]))

      expect(page).to have_text(I18n.t("admin_misc.entities.association_entries.empty_title", name: "Course"))
      expect(page).not_to have_text(I18n.t("admin_misc.entities.association_entries.empty_hint", name: "Course"))
      expect(page).not_to have_text(I18n.t("admin_modules.users.show.profiles.no_fields"))
    end

    it "offers Add <target> through the page's quick-add dialog when the viewer may write association rows" do
      render_profile(target: profile.with(associations: [section], associations_writable: true))

      block = page.find("section#user-42-domain-7-entity-93-association-95")
      expect(block["data-controller"]).to eq("association-dialog")
      expect(block["data-association-dialog-entity-quick-add-dialog-outlet"]).to eq("#entity-quick-add-dialog-0")
      add_label = I18n.t("admin_misc.entities.association_entries.new_title", name: "Course")
      add = block.find_link(add_label, href: "/12345678/admin/entities/93/entries/55/associations/95/entries/new")
      expect(add["data-action"]).to eq("association-dialog#open")
      expect(add["data-association-dialog-title-param"]).to eq(add_label)
      expect(add["data-turbo-prefetch"]).to eq("false")
      expect(add[:class]).to include("min-h-11", "w-full", "sm:w-auto")

      return_to = "/12345678/admin/modules/authentication/users/42#user-42-domain-7-entity-93-association-95"
      edit = block.find("table a[href*='/associations/95/entries/301/edit']")
      expect(edit["data-action"]).to eq("association-dialog#open")
      expect(edit["data-turbo-prefetch"]).to eq("false")
      expect(Rack::Utils.parse_query(URI.parse(edit[:href]).query)).to include("return_to" => return_to)
      destroy = block.find("table a[data-turbo-method='delete'][href*='/associations/95/entries/301']")
      expect(destroy["data-turbo-confirm"]).to eq(I18n.t("admin_misc.entities.association_entries.delete_confirm"))
      expect(Rack::Utils.parse_query(URI.parse(destroy[:href]).query)).to include("return_to" => return_to)
    end

    it "points an empty writable association at Add" do
      empty = Entities::EntryAssociations::Section.new(**section.to_h, rows: [])
      render_profile(target: profile.with(associations: [empty], associations_writable: true))

      expect(page).to have_text(I18n.t("admin_misc.entities.association_entries.empty_hint", name: "Course"))
      expect(page).to have_link(I18n.t("admin_misc.entities.association_entries.new_title", name: "Course"))
    end
  end

  it "distinguishes a linked profile without visible fields from a missing link" do
    render_profile(target: profile.with(groups: []))

    expect(page).to have_text(I18n.t("admin_modules.users.show.profiles.no_fields"))
    expect(page).not_to have_text(I18n.t("comp_admin.person_link.badge_linked"))
    expect(page).to have_css("a[href='/12345678/admin/entities/93/entries/55']")
    expect(page).not_to have_text(I18n.t("comp_admin.person_link.badge_not_linked"))
    expect(page).not_to have_text(I18n.t("admin_modules.users.show.profiles.missing_description", entity: entity.display_label))
  end

  it "escapes authored entity, group, field and value text" do
    allow(display).to receive(:text).and_call_original
    entity.display_label = "<script>entity()</script>"
    groups.first[:heading] = "<img src=x onerror=group()>"
    fields.first["display_label"] = "<script>field()</script>"
    allow(display).to receive(:text).with(entry, "name").and_return("<img src=x onerror=value()>")
    render_profile

    expect(page).to have_css("h4", text: entity.display_label)
    expect(page).to have_css("h5", text: groups.first[:heading])
    expect(page).to have_css("dt", text: fields.first["display_label"])
    expect(page).to have_css("dd", text: "<img src=x onerror=value()>")
    expect(page).not_to have_css("script, img")
  end

  it "localizes boolean values, ungrouped headings, missing copy and the entry link label in Simplified Chinese" do
    I18n.with_locale(:"zh-CN") do
      render_profile
      expect(page).to have_css("dd", text: I18n.t("common.labels.no"), exact_text: true)
      expect(page).to have_css("h5", text: I18n.t("admin_misc.entities.entry_detail.ungrouped"))
      expect(page.find("a")["aria-label"]).to eq(I18n.t("admin_modules.users.show.profiles.view_entry_label", entity: entity.display_label, id: 55))
      expect(page).to have_link(I18n.t("admin_modules.users.show.profiles.view_entry"))

      render_profile(target: missing)
      expect(page).to have_text(I18n.t("admin_modules.users.show.profiles.missing_description", entity: entity.display_label))
      expect(page).not_to have_css("a")
    end
  end
end
