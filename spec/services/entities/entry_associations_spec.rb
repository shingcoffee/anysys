# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::EntryAssociations do
  subject(:associations) { described_class.new(entity: student_entity, customer: customer) }

  let(:customer) { create(:customer) }

  include_context "student course association"

  it "resolves each declared association to its bridge, target, back reference and admin-visible columns" do
    association = associations.find(bridge_entity.id)

    expect(associations.all.map(&:id)).to eq([bridge_entity.id])
    expect(association.target).to eq(course_entity)
    expect(association.label).to eq("Course")
    expect(association.source_slug).to eq("student")
    expect(association.column_slugs).to eq(%w[course status grade])
    expect(association.links(student)).to eq("student" => student.id.to_s)
    expect(associations.find(bridge_entity.id.to_s)).to eq(association)
    expect(associations.find(0)).to be_nil
  end

  it "skips associations whose target is gone, and has none for a bridge" do
    course_entity.update_column(:status, Entity.statuses[:inactive])

    expect(associations.all).to be_empty
    expect(described_class.new(entity: bridge_entity, customer: customer).all).to be_empty
  end

  describe "from the target side" do
    subject(:inverse) { described_class.new(entity: course_entity, customer: customer) }

    it "resolves an association another entity declares towards this one, with the declaring entity as the target" do
      association = inverse.find(bridge_entity.id)

      expect(inverse.all.map(&:id)).to eq([bridge_entity.id])
      expect(association.target).to eq(student_entity)
      expect(association.label).to eq("Student")
      expect(association.source_slug).to eq("course")
      expect(association.column_slugs).to eq(%w[student status grade])
      expect(association.links(math)).to eq("course" => math.id.to_s)
    end

    it "lists the bridge rows that link this entry, with the declaring records that still exist" do
      first = enroll(student, math, status: "enrolled", grade: "90")
      enroll(student, physics)
      other_student = create(:entity_entry, :with_data, customer: customer, entity: student_entity, entry_data: {})
      second = enroll(other_student, math)
      other_student.delete

      section = inverse.sections(math).sole

      expect(section.rows).to eq([first, second])
      expect(section.display.text(first, "grade")).to eq("90")
      expect(section.existing_target_ids).to eq("student" => Set[student.id.to_s])
    end

    it "lists each association once, declared ones first, and skips an inactive declaring entity" do
      course_entity.associations_json = [{ "target_entity_id" => student_entity.id, "target_entity_name" => student_entity.name,
                                           "display_field" => "full_name", "display_field_label" => "Full Name" }]
      course_entity.save!
      course_entity.sync_bridge_entities!
      reverse_bridge = Entity.find_by!(name: "assoc_course_student", customer_id: customer.id)

      both = described_class.new(entity: course_entity.reload, customer: customer).all
      expect(both.map(&:id)).to eq([reverse_bridge.id, bridge_entity.id])
      expect(both.map(&:target)).to eq([student_entity, student_entity])

      student_entity.update_column(:status, Entity.statuses[:inactive])
      expect(described_class.new(entity: course_entity, customer: customer).all.map(&:id)).to eq([])
    end
  end

  it "lists only this entry's rows in this tenant, oldest first, whether the reference is stored as text or a number" do
    first = enroll(student, math)
    numeric = create(:entity_entry, :with_data, customer: customer, entity: bridge_entity,
                                                entry_data: { "student" => student.id, "course" => physics.id.to_s })
    enroll(create(:entity_entry, :with_data, customer: customer, entity: student_entity, entry_data: {}), math)
    other_tenant = create(:customer)
    create(:entity_entry, :with_data, customer: other_tenant, entity: bridge_entity, entry_data: { "student" => student.id.to_s })

    expect(associations.rows(associations.find(bridge_entity.id), student).to_a).to eq([first, numeric])
  end

  it "builds sections with display text and the ids of target records that still exist" do
    enroll(student, math, status: "enrolled", grade: "90")
    gone = enroll(student, physics, status: "dropped")
    physics.delete

    section = associations.sections(student).sole

    expect(section.rows.size).to eq(2)
    expect(section.display.text(section.rows.first, "course")).to eq("MATH-101")
    expect(section.display.text(section.rows.first, "status")).to eq("Enrolled")
    expect(section.display.text(gone, "course")).to eq(I18n.t("common.references.missing", id: physics.id))
    expect(section.existing_target_ids).to eq("course" => Set[math.id.to_s])
  end
end
