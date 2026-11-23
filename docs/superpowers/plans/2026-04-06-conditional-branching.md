# Conditional / Branching Logic Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enhance the Decision element to support query-count-based branching alongside existing field comparisons, with independent condition types per connection.

**Architecture:** The `DecisionGenerator` is extended to detect `conditionType: "query_count"` on connection conditions and generate inline QueryBuilder count queries. A new `build_query_count_condition` method in `ConditionBuilder` produces the query code. Each connection condition independently chooses its type, enabling mixed field + query_count branches in a single Decision.

**Tech Stack:** Ruby on Rails 8.1, RSpec, FactoryBot, Trailblazer Activity

**Spec:** `docs/superpowers/specs/2026-04-06-conditional-branching-design.md`

---

## File Map

### New Files

| File | Responsibility |
|---|---|
| `spec/services/code_generators/decision_query_count_spec.rb` | Tests for query_count code generation |
| `spec/integration/query_count_branching_spec.rb` | End-to-end branching test |

### Modified Files

| File | Change |
|---|---|
| `app/services/code_generators/element_types/decision/decision_generator.rb` | Route `query_count` conditions to new builder method |
| `app/services/code_generators/shared/condition_builder.rb` | Add `build_query_count_condition` method |

---

## Task 1: ConditionBuilder — Add query count condition builder

**Files:**
- Modify: `app/services/code_generators/shared/condition_builder.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/code_generators/condition_builder_query_count_spec.rb
# frozen_string_literal: true

require "rails_helper"

# Test helper class to include the module
class ConditionBuilderTestHarness
  include CodeGenerators::Shared::ConditionBuilder
end

RSpec.describe CodeGenerators::Shared::ConditionBuilder, "query count conditions" do
  let(:harness) { ConditionBuilderTestHarness.new }

  describe "#build_query_count_condition" do
    it "generates QueryBuilder count code" do
      condition = {
        "conditionType" => "query_count",
        "queryConfig" => {
          "entityId" => 42,
          "conditions" => {
            "operator" => "AND",
            "rules" => [{ "field" => "data.status", "op" => "==", "value" => "active" }]
          }
        },
        "countOperator" => ">",
        "countValue" => 5
      }

      code = harness.build_query_count_condition(condition)
      expect(code).to include("FlowchartRuntime::QueryBuilder")
      expect(code).to include("Entity.find(42)")
      expect(code).to include(".execute")
      expect(code).to include(".total_count")
      expect(code).to include("> 5")
    end

    it "handles == operator" do
      condition = {
        "conditionType" => "query_count",
        "queryConfig" => { "entityId" => 10 },
        "countOperator" => "==",
        "countValue" => 0
      }

      code = harness.build_query_count_condition(condition)
      expect(code).to include("== 0")
    end

    it "generates query without conditions when none specified" do
      condition = {
        "conditionType" => "query_count",
        "queryConfig" => { "entityId" => 10 },
        "countOperator" => ">",
        "countValue" => 0
      }

      code = harness.build_query_count_condition(condition)
      expect(code).to include("Entity.find(10)")
      expect(code).not_to include(".where(")
    end

    it "defaults countValue to 0" do
      condition = {
        "conditionType" => "query_count",
        "queryConfig" => { "entityId" => 10 },
        "countOperator" => ">"
      }

      code = harness.build_query_count_condition(condition)
      expect(code).to include("> 0")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/condition_builder_query_count_spec.rb`
Expected: FAIL — `undefined method 'build_query_count_condition'`

- [ ] **Step 3: Add build_query_count_condition to ConditionBuilder**

In `app/services/code_generators/shared/condition_builder.rb`, add this method inside the module (after `build_single_condition`, before the closing `end`s):

```ruby
      # Build a query-count condition that executes a count query and compares the result.
      #
      # @param condition [Hash] with keys: queryConfig, countOperator, countValue
      # @return [String] Ruby code expression
      def build_query_count_condition(condition)
        query_config = condition["queryConfig"] || {}
        entity_id = query_config["entityId"]
        where_conditions = query_config["conditions"]
        count_op = condition["countOperator"] || ">"
        count_val = condition["countValue"] || 0

        lines = []
        lines << "FlowchartRuntime::QueryBuilder.for_entity(Entity.find(#{entity_id.to_i}), customer_id: ctx[:customer_id])"

        if where_conditions.is_a?(Hash) && where_conditions["rules"].present?
          lines << "  .where(#{where_conditions.inspect}, ctx)"
        end

        lines << "  .execute.total_count #{count_op} #{count_val.to_i}"

        lines.join("\n")
      end
```

Make sure this method is public (not under the `private` keyword). Move it above the `private` keyword in the module.

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/condition_builder_query_count_spec.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/shared/condition_builder.rb spec/services/code_generators/condition_builder_query_count_spec.rb
git commit -m "feat: add build_query_count_condition to ConditionBuilder"
```

---

## Task 2: DecisionGenerator — Handle query_count connection conditions

**Files:**
- Modify: `app/services/code_generators/element_types/decision/decision_generator.rb`
- Create: `spec/services/code_generators/decision_query_count_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/code_generators/decision_query_count_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Decision::DecisionGenerator do
  let(:context) { { bound_entity: nil } }

  def build_generator(config)
    element = {
      "id" => "d1",
      "type" => "decision",
      "label" => "Test Decision",
      "properties" => {},
      "config" => config
    }
    described_class.new(element, context)
  end

  describe "query_count connection conditions" do
    it "generates QueryBuilder count code for query_count conditionType" do
      gen = build_generator({
        "condition" => {},
        "_route_index" => 0,
        "_connection_conditions" => [
          {
            "branch" => "branch_0",
            "condition" => {
              "conditionType" => "query_count",
              "queryConfig" => { "entityId" => 42, "conditions" => { "operator" => "AND", "rules" => [{ "field" => "data.status", "op" => "==", "value" => "active" }] } },
              "countOperator" => ">",
              "countValue" => 5
            }
          },
          { "branch" => "branch_1", "condition" => nil }
        ]
      })

      code = gen.generate
      expect(code).to include("FlowchartRuntime::QueryBuilder")
      expect(code).to include("Entity.find(42)")
      expect(code).to include("> 5")
      expect(code).to include("ctx[:_route_0] = :branch_0")
      expect(code).to include("ctx[:_route_0] = :branch_1")
    end

    it "generates mixed field + query_count conditions" do
      gen = build_generator({
        "condition" => {},
        "_route_index" => 0,
        "_connection_conditions" => [
          {
            "branch" => "branch_0",
            "condition" => {
              "conditionType" => "query_count",
              "queryConfig" => { "entityId" => 10 },
              "countOperator" => ">",
              "countValue" => 0
            }
          },
          {
            "branch" => "branch_1",
            "condition" => {
              "operator" => "AND",
              "rules" => [{ "field" => "ctx.status", "op" => "==", "value" => "approved" }]
            }
          },
          { "branch" => "branch_2", "condition" => nil }
        ]
      })

      code = gen.generate
      # First branch: query count
      expect(code).to include("FlowchartRuntime::QueryBuilder")
      expect(code).to include(":branch_0")
      # Second branch: field condition
      expect(code).to include("ctx.dig(:status)")
      expect(code).to include(":branch_1")
      # Default branch
      expect(code).to include(":branch_2")
    end

    it "preserves backward compatibility for field conditions" do
      gen = build_generator({
        "condition" => {},
        "_route_index" => 0,
        "_connection_conditions" => [
          {
            "branch" => "branch_0",
            "condition" => {
              "operator" => "AND",
              "rules" => [{ "field" => "ctx.amount", "op" => ">", "value" => "100" }]
            }
          },
          { "branch" => "branch_1", "condition" => nil }
        ]
      })

      code = gen.generate
      expect(code).to include("ctx.dig(:amount)")
      expect(code).not_to include("QueryBuilder")
    end

    it "handles binary decision with no connection conditions" do
      gen = build_generator({
        "condition" => { "leftOperand" => "ctx.active", "operator" => "is_true" },
        "_route_index" => 0,
        "_connection_conditions" => []
      })

      code = gen.generate
      expect(code).to include("branch_0")
      expect(code).to include("branch_1")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/decision_query_count_spec.rb`
Expected: FAIL — query_count condition not handled, generates nil

- [ ] **Step 3: Update DecisionGenerator to handle query_count**

In `app/services/code_generators/element_types/decision/decision_generator.rb`, update the `build_connection_condition` method:

Replace:
```ruby
        def build_connection_condition(condition)
          return nil unless condition.is_a?(Hash)

          if condition["rules"].present?
            # ConditionBuilder / WhereClause format — {operator, rules}
            build_rules_condition(condition)
          elsif condition["leftOperand"].present?
            # Property editor single condition
            build_structured_condition(condition)
          elsif condition["type"] == "group" && condition["conditions"].present?
            # Nested group condition
            build_structured_condition(condition)
          end
        end
```

With:
```ruby
        def build_connection_condition(condition)
          return nil unless condition.is_a?(Hash)

          if condition["conditionType"] == "query_count"
            # Query count condition — runs a count query and compares
            build_query_count_condition(condition)
          elsif condition["rules"].present?
            # ConditionBuilder / WhereClause format — {operator, rules}
            build_rules_condition(condition)
          elsif condition["leftOperand"].present?
            # Property editor single condition
            build_structured_condition(condition)
          elsif condition["type"] == "group" && condition["conditions"].present?
            # Nested group condition
            build_structured_condition(condition)
          end
        end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/decision_query_count_spec.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/decision/decision_generator.rb spec/services/code_generators/decision_query_count_spec.rb
git commit -m "feat: handle query_count conditions in DecisionGenerator"
```

---

## Task 3: Integration test — Query count branching end-to-end

**Files:**
- Create: `spec/integration/query_count_branching_spec.rb`

- [ ] **Step 1: Write the integration test**

```ruby
# spec/integration/query_count_branching_spec.rb
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

  describe "DecisionGenerator with query_count" do
    it "generates code that counts entity entries" do
      # Create some orders
      create(:entity_entry, entity: order_entity, customer: customer, data: { "status" => "active", "amount" => "100" }.to_json)
      create(:entity_entry, entity: order_entity, customer: customer, data: { "status" => "active", "amount" => "200" }.to_json)
      create(:entity_entry, entity: order_entity, customer: customer, data: { "status" => "cancelled", "amount" => "50" }.to_json)

      # Build a decision generator with query_count condition
      element = {
        "id" => "d1", "type" => "decision", "label" => "Check Orders",
        "properties" => {},
        "config" => {
          "condition" => {},
          "_route_index" => 0,
          "_connection_conditions" => [
            {
              "branch" => "branch_0",
              "condition" => {
                "conditionType" => "query_count",
                "queryConfig" => {
                  "entityId" => order_entity.id,
                  "conditions" => {
                    "operator" => "AND",
                    "rules" => [{ "field" => "data.status", "op" => "==", "value" => "active" }]
                  }
                },
                "countOperator" => ">",
                "countValue" => 1
              }
            },
            { "branch" => "branch_1", "condition" => nil }
          ]
        }
      }

      generator = CodeGenerators::ElementTypes::Decision::DecisionGenerator.new(element, {})
      code = generator.generate

      # Verify generated code is valid Ruby that evaluates correctly
      expect(code).to include("FlowchartRuntime::QueryBuilder")
      expect(code).to include("> 1")

      # Execute the generated code to verify it actually works
      ctx = { customer_id: customer.id }
      eval(code, binding) # rubocop:disable Security/Eval
      expect(ctx[:_route_0]).to eq(:branch_0) # 2 active orders > 1
    end

    it "takes else branch when count condition is false" do
      # Only 1 active order
      create(:entity_entry, entity: order_entity, customer: customer, data: { "status" => "active", "amount" => "100" }.to_json)

      element = {
        "id" => "d1", "type" => "decision", "label" => "Check Orders",
        "properties" => {},
        "config" => {
          "condition" => {},
          "_route_index" => 0,
          "_connection_conditions" => [
            {
              "branch" => "branch_0",
              "condition" => {
                "conditionType" => "query_count",
                "queryConfig" => {
                  "entityId" => order_entity.id,
                  "conditions" => {
                    "operator" => "AND",
                    "rules" => [{ "field" => "data.status", "op" => "==", "value" => "active" }]
                  }
                },
                "countOperator" => ">",
                "countValue" => 1
              }
            },
            { "branch" => "branch_1", "condition" => nil }
          ]
        }
      }

      generator = CodeGenerators::ElementTypes::Decision::DecisionGenerator.new(element, {})
      code = generator.generate

      ctx = { customer_id: customer.id }
      eval(code, binding) # rubocop:disable Security/Eval
      expect(ctx[:_route_0]).to eq(:branch_1) # 1 active order is NOT > 1
    end

    it "handles mixed field and query_count conditions" do
      create(:entity_entry, entity: order_entity, customer: customer, data: { "status" => "active", "amount" => "100" }.to_json)

      element = {
        "id" => "d1", "type" => "decision", "label" => "Mixed",
        "properties" => {},
        "config" => {
          "condition" => {},
          "_route_index" => 0,
          "_connection_conditions" => [
            {
              "branch" => "branch_0",
              "condition" => {
                "conditionType" => "query_count",
                "queryConfig" => { "entityId" => order_entity.id },
                "countOperator" => ">",
                "countValue" => 10
              }
            },
            {
              "branch" => "branch_1",
              "condition" => {
                "operator" => "AND",
                "rules" => [{ "field" => "ctx.mode", "op" => "==", "value" => "manual" }]
              }
            },
            { "branch" => "branch_2", "condition" => nil }
          ]
        }
      }

      generator = CodeGenerators::ElementTypes::Decision::DecisionGenerator.new(element, {})
      code = generator.generate

      # Count is 1 (not > 10), mode is "manual" → branch_1
      ctx = { customer_id: customer.id, mode: "manual" }
      eval(code, binding) # rubocop:disable Security/Eval
      expect(ctx[:_route_0]).to eq(:branch_1)
    end
  end
end
```

- [ ] **Step 2: Run integration test**

Run: `bundle exec rspec spec/integration/query_count_branching_spec.rb`
Expected: All PASS

- [ ] **Step 3: Commit**

```bash
git add spec/integration/query_count_branching_spec.rb
git commit -m "test: add integration tests for query-count-based branching"
```
