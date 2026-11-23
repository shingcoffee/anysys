# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntitySchemaValidation, "reference definitions" do
  let_it_be(:customer) { create(:customer) }
  let(:course_schema) do
    [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" },
     { "name" => "Notes", "name_slug" => "notes", "html_type" => "textarea" }]
  end
  let(:course) { create(:entity, customer: customer, name: "Course", property_schema: course_schema.to_json) }

  def dropdown(entity_id:, label_field: "title", name: "Course", slug: "course")
    { "name" => name, "name_slug" => slug, "html_type" => "select",
      "config" => { "options_source" => "entity_entries", "entity_id" => entity_id.to_s, "label_field" => label_field } }
  end

  def application(schema)
    build(:entity, customer: customer, name: "Application", property_schema: schema.to_json)
  end

  it "accepts a dropdown whose display field is a labelable attribute of the target" do
    expect(application([dropdown(entity_id: course.id)])).to be_valid
  end

  it "rejects a missing or foreign target" do
    foreign = create(:entity, customer: create(:customer), property_schema: course_schema.to_json)

    [999_999, foreign.id].each do |target_id|
      entity = application([dropdown(entity_id: target_id)])
      expect(entity).not_to be_valid
      expect(entity.errors[:property_schema]).to include(
        I18n.t("maint_core.errors.validations.reference_target_missing", field: "Course")
      )
    end
  end

  it "rejects a display field that is not labelable, unknown or id" do
    { "notes" => "Notes", "missing" => "missing", "id" => "id" }.each do |label_field, label|
      entity = application([dropdown(entity_id: course.id, label_field: label_field)])
      expect(entity).not_to be_valid
      expect(entity.errors[:property_schema]).to include(
        I18n.t("maint_core.errors.validations.reference_label_field_invalid",
               field: "Course", label: label, entity: course.display_label)
      )
    end
  end

  it "checks a self-reference against the schema being saved" do
    person = create(:entity, customer: customer, name: "Person",
                             property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    person.property_schema = [{ "name" => "Name", "name_slug" => "name", "html_type" => "textarea" },
                              dropdown(entity_id: person.id, label_field: "name", name: "Mentor", slug: "mentor")].to_json

    expect(person).not_to be_valid
    expect(person.errors[:property_schema]).to include(
      I18n.t("maint_core.errors.validations.reference_label_field_invalid",
             field: "Mentor", label: "Name", entity: person.display_label)
    )
  end

  it "rejects an association whose display field is not labelable" do
    student = build(:entity, customer: customer, name: "Student", property_schema: [].to_json, associations: [
      { "target_entity_id" => course.id.to_s, "target_entity_name" => "Course",
        "display_field" => "notes", "display_field_label" => "Notes" }
    ].to_json)

    expect(student).not_to be_valid
    expect(student.errors[:associations]).to include(
      I18n.t("maint_core.errors.validations.association_display_field_invalid", target_name: course.display_label, label: "Notes")
    )
  end

  it "does not check status-only saves, so trash and restore work after a target is deleted" do
    entity = application([dropdown(entity_id: course.id)])
    entity.save!
    entity.soft_delete
    course.destroy

    restored = Entity.unscope(where: :status).find(entity.id)
    expect(restored.restore).to be_truthy
  end
end
