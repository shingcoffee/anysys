# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Cast do
  describe ".apply" do
    it "casts an integer" do
      expect(described_class.apply("42", type: "integer")).to eq(42)
    end

    it "casts a decimal via ActiveModel::Type" do
      expect(described_class.apply("19.50", type: "decimal")).to eq(BigDecimal("19.50"))
    end

    it "does not silently turn abc into 0" do
      expect { described_class.apply("abc", type: "integer") }
        .to raise_error(described_class::Error)
    end

    it "casts a boolean via ActiveModel by default" do
      expect(described_class.apply("false", type: "boolean")).to be(false)
    end

    it "casts a boolean strictly when asked" do
      expect(described_class.apply("yes", type: "boolean", strict_boolean: true)).to be(false)
      expect(described_class.apply(1, type: "boolean", strict_boolean: true)).to be(true)
    end

    it "parses a date with a format" do
      expect(described_class.apply("2026-10-19", type: "date", format: "%Y-%m-%d"))
        .to eq(Date.new(2026, 10, 19))
    end

    it "raises Error for an unparsable date" do
      expect { described_class.apply("not-a-date", type: "date") }
        .to raise_error(described_class::Error)
    end

    it "returns nil or the default when on_error is not fail" do
      expect(described_class.apply("not-a-date", type: "date", on_error: "nil")).to be_nil
      expect(described_class.apply("not-a-date", type: "date", on_error: "default", default_value: "x")).to eq("x")
    end

    it "raises Error for an unknown type" do
      expect { described_class.apply("x", type: "widget") }
        .to raise_error(described_class::Error, /unsupported type/)
    end
  end
end
