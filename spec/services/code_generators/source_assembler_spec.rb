# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::SourceAssembler do
  # Boilerplate method bodies are identical across examples; only the module/
  # class scaffolding under test varies.
  let(:methods_body) { "def generate_body\n  \"true\"\nend\n\ndef validate_config(config)\n  []\nend" }

  describe "#assemble" do
    it "assembles a step action generator" do
      assembler = described_class.new(
        kind: "step_action",
        category: "model_operations",
        file_name: "new_model",
        description: "Creates a new model",
        version: "1.0.0",
        registered_names: "",
        methods_body: methods_body
      )

      source = assembler.assemble
      expect(source).to include("# frozen_string_literal: true")
      expect(source).to include("module CodeGenerators")
      expect(source).to include("module ElementTypes")
      expect(source).to include("module Process")
      expect(source).to include("module ModelOperations")
      expect(source).to include("class NewModelGenerator < CodeGenerators::BaseGenerator")
      expect(CodeGenerators::GeneratorValidator.validate_source(source)).to be_empty
      expect(source).to include('description "Creates a new model"')
      expect(source).to include("category    :model_operations")
      expect(source).to include("def generate")
      expect(source).not_to include("input_schema")
      expect(source).not_to include("output_schema")
    end

    it "assembles an element type generator" do
      assembler = described_class.new(
        kind: "element_type",
        category: "flow_control",
        file_name: "fork",
        description: "Fork element",
        version: "1.0.0",
        registered_names: "",
        methods_body: methods_body
      )

      source = assembler.assemble
      expect(source).to include("module Fork")
      expect(source).to include("class ForkGenerator < CodeGenerators::BaseGenerator")
      expect(source).not_to include("module Process")
    end

    it "includes registered_names override when provided" do
      assembler = described_class.new(
        kind: "step_action",
        category: "validation",
        file_name: "validate_contract",
        description: "Validates",
        version: "1.0.0",
        registered_names: "validate_contract, validate",
        methods_body: methods_body
      )

      source = assembler.assemble
      expect(source).to include("def self.registered_names")
      expect(source).to include('"validate_contract"')
      expect(source).to include('"validate"')
    end

    it "auto-suffixes _generator to class name" do
      assembler = described_class.new(
        kind: "step_action", category: "data_operations", file_name: "assign_value",
        description: "Test", version: "1.0.0",
        registered_names: "", methods_body: methods_body
      )

      expect(assembler.assemble).to include("class AssignValueGenerator")
    end
  end
end
