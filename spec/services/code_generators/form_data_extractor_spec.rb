# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::FormDataExtractor do
  it "seeds a new generator with a role-DSL scaffold that validates" do
    form = described_class.new(category: "data_operations").default_form_data
    expect(form).to include(category: "data_operations", version: "1.0.0", description: "", registered_names: "")

    source = CodeGenerators::SourceAssembler.new(form.merge(file_name: "scaffold_check")).assemble
    expect(source).to include("config_schema do", "assign(:resultVar, read(:sourceVariable))")
    expect(CodeGenerators::GeneratorValidator.validate_source(source)).to be_empty
  end

  it "falls back to the uncategorized category" do
    expect(described_class.new.default_form_data[:category]).to eq("uncategorized")
  end

  it "echoes submitted params when a rejected save re-renders the form" do
    params = { description: "D", category: "utility", version: "2.0.0", registered_names: "a, b", methods_body: "def x; end" }
    expect(described_class.new(params).form_data_from_params).to eq(params)
  end
end
