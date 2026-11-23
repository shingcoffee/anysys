# frozen_string_literal: true

require "rails_helper"

RSpec.describe Search::BaseSource do
  # Concrete subclass for testing — provides the abstract methods.
  let(:concrete_class) do
    Class.new(described_class) do
      def group_key   = :test_group
      def group_label = "Test Group"
      def items       = [{ id: 1, name: "Result" }]
    end
  end

  let(:customer) { build_stubbed(:customer) }
  let(:user)     { build_stubbed(:user) }

  def group_for(query)
    concrete_class.new(customer: customer, query: query, user: user).to_group
  end

  describe "#to_group" do
    it "returns a hash with key, label, and items when query is long enough" do
      result = group_for("ab")
      expect(result[:key]).to   eq(:test_group)
      expect(result[:label]).to eq("Test Group")
      expect(result[:items]).not_to be_empty
    end

    it "returns an empty items array when query is shorter than MIN_QUERY_LENGTH" do
      expect(group_for("a")[:items]).to eq([])
    end

    it "returns empty items for a blank query" do
      expect(group_for("")[:items]).to eq([])
    end

    it "strips leading/trailing whitespace from query before checking length" do
      # " a " strips to "a" which is 1 char — below threshold
      expect(group_for(" a ")[:items]).to eq([])
    end

    it "returns items when query meets exactly the minimum length" do
      expect(group_for("ab")[:items]).not_to be_empty
    end
  end

  describe "abstract interface" do
    it "raises NotImplementedError for group_key on base class" do
      source = described_class.new(customer: customer, query: "test", user: user)
      expect { source.to_group }.to raise_error(NotImplementedError)
    end
  end

  describe "MIN_QUERY_LENGTH constant" do
    it "equals 2" do
      expect(described_class::MIN_QUERY_LENGTH).to eq(2)
    end
  end

  describe "MAX_PER_GROUP constant" do
    it "equals 5" do
      expect(described_class::MAX_PER_GROUP).to eq(5)
    end
  end
end
