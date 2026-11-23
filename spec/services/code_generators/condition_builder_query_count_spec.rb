# frozen_string_literal: true

require "rails_helper"

class ConditionBuilderTestHarness
  include CodeGenerators::Shared::ConditionBuilder
end

RSpec.describe CodeGenerators::Shared::ConditionBuilder, "query count conditions" do
  let(:harness) { ConditionBuilderTestHarness.new }

  describe "#build_query_count_condition" do
    it "generates QueryBuilder count code" do
      condition = {
        "kind" => "query_count",
        "queryConfig" => {
          "entityId" => 42,
          "conditions" => { "operator" => "AND", "rules" => [{ "field" => "data.status", "op" => "==", "value" => "active" }] }
        },
        "countOperator" => ">",
        "countValue" => 5
      }
      code = harness.build_query_count_condition(condition)
      expect(code).to include("FlowchartRuntime::QueryBuilder")
      expect(code).to include("FlowchartRuntime::EntityResolver.find(42, customer_id: ctx[:customer_id])")
      expect(code).not_to include("(Entity.find(")
      expect(code).to include(".execute.total_count")
      expect(code).to include("> 5")
    end

    it "handles == operator" do
      condition = { "kind" => "query_count", "queryConfig" => { "entityId" => 10 }, "countOperator" => "==", "countValue" => 0 }
      code = harness.build_query_count_condition(condition)
      expect(code).to include("== 0")
    end

    it "omits where clause when no conditions" do
      condition = { "kind" => "query_count", "queryConfig" => { "entityId" => 10 }, "countOperator" => ">", "countValue" => 0 }
      code = harness.build_query_count_condition(condition)
      expect(code).not_to include(".where(")
    end

    it "defaults countValue to 0" do
      condition = { "kind" => "query_count", "queryConfig" => { "entityId" => 10 }, "countOperator" => ">" }
      code = harness.build_query_count_condition(condition)
      expect(code).to include("> 0")
    end
  end
end
