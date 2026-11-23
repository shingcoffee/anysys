# frozen_string_literal: true

require "rails_helper"

RSpec.describe "removed structural element generators" do
  REMOVED_TYPES = %w[
    fork join parallel_for_each saga signal_wait transaction switch timer
  ].freeze

  it "does not register unsupported structural element types" do
    registry = CodeGenerators::GeneratorRegistry.instance

    REMOVED_TYPES.each do |type|
      expect(registry.find_element_type(type)).to be_nil, type
    end
  end

  it "keeps the retained structural registry bounded" do
    expect(CodeGenerators::GeneratorRegistry.instance.element_type_generators.keys)
      .to contain_exactly("start", "end", "decision", "loop", "subflow")
  end

  # Each of these carried a full generator that the registry could never load
  # (GeneratorRegistry#discover! filters on SUPPORTED_ELEMENT_TYPES) and that
  # both structure validators reject outright. Dead generator source is worse
  # than no source: it is never exercised by the conformance, tenant-scoping or
  # audit harnesses, so it silently accumulates defects.
  REMOVED_GENERATOR_DIRS = %w[
    fork join parallel_for_each saga signal_wait transaction timer
  ].freeze

  REMOVED_GENERATOR_DIRS.each do |type|
    it "keeps no generator source for the #{type} element type" do
      expect(Rails.root.join("app/services/code_generators/element_types", type)).not_to exist
      expect(CodeGenerators::ElementTypes.const_defined?(type.camelize, false)).to be(false)
    end

    it "still rejects flowcharts that contain a #{type} element" do
      expect(ActivityGenerator::StructureValidator::UNSUPPORTED_STRUCTURAL_TYPES)
        .to include(type)
    end
  end

  it "leaves no element-type directory outside the supported set" do
    dirs = Rails.root.join("app/services/code_generators/element_types")
                .children.select(&:directory?).map { |d| d.basename.to_s }

    expect(dirs).to match_array(%w[start end decision loop subflow process])
  end
end
