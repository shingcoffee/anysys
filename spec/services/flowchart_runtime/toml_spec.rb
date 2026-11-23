# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Toml do
  describe ".parse" do
    it "parses TOML into a hash" do
      expect(described_class.parse("title = \"hello\"\ncount = 3")).to eq("title" => "hello", "count" => 3)
    end

    it "raises Error on invalid TOML" do
      expect { described_class.parse("[[broken") }.to raise_error(FlowchartRuntime::Toml::Error)
    end
  end

  describe ".generate" do
    it "serializes a hash to TOML" do
      output = described_class.generate("name" => "test", "value" => 1)
      expect(output).to include("name")
      expect(output).to include("test")
    end
  end
end
