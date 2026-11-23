# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ActionCatalog do
  def export(locale: "en")
    described_class.export(locale: locale)
  end

  def registered_step_names
    CodeGenerators::GeneratorRegistry.step_action_generators.keys
  end

  def canonical_classes
    CodeGenerators::GeneratorRegistry.step_action_generators.values.uniq
  end

  describe ".export" do
    it "returns a JSON-ready hash with digest, locale, categories, and actions" do
      catalog = export
      expect(catalog).to include("digest", "locale", "categories", "actions")
      expect(catalog["locale"]).to eq("en")
      expect(catalog["digest"]).to match(/\A[a-f0-9]{64}\z/)
      expect(catalog["categories"]).to all(include("key", "label"))
      expect(catalog["actions"]).to all(include(
        "key", "category", "label", "description", "icon", "color",
        "singleUse", "privileged", "fields", "capabilities"
      ))
    end

    it "exports every registered step action once under its canonical key" do
      catalog = export
      keys = catalog["actions"].map { |action| action["key"] }
      expect(keys).to match_array(canonical_classes.map(&:generator_name))
      expect(keys.size).to eq(canonical_classes.size)
      expect(keys).to match_array(registered_step_names)
    end

    it "registers each step action class under its canonical name only" do
      canonical_classes.each do |klass|
        expect(klass.registered_names.map(&:to_s)).to eq([klass.generator_name]), klass.generator_name
      end
    end

    it "keeps the digest stable across locales" do
      expect(export(locale: "en")["digest"]).to eq(export(locale: "zh-CN")["digest"])
    end

    it "orders categories and actions by the D4 catalog order" do
      catalog = export
      category_keys = catalog["categories"].map { |category| category["key"] }
      expect(category_keys).to eq(category_keys.sort_by { |key| described_class::CATEGORY_ORDER.index(key) || 99 })
      catalog["actions"].group_by { |action| action["category"] }.each_value do |actions|
        expect(actions.map { |action| action["key"] }).to eq(actions.map { |action| action["key"] }.sort)
      end
    end

    it "translates category labels through nested keys" do
      english = export(locale: "en")
      chinese = export(locale: "zh-CN")
      model_en = english["categories"].find { |category| category["key"] == "model" }
      model_zh = chinese["categories"].find { |category| category["key"] == "model" }
      expect(model_en["label"]).to eq("Records")
      expect(model_zh["label"]).to eq("记录")
    end

    it "declares every step action's schema and exports no alias field" do
      expect(export["actions"]).to all(satisfy { |row| !row.key?("aliases") })
      expect(canonical_classes).to all(satisfy(&:_config_schema))
    end

    it "maps flags to toggles rather than true/false selects" do
      flags = export["actions"].flat_map { |action| action["fields"] }.select { |field| field["role"] == "flag" }
      expect(flags).not_to be_empty
      flags.each do |field|
        expect(field["control"]).to eq("toggle"), field["name"]
      end
    end

    it "adds a translated None option first on optional enums" do
      optional = ->(f) { f["control"] == "select" && f["required"] == false }
      en_row = export(locale: "en")["actions"].find { |action| action["fields"].any?(&optional) }
      skip "no optional enum in the catalog" unless en_row

      name = en_row["fields"].find(&optional)["name"]
      zh_row = export(locale: "zh-CN")["actions"].find { |action| action["key"] == en_row["key"] }
      expect(en_row["fields"].find { |f| f["name"] == name }["options"].first).to eq("value" => "", "label" => "None")
      expect(zh_row["fields"].find { |f| f["name"] == name }["options"].first).to eq("value" => "", "label" => "无")
    end

    it "maps declared api_call fields onto the A4 controls" do
      api = export["actions"].find { |action| action["key"] == "api_call" }
      by_name = api["fields"].index_by { |field| field["name"] }
      expect(by_name["url"]).to include("role" => "expression", "control" => "code")
      expect(by_name["bodyTemplate"]).to include("role" => "expression")
      expect(by_name["httpMethod"]).to include("role" => "enum", "control" => "select")
      expect(by_name["headers"]).to include("role" => "mapping", "control" => "mapping")
      expect(by_name["maxRedirects"]).to include("role" => "integer", "control" => "number")
      expect(by_name["bodyTemplate"]["visibleWhen"]).to eq("httpMethod" => %w[POST PUT PATCH])
    end
  end

  describe "ported fixture generator" do
    it "exports every A1 control from the Wave 1 ported schema" do
      action = described_class.export_generator(Phase3FixtureGenerator, locale: "en")
      expect(action["key"]).to eq("phase3_fixture")
      expect(action["category"]).to eq("utility")
      expect(action["icon"]).to eq("circle")
      expect(action["color"]).to eq("blue")
      expect(action["singleUse"]).to eq(false)
      expect(action["privileged"]).to eq(false)
      expect(action["label"]).to eq("Phase 3 fixture")
      by_role = action["fields"].group_by { |field| field["role"] }
      expect(by_role.keys).to include(
        "input", "output", "expression", "literal", "template", "enum", "flag",
        "integer", "decimal", "list", "mapping", "conditions", "entity_attribute",
        "reference", "localized_text"
      )
      expect(action["fields"].find { |field| field["role"] == "input" }).to include(
        "control" => "text", "variablePicker" => true
      )
      expect(action["fields"].find { |field| field["role"] == "output" }).to include(
        "control" => "text", "variablePicker" => false
      )
      expect(action["fields"].find { |field| field["role"] == "expression" }).to include("control" => "code")
      expect(action["fields"].find { |field| field["role"] == "flag" }).to include("control" => "toggle")
      expect(action["fields"].find { |field| field["role"] == "reference" }).to include(
        "control" => "reference_picker", "source" => "email_templates"
      )
      expect(action["fields"].find { |field| field["role"] == "entity_attribute" }).to include(
        "control" => "attribute_picker"
      )
      expect(action["capabilities"]["transportRetry"]).to include(
        "idempotentWhen" => { "operation" => %w[sum] },
        "orPresent" => "idempotencyKey"
      )
      expect(action["capabilities"]["timeouts"]).to include("open" => 3, "read" => 7, "cap" => 10)
      expect(action["capabilities"]["circuitBreaker"]).to eq(true)
    end

    it "looks up ported field text in A3 order" do
      action = described_class.export_generator(Phase3FixtureGenerator, locale: "en")
      source = action["fields"].find { |field| field["name"] == "sourceVariable" }
      expect(source["label"]).to eq("Source")
      expect(source["help"]).to eq("Context path this step reads.")
      operation = action["fields"].find { |field| field["name"] == "operation" }
      expect(operation["options"].map { |option| option["value"] }).to eq(["", "sum", "avg"])
      expect(operation["options"].map { |option| option["label"] }).to eq(%w[None Sum Average])
    end
  end

  describe ".sample_export" do
    it "includes the ported fixture and a handful of catalog actions" do
      sample = described_class.sample_export(locale: "en")
      keys = sample["actions"].map { |action| action["key"] }
      expect(keys).to include("phase3_fixture", "find_model", "api_call")
      expect(keys).not_to eq(export["actions"].map { |action| action["key"] })
      expect(sample["actions"].size).to be < 20
    end
  end
end
