# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::PathIdentity do
  it "resolves generators by exact relative path" do
    expect(described_class.find("element_types/process/model_operations/query_models_generator"))
      .to eq(CodeGenerators::ElementTypes::Process::ModelOperations::QueryModelsGenerator)
    expect(described_class.find("element_types/process/data_operations/assign_value_generator"))
      .to eq(CodeGenerators::ElementTypes::Process::DataOperations::AssignValueGenerator)
  end

  it "does not fall back to basename for an unknown or traversing path" do
    expect(described_class.find("unrelated/start_generator")).to be_nil
    expect(described_class.find("../element_types/start/start_generator")).to be_nil
  end
end
