# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::AudienceGuard do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }

  let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
  let(:member) { create(:user, :member, customer: customer) }
  let(:other_member) { create(:user, :member, customer: customer) }
  let(:admin) { create(:user, :admin, customer: customer) }

  let(:student) { Entity.find_by!(customer_id: customer.id, name: "Student") }
  let(:teacher) { Entity.find_by!(customer_id: customer.id, name: "Teacher") }
  let(:course) { Entity.find_by!(customer_id: customer.id, name: "Course") }
  let(:enrollment) { Entity.find_by!(customer_id: customer.id, name: "Enrollment") }
  let(:assignment) { Entity.find_by!(customer_id: customer.id, name: "Assignment") }
  let(:review) { Entity.find_by!(customer_id: customer.id, name: "Review") }

  before do
    enable_module!("authentication", customer).set_extendable_model!(person_model, true)

    name_field = [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json
    create(:entity, customer: customer, name: "Student", extended_model: person_model, property_schema: name_field)
    create(:entity, customer: customer, name: "Teacher", extended_model: person_model, property_schema: name_field)
    create(:entity, customer: customer, name: "Course",
           property_schema: [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json)

    create(:entity, customer: customer, name: "Enrollment", category: :bridge, property_schema: [
      { "name" => "Student", "name_slug" => "student", "type" => "EntityReference", "entity_id" => student.id },
      { "name" => "Course", "name_slug" => "course", "type" => "EntityReference", "entity_id" => course.id }
    ].to_json)
    student.update!(associations: [{
      "target_entity_id" => course.id, "target_entity_name" => course.name,
      "bridge_entity_id" => enrollment.id, "bridge_entity_name" => enrollment.name,
      "display_field" => "title", "display_field_label" => "Title"
    }].to_json)
    course.update!(associations: [{
      "target_entity_id" => student.id, "target_entity_name" => student.name,
      "bridge_entity_id" => enrollment.id, "bridge_entity_name" => enrollment.name,
      "display_field" => "name", "display_field_label" => "Name"
    }].to_json)

    create(:entity, customer: customer, name: "Assignment", property_schema: [
      { "name" => "Title", "name_slug" => "title", "html_type" => "text" },
      person_select("student", student, owner: true),
      person_select("mentor", teacher, name: "Mentor")
    ].to_json)
    create(:entity, customer: customer, name: "Review", property_schema: [
      person_select("student", student),
      person_select("teacher", teacher)
    ].to_json)
  end

  describe "member audience" do
    let!(:own_student) { create(:entity_entry, entity: student, customer: customer, user: member) }
    let!(:peer_student) { create(:entity_entry, entity: student, customer: customer, user: other_member) }
    let!(:own_teacher) { create(:entity_entry, entity: teacher, customer: customer, user: member) }
    let!(:peer_teacher) { create(:entity_entry, entity: teacher, customer: customer, user: other_member) }
    let!(:own_course) { create(:entity_entry, :with_data, entity: course, customer: customer, entry_data: { "title" => "A" }) }

    it "replaces a forged owner reference with the member's linked person entry" do
      result = guard(
        entity: assignment, audience: "member", viewer: member,
        primary: { "title" => "Essay", "student" => peer_student.id.to_s }
      )

      expect(result.error).to be_nil
      expect(result.primary).to include("student" => own_student.id.to_s, "title" => "Essay")
    end

    it "binds the owner on an owned bridge submitted as the primary" do
      result = guard(
        entity: enrollment, audience: "member", viewer: member,
        primary: { "student" => peer_student.id.to_s, "course" => own_course.id.to_s }
      )

      expect(result.error).to be_nil
      expect(result.primary).to include("student" => own_student.id.to_s, "course" => own_course.id.to_s)
    end

    it "rejects a member with no linked person profile" do
      unlinkable = create(:user, :member, customer: customer)

      result = guard(
        entity: assignment, audience: "member", viewer: unlinkable,
        primary: { "title" => "Essay", "student" => peer_student.id.to_s }
      )

      expect(result).to be_rejected
      expect(result.error).to eq(
        I18n.t("common.errors.dynamic.profile_required", entity: student.display_label)
      )
      expect(result.primary["student"]).to eq(peer_student.id.to_s)
    end

    it "rejects a mentor outside the member's scope" do
      result = guard(
        entity: assignment, audience: "member", viewer: member,
        primary: { "title" => "Essay", "mentor" => peer_teacher.id.to_s }
      )

      expect(result).to be_rejected
      expect(result.error).to eq(
        I18n.t("common.errors.dynamic.reference_not_allowed", field: "Mentor")
      )
    end

    it "rejects a forged person id from another tenant" do
      enable_module!("authentication", other_customer).set_extendable_model!(person_model, true)
      foreign_teacher = create(:entity, customer: other_customer, name: "Teacher",
                               extended_model: person_model)
      foreign_entry = create(:entity_entry, entity: foreign_teacher, customer: other_customer)

      result = guard(
        entity: assignment, audience: "member", viewer: member,
        primary: { "title" => "Essay", "mentor" => foreign_entry.id.to_s }
      )

      expect(result).to be_rejected
      expect(result.error).to eq(
        I18n.t("common.errors.dynamic.reference_not_allowed", field: "Mentor")
      )
    end

    it "does not extra-check a reference to an open entity" do
      result = guard(
        entity: enrollment, audience: "member", viewer: member,
        primary: { "course" => own_course.id.to_s }
      )

      expect(result.error).to be_nil
      expect(result.primary["course"]).to eq(own_course.id.to_s)
    end

    it "strips a forged Enrollment back-reference on a Student page so only BridgeEntries sets it" do
      result = guard(
        entity: student, audience: "member", viewer: member,
        primary: { "name" => "Ada" },
        sections: { "enrollment" => { "course" => own_course.id.to_s, "student" => peer_student.id.to_s } }
      )

      expect(result.error).to be_nil
      expect(result.sections["enrollment"]).to eq("course" => own_course.id.to_s)
      expect(result.primary["name"]).to eq("Ada")
    end

    it "rejects a member of another tenant instead of binding their home-tenant person entry" do
      foreign_member = create(:user, :member, customer: other_customer)

      result = guard(entity: assignment, audience: "member", viewer: foreign_member, primary: { "title" => "Essay" })

      expect(result).to be_rejected
      expect(result.error).to eq(I18n.t("common.errors.dynamic.sign_in_required"))
    end

    it "accepts the member's own mentor" do
      result = guard(
        entity: assignment, audience: "member", viewer: member,
        primary: { "title" => "Essay", "mentor" => own_teacher.id.to_s }
      )

      expect(result.error).to be_nil
      expect(result.primary["mentor"]).to eq(own_teacher.id.to_s)
      expect(result.primary["student"]).to eq(own_student.id.to_s)
    end
  end

  describe "public audience" do
    let!(:own_student) { create(:entity_entry, entity: student, customer: customer) }
    let!(:own_course) { create(:entity_entry, :with_data, entity: course, customer: customer, entry_data: { "title" => "A" }) }

    it "rejects a page bound to an owned entity" do
      result = guard(entity: assignment, audience: "public", viewer: nil, primary: { "title" => "Essay" })

      expect(result).to be_rejected
      expect(result.error).to eq(I18n.t("common.errors.dynamic.sign_in_required"))
    end

    it "rejects a page bound to a private entity" do
      result = guard(entity: review, audience: "public", viewer: nil, primary: { "student" => own_student.id.to_s })

      expect(result).to be_rejected
      expect(result.error).to eq(I18n.t("common.errors.dynamic.sign_in_required"))
    end

    it "rejects a filled owned bridge section" do
      result = guard(
        entity: student, audience: "public", viewer: nil,
        primary: { "name" => "Ada" },
        sections: { "enrollment" => { "course" => own_course.id.to_s } }
      )

      expect(result).to be_rejected
      expect(result.error).to eq(I18n.t("common.errors.dynamic.sign_in_required"))
    end

    it "strips a forged back-reference from a public section" do
      result = guard(
        entity: student, audience: "public", viewer: nil,
        primary: { "name" => "Ada" },
        sections: { "enrollment" => { "student" => own_student.id.to_s } }
      )

      expect(result.error).to be_nil
      expect(result.sections["enrollment"]).to eq({})
    end

    it "rejects an owned bridge section filled only through an entity_entries select" do
      enrollment.update!(property_schema: (enrollment.property_schema_json + [
        { "name" => "Elective", "name_slug" => "elective", "html_type" => "select",
          "config" => { "options_source" => "entity_entries", "entity_id" => course.id.to_s, "label_field" => "title" } }
      ]).to_json)

      result = guard(
        entity: student, audience: "public", viewer: nil,
        primary: { "name" => "Ada" },
        sections: { "enrollment" => { "elective" => own_course.id.to_s } }
      )

      expect(result).to be_rejected
      expect(result.error).to eq(I18n.t("common.errors.dynamic.sign_in_required"))
    end

    it "ignores an empty owned bridge section and keeps the primary" do
      result = guard(
        entity: student, audience: "public", viewer: nil,
        primary: { "name" => "Ada" },
        sections: { "enrollment" => { "course" => "", "student" => "" } }
      )

      expect(result.error).to be_nil
      expect(result.primary).to eq("name" => "Ada")
    end

    it "rejects a filled reference to a person entity" do
      student.property_schema_json = [
        { "name" => "Name", "name_slug" => "name", "html_type" => "text" },
        person_select("mentor", teacher, name: "Mentor")
      ]
      student.save!

      result = guard(
        entity: student, audience: "public", viewer: nil,
        primary: { "name" => "Ada", "mentor" => own_student.id.to_s }
      )

      expect(result).to be_rejected
      expect(result.error).to eq(
        I18n.t("common.errors.dynamic.reference_not_allowed", field: "Mentor")
      )
    end

    it "allows a public person primary with no restricted references" do
      result = guard(entity: student, audience: "public", viewer: nil, primary: { "name" => "Ada" })

      expect(result.error).to be_nil
      expect(result.primary).to eq("name" => "Ada")
    end
  end

  describe "admin audience" do
    let!(:peer_student) { create(:entity_entry, entity: student, customer: customer) }

    it "does not bind the owner or extra-check references" do
      result = guard(
        entity: assignment, audience: "admin", viewer: admin,
        primary: { "title" => "Essay", "student" => peer_student.id.to_s, "mentor" => "999" }
      )

      expect(result.error).to be_nil
      expect(result.primary).to eq(
        "title" => "Essay", "student" => peer_student.id.to_s, "mentor" => "999"
      )
    end
  end

  def guard(entity:, audience:, viewer:, primary:, sections: {})
    described_class.call(
      entity: entity,
      primary: primary,
      sections: sections,
      viewer: viewer,
      audience: audience,
      customer_id: customer.id
    )
  end

  def person_select(slug, target, owner: false, name: nil)
    attribute = {
      "name" => name || slug.capitalize,
      "name_slug" => slug,
      "html_type" => "select",
      "config" => {
        "options_source" => "entity_entries",
        "entity_id" => target.id.to_s,
        "label_field" => "name"
      }
    }
    attribute["owner"] = true if owner
    attribute
  end
end
