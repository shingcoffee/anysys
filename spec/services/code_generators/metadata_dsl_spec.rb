# frozen_string_literal: true

require "rails_helper"
# MetadataDSL lives in metadata_dsl.rb but its constant name doesn't match
# Zeitwerk's expected MetadataDsl. GeneratorInterface loads it via
# require_relative, so touching that constant first is the workaround.
CodeGenerators::GeneratorInterface

RSpec.describe CodeGenerators::MetadataDSL do
  subject(:dsl) { described_class.new }

  it "captures description" do
    dsl.description("Does the thing")
    expect(dsl.to_h[:description]).to eq("Does the thing")
  end

  it "captures category" do
    dsl.category(:validation)
    expect(dsl.to_h[:category]).to eq(:validation)
  end

  it "captures version" do
    dsl.version("2.1.0")
    expect(dsl.to_h[:version]).to eq("2.1.0")
  end

  it "captures an explicit generator name" do
    dsl.name("query_models")
    expect(dsl.to_h[:name]).to eq("query_models")
  end

  it "captures presentation metadata" do
    dsl.presentation(icon: "circle", color: "blue", single_use: false, privileged: true)
    expect(dsl.to_h[:presentation]).to eq(icon: "circle", color: "blue", single_use: false, privileged: true)
  end

  it "raises on an unknown presentation option" do
    expect { dsl.presentation(icon: "x", extra: true) }
      .to raise_error(ArgumentError, /unknown presentation option/)
  end

  it "captures error_strategy_default" do
    dsl.error_strategy_default(:fail)
    expect(dsl.to_h[:error_strategy_default]).to eq(:fail)
  end

  it "returns a frozen Hash from to_h" do
    dsl.description("x")
    result = dsl.to_h
    expect(result).to be_frozen
  end

  it "allows multiple to_h calls without raising FrozenError" do
    dsl.description("x")
    dsl.to_h
    expect { dsl.to_h }.not_to raise_error
  end

  it "allows fields to be set after to_h has been called" do
    dsl.description("initial")
    dsl.to_h
    expect { dsl.version("3.0.0") }.not_to raise_error
    expect(dsl.to_h[:version]).to eq("3.0.0")
  end

  describe ".bump_patch" do
    it "increments the patch segment" do
      expect(described_class.bump_patch("1.2.3")).to eq("1.2.4")
    end

    it "handles zero patch" do
      expect(described_class.bump_patch("2.0.0")).to eq("2.0.1")
    end

    it "handles single-digit edge version" do
      expect(described_class.bump_patch("1.0.9")).to eq("1.0.10")
    end

    it "defaults to '1.0.1' when the input has fewer than 3 parts" do
      # Parts < 3 resets to ["1","0","0"] then bumps patch to 1
      expect(described_class.bump_patch("1.0")).to eq("1.0.1")
    end

    it "handles nil input" do
      # nil.to_s = "" → split(".") = [""] → size 1 < 3 → resets then bumps
      expect(described_class.bump_patch(nil)).to eq("1.0.1")
    end
  end
end
