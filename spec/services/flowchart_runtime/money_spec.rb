# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Money do
  describe ".round" do
    it "uses BigDecimal modes and never Float" do
      value = described_class.round("1.225", 2, "half_up")
      expect(value).to be_a(BigDecimal)
      expect(value).to eq(BigDecimal("1.23"))
      expect(described_class.round("1.225", 2, "half_even")).to eq(BigDecimal("1.22"))
      expect(described_class.round("1.229", 2, "floor")).to eq(BigDecimal("1.22"))
      expect(described_class.round("1.221", 2, "ceiling")).to eq(BigDecimal("1.23"))
    end
  end

  describe ".serialize" do
    it "returns a fixed-scale decimal string" do
      expect(described_class.serialize("10", 2, "half_up")).to eq("10.00")
      expect(described_class.serialize("10.5", 0, "half_up")).to eq("11")
    end
  end
end
