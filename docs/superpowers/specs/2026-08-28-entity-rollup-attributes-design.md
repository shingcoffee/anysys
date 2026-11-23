# Entity Rollup Attributes — Design

**Date:** 2026-08-28
**Status:** Approved for planning
**Motivating case:** Customer `49700484` has entities `student` and `class`, associated through the
auto-generated bridge `assoc_student_class` which carries a `score` attribute. A `student` needs a
derived attribute showing the average `score` across every `class` that student is enrolled in.

---

## 1. Problem

The association machinery already models one-to-many/many-to-many relationships: an association
declared on `student` targeting `class` causes `BridgeEntityManagement#sync_bridge_entities!` to
generate a bridge entity whose `property_schema` is

| index | slug | type | meaning |
|-------|------|------|---------|
| 0 | `student` | `NestedEntity` | reference to the source entry |
| 1 | `class` | `NestedEntity` | reference to the target entry |
| 2..n | e.g. `score` | author-defined | the association's additional attributes |

What is missing is any way to surface an **aggregate over those bridge rows as an attribute of the
host entity**.

The existing `Calculated` attribute type is not sufficient. `FlowchartRuntime::FormulaCompiler`
transpiles a formula into SQL, but every identifier resolves to
`json_extract(entity_entries.data, '$.slug')` — strictly the **same row**. It has no aggregate
functions and no notion of traversing to another entity.

A second gap: `Admin::Entities::ColumnsBuilder` builds its candidate columns from
`Entity#data_fields`, which rejects `Calculated`. So computed attributes are not displayable in the
entries table today at all. Any solution must wire display, not only computation.

## 2. Chosen approach

A new attribute type, `Rollup`, defined by **structured configuration** (not formula text), compiled
to a correlated SQL subquery at read time. The value is never stored.

### Why not formula syntax

The alternative was extending the `Calculated` grammar to accept `AVG(assoc_student_class.score)`.
It was rejected on a concrete failure path:

`BridgeEntityManagement#rename_bridge_entities` fires on any host entity rename. Renaming
`Student` to `Pupil` renames the bridge `assoc_student_class` to `assoc_pupil_class` **and** rewrites
the bridge's reference slug `student` to `pupil`. Nothing in the codebase rewrites references to the
old names — there is no formula-rewrite pass anywhere. A formula string would break silently, and it
would break loudly in the wrong place: `FormulaCompiler.compile_all` raises `Unknown field`, which
propagates out of `QueryBuilder#inject_calculated_fields` and takes down the entire entries query.
Renaming an entity would 500 an unrelated list page.

Structured config storing `bridge_entity_id` (a primary key) and `bridge_role` (a structural
position guaranteed by `bridge_property_schema`) is immune by construction: the compiler resolves the
role to whatever the current slug is, at compile time.

Secondary reasons: bridge entity names are machine-generated artifacts the user never chose, so
putting them in user-authored formula text exposes an internal convention; and the "formula reuses
existing UI" advantage is illusory, because the entity attribute modal has no formula input today
and the page-builder pill editor is bound to page field IDs with `{field_id}` tokens rather than the
entity grammar's bare identifiers.

### Why config does not cost composability

`FormulaCompiler::Parser#resolve_field` checks its `@resolved_calculated` hash **before** the field
map, and `compile` already accepts that hash as a third argument. Seeding it with rollup SQL lets an
ordinary `Calculated` attribute write `average_score * 0.9 + bonus` and compile correctly, with the
existing TSort ordering handling chains. This is included in the first pass.

## 3. Definition shape

Stored in `property_schema`, so it versions through `EntityDefinitionContent` with no migration.

```json
{
  "name": "Average Score",
  "display_label": "Average Score",
  "name_slug": "average_score",
  "type": "Rollup",
  "html_type": "number",
  "readonly": true,
  "storage": "computed",
  "group_id": null,
  "description": "Average score across all enrolled classes",
  "visibility": { "admin": true, "member": true, "public": false },
  "config": {
    "bridge_entity_id": 15,
    "bridge_role": "source",
    "source_slug": "score",
    "function": "avg",
    "precision": 2,
    "filter": { "slug": "status", "op": "=", "value": "completed" }
  }
}
```

**`bridge_role`** is the reverse-direction mechanism:

- `"source"` — the host entity occupies index 0 of the bridge schema. This is `student` rolling up
  over `assoc_student_class` (the association is declared on `student`).
- `"target"` — the host entity occupies index 1. This is `class` rolling up over the *same* bridge,
  e.g. the average score achieved in that class.

**`function`** is one of `avg`, `sum`, `count`, `min`, `max`.

**`precision`** applies to `avg`, `sum`, `min`, and `max`. It is ignored for `count`, which is
always an integer.

**`filter`** is optional and holds a single condition applied to bridge rows before aggregating.
Its `op` is drawn from an allowlist (`=`, `!=`, `>`, `>=`, `<`, `<=`) and its `slug` must name an
attribute on the bridge; the value is always passed as a bound parameter.

**`storage`** is `"computed"` in this design. The key exists so a future `"cached"` mode (materialize
the value, maintained on bridge writes) can be added behind the same definition without a config
change. Only `"computed"` is implemented.

## 4. `Entities::RollupCompiler`

A sibling of `FlowchartRuntime::FormulaCompiler`, following the same allowlist discipline.

```ruby
Entities::RollupCompiler.compile_all(entity, customer_id:)
# => [{ name: "average_score", sql: "(SELECT ROUND(AVG(...), 2) ...)" }, ...]
```

Resolution per rollup:

1. Load the bridge `Entity` by `config["bridge_entity_id"]`, scoped to `customer_id` and
   `category: :bridge`. A missing, soft-deleted, or cross-tenant bridge yields nil SQL.
2. Read the bridge's **live** `property_schema_json` and take index 0 (`source`) or index 1
   (`target`) per `bridge_role` to obtain the current join slug. This step is what makes the
   definition rename-proof.
3. Verify `source_slug` exists among the bridge's attributes and pass it through
   `FlowchartRuntime::JsonPathValidator.safe_json_path!`.
4. Emit the subquery.

Generated SQL for the motivating case:

```sql
(SELECT ROUND(AVG(CAST(json_extract(b.data, '$.score') AS NUMERIC)), 2)
   FROM entity_entries b
  WHERE b.entity_id = 15
    AND b.customer_id = 49700484
    AND json_extract(b.data, '$.student') = CAST(entity_entries.id AS TEXT))
```

The join predicate mirrors `FlowchartRuntime::JoinResolver#apply_sql_join`, which already compares
`json_extract(bridge.data, '$.slug')` against `CAST(entity_entries.id AS TEXT)`.

### Safety

Every interpolated value is one of: an integer cast (`entity_id`, `customer_id`), an allowlisted
enum (`function`, filter `op`), or a slug validated by `JsonPathValidator`. Filter values are bound
parameters, never interpolated. There is no path by which author-supplied text reaches the SQL string.

### Failure policy

`RollupCompiler` **never raises**. This is a deliberate divergence from `FormulaCompiler`, whose
`compile_all` raises on an unknown field and thereby fails the whole `QueryBuilder` query. A rollup
whose bridge or source attribute cannot be resolved returns a nil-SQL entry, and the column renders
empty. One broken definition must not take down the entries page.

### Empty-set semantics

- `avg`, `min`, `max` produce SQL NULL, rendered as an em dash
- `sum`, `count` produce `0`, via `COALESCE(SUM(...), 0)` and `COUNT`'s natural zero

## 5. Model layer changes

| File | Change |
|---|---|
| `app/models/entity.rb` | add `rollup_fields`; extend `data_fields` to reject `Rollup` as well as `Calculated`, so it never becomes a writable column, a filter, or a form input |
| `app/models/entity_entry.rb` | `build_for` passes `writable: false` for `Rollup` (same branch as `Calculated`); `valid_attribute_slugs` excludes `Rollup` so `validate_data_keys` rejects a forged `average_score` key in submitted data |
| `app/models/concerns/entity_schema_validation.rb` | new `validate_rollup_definitions` |

`validate_rollup_definitions` checks:

- `function` is in the allowlist
- `bridge_entity_id` resolves to an entity in the same tenant with `category: :bridge`
- the host entity actually participates in that bridge at the declared `bridge_role`
- `source_slug` exists on the bridge and, for every function except `count`, has a numeric
  `html_type` (`number` or `range`)
- the host entity is `customer_specific` — shared entities already cannot have associations
  (`shared_entity_has_no_associations`), so a rollup on one is incoherent

## 6. Composability with `Calculated`

`FormulaCompiler.compile_all` gains an optional seed argument carrying `{ slug => rollup_sql }`.
Because `resolve_field` consults `@resolved_calculated` first, `weighted = average_score * 0.9`
compiles to `((SELECT AVG(...)) * 0.9)`. Rollup slugs also join `all_slugs` in the dependency scan so
they are recognized as legitimate references rather than ignored.

Rollups themselves cannot reference other rollups or calculated fields — they aggregate raw bridge
attributes only. This keeps the dependency graph acyclic without new cycle detection.

## 7. Read paths

### 7a. Admin entries index — primary surface

`Admin::Entities::ColumnsBuilder` gains rollup columns, appended after the data columns:

```ruby
{
  key: slug.to_sym,
  label: attribute display_label or name, humanized,
  type: :number,
  align: :right,
  sortable: true,
  searchable: false,
  sql: rollup_sql,           # the correlated subquery
  cell: ->(row) { ... }      # reads the batch-loaded value
}
```

Sorting works with **zero changes** to `ModuleEntriesResolver`: `apply_sort` already uses `col[:sql]`
and already wraps `:number` columns in `CAST(... AS REAL)`.

`Admin::Entities::ColumnPickerComponent` gains the rollup slugs as toggleable candidates.

`Admin::Entities::FiltersBuilder` is unchanged — rollups are numeric and the builder only emits
filters for `select`/`radio`/`checkbox`.

### 7b. `Entities::RollupLoader` — batched value loading

Rendering N rows must not run N correlated subqueries. `EntitiesController#show` paginates first via
`listable`, then loads values for the visible ids only:

```ruby
Entities::RollupLoader.call(entity:, customer_id:, entry_ids:)
# => { entry_id => { "average_score" => 87.5, ... } }
```

Each rollup issues one grouped query:

```sql
SELECT json_extract(b.data, '$.student') AS host_id,
       ROUND(AVG(CAST(json_extract(b.data, '$.score') AS NUMERIC)), 2)
  FROM entity_entries b
 WHERE b.entity_id = ? AND b.customer_id = ?
   AND json_extract(b.data, '$.student') IN (?)
 GROUP BY 1
```

Cost is one extra query per rollup per page, independent of page size. The correlated subquery form
is used only when the user actually sorts by the rollup column.

### 7c. `FlowchartRuntime::QueryBuilder`

`inject_calculated_fields` also injects rollup SQL into `@computed_fields` and
`@auto_calculated_fields`. Flowcharts therefore get `average_score` as a selected alias, and
`WhereClauseBuilder` can filter on it — it already accepts a `calculated_fields:` map.

### 7d. `PageFieldPopulator`

Rollups take the same branch as `Calculated`: `readonly => true`, `storage => "computed"`. The
rendered value is supplied by `RollupLoader`. `PageContentGenerator::FormFields` already disables any
field with `storage == "computed"`, so form generation needs no change.

### 7e. Member surfaces

`Member::EntitySurfaceBuilder` currently rejects `Calculated` outright. Rollups are instead
**included read-only**, honoring the existing per-attribute `visibility.member` flag — the same flag
`PageTemplateApplier::FieldPreprocessor#apply_visibility_filter!` already applies on the member detail
path via `Member::SurfaceTemplateApplier`. "My average score" is a natural member-facing value.

### 7f. CSV export

No change required. `Admin::Entities::EntriesCsv` consumes the same columns array, so rollup columns
export automatically.

## 8. Authoring UI

`Admin::Maintenance::Entities::AttributeModalComponent` gains a Data / Rollup mode toggle at the top.
Rollup mode reveals four controls:

1. **Related entity** — options carry `bridge_entity_id` and `bridge_role`. Forward options come from
   `entity.associations_list`. Reverse options come from bridges where the host sits at schema index
   1, discovered with the existing `TARGET_REFERENCE_SQL` lookup in `BridgeEntityManagement`.
2. **Attribute** — the selected bridge's additional attributes, filtered to numeric ones unless the
   function is `count`.
3. **Function** — avg / sum / count / min / max.
4. **Decimals** — integer precision, defaulting to 2.

A new `app/javascript/controllers/entity_form/rollup_manager.js` follows the existing `BaseManager`
pattern and is registered in `entity_form/index.js`.

Option data is server-rendered as a JSON Stimulus Value on the form — the same style as the existing
`entity_form_html_type_validators_value` — produced by a new `Entities::RollupOptions` service. This
avoids a fetch, a new route, and a new authorization surface, and keeps all user-facing text
server-translated so the 100% Vitest requirement stays tractable.

## 9. Multi-tenancy and authorization

- Every emitted subquery hard-codes `b.customer_id = <integer>`.
- `RollupCompiler` refuses a `bridge_entity_id` outside the host entity's tenant, at both compile and
  validation time.
- Rollups are restricted to `customer_specific` entities.
- No new routes and no new controllers, so no new auth guards. The value rides the existing
  `/:cid/admin/entities/:id` surface, which is already guarded.

## 10. I18n

New keys in `config/locales/maint_core.en.yml` / `maint_core.zh-CN.yml` (rollup mode label, function
names, empty-value dash, validation errors) and `comp_admin.*` for the modal controls. Both locales
in parity. `rollup_manager.js` declares English `default:` Values with the translated strings passed
from the server via `data-*-value`.

## 11. Testing

Scope: this is a feature slice touching model, services, component, and JS, so touched-layer specs
rather than the full suite.

| Spec | Covers |
|---|---|
| `spec/services/entities/rollup_compiler_spec.rb` | golden SQL for all five functions, both roles, with and without filter; injection attempts on every config field; missing / soft-deleted / cross-tenant bridge returns nil SQL rather than raising |
| `spec/services/entities/rollup_loader_spec.rb` | batching shape, empty id list, entries with no bridge rows, empty-set semantics per function |
| `spec/models/entity_rollup_validation_spec.rb` | each `validate_rollup_definitions` branch |
| `spec/models/entity_entry_spec.rb` | forged `average_score` key in submitted data is rejected; no writer generated |
| `spec/services/flowchart_runtime/formula_compiler_spec.rb` | a `Calculated` field referencing a rollup slug compiles to the nested subquery |
| `spec/services/admin/entities/columns_builder_spec.rb` | rollup column shape, sortability, exclusion from filters/search |
| `spec/integration/rollup_fields_integration_spec.rb` | the literal student / class / score scenario end to end, forward and reverse direction |
| rename regression (in the integration spec) | rename `Student`, assert the rollup still resolves — this is the specific failure the design exists to prevent |
| `spec/javascript/controllers/entity_form/rollup_manager.test.js` | 100% lines and branches |

## 12. Known risks and limits

1. **No expression index.** `entity_entries` is indexed on `(customer_id, entity_id)` but not on
   `json_extract(data, '$.<slug>')`, so each grouped query scans the bridge entity's entries.
   Batching bounds this to one scan per rollup per page. If a tenant's bridge volume outgrows it, the
   `storage: "cached"` mode slots in behind the identical definition.
2. **Single hop only.** A rollup aggregates attributes on the bridge itself, not on the far entity
   (`AVG(class.credits)` is out of scope). Adding it later means a path array in config, not a
   redesign.
3. **`source_slug` drift.** Renaming the association's additional attribute in the association modal
   is the one remaining way to break a rollup. It is validated at save time and surfaces as a
   validation error rather than silent breakage.
