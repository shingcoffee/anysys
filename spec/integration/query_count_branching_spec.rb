# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Query count branching integration", type: :model do
  let(:customer) { create(:customer) }
  let(:order_entity) do
    create(:entity, name: "Order", customer: customer, property_schema: [
      { "name" => "Status", "name_slug" => "status", "type" => "String", "html_type" => "text" },
      { "name" => "Amount", "name_slug" => "amount", "type" => "Float", "html_type" => "number" }
    ].to_json)
  end

  # Builds a DecisionGenerator element using the current interface:
  #   - `condition`: a group containing a single query_count kind member
  # Without topology the generator returns the boolean condition value
  # (true / false), not a route signal.
  def decision_element(entity_id:, rules:, count_operator:, count_value:)
    {
      "id" => "d1", "type" => "decision", "label" => "Check Orders",
      "properties" => {
        "routeBy" => "condition",
        "condition" => {
          "type" => "group",
          "joins" => [],
          "conditions" => [
            {
              "kind" => "query_count",
              "queryConfig" => {
                "entityId" => entity_id,
                "conditions" => { "operator" => "AND", "rules" => rules }
              },
              "countOperator" => count_operator,
              "countValue" => count_value
            }
          ]
        },
      }
    }
  end

  # Compiles the decision condition (no topology) and returns the boolean result.
  def route_for(element)
    code = CodeGenerators::ElementTypes::Decision::DecisionGenerator.new(element, {}).generate_body
    ctx = { customer_id: customer.id }
    eval(code, binding) # rubocop:disable Security/Eval
  end

  describe "query_count condition execution" do
    it "takes true branch when count exceeds threshold" do
      create(:entity_entry, entity: order_entity, customer: customer, data: { "status" => "active", "amount" => "100" }.to_json)
      create(:entity_entry, entity: order_entity, customer: customer, data: { "status" => "active", "amount" => "200" }.to_json)
      create(:entity_entry, entity: order_entity, customer: customer, data: { "status" => "cancelled", "amount" => "50" }.to_json)

      element = decision_element(
        entity_id: order_entity.id,
        rules: [{ "field" => "data.status", "op" => "==", "value" => "active" }],
        count_operator: ">",
        count_value: 1
      )

      expect(route_for(element)).to be(true) # 2 active orders > 1
    end

    it "takes else branch when count condition is false" do
      create(:entity_entry, entity: order_entity, customer: customer, data: { "status" => "active", "amount" => "100" }.to_json)

      element = decision_element(
        entity_id: order_entity.id,
        rules: [{ "field" => "data.status", "op" => "==", "value" => "active" }],
        count_operator: ">",
        count_value: 1
      )

      expect(route_for(element)).to be(false) # 1 active order is NOT > 1
    end

    it "routes via query_count without an entity-level where clause" do
      # No entries at all — count == 0, threshold == 0 → false (not > 0)
      element = decision_element(
        entity_id: order_entity.id,
        rules: [],
        count_operator: ">",
        count_value: 0
      )

      expect(route_for(element)).to be(false) # 0 orders NOT > 0
    end

    it "checks existence with == 0" do
      # No orders at all
      element = decision_element(
        entity_id: order_entity.id,
        rules: [],
        count_operator: "==",
        count_value: 0
      )

      expect(route_for(element)).to be(true) # 0 orders == 0
    end

    it "refuses another tenant's entity instead of counting it" do
      other_entity = create(:entity, name: "Foreign", customer: create(:customer))
      element = decision_element(entity_id: other_entity.id, rules: [], count_operator: "==", count_value: 0)

      expect { route_for(element) }.to raise_error(FlowchartRuntime::EntityResolver::Error)
    end
  end
end
