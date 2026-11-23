# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Json do
  describe ".parse" do
    it "parses a JSON document under the byte cap" do
      expect(described_class.parse('{"a":1}', max_bytes: 32)).to eq("a" => 1)
    end

    it "raises when the payload exceeds max_bytes" do
      expect { described_class.parse('{"a":1}', max_bytes: 3) }
        .to raise_error(described_class::Error, /bytes/)
    end

    it "raises a namespaced error for invalid JSON" do
      expect { described_class.parse("{", max_bytes: 16) }
        .to raise_error(described_class::Error)
    end
  end
end
