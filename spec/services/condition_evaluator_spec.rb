# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConditionEvaluator do
  describe "#evaluate" do
    let(:field_values) do
      {
        "field_1" => "test",
        "field_2" => 100,
        "field_3" => true,
        "field_4" => ""
      }
    end

    def evaluate(conditions)
      described_class.new(conditions, field_values).evaluate
    end

    context "with equals operator" do
      it "returns true when values match" do
        expect(evaluate([{ "field_id" => "field_1", "operator" => "equals", "value" => "test" }])).to be true
      end

      it "returns false when values don't match" do
        expect(evaluate([{ "field_id" => "field_1", "operator" => "equals", "value" => "other" }])).to be false
      end
    end

    context "with not_equals operator" do
      it "returns true when values are different" do
        expect(evaluate([{ "field_id" => "field_1", "operator" => "not_equals", "value" => "other" }])).to be true
      end
    end

    context "with greater_than operator" do
      it "returns true when value is greater" do
        expect(evaluate([{ "field_id" => "field_2", "operator" => "greater_than", "value" => 50 }])).to be true
      end

      it "returns false when value is not greater" do
        expect(evaluate([{ "field_id" => "field_2", "operator" => "greater_than", "value" => 200 }])).to be false
      end
    end

    context "with less_than operator" do
      it "returns true when value is less" do
        expect(evaluate([{ "field_id" => "field_2", "operator" => "less_than", "value" => 200 }])).to be true
      end
    end

    context "with contains operator" do
      it "returns true when string contains value" do
        expect(evaluate([{ "field_id" => "field_1", "operator" => "contains", "value" => "es" }])).to be true
      end

      it "returns false when string does not contain value" do
        expect(evaluate([{ "field_id" => "field_1", "operator" => "contains", "value" => "xyz" }])).to be false
      end
    end

    context "with is_empty operator" do
      it "returns true when value is empty" do
        expect(evaluate([{ "field_id" => "field_4", "operator" => "is_empty", "value" => nil }])).to be true
      end

      it "returns false when value is not empty" do
        expect(evaluate([{ "field_id" => "field_1", "operator" => "is_empty", "value" => nil }])).to be false
      end
    end

    context "with is_not_empty operator" do
      it "returns true when value is not empty" do
        expect(evaluate([{ "field_id" => "field_1", "operator" => "is_not_empty", "value" => nil }])).to be true
      end
    end

    context "with multiple conditions and AND logic" do
      it "returns true when all conditions match" do
        expect(evaluate([
          { "field_id" => "field_1", "operator" => "equals", "value" => "test", "logic" => "and" },
          { "field_id" => "field_3", "operator" => "equals", "value" => true, "logic" => "and" }
        ])).to be true
      end

      it "returns false when any condition fails" do
        expect(evaluate([
          { "field_id" => "field_1", "operator" => "equals", "value" => "test", "logic" => "and" },
          { "field_id" => "field_3", "operator" => "equals", "value" => false, "logic" => "and" }
        ])).to be false
      end
    end

    context "with multiple conditions and OR logic" do
      it "returns true when any condition matches" do
        expect(evaluate([
          { "field_id" => "field_1", "operator" => "equals", "value" => "wrong", "logic" => "or" },
          { "field_id" => "field_3", "operator" => "equals", "value" => true, "logic" => "or" }
        ])).to be true
      end
    end

    context "with empty conditions" do
      it "returns true when no conditions" do
        expect(evaluate([])).to be true
      end

      it "returns true when conditions is nil" do
        expect(evaluate(nil)).to be true
      end
    end
  end
end
