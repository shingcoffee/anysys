# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityDefinitions::Normalizer do
  it "strips serializer identity keys so a catalog echo can update by name" do
    result = described_class.call([{
      "id" => 99,
      "shared" => false,
      "status" => "active",
      "category" => "plain",
      "current_version" => { "id" => 1 },
      "name" => "Student"
    }])

    expect(result).to be_ok
    expect(result.definitions.first.keys).to include("name")
    expect(result.definitions.first).not_to have_key("id")
    expect(result.definitions.first).not_to have_key("shared")
    expect(result.definitions.first).not_to have_key("status")
    expect(result.definitions.first).not_to have_key("category")
  end

  it "keeps data fields and drops storage type hints" do
    result = described_class.call([{
      "name" => "Student",
      "property_schema" => [{ "name" => "Email", "type" => "String", "html_type" => "email" }]
    }])

    expect(result).to be_ok
    attr = result.definitions.first["property_schema"].first
    expect(attr["type"]).to be_nil
    expect(attr["html_type"]).to eq("email")
    expect(attr).not_to have_key("entity_id")
  end

  it "keeps the per-audience editable flags" do
    editable = { "admin" => true, "member" => false, "public" => false }
    result = described_class.call([{ "name" => "Order", "property_schema" => [{ "name" => "Status", "html_type" => "text", "editable" => editable }] }])

    expect(result).to be_ok
    expect(result.definitions.first["property_schema"].first["editable"]).to eq(editable)
  end

  it "keeps a status lifecycle on an attribute and drops one that is not an object or sits on a bridge field" do
    lifecycle = { "transitions" => [{ "from" => "draft", "to" => "submitted", "by" => ["member"] }] }
    result = described_class.call([{
      "name" => "Application",
      "property_schema" => [
        { "name" => "Status", "name_slug" => "status", "html_type" => "select", "lifecycle" => lifecycle },
        { "name" => "Stage", "name_slug" => "stage", "html_type" => "select", "lifecycle" => "draft" }
      ],
      "associations" => [{ "associated_entity_name" => "Course", "additional_attributes" => [
        { "name" => "Role", "name_slug" => "role", "html_type" => "select", "lifecycle" => lifecycle }
      ] }]
    }])

    expect(result).to be_ok
    definition = result.definitions.first
    expect(definition["property_schema"][0]["lifecycle"]).to eq(lifecycle)
    expect(definition["property_schema"][1]).not_to have_key("lifecycle")
    expect(definition["associations"][0]["additional_attributes"][0]).not_to have_key("lifecycle")
  end

  it "keeps owner: true on an attribute and drops owner: false" do
    result = described_class.call([{
      "name" => "Assignment",
      "property_schema" => [
        { "name" => "Student", "name_slug" => "student", "html_type" => "select", "owner" => true },
        { "name" => "Title", "name_slug" => "title", "html_type" => "text", "owner" => false }
      ]
    }])

    expect(result).to be_ok
    schema = result.definitions.first["property_schema"]
    expect(schema[0]["owner"]).to eq(true)
    expect(schema[1]).not_to have_key("owner")
  end

  it "derives omitted slugs for partial input, calculated, computed, and bridge-extra fields" do
    fields = [
      { "name" => "First name", "html_type" => "text" },
      { "name" => "Total price", "type" => "Calculated", "formula" => "price * quantity", "html_type" => "number" },
      { "name" => "Course count", "type" => "Computed", "html_type" => "number",
        "config" => { "target_entity_name" => "Course", "function" => "count" } }
    ]
    result = described_class.call([{
      "name" => "Student", "property_schema" => fields,
      "associations" => [{ "associated_entity_name" => "Course", "display_field" => "name", "display_field_label" => "Name",
                           "additional_attributes" => [{ "name" => "Final score", "html_type" => "number" }] }]
    }])

    expect(result).to be_ok
    definition = result.definitions.first
    expect(definition["property_schema"].map { |field| field["name_slug"] }).to eq(%w[first_name total_price course_count])
    expect(definition.dig("associations", 0, "additional_attributes", 0, "name_slug")).to eq("final_score")
    expect(fields).to all(satisfy { |field| !field.key?("name_slug") })
  end

  it "preserves explicit identifiers, including invalid ones, for strict persistence validation" do
    result = described_class.call([{
      "name" => "Student",
      "property_schema" => [
        { "name" => "Email address", "name_slug" => "email", "html_type" => "email" },
        { "name" => "Notes", "name_slug" => "notes.bad", "html_type" => "textarea" },
        { "name" => "Blank slug", "name_slug" => "", "html_type" => "text" }
      ]
    }])
    expect(result.definitions.first["property_schema"].map { |field| field["name_slug"] }).to eq(["email", "notes.bad", ""])
  end

  it "maps stored association keys to associated_entity_name" do
    result = described_class.call([{
      "name" => "Student",
      "associations" => [{
        "target_entity_id" => 8,
        "target_entity_name" => "Course",
        "bridge_entity_id" => 9,
        "display_field" => "name",
        "display_field_label" => "Name"
      }]
    }])

    expect(result).to be_ok
    assoc = result.definitions.first["associations"].first
    expect(assoc["associated_entity_name"]).to eq("Course")
    expect(assoc).not_to have_key("target_entity_id")
    expect(assoc).not_to have_key("bridge_entity_id")
  end

  it "rejects customer_id on a definition" do
    result = described_class.call([{ "name" => "Student", "customer_id" => 1 }])
    expect(result.ok?).to be false
    expect(result.errors.join).to include("identity")
  end

  it "rejects an unknown html_type" do
    result = described_class.call([{
      "name" => "Student",
      "property_schema" => [{ "name" => "X", "html_type" => "javascript" }]
    }])
    expect(result.ok?).to be false
    expect(result.errors.join).to include("javascript")
  end

  it "rejects a document that names the same entity twice rather than picking one" do
    result = described_class.call([
      { "name" => "Student", "description" => "First" },
      { "name" => "Student", "description" => "Second" }
    ])

    expect(result.ok?).to be false
    expect(result.definitions).to eq([])
    expect(result.errors).to eq([
      I18n.t("ai_assistant.assistant.apply_errors.duplicate_entity_name", names: "Student")
    ])
  end

  it "accepts every html type the app currently registers" do
    result = described_class.call([{
      "name" => "Student",
      "property_schema" => EntityDefinitions::Capabilities.control_values.each_with_index.map do |html_type, index|
        { "name" => "Field #{index}", "html_type" => html_type }
      end
    }])

    expect(result).to be_ok
  end

  describe "choice list config" do
    def normalize_config(config)
      described_class.call([{
        "name" => "Ticket",
        "property_schema" => [{ "name" => "Priority", "html_type" => "select", "config" => config }]
      }]).definitions.first["property_schema"].first["config"]
    end

    # Filters, badge columns and page fields all index options by value/label,
    # so a bare string has to be canonicalized before it is stored.
    it "expands bare string options into value/label pairs" do
      expect(normalize_config("options" => %w[Low High])).to eq(
        "options" => [
          { "value" => "Low", "label" => "Low" },
          { "value" => "High", "label" => "High" }
        ]
      )
    end

    it "keeps an explicit value/label pair as given" do
      expect(normalize_config("options" => [{ "value" => "hi", "label" => "High" }]))
        .to eq("options" => [{ "value" => "hi", "label" => "High" }])
    end

    it "back-fills a missing half of the pair and drops empty entries" do
      expect(normalize_config("options" => [{ "label" => "High" }, { "value" => "low" }, {}, "  "]))
        .to eq(
          "options" => [
            { "value" => "High", "label" => "High" },
            { "value" => "low", "label" => "low" }
          ]
        )
    end

    it "keeps a list bound to another entity's entries, by name" do
      config = normalize_config(
        "options_source" => "entity_entries",
        "options_entity_name" => "Course",
        "label_field" => "title"
      )

      expect(config).to eq(
        "options_source" => "entity_entries",
        "options_entity_name" => "Course",
        "label_field" => "title"
      )
    end

    it "never lets a record id through the config" do
      expect(normalize_config("options_source" => "entity_entries", "entity_id" => "42"))
        .to eq("options_source" => "entity_entries")
    end

    it "keeps editor source, constant, file, and option default keys" do
      expect(normalize_config(
        "source" => "manual",
        "options" => [{ "value" => "low", "label" => "Low", "default" => true }],
        "accept" => ".pdf",
        "multiple" => true
      )).to eq(
        "source" => "manual",
        "options" => [{ "value" => "low", "label" => "Low", "default" => true }],
        "accept" => ".pdf",
        "multiple" => true
      )
      expect(normalize_config("source" => "constant", "constant_id" => 7, "constant_name" => "Status"))
        .to eq("source" => "constant", "constant_id" => 7, "constant_name" => "Status")
    end
  end

  describe "computed config" do
    it "keeps the aggregate keys and drops input-only ones" do
      result = described_class.call([{
        "name" => "Course",
        "property_schema" => [{
          "name" => "Enrolled",
          "html_type" => "number",
          "type" => "Computed",
          "config" => {
            "target_entity_name" => "Student",
            "function" => "count",
            "options" => %w[nope],
            "bridge_entity_id" => 7
          }
        }]
      }])

      config = result.definitions.first["property_schema"].first["config"]
      expect(config).to eq("target_entity_name" => "Student", "function" => "count")
    end

    it "keeps the mapper's filter and bridge_role" do
      result = described_class.call([{
        "name" => "Course",
        "property_schema" => [{
          "name" => "Average",
          "html_type" => "number",
          "type" => "Computed",
          "config" => {
            "target_entity_name" => "Student",
            "function" => "avg",
            "source_slug" => "score",
            "precision" => 2,
            "filter" => { "slug" => "status", "op" => "=", "value" => "active" },
            "bridge_role" => "target"
          }
        }]
      }])

      expect(result.definitions.first["property_schema"].first["config"]).to eq(
        "target_entity_name" => "Student",
        "function" => "avg",
        "source_slug" => "score",
        "precision" => 2,
        "filter" => { "slug" => "status", "op" => "=", "value" => "active" },
        "bridge_role" => "target"
      )
    end
  end
end
