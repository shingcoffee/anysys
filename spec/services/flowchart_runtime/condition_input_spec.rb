# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::ConditionInput do
  describe ".provided?" do
    it "is false for nil and blank text" do
      expect(described_class.provided?(nil)).to be(false)
      expect(described_class.provided?("   ")).to be(false)
    end

    it "is false for an empty hash or array" do
      expect(described_class.provided?({})).to be(false)
      expect(described_class.provided?([])).to be(false)
    end

    it "is true for text and populated collections" do
      expect(described_class.provided?("anything")).to be(true)
      expect(described_class.provided?({ "type" => "group" })).to be(true)
      expect(described_class.provided?([1])).to be(true)
    end
  end

  describe ".structured" do
    it "passes a structured hash through" do
      hash = { "type" => "group", "conditions" => [] }
      expect(described_class.structured(hash)).to eq(hash)
    end

    it "parses a JSON document typed into the text field" do
      expect(described_class.structured('{"type":"group","conditions":[]}'))
        .to eq({ "type" => "group", "conditions" => [] })
    end

    it "returns nil for a hash without a type" do
      expect(described_class.structured({ "conditions" => [] })).to be_nil
    end

    it "returns nil for invalid JSON" do
      expect(described_class.structured("not json")).to be_nil
    end

    it "returns nil for JSON that is not an object" do
      expect(described_class.structured("[1,2]")).to be_nil
    end

    it "returns nil for unsupported input types" do
      expect(described_class.structured(42)).to be_nil
      expect(described_class.structured(nil)).to be_nil
    end
  end

  describe ".literal_pairs" do
    it "reads the editor's key_value_list shape" do
      raw = [{ "key" => "status", "value" => '"active"' }, { "key" => "role", "value" => "ctx[:role]" }]
      expect(described_class.literal_pairs(raw))
        .to eq([["status", '"active"'], ["role", "ctx[:role]"]])
    end

    it "reads a plain hash" do
      expect(described_class.literal_pairs({ "status" => "1" })).to eq([["status", "1"]])
    end

    it "drops entries whose column is not a bare identifier" do
      raw = [{ "key" => "id, admin: true", "value" => "1" }, { "key" => "ok", "value" => "2" }]
      expect(described_class.literal_pairs(raw)).to eq([["ok", "2"]])
    end

    it "drops non-hash array entries and returns [] for other input" do
      expect(described_class.literal_pairs(["nope"])).to eq([])
      expect(described_class.literal_pairs("nope")).to eq([])
      expect(described_class.literal_pairs(nil)).to eq([])
    end
  end

  describe ".safe_column?" do
    it "accepts bare identifiers only" do
      expect(described_class.safe_column?("created_at")).to be(true)
      expect(described_class.safe_column?("data.total")).to be(false)
      expect(described_class.safe_column?("")).to be(false)
    end
  end

  describe ".compare" do
    operators = %w[> >= < <=].freeze
    non_finite_strings = %w[Infinity -Infinity NaN 1e309].freeze

    it "compares numeric strings and numbers for > >= < <=" do
      expect(described_class.compare("150", ">", 100)).to be(true)
      expect(described_class.compare("abc", ">", 1)).to be(false)
      expect(described_class.compare(nil, "<", 1)).to be(false)
      expect(described_class.compare(2.5, "<=", "2.5")).to be(true)
    end

    it "treats non-finite form strings as non-numeric for every operator" do
      operators.each do |operator|
        non_finite_strings.each do |raw|
          expect(described_class.compare(raw, operator, 100)).to be(false),
            "expected compare(#{raw.inspect}, #{operator.inspect}, 100) to be false"
          expect(described_class.compare(100, operator, raw)).to be(false),
            "expected compare(100, #{operator.inspect}, #{raw.inspect}) to be false"
        end
      end
    end

    it "treats empty and whitespace-only strings as non-numeric" do
      operators.each do |operator|
        expect(described_class.compare("", operator, 1)).to be(false)
        expect(described_class.compare("   ", operator, 1)).to be(false)
        expect(described_class.compare(1, operator, "")).to be(false)
        expect(described_class.compare(1, operator, " \t\n")).to be(false)
      end
    end

    it "treats booleans as non-numeric" do
      operators.each do |operator|
        expect(described_class.compare(true, operator, 1)).to be(false)
        expect(described_class.compare(false, operator, 0)).to be(false)
        expect(described_class.compare(1, operator, true)).to be(false)
        expect(described_class.compare(0, operator, false)).to be(false)
      end
    end

    it "compares BigDecimal, Integer, and Float mixes" do
      expect(described_class.compare(BigDecimal("2.50"), "<=", "2.5")).to be(true)
      expect(described_class.compare(BigDecimal("2.50"), ">", 2)).to be(true)
      expect(described_class.compare(2, "<=", 2.0)).to be(true)
      expect(described_class.compare(2.5, ">=", BigDecimal("2.50"))).to be(true)
    end

    it "raises ArgumentError for an unsupported operator" do
      expect { described_class.compare(1, "==", 1) }.to raise_error(ArgumentError, /unsupported comparison operator/)
      expect { described_class.compare(1, "contains", 1) }.to raise_error(ArgumentError, /unsupported comparison operator/)
    end
  end
end
