# frozen_string_literal: true

require "rails_helper"

RSpec.describe People::Ownership do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }

  let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
  let(:member) { create(:user, :member, customer: customer) }
  let(:other_member) { create(:user, :member, customer: customer) }
  let(:foreign_member) { create(:user, :member, customer: other_customer) }

  let(:student) { Entity.find_by!(customer_id: customer.id, name: "Student") }
  let(:teacher) { Entity.find_by!(customer_id: customer.id, name: "Teacher") }
  let(:course) { Entity.find_by!(customer_id: customer.id, name: "Course") }
  let(:enrollment) { Entity.find_by!(customer_id: customer.id, name: "assoc_student_course") }
  let(:review) { Entity.find_by!(customer_id: customer.id, name: "Review") }
  let(:assignment) { Entity.find_by!(customer_id: customer.id, name: "Assignment") }
  let(:note) { Entity.find_by!(customer_id: customer.id, name: "Note") }

  before do
    enable_module!("authentication", customer).set_extendable_model!(person_model, true)

    name_field = [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json
    create(:entity, customer: customer, name: "Student", extended_model: person_model, property_schema: name_field)
    create(:entity, customer: customer, name: "Teacher", extended_model: person_model, property_schema: name_field)
    create(:entity, customer: customer, name: "Course",
           property_schema: [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json)

    student.associations_json = [association_to(course)]
    student.save!
    student.sync_bridge_entities!

    create(:entity, customer: customer, name: "Review",
           property_schema: [person_select("student", student), person_select("teacher", teacher)].to_json)
    create(:entity, customer: customer, name: "Assignment",
           property_schema: [
             person_select("student", student, owner: true),
             person_select("teacher", teacher)
           ].to_json)
    create(:entity, customer: customer, name: "Note",
           property_schema: [person_select("student", student)].to_json)
    create(:entity, customer: customer, name: "Basket",
           property_schema: [{ "name" => "Label", "name_slug" => "label", "html_type" => "text" },
                             person_select("student", student)].to_json)
    create(:entity, customer: customer, name: "Basket item",
           property_schema: [reference_select("basket", basket, "label"), reference_select("course", course, "title"),
                             { "name" => "Quantity", "name_slug" => "quantity", "html_type" => "number" }].to_json)
  end

  let(:basket) { Entity.find_by!(customer_id: customer.id, name: "Basket") }
  let(:basket_item) { Entity.find_by!(customer_id: customer.id, name: "Basket item") }

  describe ".kind / .describe" do
    it "classifies person, owned, private and open entities" do
      expect(described_class.kind(student)).to eq(:person)
      expect(described_class.kind(enrollment)).to eq(:owned)
      expect(described_class.kind(assignment)).to eq(:owned)
      expect(described_class.kind(note)).to eq(:owned)
      expect(described_class.kind(review)).to eq(:private)
      expect(described_class.kind(course)).to eq(:open)
    end

    it "still treats a reference to a trashed person entity as a person reference" do
      student.update_column(:status, :inactive)

      expect(Entity.find_by(id: student.id)).to be_nil
      expect(described_class.kind(enrollment.reload)).to eq(:owned)
    end
  end

  describe ".owner_reference" do
    it "returns the inferred bridge source ref for Enrollment" do
      owner = described_class.owner_reference(enrollment)

      expect(owner).to have_attributes(slug: "student", person_entity_id: student.id)
    end

    it "returns the flagged person reference for an owned entity" do
      expect(described_class.owner_reference(assignment))
        .to have_attributes(slug: "student", person_entity_id: student.id)
    end

    it "returns the single inferred person reference" do
      expect(described_class.owner_reference(note))
        .to have_attributes(slug: "student", person_entity_id: student.id)
    end

    it "is nil for person, private and open entities" do
      expect(described_class.owner_reference(student)).to be_nil
      expect(described_class.owner_reference(review)).to be_nil
      expect(described_class.owner_reference(course)).to be_nil
    end
  end

  describe ".scope" do
    let!(:own_student) { create(:entity_entry, entity: student, customer: customer, user: member) }
    let!(:peer_student) { create(:entity_entry, entity: student, customer: customer, user: other_member) }
    let!(:foreign_student_entity) do
      enable_module!("authentication", other_customer).set_extendable_model!(person_model, true)
      create(:entity, customer: other_customer, name: "Student", extended_model: person_model)
    end
    let!(:foreign_student) do
      create(:entity_entry, entity: foreign_student_entity, customer: other_customer, user: foreign_member)
    end

    let!(:own_course) { create(:entity_entry, :with_data, entity: course, customer: customer, entry_data: { "title" => "A" }) }
    let!(:peer_course) { create(:entity_entry, :with_data, entity: course, customer: customer, entry_data: { "title" => "B" }) }
    let!(:foreign_course_entity) { create(:entity, customer: other_customer, name: "Course") }
    let!(:foreign_course) { create(:entity_entry, entity: foreign_course_entity, customer: other_customer) }

    let!(:own_enrollment) do
      create(:entity_entry, :with_data, entity: enrollment, customer: customer,
             entry_data: { "student" => own_student.id.to_s, "course" => own_course.id.to_s })
    end
    let!(:peer_enrollment) do
      create(:entity_entry, :with_data, entity: enrollment, customer: customer,
             entry_data: { "student" => peer_student.id, "course" => peer_course.id })
    end
    let!(:own_assignment) do
      create(:entity_entry, :with_data, entity: assignment, customer: customer,
             entry_data: { "student" => own_student.id.to_s, "teacher" => "1" })
    end
    let!(:peer_assignment) do
      create(:entity_entry, :with_data, entity: assignment, customer: customer,
             entry_data: { "student" => peer_student.id, "teacher" => "2" })
    end
    let!(:own_note) do
      create(:entity_entry, :with_data, entity: note, customer: customer,
             entry_data: { "student" => own_student.id })
    end
    let!(:peer_note) do
      create(:entity_entry, :with_data, entity: note, customer: customer,
             entry_data: { "student" => peer_student.id.to_s })
    end
    let!(:own_review) do
      create(:entity_entry, :with_data, entity: review, customer: customer,
             entry_data: { "student" => own_student.id.to_s, "teacher" => "1" })
    end
    let!(:peer_review) do
      create(:entity_entry, :with_data, entity: review, customer: customer,
             entry_data: { "student" => peer_student.id.to_s, "teacher" => "2" })
    end

    it "returns every tenant row for admin and never another tenant's rows" do
      {
        student => [own_student, peer_student],
        enrollment => [own_enrollment, peer_enrollment],
        assignment => [own_assignment, peer_assignment],
        review => [own_review, peer_review],
        course => [own_course, peer_course]
      }.each do |entity, rows|
        expect(scope_ids(entity, viewer: member, audience: EntityAttributeAudience::ADMIN))
          .to match_array(rows.map(&:id))
      end

      expect(scope_ids(student, viewer: member, audience: EntityAttributeAudience::ADMIN))
        .not_to include(foreign_student.id)
      expect(scope_ids(course, viewer: member, audience: EntityAttributeAudience::ADMIN))
        .not_to include(foreign_course.id)
    end

    it "scopes member reads by ownership kind" do
      expect(scope_ids(student, viewer: member, audience: EntityAttributeAudience::MEMBER))
        .to eq([own_student.id])
      expect(scope_ids(enrollment, viewer: member, audience: EntityAttributeAudience::MEMBER))
        .to eq([own_enrollment.id])
      expect(scope_ids(assignment, viewer: member, audience: EntityAttributeAudience::MEMBER))
        .to eq([own_assignment.id])
      expect(scope_ids(note, viewer: member, audience: EntityAttributeAudience::MEMBER))
        .to eq([own_note.id])
      expect(scope_ids(review, viewer: member, audience: EntityAttributeAudience::MEMBER)).to eq([])
      expect(scope_ids(course, viewer: member, audience: EntityAttributeAudience::MEMBER))
        .to match_array([own_course.id, peer_course.id])
    end

    it "hides another member's person and owned rows from a member" do
      expect(scope_ids(student, viewer: member, audience: EntityAttributeAudience::MEMBER))
        .not_to include(peer_student.id)
      expect(scope_ids(enrollment, viewer: member, audience: EntityAttributeAudience::MEMBER))
        .not_to include(peer_enrollment.id)
      expect(scope_ids(assignment, viewer: other_member, audience: EntityAttributeAudience::MEMBER))
        .to eq([peer_assignment.id])
    end

    it "returns no person, owned or private rows to the public, and every tenant row for open" do
      [student, enrollment, assignment, review].each do |entity|
        expect(scope_ids(entity, viewer: nil, audience: EntityAttributeAudience::PUBLIC)).to eq([])
      end

      expect(scope_ids(course, viewer: nil, audience: EntityAttributeAudience::PUBLIC))
        .to match_array([own_course.id, peer_course.id])
      expect(scope_ids(course, viewer: nil, audience: EntityAttributeAudience::PUBLIC))
        .not_to include(foreign_course.id)
    end

    it "fails closed when the viewer or audience cannot be resolved" do
      expect(scope_ids(student, viewer: nil, audience: EntityAttributeAudience::MEMBER)).to eq([])
      expect(scope_ids(enrollment, viewer: foreign_member, audience: EntityAttributeAudience::MEMBER)).to eq([])
      expect(scope_ids(course, viewer: member, audience: "staff")).to eq([])
      expect(scope_ids(assignment, viewer: create(:user, :member, customer: customer),
                       audience: EntityAttributeAudience::MEMBER)).to eq([])
    end
  end

  describe "rows that hang off a member's records" do
    let!(:own_student) { create(:entity_entry, entity: student, customer: customer, user: member) }
    let!(:peer_student) { create(:entity_entry, entity: student, customer: customer, user: other_member) }
    let!(:own_basket) { basket_entry("Mine", own_student) }
    let!(:peer_basket) { basket_entry("Theirs", peer_student) }
    let!(:own_item) { item_entry("basket" => own_basket.id) }
    let!(:peer_item) { item_entry("basket" => peer_basket.id.to_s) }
    let!(:loose_item) { item_entry("quantity" => 1) }

    def basket_entry(label, student_row)
      create(:entity_entry, :with_data, entity: basket, customer: customer,
                                        entry_data: { "label" => label, "student" => student_row.id.to_s })
    end

    def item_entry(data)
      create(:entity_entry, :with_data, entity: basket_item, customer: customer, entry_data: data)
    end

    it "classifies them as nested under the record type they hang off" do
      descriptor = described_class.describe(basket_item)

      expect(descriptor.kind).to eq(:nested)
      expect(descriptor.parents).to eq([described_class::Parent.new(slug: "basket", entity_id: basket.id)])
      expect(described_class.owner_reference(basket_item)).to be_nil
      expect(described_class.kind(course)).to eq(:open)
    end

    it "lets a member reach only the rows of records they reach, the public none and admins all" do
      expect(scope_ids(basket_item, viewer: member, audience: EntityAttributeAudience::MEMBER)).to eq([own_item.id])
      expect(scope_ids(basket_item, viewer: other_member, audience: EntityAttributeAudience::MEMBER)).to eq([peer_item.id])
      expect(scope_ids(basket_item, viewer: foreign_member, audience: EntityAttributeAudience::MEMBER)).to eq([])
      expect(scope_ids(basket_item, viewer: nil, audience: EntityAttributeAudience::PUBLIC)).to eq([])
      expect(scope_ids(basket_item, viewer: member, audience: EntityAttributeAudience::ADMIN))
        .to match_array([own_item.id, peer_item.id, loose_item.id])
      expect(described_class.reachable_ids(basket_item, [own_item.id, peer_item.id], viewer: member,
                                                                                     audience: EntityAttributeAudience::MEMBER,
                                                                                     customer_id: customer.id)).to eq([own_item.id.to_s])
    end
  end

  describe ".reachable_ids" do
    let!(:own_student) { create(:entity_entry, entity: student, customer: customer, user: member) }
    let!(:peer_student) { create(:entity_entry, entity: student, customer: customer, user: other_member) }

    it "returns only the in-scope subset as strings and ignores non-numeric ids" do
      ids = [own_student.id, peer_student.id, "x", "", nil, own_student.id.to_s]

      expect(
        described_class.reachable_ids(
          student, ids, viewer: member, audience: EntityAttributeAudience::MEMBER, customer_id: customer.id
        )
      ).to eq([own_student.id.to_s])

      expect(
        described_class.reachable_ids(
          student, ids, viewer: member, audience: EntityAttributeAudience::ADMIN, customer_id: customer.id
        )
      ).to match_array([own_student.id.to_s, peer_student.id.to_s])
    end
  end

  describe ".person_entry_ids / .person_entry_id" do
    let!(:own_student) { create(:entity_entry, entity: student, customer: customer, user: member) }
    let!(:own_teacher) { create(:entity_entry, entity: teacher, customer: customer, user: member) }
    let!(:foreign_student_entity) do
      enable_module!("authentication", other_customer).set_extendable_model!(person_model, true)
      create(:entity, customer: other_customer, name: "Student", extended_model: person_model)
    end
    let!(:forged_foreign) do
      create(:entity_entry, entity: foreign_student_entity, customer: other_customer).tap do |entry|
        entry.update_columns(user_id: member.id)
      end
    end

    it "returns only this user's linked person entries in their tenant" do
      expect(described_class.person_entry_ids(member)).to eq(
        student.id.to_s => own_student.id,
        teacher.id.to_s => own_teacher.id
      )
      expect(described_class.person_entry_ids(member).values).not_to include(forged_foreign.id)
      expect(described_class.person_entry_id(member, student.id)).to eq(own_student.id)
      expect(described_class.person_entry_id(member, foreign_student_entity.id)).to be_nil
    end
  end

  def association_to(target)
    {
      "target_entity_id" => target.id,
      "target_entity_name" => target.name,
      "display_field" => "title",
      "display_field_label" => "Title",
      "additional_attributes" => []
    }
  end

  def person_select(slug, target, owner: false)
    attribute = {
      "name" => slug.capitalize,
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

  def reference_select(slug, target, label_field)
    { "name" => slug.capitalize, "name_slug" => slug, "html_type" => "select",
      "config" => { "options_source" => "entity_entries", "entity_id" => target.id.to_s, "label_field" => label_field } }
  end

  def scope_ids(entity, viewer:, audience:, customer_id: customer.id)
    described_class.scope(entity, viewer: viewer, audience: audience, customer_id: customer_id).pluck(:id)
  end
end
