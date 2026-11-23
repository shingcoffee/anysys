# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::ValueMap do
  describe ".apply" do
    it "maps an exact value" do
      expect(described_class.apply("active", match_mode: "exact",
                                   mappings: { "active" => "Active" })).to eq("Active")
    end

    it "returns the default when nothing matches" do
      expect(described_class.apply("unknown", match_mode: "exact",
                                   mappings: { "active" => "Active" }, default: "Unknown"))
        .to eq("Unknown")
    end

    it "passes the input through on pass_through" do
      expect(described_class.apply("x", match_mode: "exact", mappings: {},
                                   fallback: "pass_through")).to eq("x")
    end

    it "raises Error on raise fallback" do
      expect { described_class.apply("x", match_mode: "exact", mappings: {}, fallback: "raise") }
        .to raise_error(described_class::Error, /no mapping for x/)
    end

    it "matches a regex rule without regard to case when asked" do
      expect(described_class.apply("AbC", match_mode: "regex",
                                   rules: [{ "pattern" => "^ABC$", "value" => "upper" }],
                                   case_sensitive: false)).to eq("upper")
    end

    it "matches a numeric range" do
      expect(described_class.apply(5, match_mode: "range",
                                   rules: [{ "pattern" => "1..10", "value" => "low" }])).to eq("low")
    end

    it "does not execute a malformed range pattern" do
      expect(described_class.apply(1, match_mode: "range",
                                   rules: [{ "pattern" => 'system("echo pwned")', "value" => "hit" }],
                                   default: "safe")).to eq("safe")
    end
  end
end
