# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::GeneratorValidator do
  describe ".validate_source" do
    let(:valid_source) do
      <<~RUBY
        class CodeGenerators::StepActions::TestGenerator < CodeGenerators::BaseGenerator
          generator_metadata do
            description "Test"
            category :test
            version "1.0.0"
          end

          def generate_body
            "true"
          end

          def validate_config(config)
            []
          end
        end
      RUBY
    end

    it "returns empty array for valid source" do
      expect(described_class.validate_source(valid_source)).to eq([])
    end

    it "rejects source with only generate (not generate_body)" do
      source = valid_source.gsub("def generate_body", "def generate")
      errors = described_class.validate_source(source)
      expect(errors).to include("Missing required method: generate_body")
    end

    it "catches syntax errors" do
      errors = described_class.validate_source("def foo(")
      expect(errors.first).to start_with("Syntax error:")
    end

    it "rejects missing BaseGenerator inheritance" do
      source = valid_source.gsub("< CodeGenerators::BaseGenerator", "")
      errors = described_class.validate_source(source)
      expect(errors).to include("Must inherit from CodeGenerators::BaseGenerator")
    end

    it "rejects missing generate_body method" do
      source = valid_source.gsub(/def generate_body.*?end/m, "")
      errors = described_class.validate_source(source)
      expect(errors).to include("Missing required method: generate_body")
    end

    it "rejects source with neither validate_config nor a config_schema block" do
      source = valid_source.gsub(/def validate_config.*?end/m, "")
      errors = described_class.validate_source(source)
      expect(errors).to include("Missing required config validation: define validate_config or a config_schema block")
    end

    it "accepts a config_schema block in place of def validate_config (standard DSL style)" do
      source = valid_source.gsub(/def validate_config.*?end/m, <<~RUBY.strip)
        config_schema do
          field :sourceVariable, required: true
        end
      RUBY
      expect(described_class.validate_source(source)).to eq([])
    end

    it "rejects missing generator_metadata block" do
      source = valid_source.gsub(/generator_metadata do.*?end/m, "")
      errors = described_class.validate_source(source)
      expect(errors).to include("Missing generator_metadata block")
    end

    it "rejects missing metadata fields" do
      source = valid_source.gsub(/description "Test"/, "")
      errors = described_class.validate_source(source)
      expect(errors).to include("Missing metadata: description")
    end

    it "stops after syntax errors (does not check interface)" do
      errors = described_class.validate_source("def foo(")
      expect(errors.length).to eq(1)
    end
  end
end
