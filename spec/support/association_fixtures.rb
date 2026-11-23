# frozen_string_literal: true

# A Student ↔ Course many-to-many association whose bridge carries a required
# status and an optional 0–100 grade, for the entry detail association specs.
RSpec.shared_context "student course association" do
  let(:association_customer) { customer }
  let(:student_entity) do
    create(:entity, customer: association_customer, name: "Student", display_label: "Student",
                    property_schema: [{ "name" => "Full Name", "name_slug" => "full_name", "html_type" => "text" }].to_json)
  end
  let(:course_entity) do
    create(:entity, customer: association_customer, name: "Course", display_label: "Course",
                    property_schema: [{ "name" => "Code", "name_slug" => "code", "html_type" => "text" }].to_json)
  end
  let(:bridge_attributes) do
    [
      { "name" => "Status", "name_slug" => "status", "html_type" => "select",
        "config" => { "source" => "manual", "options" => [{ "label" => "Enrolled", "value" => "enrolled", "default" => true },
                                                          { "label" => "Dropped", "value" => "dropped" }] },
        "validators" => [{ "type" => "presence" }] },
      { "name" => "Grade", "name_slug" => "grade", "html_type" => "number",
        "validators" => [{ "type" => "numericality" },
                         { "type" => "greater_than_or_equal_to", "config" => { "value" => 0 } },
                         { "type" => "less_than_or_equal_to", "config" => { "value" => 100 } }] },
      { "name" => "Secret", "name_slug" => "secret", "html_type" => "text",
        "visibility" => { "admin" => false, "member" => true, "public" => false } }
    ]
  end
  let!(:bridge_entity) do
    student_entity.associations_json = [{
      "target_entity_id" => course_entity.id, "target_entity_name" => course_entity.name,
      "display_field" => "code", "display_field_label" => "Code", "additional_attributes" => bridge_attributes
    }]
    student_entity.save!
    student_entity.sync_bridge_entities!
    student_entity.reload
    Entity.find_by!(name: "assoc_student_course", customer_id: association_customer.id)
  end
  let!(:student) { create(:entity_entry, :with_data, customer: association_customer, entity: student_entity, entry_data: { "full_name" => "Ada" }) }
  let!(:math) { create(:entity_entry, :with_data, customer: association_customer, entity: course_entity, entry_data: { "code" => "MATH-101" }) }
  let!(:physics) { create(:entity_entry, :with_data, customer: association_customer, entity: course_entity, entry_data: { "code" => "PHYS-201" }) }

  def enroll(student_entry, course_entry, **data)
    create(:entity_entry, :with_data, customer: association_customer, entity: bridge_entity,
                                      entry_data: { "student" => student_entry.id.to_s, "course" => course_entry.id.to_s }
                                                    .merge(data.transform_keys(&:to_s)))
  end
end
