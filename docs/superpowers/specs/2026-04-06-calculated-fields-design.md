# Calculated Fields (Server-Side SQL) Design

**Date:** 2026-04-06
**Gap Reference:** Gap #5 from gap-analysis-anysys-vs-fw.md
**Status:** Draft

---

## Overview

Add SQL-level calculated fields to entity definitions. Calculated fields are defined in property_schema with a simple expression syntax, compiled to SQL at query time, and usable in conditions, ordering, display, and flowchart logic. A FormulaCompiler service translates simple expressions to SQL with automatic field reference resolution, type-aware casting, and topological sorting for chained dependencies.

---

## 1. FormulaCompiler Service

### New service: `FlowchartRuntime::FormulaCompiler`

Takes a simple expression string and an entity's property_schema, produces a SQL expression.

### Field reference translation

- Numeric fields (`Float`, `Integer`, `number`, `range`, `currency`): `price` → `CAST(json_extract(entity_entries.data, '$.price') AS NUMERIC)`
- String fields (all others): `first_name` → `json_extract(entity_entries.data, '$.first_name')`
- Type detection uses the field's `html_type` from property_schema

### Supported operations

- Arithmetic: `+`, `-`, `*`, `/`
- String concatenation: `first_name + " " + last_name` (when operands are string-typed)
- Parentheses: `(price + tax) * quantity`
- Numeric literals: `42`, `3.14`
- String literals: `"text"`
- Functions: `ROUND(expr, decimals)`, `ABS(expr)`, `COALESCE(expr, default)`, `UPPER(expr)`, `LOWER(expr)`, `LENGTH(expr)`

### Chaining with topological sort

Calculated fields can reference other calculated fields. The compiler topologically sorts dependencies to ensure correct resolution order.

Example:
- `subtotal` = `price * quantity`
- `tax` = `subtotal * 0.1`
- `total` = `subtotal + tax`

Compile order: subtotal → tax → total. Each calculated field reference is inlined as its resolved SQL expression.

Circular dependencies are detected and raise an error.

### API

```ruby
# Compile a single formula against schema fields
FormulaCompiler.compile(formula_string, schema_fields)
# => "CAST(json_extract(entity_entries.data, '$.price') AS NUMERIC) * 2"

# Compile all calculated fields for an entity (topologically sorted)
FormulaCompiler.compile_all(schema_fields)
# => [
#   { name: "subtotal", sql: "..." },
#   { name: "tax", sql: "..." },
#   { name: "total", sql: "..." }
# ]
```

---

## 2. Entity Schema — Calculated Field Definition

### No database migration needed

Calculated fields are stored in the existing `property_schema` JSON column.

### Calculated field structure in property_schema

```json
{
  "name": "Total",
  "name_slug": "total",
  "type": "Calculated",
  "html_type": "number",
  "readonly": true,
  "storage": "computed",
  "formula": "subtotal + tax",
  "description": "Order total including tax"
}
```

### Key attributes

- `type: "Calculated"` — identifies this as a computed field
- `readonly: true` — prevents form submission
- `storage: "computed"` — signals that no data is stored in entity_entry JSON
- `formula` — the simple expression (field references + math/string ops)
- `html_type` — determines output type (`number` for numeric results, `text` for string results)

### Entity model changes

- Add `calculated_fields` helper method: filters property_schema for `type == "Calculated"`
- Add `data_fields` helper method: filters property_schema for `type != "Calculated"`
- EntityEntry's `validate_data_keys` skips calculated field slugs
- EntityEntry's `build_for` skips defining setter methods for calculated fields

---

## 3. Auto-injection into QueryBuilder

When `QueryBuilder.for_entity(entity, customer_id:)` is called, it automatically compiles and injects all calculated fields from the entity's property_schema as computed fields in the SELECT clause. No manual `.computed_field()` calls needed for entity-defined calculated fields.

```ruby
# Automatic — calculated fields from schema are always available
result = FlowchartRuntime::QueryBuilder
  .for_entity(entity, customer_id: customer.id)
  .order("total", "desc")
  .execute

result.records.first["total"]  # calculated value available on result
```

The manual `.computed_field()` method still works for ad-hoc computed fields not in the schema.

---

## 4. WhereClauseBuilder Integration

When a condition references a calculated field (`data.total`), the WhereClauseBuilder substitutes the compiled SQL expression instead of `json_extract(data, '$.total')`.

An optional `calculated_fields` parameter is added:

```ruby
WhereClauseBuilder.apply(scope, conditions, ctx, calculated_fields: compiled_map)
```

`compiled_map` is a hash: `{ "total" => "(...sql expression...)" }`.

QueryBuilder passes this automatically when calling WhereClauseBuilder.

---

## 5. Page Builder Integration

- `PageFieldPopulator` generates fields from property_schema — calculated fields appear automatically with `readonly: true`
- `PageContentGenerator` renders calculated fields as display-only (no input element, just a value display)
- At render time for public pages, entity data is queried with calculated fields included via QueryBuilder
- The form field component for calculated fields shows a read-only computed value

---

## 6. Flowchart Condition Builder Integration

- Calculated fields appear in field picker dropdowns (they're in property_schema)
- When a flowchart step queries data via QueryBuilder, calculated fields are auto-included in results
- `ctx[:model].total` works naturally in Decision/Switch conditions
- ConditionBuilder's operand converter handles `ctx.field` references as before

---

## 7. File Changes

### New files

| File | Purpose |
|---|---|
| `app/services/flowchart_runtime/formula_compiler.rb` | Translates simple expressions to SQL with field resolution and topological sort |
| `spec/services/flowchart_runtime/formula_compiler_spec.rb` | FormulaCompiler unit tests |
| `spec/integration/calculated_fields_integration_spec.rb` | End-to-end tests |

### Modified files

| File | Change |
|---|---|
| `app/models/entity.rb` | Add `calculated_fields` and `data_fields` helper methods |
| `app/models/entity_entry.rb` | Skip calculated fields in `validate_data_keys` and `build_for` setters |
| `app/services/flowchart_runtime/query_builder.rb` | Auto-inject calculated fields from entity schema in `base_scope` |
| `app/services/flowchart_runtime/where_clause_builder.rb` | Accept optional `calculated_fields` map, substitute expressions |
| `app/services/page_content_generator.rb` | Render calculated fields as display-only |
| `app/services/page_field_populator.rb` | Mark calculated fields as readonly when populating page fields |

### No database migration needed

---

## 8. Testing Strategy

- **FormulaCompiler specs:** Field reference translation (numeric vs string), arithmetic operators, string concatenation, parentheses, functions, chaining with topological sort, circular dependency detection, unknown field handling
- **Entity model specs:** `calculated_fields` and `data_fields` methods
- **EntityEntry specs:** Calculated fields excluded from `validate_data_keys`, no setters generated
- **QueryBuilder specs:** Auto-injection of calculated fields, ordering by calculated field, filtering by calculated field
- **WhereClauseBuilder specs:** Conditions referencing calculated fields resolve correctly
- **Integration specs:** Full pipeline — entity with calculated fields → QueryBuilder query → filter by calculated field → order by calculated field → results include computed values
