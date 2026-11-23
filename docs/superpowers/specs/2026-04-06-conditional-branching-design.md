# Conditional / Branching Logic Enhancement Design

**Date:** 2026-04-06
**Gap Reference:** Gap #1 from gap-analysis-anysys-vs-fw.md
**Status:** Draft

---

## Overview

Enhance the Decision element to support query-count-based branching alongside existing field comparisons. Each connection condition independently specifies its type (`field` or `query_count`), allowing mixed conditions within a single Decision. Query count conditions execute a database count query inline and branch based on the result. Calculated fields are already usable in conditions via the WhereClauseBuilder enhancement from Gap #5.

---

## 1. Decision Element — Query Count Mode

### Connection condition format

Each connection condition gains an optional `conditionType` field:

```json
{
  "id": "conn_1",
  "from": "decision_1",
  "to": "process_high",
  "label": "Many orders",
  "condition": {
    "conditionType": "query_count",
    "queryConfig": {
      "entityId": 45,
      "conditions": {
        "operator": "AND",
        "rules": [
          { "field": "data.status", "op": "==", "value": "active" }
        ]
      }
    },
    "countOperator": ">",
    "countValue": 5
  }
}
```

### conditionType values

- `"field"` (default, current behavior) — evaluates field comparison rules
- `"query_count"` — runs a count query and compares the result

When `conditionType` is absent or `"field"`, the existing condition format applies unchanged (backward compatible).

---

## 2. Code Generation

### Query count condition — generated code

```ruby
_query_count = FlowchartRuntime::QueryBuilder
  .for_entity(Entity.find(45), customer_id: ctx[:customer_id])
  .where({"operator" => "AND", "rules" => [...]}, ctx)
  .execute
  .total_count
_query_count > 5
```

### Field condition — unchanged

Existing code generation for field comparisons is unchanged.

### Mixed example — Decision with three branches

```ruby
if (FlowchartRuntime::QueryBuilder.for_entity(Entity.find(45), customer_id: ctx[:customer_id]).where(..., ctx).execute.total_count > 5)
  ctx[:_route_0] = :branch_0
elsif ctx.dig(:status) == "approved"
  ctx[:_route_0] = :branch_1
else
  ctx[:_route_0] = :branch_2
end
true
```

---

## 3. ConditionBuilder Enhancements

### Calculated fields in conditions

Already addressed by Gap #5 — calculated fields appear in property_schema field picker automatically and WhereClauseBuilder substitutes their SQL expressions.

### Query count configuration panel

When a connection's `conditionType` is `"query_count"`, the property panel shows a dedicated configuration:
- Entity selector dropdown
- WHERE conditions (reuses existing ConditionBuilderComponent)
- Count operator dropdown (>, >=, ==, <, <=, !=)
- Count value input (number)

This is a property panel UI change in the flowchart editor.

---

## 4. File Changes

### New files

| File | Purpose |
|---|---|
| `spec/services/code_generators/decision_query_count_spec.rb` | Tests for query_count condition code generation |
| `spec/integration/query_count_branching_spec.rb` | Integration test for query-count-based branching |

### Modified files

| File | Change |
|---|---|
| `app/services/code_generators/element_types/decision/decision_generator.rb` | Handle `conditionType: "query_count"` in `build_connection_condition` |
| `app/services/code_generators/shared/condition_builder.rb` | Add `build_query_count_condition` method |

### No database migration needed

---

## 5. Testing Strategy

- **DecisionGenerator specs:** Test that `query_count` conditions generate QueryBuilder code. Test mixed conditions (field + query_count in same Decision). Test backward compatibility (no conditionType defaults to field).
- **Integration specs:** Create entity with entries, build a flowchart with query-count Decision, execute via ActivityTracer, verify correct branch taken.
