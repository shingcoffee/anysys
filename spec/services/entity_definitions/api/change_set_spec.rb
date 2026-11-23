# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityDefinitions::Api::ChangeSet do
  let_it_be(:customer) { create(:customer) }
  let(:mapper) { EntityDefinitions::Api::Mapper.new(customer: customer) }

  def document
    {
      "name" => "Student",
      "display_label" => "Student",
      "name_slug" => "student",
      "extended_model" => nil,
      "icon" => "custom",
      "color" => "#6366f1",
      "description" => "People",
      "property_schema" => [
        { "name" => "Email", "name_slug" => "email", "html_type" => "email", "display_label" => "Email", "group_id" => "basics" },
        { "name" => "Fax", "name_slug" => "fax", "html_type" => "tel", "display_label" => "Fax", "group_id" => "extra" }
      ],
      "attribute_groups" => [
        { "id" => "basics", "name" => "Basics", "icon" => "folder", "color" => "indigo" },
        { "id" => "extra", "name" => "Extra", "icon" => "tag", "color" => "amber" }
      ],
      "associations" => [{
        "associated_entity_name" => "Course",
        "display_field" => "title",
        "display_field_label" => "Title",
        "additional_attributes" => [
          { "name" => "Seat", "name_slug" => "seat", "html_type" => "number", "display_label" => "Seat" }
        ]
      }],
      "default_properties" => { "email" => "a@b.c", "fax" => "1" },
      "referenced_template" => "kept"
    }
  end

  def apply(changes, doc: document)
    described_class.apply(doc, changes, mapper: mapper, pointer_prefix: "/updates/0/changes")
  end

  it "applies each of the 16 change ops and keeps untouched bytes plus referenced_template" do
    original_email = document["property_schema"].first.dup
    result = apply([
      { "op" => "set_details", "display_label" => "Learner", "description" => "Enrolled people" },
      { "op" => "set_settings", "icon" => "user", "color" => "#111827", "default_values" => { "email" => "x@y.z" } },
      { "op" => "add_attribute", "attribute" => { "name" => "Phone", "html_type" => "tel" }, "position" => { "after" => "email" } },
      { "op" => "update_attribute", "slug" => "email", "set" => { "description" => "Work email" } },
      { "op" => "remove_attribute", "slug" => "fax" },
      { "op" => "add_group", "group" => { "key" => "schedule", "name" => "Schedule", "icon" => "calendar", "color" => "sky" } },
      { "op" => "update_group", "key" => "basics", "set" => { "name" => "Overview" } },
      { "op" => "move_attribute", "slug" => "phone", "to_group" => "schedule" },
      { "op" => "remove_group", "key" => "extra", "move_attributes_to" => "basics" },
      { "op" => "reorder_groups", "order" => %w[schedule basics] },
      { "op" => "update_association", "related_entity" => "Course", "set" => { "display_field_label" => "Course title" } },
      { "op" => "add_bridge_attribute", "related_entity" => "Course", "attribute" => { "name" => "Note", "html_type" => "text" } },
      { "op" => "update_bridge_attribute", "related_entity" => "Course", "slug" => "seat", "set" => { "display_label" => "Seat no" } },
      { "op" => "remove_bridge_attribute", "related_entity" => "Course", "slug" => "note" },
      { "op" => "remove_association", "related_entity" => "Course" },
      { "op" => "add_association", "association" => { "related_entity" => "Campus", "display_field" => "name" } }
    ])

    expect(result).to be_ok
    doc = result.document
    expect(doc["display_label"]).to eq("Learner")
    expect(doc["icon"]).to eq("user")
    expect(doc["referenced_template"]).to eq("kept")
    expect(doc["property_schema"].map { |attr| attr["name_slug"] }).to eq(%w[email phone])
    expect(doc["property_schema"][0]["description"]).to eq("Work email")
    expect(doc["property_schema"][0]["html_type"]).to eq(original_email["html_type"])
    expect(doc["default_properties"]).to eq("email" => "x@y.z")
    expect(doc["attribute_groups"].map { |group| group["id"] }).to eq(%w[schedule basics])
    expect(doc["attribute_groups"][1]["name"]).to eq("Overview")
    expect(doc["property_schema"][1]["group_id"]).to eq("schedule")
    expect(doc["associations"].map { |assoc| assoc["associated_entity_name"] }).to eq(["Campus"])
  end

  it "keeps an untouched attribute object identical" do
    result = apply([{ "op" => "add_attribute", "attribute" => { "name" => "Phone" } }])
    expect(result.document["property_schema"][0]).to eq(document["property_schema"][0])
  end

  it "reports missing slugs, groups, associations, and position targets with pointers" do
    result = apply([
      { "op" => "remove_attribute", "slug" => "missing" },
      { "op" => "update_group", "key" => "ghost", "set" => { "name" => "X" } },
      { "op" => "remove_association", "related_entity" => "Ghost" },
      { "op" => "add_attribute", "attribute" => { "name" => "Phone" }, "position" => { "after" => "nope" } }
    ])

    expect(result.violations.map(&:code)).to include(
      "attribute.not_found", "group.not_found", "association.not_found", "change.position_target_not_found"
    )
    expect(result.violations.map(&:pointer)).to include(
      "/updates/0/changes/0/slug",
      "/updates/0/changes/1/key",
      "/updates/0/changes/2/related_entity",
      "/updates/0/changes/3/position"
    )
  end

  it "refuses to remove an attribute still referenced by a formula" do
    doc = document
    doc["property_schema"] << { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "formula" => "fax * 2" }
    result = apply([{ "op" => "remove_attribute", "slug" => "fax" }], doc: doc)
    expect(result.violations.map(&:code)).to include("attribute.in_use")
    expect(result.document["property_schema"].map { |attr| attr["name_slug"] }).to include("fax")
  end

  it "drops an attribute's default value along with the attribute" do
    result = apply([{ "op" => "remove_attribute", "slug" => "fax" }])

    expect(result).to be_ok
    expect(result.document["property_schema"].map { |attr| attr["name_slug"] }).to eq(["email"])
    expect(result.document["default_properties"]).to eq("email" => "a@b.c")
  end

  it "refuses to remove a bridge attribute an aggregate reads, but not a same-named sibling" do
    doc = document
    doc["property_schema"] << {
      "name" => "Seats", "name_slug" => "seats", "html_type" => "number", "type" => "Computed",
      "config" => { "target_entity_name" => "Course", "function" => "sum", "source_slug" => "seat", "bridge_role" => "source" }
    }
    doc["property_schema"] << { "name" => "Seat", "name_slug" => "seat", "html_type" => "text" }

    bridge = apply([{ "op" => "remove_bridge_attribute", "related_entity" => "Course", "slug" => "seat" }], doc: doc)
    sibling = apply([{ "op" => "remove_attribute", "slug" => "seat" }], doc: doc)

    expect(bridge.violations.map(&:code)).to eq(["attribute.in_use"])
    expect(sibling).to be_ok
  end

  it "rejects a reorder_groups list that is not a permutation" do
    result = apply([{ "op" => "reorder_groups", "order" => %w[basics] }])
    expect(result.violations.map(&:code)).to include("group.order_mismatch")
  end

  describe "changing an attribute's control or kind" do
    def document_with(attribute)
      document.merge("property_schema" => [attribute])
    end

    let(:level) do
      {
        "name" => "Level", "name_slug" => "level", "display_label" => "Level", "html_type" => "select",
        "config" => { "source" => "manual", "options" => [{ "label" => "Beginner", "value" => "Beginner", "default" => false }] },
        "validators" => [{ "type" => "inclusion", "config" => { "values" => ["Beginner"] } }]
      }
    end

    it "drops the inherited choice list when a select becomes a text box" do
      result = apply([{ "op" => "update_attribute", "slug" => "level", "set" => { "html_type" => "text" } }],
                     doc: document_with(level))

      expect(result).to be_ok
      stored = result.document["property_schema"].first
      expect(stored["html_type"]).to eq("text")
      expect(stored).not_to have_key("config")
    end

    it "reports options sent alongside a control that has no choice list" do
      result = apply(
        [{ "op" => "update_attribute", "slug" => "level",
           "set" => { "html_type" => "text", "options" => { "source" => "static", "values" => ["A"] } } }],
        doc: document_with(level)
      )

      expect(result.violations.map { |violation| [violation.code, violation.pointer] })
        .to include(["options.not_applicable", "/updates/0/changes/0/set/options"])
    end

    it "clears the aggregate and its config when a computed attribute becomes an input" do
      computed = {
        "name" => "Seats", "name_slug" => "seats", "display_label" => "Seats", "html_type" => "number",
        "type" => "Computed", "readonly" => true, "storage" => "computed",
        "config" => { "target_entity_name" => "Course", "function" => "count", "bridge_role" => "source" }
      }
      result = apply([{ "op" => "update_attribute", "slug" => "seats", "set" => { "kind" => "input" } }],
                     doc: document_with(computed))

      expect(result).to be_ok
      stored = result.document["property_schema"].first
      expect(stored).not_to include("type", "readonly", "storage", "config")
      expect(stored["html_type"]).to eq("number")
    end
  end
end
