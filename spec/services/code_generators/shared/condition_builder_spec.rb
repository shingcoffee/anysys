# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::Shared::ConditionBuilder do
  let(:builder) do
    Class.new do
      include CodeGenerators::Shared::ConditionBuilder
    end.new
  end

  describe "#build_structured_condition" do
    it "returns 'true' for blank condition" do
      expect(builder.build_structured_condition(nil)).to eq("true")
      expect(builder.build_structured_condition({})).to eq("true")
    end

    it "builds a simple equality condition" do
      condition = { "leftOperand" => "ctx.status", "operator" => "==", "rightOperand" => "active" }
      result = builder.build_structured_condition(condition)
      expect(result).to eq('ctx[:status] == "active"')
    end

    it "emits ConditionInput.compare for numeric comparison operators" do
      {
        ">" => 'FlowchartRuntime::ConditionInput.compare(FlowchartRuntime::Step.dig(ctx[:params], :amount), ">", 100)',
        ">=" => 'FlowchartRuntime::ConditionInput.compare(ctx[:count], ">=", 1)',
        "<" => 'FlowchartRuntime::ConditionInput.compare(ctx[:count], "<", 5)',
        "<=" => 'FlowchartRuntime::ConditionInput.compare(ctx[:score], "<=", 2.5)'
      }.each do |operator, expected|
        left, right = case operator
        when ">" then ["ctx.params.amount", "100"]
        when ">=" then ["ctx.count", "1"]
        when "<" then ["ctx.count", "5"]
        else ["ctx.score", "2.5"]
        end
        result = builder.build_structured_condition(
          { "leftOperand" => left, "operator" => operator, "rightOperand" => right }
        )
        expect(result).to eq(expected)
      end
    end

    it "builds unary operators that cover booleans and blank" do
      expect(builder.build_structured_condition(
        { "leftOperand" => "ctx.name", "operator" => "is_empty" }
      )).to eq("ctx[:name].blank?")

      expect(builder.build_structured_condition(
        { "leftOperand" => "ctx.name", "operator" => "is_not_empty" }
      )).to eq("ctx[:name].present?")

      expect(builder.build_structured_condition(
        { "leftOperand" => "ctx.flag", "operator" => "is_true" }
      )).to eq("!!ctx[:flag]")

      expect(builder.build_structured_condition(
        { "leftOperand" => "ctx.flag", "operator" => "is_false" }
      )).to eq("!ctx[:flag]")

      expect(builder.build_structured_condition(
        { "leftOperand" => "ctx.val", "operator" => "is_nil" }
      )).to eq("ctx[:val].nil?")
    end

    it "builds string operators" do
      expect(builder.build_structured_condition(
        { "leftOperand" => "ctx.name", "operator" => "contains", "rightOperand" => "test" }
      )).to eq('ctx[:name].to_s.include?("test".to_s)')

      expect(builder.build_structured_condition(
        { "leftOperand" => "ctx.name", "operator" => "starts_with", "rightOperand" => "pre" }
      )).to eq('ctx[:name].to_s.start_with?("pre".to_s)')
    end

    it "normalizes malformed regular expressions to false" do
      expect(builder.build_structured_condition(
        { "leftOperand" => "ctx.name", "operator" => "matches_regex", "rightOperand" => "[" }
      )).to eq("false")
    end

    it "raises for an unknown operator instead of falling back to ==" do
      expect {
        builder.build_structured_condition(
          { "leftOperand" => "ctx.status", "operator" => "wat", "rightOperand" => "x" }
        )
      }.to raise_error(ArgumentError, /unknown condition operator: "wat"/)
    end

    it "builds AND group conditions" do
      group = {
        "type" => "group",
        "operator" => "AND",
        "conditions" => [
          { "leftOperand" => "ctx.a", "operator" => "==", "rightOperand" => "active" },
          { "leftOperand" => "ctx.b", "operator" => "==", "rightOperand" => "pending" }
        ]
      }
      result = builder.build_structured_condition(group)
      expect(result).to eq('(ctx[:a] == "active" && ctx[:b] == "pending")')
    end

    it "builds OR group conditions" do
      group = {
        "type" => "group",
        "joins" => ["OR"],
        "conditions" => [
          { "leftOperand" => "ctx.x", "operator" => "is_true" },
          { "leftOperand" => "ctx.y", "operator" => "is_true" }
        ]
      }
      result = builder.build_structured_condition(group)
      expect(result).to eq("(!!ctx[:x] || !!ctx[:y])")
    end

    it "rejects nested group members" do
      group = {
        "type" => "group",
        "joins" => ["AND"],
        "conditions" => [
          { "leftOperand" => "ctx.a", "operator" => "==", "rightOperand" => "1" },
          {
            "type" => "group",
            "joins" => ["OR"],
            "conditions" => [
              { "leftOperand" => "ctx.b", "operator" => "==", "rightOperand" => "2" },
              { "leftOperand" => "ctx.c", "operator" => "==", "rightOperand" => "3" }
            ]
          }
        ]
      }
      expect { builder.build_structured_condition(group) }
        .to raise_error(ArgumentError, /nested condition groups are not allowed/)
    end
  end

  describe "per-join groups" do
    it "folds left-to-right with explicit parens and per-join operators" do
      cond = { "type" => "group", "joins" => ["AND", "OR"],
               "conditions" => [
                 { "kind" => "field", "leftOperand" => "ctx.a", "operator" => "==", "rightOperand" => "1" },
                 { "kind" => "field", "leftOperand" => "ctx.b", "operator" => "==", "rightOperand" => "2" },
                 { "kind" => "field", "leftOperand" => "ctx.c", "operator" => "==", "rightOperand" => "3" }
               ] }
      expect(builder.build_structured_condition(cond))
        .to eq('((ctx[:a] == 1 && ctx[:b] == 2) || ctx[:c] == 3)')
    end

    it "includes a query-count member inside a group" do
      cond = { "type" => "group", "joins" => ["AND"],
               "conditions" => [
                 { "kind" => "field", "leftOperand" => "ctx.a", "operator" => "==", "rightOperand" => "1" },
                 { "kind" => "query_count", "queryConfig" => { "entityId" => 7 }, "countOperator" => ">", "countValue" => 0 }
               ] }
      code = builder.build_structured_condition(cond)
      expect(code).to start_with("(ctx[:a] == 1 && ")
      expect(code).to include("FlowchartRuntime::QueryBuilder.for_entity(FlowchartRuntime::EntityResolver.find(7, customer_id: ctx[:customer_id])")
      expect(code).to include(".execute.total_count > 0")
    end
  end
end
