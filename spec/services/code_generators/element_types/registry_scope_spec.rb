# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::GeneratorRegistry do
  UNSUPPORTED_TYPES = %w[fork join saga transaction parallel_for_each signal_wait switch timer].freeze

  it "registers exactly the five supported element types" do
    expect(described_class.element_type_generators.keys)
      .to match_array(%w[start end decision loop subflow])
  end

  UNSUPPORTED_TYPES.each do |type|
    it "does not resolve the unsupported #{type} element type" do
      expect(described_class.find_element_type(type)).to be_nil
    end

    it "does not offer #{type} in the builder property schema" do
      expect(CodeGenerators::Shared::SchemaReader.read(type)).to eq([])
    end
  end
end
