# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::HashDiff do
  describe ".diff" do
    it "returns hashdiff patch tuples" do
      result = described_class.diff({ a: 1 }, { a: 2, b: 3 })
      expect(result).to eq([["~", "a", 1, 2], ["+", "b", 3]])
    end

    it "does not swallow unexpected hashdiff failures" do
      allow(Hashdiff).to receive(:diff).and_raise(StandardError, "diff failed")
      expect { described_class.diff({}, {}) }.to raise_error(StandardError, "diff failed")
    end
  end

  describe ".compare" do
    let(:before) { { name: "old", removed: 1, updated_at: 1 } }
    let(:after) { { name: "new", added: 2, updated_at: 2 } }

    it "returns added/removed/changed hashes in keys mode" do
      result = described_class.compare(before, after, ignore_keys: [:updated_at])
      expect(result[:added]).to eq(added: 2)
      expect(result[:removed]).to eq(removed: 1)
      expect(result[:changed]).to eq(name: { from: "old", to: "new" })
    end

    it "returns a boolean for equal" do
      expect(described_class.compare({ a: 1 }, { a: 1 }, comparison_type: "equal")).to be(true)
      expect(described_class.compare({ a: 1 }, { a: 2 }, comparison_type: "equal")).to be(false)
    end

    it "returns a boolean for schema_match" do
      expect(described_class.compare({ a: 1 }, { a: 2, b: 3 }, comparison_type: "schema_match")).to be(false)
    end
  end
end
