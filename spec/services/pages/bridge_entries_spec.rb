# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::BridgeEntries do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }

  let(:student) { create(:entity, customer: customer, name: "Student", property_schema: [{ "name" => "Code", "name_slug" => "code", "html_type" => "text" }].to_json) }
  let(:course) { create(:entity, customer: customer, name: "Course", property_schema: [{ "name_slug" => "title" }].to_json) }
  let(:bridge) do
    create(:entity, customer: customer, name: "assoc_course_student", category: :bridge, property_schema: [
      { "name" => "Course", "name_slug" => "course", "type" => "EntityReference", "entity_id" => course.id,
        "validators" => [{ "type" => "presence" }] },
      { "name" => "Student", "display_label" => "Learner", "name_slug" => "student", "type" => "EntityReference",
        "entity_id" => student.id, "html_type" => "select",
        "config" => { "options_source" => "entity_entries", "entity_id" => student.id.to_s, "label_field" => "code" },
        "validators" => [{ "type" => "presence" }] },
      { "name" => "Selected on", "name_slug" => "selected_on", "validators" => [{ "type" => "presence" }] },
      { "name" => "Grade", "name_slug" => "grade", "validators" => [{ "type" => "numericality" }],
        "visibility" => { "admin" => true, "member" => false, "public" => false } }
    ].to_json)
  end
  let(:student_entry) { create(:entity_entry, customer: customer, entity: student, data: { code: "S-1" }.to_json) }
  let(:course_entry) { create(:entity_entry, customer: customer, entity: course, data: { title: "Maths" }.to_json) }

  before do
    allow(course).to receive(:associations_json).and_return(
      [{ "target_entity_id" => student.id, "bridge_entity_id" => bridge.id, "bridge_entity_name" => bridge.name }]
    )
  end

  def write(values, section: "assoc_course_student", audience: "admin", entity: course)
    Current.set(customer: customer) do
      described_class.call(entry: course_entry, entity: entity, sections: { section => values },
                           customer_id: customer.id, audience: audience)
    end
  end

  def bridge_rows
    EntityEntry.where(customer_id: customer.id, entity_id: bridge.id)
  end

  it "creates the bridge row linked to the new primary entry and the chosen target" do
    expect(write({ "student" => student_entry.id.to_s, "selected_on" => "2026-09-01", "grade" => "" })).to eq([])

    row = bridge_rows.sole
    expect(row.data_json).to include("course" => course_entry.id.to_s, "student" => student_entry.id.to_s,
                                     "selected_on" => "2026-09-01")
  end

  it "never takes the link to the primary entry from the submission" do
    write({ "student" => student_entry.id.to_s, "selected_on" => "2026-09-01", "course" => "999" })

    expect(bridge_rows.sole.data_json["course"]).to eq(course_entry.id.to_s)
  end

  it "accepts a section keyed by the bridge entity id" do
    expect(write({ "student" => student_entry.id.to_s, "selected_on" => "2026-09-01" }, section: bridge.id.to_s)).to eq([])
    expect(bridge_rows.count).to eq(1)
  end

  it "skips a section whose target reference is blank" do
    expect(write({ "student" => "", "selected_on" => "2026-09-01" })).to eq([])
    expect(bridge_rows).to be_empty
  end

  it "rejects a target entry that belongs to another tenant" do
    foreign = create(:entity_entry, customer: other_customer, entity: student, data: { code: "X" }.to_json)

    errors = write({ "student" => foreign.id.to_s, "selected_on" => "2026-09-01" })

    expect(errors).to eq([I18n.t("common.errors.dynamic.association_target_missing", field: "Learner")])
    expect(bridge_rows).to be_empty
  end

  it "rejects a target entry of a different entity and a malformed id" do
    expect(write({ "student" => course_entry.id.to_s, "selected_on" => "2026-09-01" })).not_to be_empty
    expect(write({ "student" => "1 OR 1=1", "selected_on" => "2026-09-01" })).not_to be_empty
    expect(bridge_rows).to be_empty
  end

  it "returns the bridge contract errors for the submitter's audience" do
    errors = write({ "student" => student_entry.id.to_s, "selected_on" => "", "grade" => "abc" })

    expect(errors).to include(a_string_matching(/Selected on/), a_string_matching(/Grade/))
    expect(bridge_rows).to be_empty
  end

  it "does not apply admin-only validators to a public submission" do
    expect(write({ "student" => student_entry.id.to_s, "selected_on" => "2026-09-01", "grade" => "abc" },
                 audience: "public")).to eq([])
  end

  it "saves the bridge row as the submitter's audience, or as system without one" do
    allow(Entries::Save).to receive(:call).and_call_original

    write({ "student" => student_entry.id.to_s, "selected_on" => "2026-09-01" }, audience: "public")
    write({ "student" => student_entry.id.to_s, "selected_on" => "2026-09-02" }, audience: nil)

    expect(Entries::Save).to have_received(:call).with(hash_including(audience: "public"))
    expect(Entries::Save).to have_received(:call).with(hash_including(audience: "system"))
  end

  it "reports an unknown section as a configuration error" do
    errors = write({ "student" => student_entry.id.to_s }, section: "unknown_bridge")

    expect(errors).to eq([I18n.t("common.errors.dynamic.association_unavailable")])
  end

  it "ignores a bridge entity owned by another tenant" do
    bridge.update_column(:customer_id, other_customer.id)

    errors = write({ "student" => student_entry.id.to_s, "selected_on" => "2026-09-01" })

    expect(errors).to eq([I18n.t("common.errors.dynamic.association_unavailable")])
    expect(EntityEntry.where(entity_id: bridge.id)).to be_empty
  end
end
