# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Entity computed definition validation", type: :model do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }

  let!(:student) { create(:entity, name: "Student", customer: customer) }
  let!(:klass) { create(:entity, name: "Class", customer: customer) }
  let!(:bridge) do
    create(:entity, name: "assoc_student_class", customer: customer, category: :bridge,
      property_schema: [
        { "name" => "Student", "name_slug" => "student", "type" => "EntityReference", "entity_id" => student.id.to_s, "html_type" => "number" },
        { "name" => "Class", "name_slug" => "class", "type" => "EntityReference", "entity_id" => klass.id.to_s, "html_type" => "select" },
        { "name" => "Score", "name_slug" => "score", "type" => "Float", "html_type" => "number" },
        { "name" => "Note", "name_slug" => "note", "type" => "String", "html_type" => "text" }
      ].to_json)
  end

  def computed_field(overrides = {})
    config = {
      "bridge_entity_id" => bridge.id,
      "bridge_role" => "source",
      "source_slug" => "score",
      "function" => "avg",
      "precision" => 2
    }.merge(overrides.delete("config") || {})
    {
      "name" => "Average Score",
      "name_slug" => "average_score",
      "type" => "Computed",
      "html_type" => "number",
      "readonly" => true,
      "storage" => "computed",
      "config" => config
    }.merge(overrides.except("config"))
  end

  def assign_computed!(entity = student, field = computed_field)
    entity.property_schema_json = [field]
    entity
  end

  def validation_message(key, name: "Average Score")
    I18n.t("maint_core.errors.validations.#{key}", name: name)
  end

  it "accepts a valid computed config" do
    expect(assign_computed!).to be_valid
  end

  it "rejects an unsupported function" do
    entity = assign_computed!(student, computed_field("config" => { "function" => "median" }))
    expect(entity).not_to be_valid
    expect(entity.errors[:property_schema]).to include(validation_message("computed_function_invalid"))
  end

  it "rejects a bridge_role other than source or target" do
    entity = assign_computed!(student, computed_field("config" => { "bridge_role" => "both" }))
    expect(entity).not_to be_valid
    expect(entity.errors[:property_schema]).to include(validation_message("computed_role_invalid"))
  end

  it "rejects a missing bridge" do
    entity = assign_computed!(student, computed_field("config" => { "bridge_entity_id" => 0 }))
    expect(entity).not_to be_valid
    expect(entity.errors[:property_schema]).to include(validation_message("computed_bridge_not_found"))
  end

  it "rejects a cross-tenant bridge" do
    foreign = create(:entity, name: "assoc_student_class", customer: other_customer, category: :bridge,
      property_schema: bridge.property_schema)
    entity = assign_computed!(student, computed_field("config" => { "bridge_entity_id" => foreign.id }))
    expect(entity).not_to be_valid
    expect(entity.errors[:property_schema]).to include(validation_message("computed_bridge_not_found"))
  end

  it "rejects when the host does not participate at the declared role" do
    entity = assign_computed!(student, computed_field("config" => { "bridge_role" => "target" }))
    expect(entity).not_to be_valid
    expect(entity.errors[:property_schema]).to include(validation_message("computed_host_not_participant"))
  end

  it "rejects a missing source_slug for avg/sum/min/max" do
    entity = assign_computed!(student, computed_field("config" => { "source_slug" => "" }))
    expect(entity).not_to be_valid
    expect(entity.errors[:property_schema]).to include(validation_message("computed_source_missing"))
  end

  it "rejects a source_slug that is not on the bridge" do
    entity = assign_computed!(student, computed_field("config" => { "source_slug" => "credits" }))
    expect(entity).not_to be_valid
    expect(entity.errors[:property_schema]).to include(validation_message("computed_source_unknown"))
  end

  it "rejects a non-numeric source attribute for avg/sum/min/max" do
    entity = assign_computed!(student, computed_field("config" => { "source_slug" => "note" }))
    expect(entity).not_to be_valid
    expect(entity.errors[:property_schema]).to include(validation_message("computed_source_not_numeric"))
  end

  it "rejects a filter with an unknown op" do
    entity = assign_computed!(student, computed_field("config" => {
      "filter" => { "slug" => "score", "op" => "LIKE", "value" => "1" }
    }))
    expect(entity).not_to be_valid
    expect(entity.errors[:property_schema]).to include(validation_message("computed_filter_invalid"))
  end

  it "rejects precision outside 0..6" do
    entity = assign_computed!(student, computed_field("config" => { "precision" => 7 }))
    expect(entity).not_to be_valid
    expect(entity.errors[:property_schema]).to include(validation_message("computed_precision_invalid"))

    entity = assign_computed!(student, computed_field("config" => { "precision" => -1 }))
    expect(entity).not_to be_valid
    expect(entity.errors[:property_schema]).to include(validation_message("computed_precision_invalid"))
  end

  it "rejects a computed on a shared entity" do
    shared = build(:entity, :shared, name: "SharedComputed", property_schema: [computed_field].to_json)
    expect(shared).not_to be_valid
    expect(shared.errors[:property_schema]).to include(validation_message("computed_not_customer_specific"))
  end

  it "rejects a non-Hash config" do
    entity = assign_computed!(student, computed_field.merge("config" => "nope"))
    expect(entity).not_to be_valid
    expect(entity.errors[:property_schema]).to include(validation_message("computed_config_invalid"))
  end

  it "allows count with a blank source_slug" do
    entity = assign_computed!(student, computed_field(
      "name" => "Enrollment Count",
      "name_slug" => "enrollment_count",
      "config" => { "function" => "count", "source_slug" => "" }
    ))
    expect(entity).to be_valid
  end

  it "skips the host-participation check on a new record" do
    newbie = build(:entity, name: "Newbie", customer: customer, property_schema: [computed_field].to_json)
    expect(newbie).to be_valid
  end
end
