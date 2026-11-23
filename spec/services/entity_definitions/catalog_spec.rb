# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityDefinitions::Catalog do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other) { create(:customer) }

  it "returns definition-shaped documents without identity or bridge ids" do
    target = create(:entity, customer: customer, name: "Course",
                    property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    source = create(:entity, customer: customer, name: "Student")
    source.associations_json = [{
      "target_entity_id" => target.id,
      "target_entity_name" => target.name,
      "display_field" => "name",
      "display_field_label" => "Name"
    }]
    source.save!
    source.sync_bridge_entities!
    create(:entity, customer: other, name: "Foreign")

    docs = described_class.for_customer(customer.id)
    names = docs.map { |row| row["name"] }
    expect(names).to contain_exactly("Course", "Student")
    student = docs.find { |row| row["name"] == "Student" }
    expect(student).not_to have_key("id")
    expect(student).not_to have_key("shared")
    assoc = student["associations"].first
    expect(assoc["associated_entity_name"]).to eq("Course")
    expect(assoc).not_to have_key("bridge_entity_id")
    expect(assoc).not_to have_key("target_entity_id")
  end

  # An echo has to be able to round-trip: the model is shown a name and Persist
  # turns that name back into the id, so an id never has to reach the prompt.
  it "echoes a dynamic choice list by entity name rather than by id" do
    course = create(:entity, customer: customer, name: "Course",
                    property_schema: [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json)
    create(
      :entity,
      customer: customer,
      name: "Enrollment",
      property_schema: [{
        "name" => "Course",
        "name_slug" => "course",
        "html_type" => "select",
        "config" => {
          "options_source" => "entity_entries",
          "entity_id" => course.id.to_s,
          "label_field" => "title"
        }
      }].to_json
    )

    config = described_class.for_customer(customer.id)
                            .find { |row| row["name"] == "Enrollment" }
                            .dig("property_schema", 0, "config")

    expect(config["options_entity_name"]).to eq("Course")
    expect(config).not_to have_key("entity_id")
  end

  it "drops a dangling entity_id instead of leaking it" do
    enrollment = build(
      :entity,
      customer: customer,
      name: "Enrollment",
      property_schema: [{
        "name" => "Course",
        "name_slug" => "course",
        "html_type" => "select",
        "config" => { "options_source" => "entity_entries", "entity_id" => "999999" }
      }].to_json
    )
    enrollment.save(validate: false)

    config = described_class.for_customer(customer.id)
                            .find { |row| row["name"] == "Enrollment" }
                            .dig("property_schema", 0, "config")

    expect(config).to eq("options_source" => "entity_entries")
  end

  it "echoes target_entity_name for a computed attribute in the source direction" do
    target = create(:entity, customer: customer, name: "Course",
                    property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    source = create(:entity, customer: customer, name: "Student")
    source.associations_json = [{
      "target_entity_id" => target.id,
      "target_entity_name" => target.name,
      "display_field" => "name",
      "display_field_label" => "Name"
    }]
    source.save!
    source.sync_bridge_entities!
    source.reload
    bridge_id = source.associations_list.first["bridge_entity_id"]
    source.property_schema_json = [{
      "name" => "Course count",
      "name_slug" => "course_count",
      "type" => Entity::COMPUTED_TYPE,
      "html_type" => "number",
      "config" => { "function" => "count", "bridge_role" => "source", "bridge_entity_id" => bridge_id }
    }]
    source.save!

    config = described_class.for_customer(customer.id)
                            .find { |row| row["name"] == "Student" }
                            .dig("property_schema", 0, "config")

    expect(config["target_entity_name"]).to eq("Course")
    expect(config).not_to have_key("bridge_entity_id")
  end

  it "echoes target_entity_name for a computed attribute in the target direction" do
    target = create(:entity, customer: customer, name: "Course",
                    property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    source = create(:entity, customer: customer, name: "Student")
    source.associations_json = [{
      "target_entity_id" => target.id,
      "target_entity_name" => target.name,
      "display_field" => "name",
      "display_field_label" => "Name"
    }]
    source.save!
    source.sync_bridge_entities!
    source.reload
    bridge_id = source.associations_list.first["bridge_entity_id"]
    target.property_schema_json = [
      { "name" => "Name", "name_slug" => "name", "html_type" => "text" },
      {
        "name" => "Enrollment count",
        "name_slug" => "enrollment_count",
        "type" => Entity::COMPUTED_TYPE,
        "html_type" => "number",
        "config" => { "function" => "count", "bridge_role" => "target", "bridge_entity_id" => bridge_id }
      }
    ]
    target.save!

    config = described_class.for_customer(customer.id)
                            .find { |row| row["name"] == "Course" }
                            .dig("property_schema", 1, "config")

    expect(config["target_entity_name"]).to eq("Student")
    expect(config).not_to have_key("bridge_entity_id")
  end

  it "leaves an attribute without config alone rather than adding an empty one" do
    create(
      :entity,
      customer: customer,
      name: "Student",
      property_schema: [{ "name" => "Email", "name_slug" => "email", "html_type" => "email" }].to_json
    )

    attribute = described_class.for_customer(customer.id)
                               .find { |row| row["name"] == "Student" }
                               .dig("property_schema", 0)

    expect(attribute).not_to have_key("config")
  end
end
