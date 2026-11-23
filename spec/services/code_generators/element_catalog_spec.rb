# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementCatalog do
  def export(locale: "en")
    described_class.export(locale: locale)
  end

  describe ".export" do
    it "matches the committed JavaScript fixture" do
      path = Rails.root.join("spec/javascript/fixtures/element_catalog.sample.json")
      expect(JSON.parse(path.read)).to eq(JSON.parse(JSON.generate(export))),
                                       "run `bin/rails element_catalog:fixture` to regenerate #{path}"
    end

    it "returns locale, types, connection, operators, chrome, and digest" do
      catalog = export
      expect(catalog).to include("locale", "types", "connection", "operators", "chrome", "digest")
      expect(catalog["locale"]).to eq("en")
      expect(catalog["digest"]).to match(/\A[a-f0-9]{64}\z/)
      expect(catalog["types"].keys).to eq(%w[start end process decision loop subflow])
    end

    it "keeps the digest stable across locales" do
      expect(export(locale: "en")["digest"]).to eq(export(locale: "zh-CN")["digest"])
    end

    it "exports start with no config fields and general+io tabs" do
      start = export["types"]["start"]
      expect(start).to include(
        "type" => "start",
        "label" => "Start",
        "defaultLabel" => "Start",
        "tabs" => %w[general io],
        "fields" => []
      )
    end

    it "exports end fields through FieldPresenter with visibility" do
      by_name = export["types"]["end"]["fields"].index_by { |field| field["name"] }
      expect(by_name["responseType"]).to include(
        "role" => "enum",
        "control" => "select",
        "label" => "Response Type",
        "default" => "none",
        "required" => true
      )
      expect(by_name["responseType"]["options"]).to eq([
        { "value" => "none", "label" => "Nothing" },
        { "value" => "value", "label" => "Return a value" }
      ])
      expect(by_name["returnValue"]).to include(
        "role" => "expression",
        "control" => "code",
        "placeholder" => "ctx.result",
        "visibleWhen" => { "responseType" => "value" },
        "requiredWhen" => { "responseType" => "value" }
      )
      expect(by_name.keys).not_to include("httpStatus", "responseBody", "label", "description")
    end

    it "translates end option labels in zh-CN" do
      by_name = export(locale: "zh-CN")["types"]["end"]["fields"].index_by { |field| field["name"] }
      expect(by_name["responseType"]["options"]).to eq([
        { "value" => "none", "label" => "不返回" },
        { "value" => "value", "label" => "返回一个值" }
      ])
      expect(export(locale: "zh-CN")["types"]["end"]["defaultLabel"]).to eq("结束")
    end

    it "exports process with no config fields and a steps tab" do
      process = export["types"]["process"]
      expect(process["fields"]).to eq([])
      expect(process["tabs"]).to eq(%w[general steps io])
    end

    it "exports subflow flowchartId as a flowcharts reference" do
      field = export["types"]["subflow"]["fields"].find { |item| item["name"] == "flowchartId" }
      expect(field).to include(
        "role" => "reference",
        "control" => "reference_picker",
        "source" => "flowcharts",
        "required" => true,
        "label" => "Flowchart"
      )
    end

    it "exports connection label and description only" do
      names = export["connection"]["fields"].map { |field| field["name"] }
      expect(names).to eq(%w[label description])
      description = export["connection"]["fields"].find { |field| field["name"] == "description" }
      expect(description).to include("control" => "textarea", "multiline" => true, "label" => "Notes")
    end

    it "embeds condition operators from ConditionOperators" do
      expect(export["operators"]).to eq(CodeGenerators::ConditionOperators.export(locale: "en"))
    end

    it "exposes chrome labels for Label and Notes rather than as config fields" do
      expect(export["chrome"]).to eq(
        "label" => { "label" => "Label" },
        "notes" => { "key" => "description", "label" => "Notes" }
      )
      expect(export(locale: "zh-CN")["chrome"]).to eq(
        "label" => { "label" => "名称" },
        "notes" => { "key" => "description", "label" => "备注" }
      )
    end

    it "round-trips element sample configs through validate_config" do
      %w[start end subflow].each do |type|
        generator = CodeGenerators::GeneratorRegistry.find_element_type(type)
        errors = generator.new({ "properties" => generator.sample_input }, {}).validate_config(generator.sample_input)
        expect(errors).to eq([]), "#{type}: #{errors.inspect}"
      end
    end

    it "raises when an element generator declares no config schema" do
      generator = CodeGenerators::GeneratorRegistry.find_element_type("start")
      allow(generator).to receive(:_config_schema).and_return(nil)
      expect { export }.to raise_error(ArgumentError, /declares no config_schema/)
    end
  end
end
