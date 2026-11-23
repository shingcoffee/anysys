# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityDomains::JourneyPlanner do
  let(:customer) { create(:customer) }

  include_context "student course association"

  def note_entity(name: "Note", reference: { "type" => "EntityReference", "entity_id" => student_entity.id.to_s })
    create(:entity, customer: customer, name: name, display_label: name, property_schema: [
      { "name" => "Student", "name_slug" => "student", "html_type" => "select" }.merge(reference),
      { "name" => "Body", "name_slug" => "body", "html_type" => "text" }
    ].to_json)
  end

  def child_of(parent, name, extra: [])
    create(:entity, customer: customer, name: name, display_label: name, property_schema: [
      { "name" => parent.name, "name_slug" => parent.name.downcase, "html_type" => "select", "type" => "EntityReference",
        "entity_id" => parent.id.to_s },
      *extra
    ].to_json)
  end

  def link_note_to_course(note)
    note.associations_json = [{ "target_entity_id" => course_entity.id, "target_entity_name" => course_entity.name,
                                "display_field" => "code", "display_field_label" => "Code",
                                "additional_attributes" => [{ "name" => "Quantity", "name_slug" => "quantity", "html_type" => "number" }] }]
    note.save!
    note.sync_bridge_entities!
    Entity.find_by!(name: "assoc_note_course", customer_id: customer.id)
  end

  def plan(*entities) = described_class.new(customer_id: customer.id, entities: entities)
  def school = plan(student_entity, course_entity, bridge_entity)
  def step_row(step) = [step.entity, step.parent_slug, step.label, step.link, step.page_key]

  def make_person!(entity)
    person_model = EntityDefinitions::Capabilities::PERSON_MODEL
    enable_module!("authentication", customer).set_extendable_model!(person_model, true)
    entity.update_columns(extended_model: person_model)
  end

  describe "journeys that start with a new record" do
    it "offers every record type one, the one collecting the most related rows first" do
      candidates = school.candidates.select(&:create?)

      expect(candidates.map(&:key)).to eq(["create-#{student_entity.id}", "create-#{course_entity.id}"])
      expect(candidates.first).to have_attributes(
        audience: "admin", start: student_entity, page_key: "student_new", journey_key: "student_journey", left_out: [],
        name: I18n.t("journeys.generate.journey_name", start: "Student")
      )
      expect(candidates.first.steps.map { |step| step_row(step) }).to eq([[bridge_entity, "student", "Course", true, "student_add_course"]])
    end

    it "adds the link's other side from the course too, picking the student that declares it" do
      course = school.find("create-#{course_entity.id}")

      expect(course.steps.map { |step| step_row(step) }).to eq([[bridge_entity, "course", "Student", true, "course_add_student"]])
    end

    it "treats a child record type that references the start as a step, after the links" do
      note = note_entity
      steps = plan(student_entity, course_entity, bridge_entity, note).find("create-#{student_entity.id}").steps

      expect(steps.map { |step| step_row(step) }).to eq([[bridge_entity, "student", "Course", true, "student_add_course"],
                                                         [note, "student", "Note", false, "student_add_note"]])
    end

    it "recognises a child that references the start through a record picker" do
      note = note_entity(reference: { "type" => "String",
                                      "config" => { "options_source" => "entity_entries", "entity_id" => student_entity.id.to_s,
                                                    "label_field" => "full_name" } })
      steps = plan(student_entity, note).find("create-#{student_entity.id}").steps

      expect(steps.map { |step| [step.entity, step.parent_slug] }).to eq([[note, "student"]])
    end

    it "still offers a lone record type, with nothing to add after it" do
      expect(plan(course_entity).candidates.map { |candidate| [candidate.key, candidate.steps] }).to eq([["create-#{course_entity.id}", []]])
    end

    it "skips a link whose bridge is outside the domain" do
      expect(plan(student_entity, course_entity).candidates.flat_map(&:steps)).to be_empty
    end

    it "never starts at a bridge" do
      expect(school.candidates.map(&:start)).not_to include(bridge_entity)
    end
  end

  describe "journeys that start from an existing record" do
    it "offers one per related row a record's page adds, as its section's Add does" do
      candidates = school.candidates.select(&:record?)

      expect(candidates.map(&:key)).to eq(["record-#{course_entity.id}-#{bridge_entity.id}-course",
                                           "record-#{student_entity.id}-#{bridge_entity.id}-student"])
      expect(candidates.last).to have_attributes(
        audience: "admin", start: student_entity, page_key: nil, journey_key: "student_add_course_journey", left_out: [],
        name: I18n.t("journeys.generate.relate_page_name", target: "Course", parent: "Student")
      )
      expect(candidates.last.steps.map { |step| step_row(step) }).to eq([[bridge_entity, "student", "Course", true, "student_add_course"]])
    end
  end

  context "when the link rows are owned by the member that is the student" do
    before { make_person!(student_entity) }

    it "only links from the owner's side for admins" do
      expect(school.find("create-#{course_entity.id}").steps).to be_empty
      expect(school.candidates.select(&:record?).map(&:start)).to eq([student_entity])
    end

    it "lets a member choose a course, leaving to admins what they see but members needn't fill" do
      member = school.candidates.select(&:member?)

      expect(member.size).to eq(1)
      expect(member.first).to have_attributes(
        key: "member-#{bridge_entity.id}", audience: "member", start: bridge_entity, steps: [],
        name: I18n.t("journeys.generate.member_choose_name", target: "Course"),
        page_key: "member_choose_course", journey_key: "member_choose_course_journey"
      )
      expect(member.first.left_out.map { |attribute| attribute["name_slug"] }).to eq(%w[grade])
    end

    it "lets a member add a record they own" do
      note = note_entity
      candidate = plan(student_entity, note).find("member-#{note.id}")

      expect(candidate).to have_attributes(
        audience: "member", start: note, steps: [], left_out: [], page_key: "member_new_note", journey_key: "member_new_note_journey",
        name: I18n.t("journeys.generate.member_new_name", entity: "Note")
      )
    end

    it "lets a member add the rows that hang off a record they own, on member pages of their own" do
      note = note_entity
      note_bridge = link_note_to_course(note)
      line = child_of(note, "Line")
      candidate = plan(student_entity, course_entity, note, note_bridge, line).find("member-#{note.id}")

      expect(candidate.steps.map { |step| step_row(step) }).to eq([[note_bridge, "note", "Course", true, "member_note_add_course"],
                                                                   [line, "note", "Line", false, "member_note_add_line"]])
      expect(candidate).to have_attributes(page_key: "member_new_note", journey_key: "member_new_note_journey")
    end

    it "keeps the admin pages' keys for those rows on the admin journeys" do
      note = note_entity
      line = child_of(note, "Line")

      expect(plan(student_entity, note, line).find("create-#{note.id}").steps.map(&:page_key)).to eq(["note_add_line"])
    end

    it "adds rows the same person owns, but not rows owned ambiguously or pointing at private records" do
      note = note_entity
      student_ref = { "html_type" => "select", "type" => "EntityReference", "entity_id" => student_entity.id.to_s }
      owned = child_of(note, "Reply", extra: [student_ref.merge("name" => "Author", "name_slug" => "author")])
      shared = child_of(note, "Review", extra: [student_ref.merge("name" => "Author", "name_slug" => "author"),
                                                student_ref.merge("name" => "Reviewer", "name_slug" => "reviewer")])
      pointer = child_of(note, "Flag", extra: [{ "name" => "Review", "name_slug" => "review", "html_type" => "select",
                                                 "type" => "EntityReference", "entity_id" => shared.id.to_s }])
      candidate = plan(student_entity, note, owned, shared, pointer).find("member-#{note.id}")

      expect(People::Ownership.kind(shared)).to eq(:private)
      expect(candidate.steps.map(&:entity)).to eq([owned])
    end

    it "opens only the person's own create journey with creating its user account" do
      expect(school.find("create-#{student_entity.id}")).to be_user_first
      expect(school.find("create-#{course_entity.id}")).not_to be_user_first
      expect(school.candidates.select(&:record?)).to all(satisfy { |candidate| !candidate.user_first? })
    end

    it "offers a public sign-up as the person for each member journey to continue on" do
      note = note_entity
      domain = plan(student_entity, course_entity, bridge_entity, note)
      public = domain.candidates.select(&:public?)

      expect(public.map(&:key)).to eq(["public-#{bridge_entity.id}", "public-#{note.id}"])
      expect(public.first).to have_attributes(
        audience: "public", start: student_entity, steps: [], left_out: [], follow: domain.find("member-#{bridge_entity.id}"),
        page_key: "signup_choose_course", journey_key: "signup_choose_course_journey",
        name: I18n.t("journeys.generate.signup_then_name", next: I18n.t("journeys.generate.member_choose_name", target: "Course"))
      )
      expect(public.last).to have_attributes(page_key: "signup_new_note", follow: domain.find("member-#{note.id}"))
      expect(public).to all(satisfy { |candidate| !candidate.user_first? })
    end

    it "offers one plain public sign-up when no member journey follows" do
      public = plan(student_entity, course_entity).candidates.select(&:public?)

      expect(public.size).to eq(1)
      expect(public.first).to have_attributes(
        key: "public-#{student_entity.id}", audience: "public", start: student_entity, follow: nil,
        page_key: "signup_student", journey_key: "signup_student_journey",
        name: I18n.t("journeys.generate.signup_name", entity: "Student")
      )
    end
  end

  it "offers members nothing when no record type is owned by a member" do
    expect(school.candidates.select(&:member?)).to be_empty
  end

  it "offers no public sign-up and no user step when the domain has no person" do
    expect(school.candidates.select(&:public?)).to be_empty
    expect(school.candidates).to all(satisfy { |candidate| !candidate.user_first? })
  end

  it "finds a candidate by key and nothing for an unknown one" do
    expect(school.find("create-#{student_entity.id}").start).to eq(student_entity)
    expect(school.find("create-0")).to be_nil
    expect(described_class.call(customer_id: customer.id, entities: [course_entity]).map(&:key)).to eq(["create-#{course_entity.id}"])
  end
end
