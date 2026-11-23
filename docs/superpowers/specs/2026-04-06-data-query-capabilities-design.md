# Data Query Capabilities Enhancement Design

**Date:** 2026-04-06
**Gap Reference:** Gap #3 from gap-analysis-anysys-vs-fw.md
**Status:** Draft

---

## Overview

Enhance the anysys's data query system to support cross-entity JOINs, sub-queries, pagination, computed fields, query-driven dropdowns, and automatic SQL debugging. All query construction is centralized in a new `FlowchartRuntime::QueryBuilder` fluent service that generators delegate to.

---

## 1. QueryBuilder Service Architecture

### New service: `FlowchartRuntime::QueryBuilder`

A fluent query builder that generators delegate to. It wraps an ActiveRecord scope and chains operations:

```ruby
FlowchartRuntime::QueryBuilder
  .for_entity(entity)                           # base scope
  .join_entity(target_entity, via: bridge)       # cross-entity JOIN
  .computed_field(:full_name, "first_name || ' ' || last_name")  # SQL computed
  .where(conditions, ctx)                        # reuses existing WhereClauseBuilder logic
  .sub_where("data.amount > (SELECT AVG(...))")  # sub-query in WHERE
  .group(:category)                              # GROUP BY
  .having("COUNT(*) > 1")                        # HAVING
  .order(:created_at, :desc)                     # ORDER BY
  .paginate(page: 2, per_page: 25)              # LIMIT/OFFSET + metadata
  .execute                                       # returns Result
```

### Result struct

```ruby
Result = Struct.new(
  :records,       # Array of records
  :total_count,   # Total before pagination
  :page,          # Current page number
  :per_page,      # Page size
  :total_pages,   # Calculated
  :has_next,      # Boolean
  :sql,           # Generated SQL (for debugging)
  keyword_init: true
)
```

### Internal structure

- `QueryBuilder` stores pending operations as a chain
- `WhereClauseBuilder` is extracted as a module/mixin within QueryBuilder (reuse existing logic)
- `JoinResolver` handles bridge-entity-based JOINs (SQL level) and application-level fallback
- `ComputedFieldRegistry` tracks computed field expressions for SELECT/WHERE reference
- `execute` materializes the chain into SQL and runs it

---

## 2. Cross-Entity JOIN via Bridge Entities

### How it works today

Bridge entities are auto-created with two `NestedEntity` reference fields linking entity A to entity B. The bridge's property_schema uses each entity's `name_slug` as field names. For example, a bridge linking "Product" (slug: `product`) and "Order" (slug: `order`) stores `{"product": "5", "order": "12"}` in its `data` JSON column.

### SQL-level JOIN strategy

For a query on Entity A that joins Entity B through a bridge:

```sql
SELECT e1.*
FROM entity_entries e1
INNER JOIN entity_entries bridge
  ON bridge.entity_id = :bridge_entity_id
  AND json_extract(bridge.data, '$.source_slug') = CAST(e1.id AS TEXT)
INNER JOIN entity_entries e2
  ON e2.entity_id = :entity_b_id
  AND CAST(e2.id AS TEXT) = json_extract(bridge.data, '$.target_slug')
WHERE e1.entity_id = :entity_a_id
  AND e1.customer_id = :customer_id
```

### Application-level fallback

For deeper joins or when SQL gets too complex:

```ruby
# Query primary records
primary = EntityEntry.build_for(entity_a).where(...)
# Resolve related via bridge
bridge_entries = EntityEntry.where(entity_id: bridge.id)
related_ids = bridge_entries.map { |b| b.data_json["entity_b_id"] }
related = EntityEntry.build_for(entity_b).where(id: related_ids)
# Merge into context
```

### Generator config for JOINs

```json
{
  "joins": [
    {
      "targetEntityId": 45,
      "targetEntityName": "Order",
      "bridgeEntityId": 78,
      "joinType": "inner",
      "alias": "orders",
      "conditions": []
    }
  ]
}
```

### Design decisions

- **Automatic bridge detection:** When the designer picks a target entity to join, the system looks up existing associations on the source entity to find the bridge. No manual bridge selection needed if there's exactly one association linking the two.
- **One-level JOIN limit for SQL path.** If a query needs A→B→C (two hops), the first hop is SQL, the second is resolved in Ruby. This keeps SQL complexity manageable.

---

## 3. Pagination

Optional parameters on the `query_models` step config:

```json
{
  "action": "query_models",
  "config": {
    "queryType": "where",
    "conditions": [...],
    "pageSize": 25,
    "pageVariable": "ctx.page",
    "orderBy": "created_at",
    "orderDirection": "desc"
  }
}
```

Generated code delegates to QueryBuilder:

```ruby
result = FlowchartRuntime::QueryBuilder
  .for_entity(ctx[:bound_entity])
  .where(conditions, ctx)
  .order(:created_at, :desc)
  .paginate(page: ctx[:page] || 1, per_page: 25)
  .execute

ctx[:models] = result.records
ctx[:pagination] = {
  total_count: result.total_count,
  page: result.page,
  per_page: result.per_page,
  total_pages: result.total_pages,
  has_next: result.has_next
}
```

When `pageSize` is absent, no pagination is applied (backward compatible).

---

## 4. Enhanced GROUP BY

Extend the existing `aggregate_query` generator config:

```json
{
  "action": "aggregate_query",
  "config": {
    "aggregateFunction": "sum",
    "aggregateField": "amount",
    "groupByFields": ["category", "status"],
    "havingClause": "SUM(json_extract(data, '$.amount')) > 100",
    "conditions": [...],
    "targetVariable": "totals"
  }
}
```

The enhancement is routing through `QueryBuilder` so GROUP BY composes with JOINs and computed fields.

---

## 5. Sub-queries in WHERE Clauses

New rule type in the conditions JSON:

```json
{
  "operator": "AND",
  "rules": [
    {
      "field": "data.amount",
      "op": ">",
      "subQuery": {
        "entityId": 45,
        "aggregateFunction": "avg",
        "aggregateField": "amount",
        "conditions": []
      }
    }
  ]
}
```

`WhereClauseBuilder` detects `subQuery` key and generates:

```sql
json_extract(data, '$.amount') > (
  SELECT AVG(json_extract(data, '$.amount'))
  FROM entity_entries
  WHERE entity_id = 45 AND customer_id = ?
)
```

Only aggregate sub-queries supported (AVG, SUM, COUNT, MIN, MAX) — not arbitrary nested SELECTs. This keeps it safe and predictable.

---

## 6. Computed Fields in Queries

New config on `query_models`:

```json
{
  "computedFields": [
    {
      "name": "full_name",
      "expression": "json_extract(data, '$.first_name') || ' ' || json_extract(data, '$.last_name')"
    },
    {
      "name": "age",
      "expression": "CAST((julianday('now') - julianday(json_extract(data, '$.birth_date'))) / 365.25 AS INTEGER)"
    }
  ]
}
```

QueryBuilder adds these as SELECT aliases and makes them available for WHERE/ORDER references. The computed field values are included in the result records via `AS` aliasing.

---

## 7. Query-Driven Dropdowns

### Extending `dynamic_options`

New `"query"` source type:

```json
{
  "dynamic_options": {
    "options_source": "query",
    "entity_id": 123,
    "label_field": "name",
    "value_field": "id",
    "conditions": {
      "operator": "AND",
      "rules": [
        { "field": "data.status", "op": "==", "value": "active" }
      ]
    },
    "order_by": "name",
    "order_direction": "asc",
    "limit": 100,
    "join": {
      "targetEntityId": 45,
      "bridgeEntityId": 78
    }
  }
}
```

### Resolution flow

1. `PageContentGenerator` encounters field with `options_source: "query"`
2. Delegates to `FlowchartRuntime::QueryBuilder` to build and execute the query
3. Results are mapped to `[{label:, value:}]` pairs using `label_field` and `value_field`
4. For public pages, options are resolved at render time (server-side) and embedded in the HTML
5. For authenticated pages, options can also be fetched via an AJAX endpoint for dependent dropdowns

### New endpoint for dynamic option loading

```
GET /:customer_id/pages/:page_id/field_options/:field_id
```

Returns JSON array of `{label, value}` pairs. This enables cascading/dependent dropdowns where field B's options depend on field A's current value.

---

## 8. Query Debugging — Global SQL Capture

### New service: `FlowchartRuntime::QueryLogger`

```ruby
module FlowchartRuntime
  class QueryLogger
    def self.capture(&block)
      queries = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        next if payload[:name] == "SCHEMA"
        queries << {
          sql: payload[:sql],
          duration_ms: payload[:duration]&.round(2),
          name: payload[:name]
        }
      end

      result = block.call
      ActiveSupport::Notifications.unsubscribe(subscriber)

      [result, queries]
    end
  end
end
```

### Integration with ActivityTracer

When executing via the `trace` endpoint, wrap the activity invocation:

```ruby
result, queries = FlowchartRuntime::QueryLogger.capture do
  activity_tracer.call(ctx)
end
result.queries = queries
```

The trace response then includes:

```json
{
  "success": true,
  "trace": "...",
  "trace_nodes": [...],
  "queries": [
    { "sql": "SELECT ... FROM entity_entries WHERE ...", "duration_ms": 1.23, "name": "EntityEntry Load" },
    { "sql": "SELECT COUNT(*) ...", "duration_ms": 0.45, "name": "COUNT" }
  ]
}
```

No per-step configuration needed. Designers use the existing trace button and get SQL output automatically.

---

## 9. File Changes

### New files

| File | Purpose |
|---|---|
| `app/services/flowchart_runtime/query_builder.rb` | Fluent query builder service — core of this feature |
| `app/services/flowchart_runtime/join_resolver.rb` | Bridge-entity-based JOIN logic (SQL + app-level fallback) |
| `app/services/flowchart_runtime/computed_field_registry.rb` | Tracks computed field expressions for SELECT/WHERE |
| `app/services/flowchart_runtime/query_logger.rb` | SQL capture via ActiveSupport::Notifications |
| `spec/services/flowchart_runtime/query_builder_spec.rb` | QueryBuilder specs |
| `spec/services/flowchart_runtime/join_resolver_spec.rb` | JoinResolver specs |
| `spec/services/flowchart_runtime/computed_field_registry_spec.rb` | ComputedFieldRegistry specs |
| `spec/services/flowchart_runtime/query_logger_spec.rb` | QueryLogger specs |

### Modified files

| File | Change |
|---|---|
| `app/services/code_generators/element_types/process/model_operations/query_models_generator.rb` | Delegate to QueryBuilder; add pagination, joins, computedFields config |
| `app/services/code_generators/element_types/process/model_operations/aggregate_query_generator.rb` | Delegate to QueryBuilder; compose GROUP BY with JOINs/computed fields |
| `app/services/flowchart_runtime/where_clause_builder.rb` | Add `subQuery` rule support; extract shared logic for reuse by QueryBuilder |
| `app/services/activity_tracer.rb` | Wrap execution with QueryLogger during trace |
| `app/services/page_content_generator.rb` | Handle `options_source: "query"` for dynamic dropdowns |
| `app/controllers/pages_controller.rb` | Add `field_options` action for AJAX dropdown loading |
| `config/routes.rb` | Add `field_options` route |

### No schema changes needed

All configuration is stored in existing JSON fields (flowchart `configuration`, page `configuration`).

---

## 10. Testing Strategy

- **QueryBuilder specs:** Unit tests for each chain method (`.where`, `.join_entity`, `.computed_field`, `.paginate`, `.group`, `.execute`). Test composition (JOIN + WHERE + pagination together).
- **JoinResolver specs:** Test SQL-level JOIN through bridge entities. Test application-level fallback for multi-hop. Test auto-detection of bridge entity from associations.
- **WhereClauseBuilder specs:** Add sub-query rule tests. Verify generated SQL for aggregate sub-queries.
- **Generator specs:** Test that `query_models_generator` and `aggregate_query_generator` produce correct code that delegates to QueryBuilder.
- **QueryLogger specs:** Test SQL capture and unsubscribe cleanup.
- **Integration specs:** End-to-end test via DynamicController trace endpoint — execute a flowchart with JOIN + pagination + computed field and verify result structure.
- **Page dropdown specs:** Test `options_source: "query"` resolves correctly with conditions and ordering.
