# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Task 4 UI wire-shape parity for data actions" do
  def body(klass, config)
    klass.new({ "config" => config }, {}).generate_body
  end

  describe "AssignValue boolean strings" do
    let(:klass) { CodeGenerators::ElementTypes::Process::DataOperations::AssignValueGenerator }

    it "emits false for booleanValue 'false'" do
      code = body(klass, "resultVar" => "x", "valueType" => "boolean", "booleanValue" => "false")
      expect(code).to include("ctx[:x] = false")
    end

    it "emits true for booleanValue 'true'" do
      code = body(klass, "resultVar" => "x", "valueType" => "boolean", "booleanValue" => "true")
      expect(code).to include("ctx[:x] = true")
    end
  end

  describe "CollectionManipulate pluck flatten" do
    let(:klass) { CodeGenerators::ElementTypes::Process::DataOperations::CollectionManipulateGenerator }

    it "flattens a single plucked field" do
      code = body(klass, "operation" => "pluck", "sourceVariable" => "items", "resultVar" => "names",
                         "fields" => [{ "key" => "name", "value" => "name" }])
      expect(code).to include("FlowchartRuntime::Collections.pluck")
      expect(code).to include("flatten: true")
    end
  end

  describe "MapValue mappings as KV list" do
    let(:klass) { CodeGenerators::ElementTypes::Process::DataOperations::MapValueGenerator }

    it "accepts UI key_value_list mappings" do
      code = body(klass, "sourceVariable" => "status", "resultVar" => "label",
                         "mappings" => [{ "key" => "active", "value" => "Active" }], "matchMode" => "exact")
      expect(code).to include('"active"')
      expect(code).to include('"Active"')
    end

    it "accepts UI key_value_list rules for regex matchMode" do
      code = body(klass, "sourceVariable" => "code", "resultVar" => "label",
                         "matchMode" => "regex",
                         "rules" => [{ "key" => "^A", "value" => "starts-a" }],
                         "defaultValue" => "other")
      expect(code).to include('match_mode: "regex"')
      expect(code).to include("starts-a")
    end
  end

  describe "TemplateRender variables as KV list" do
    let(:klass) { CodeGenerators::ElementTypes::Process::Utility::TemplateRenderGenerator }

    it "maps key->placeholder and value->path" do
      code = body(klass, "template" => "Hello {{name}}", "resultVar" => "out",
                         "variables" => [{ "key" => "name", "value" => "ctx.user_name" }])
      expect(code).to include("{{name}}")
      expect(code).to include("ctx[:user_name]")
    end
  end

  describe "OperandConverter ctx bracket paths" do
    include CodeGenerators::Shared::OperandConverter

    it "accepts ctx[:orders]" do
      expect(condition_operand_to_ruby("ctx[:orders]")).to eq("ctx[:orders]")
    end
  end

  describe "Calculate ignoreNils" do
    let(:klass) { CodeGenerators::ElementTypes::Process::DataOperations::CalculateGenerator }

    it "relies on the runtime default when ignoreNils is true" do
      code = body(klass, "operation" => "count", "sourceVariable" => "orders",
                         "resultVar" => "n", "ignoreNils" => true)
      expect(code).not_to include("ignore_nils")
      expect(code).to include("ctx[:orders]")
    end

    it "keeps nils when ignoreNils is off" do
      code = body(klass, "operation" => "count", "sourceVariable" => "orders",
                         "resultVar" => "n", "ignoreNils" => false)
      expect(code).to include("ignore_nils: false")
    end
  end

  describe "DateTimeCalc timezoneAware string" do
    let(:klass) { CodeGenerators::ElementTypes::Process::DataOperations::DateTimeCalcGenerator }

    it "applies timezone when timezoneAware is true" do
      code = body(klass, "operation" => "add", "sourceVariable" => "t", "amount" => 1, "unit" => "days",
                         "resultVar" => "out", "timezoneAware" => true, "timezone" => "UTC")
      expect(code).to include("timezone_aware: true")
      expect(code).to include('timezone: "UTC"')
    end
  end

  describe "AssignValue first_present" do
    let(:klass) { CodeGenerators::ElementTypes::Process::DataOperations::AssignValueGenerator }

    it "emits Collections.first_present_from_ctx without programmer predicates" do
      code = body(klass, "valueType" => "first_present", "candidates" => %w[a b], "resultVar" => "out")
      expect(code).to include("first_present_from_ctx")
      expect(code).not_to include("blank_definition")
      expect(code).not_to include("predicate:")
    end
  end
end
