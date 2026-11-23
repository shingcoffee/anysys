# Rollup Attributes — Implementation Plan

Design spec: `docs/superpowers/specs/2026-08-28-entity-rollup-attributes-design.md`
(that path is `.cursorignore`d — this file is the authoritative contract for implementers).

## Goal

Give an entity a derived attribute that aggregates an attribute stored on a bridge entity.

Motivating case: customer `49700484` has `student` and `class`, associated through the generated
bridge `assoc_student_class` which carries `score`. The `student` entity gets an `average_score`
attribute = AVG of `score` across that student's bridge rows.

## Key existing facts (verified — do not re-litigate)

- `BridgeEntityManagement#bridge_property_schema` always builds the bridge schema as
  **index 0 = source entity ref** (slug = source `name_slug`), **index 1 = target entity ref**
  (slug = target `name_slug`), then the association's `additional_attributes`.
- `FlowchartRuntime::JoinResolver#apply_sql_join` joins with
  `json_extract(bridge.data, '$.<slug>') = CAST(entity_entries.id AS TEXT)`. Rollup SQL MUST use the
  same comparison shape (bridge value is a string, entry id is an integer).
- `FormulaCompiler::Parser#resolve_field` checks `@resolved_calculated` **before** `@field_map`
  (formula_compiler.rb line ~243). This is the composability hook.
- `ModuleEntriesResolver.apply_sort` already uses `col[:sql]` and wraps `:number` columns in
  `CAST(<expr> AS REAL)`. No resolver change needed for rollup sorting.
- `Entity#data_fields` currently only rejects `"Calculated"`.
- Entity attributes saved through the form currently carry **no `type` key at all**
  (`SchemaManager#extractAttributeFromRow` does not emit one). Adding `type` is part of this work.
- DB is SQLite. `entity_entries` is indexed on `(customer_id, entity_id)` only.

## Definition shape (stored in `property_schema`)

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
  "description": "",
  "visibility": { "admin": true, "member": true, "public": false },
  "validators": [],
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

- `bridge_role`: `"source"` = host entity is at bridge schema index 0 (forward, e.g. `student`).
  `"target"` = host entity is at index 1 (reverse, e.g. `class` over the same bridge).
- `function`: one of `avg` `sum` `count` `min` `max`.
- `precision`: integer 0..6. Applies to avg/sum/min/max; ignored for `count`.
- `filter`: optional. `op` allowlist: `=` `!=` `>` `>=` `<` `<=`. Value is a **bound parameter**.

## Empty-set semantics

- `avg`, `min`, `max` → SQL NULL → rendered as `—`
- `sum`, `count` → `0` (`COALESCE(SUM(...), 0)`; COUNT is naturally 0)

---

# Work package A — Backend services and models

## A1. `app/services/entities/rollup_compiler.rb` (new)

```ruby
module Entities
  module RollupCompiler
    FUNCTIONS  = %w[avg sum count min max].freeze
    FILTER_OPS = %w[= != > >= < <=].freeze
    MAX_PRECISION = 6

    # => [{ name: "average_score", sql: "(SELECT ...)" or nil }, ...]
    def self.compile_all(entity, customer_id:)

    # => "(SELECT ...)" or nil
    def self.compile(rollup_field, entity, customer_id:)
  end
end
```

Resolution per rollup field:

1. `config = field["config"]`; bail (nil SQL) unless it is a Hash.
2. `function` must be in `FUNCTIONS`, else nil.
3. Load bridge:
   `Entity.where(customer_id: customer_id, category: :bridge).find_by(id: config["bridge_entity_id"].to_i)`
   — nil → nil SQL. (Default scope already excludes soft-deleted.)
4. `bridge_schema = bridge.property_schema_json || []`; index `0` for `bridge_role == "source"`,
   `1` for `"target"`; any other role → nil. Missing entry → nil.
   `join_slug = bridge_schema[idx]["name_slug"]` → `JsonPathValidator.safe_json_path!`.
5. `source_slug` must exist in `bridge_schema` (`name_slug` match) → `safe_json_path!`.
   Skipped for `count` when `source_slug` is blank (COUNT(*) form is allowed).
6. Optional filter: `slug` must exist in `bridge_schema` and pass `safe_json_path!`;
   `op` must be in `FILTER_OPS`. Anything invalid → **drop the filter**, keep the rollup.
7. Emit.

Aggregate expression:

| function | expression |
|---|---|
| avg | `AVG(CAST(json_extract(b.data, '$.<src>') AS NUMERIC))` |
| sum | `COALESCE(SUM(CAST(json_extract(b.data, '$.<src>') AS NUMERIC)), 0)` |
| min | `MIN(CAST(json_extract(b.data, '$.<src>') AS NUMERIC))` |
| max | `MAX(CAST(json_extract(b.data, '$.<src>') AS NUMERIC))` |
| count | `COUNT(*)` when `source_slug` blank, else `COUNT(json_extract(b.data, '$.<src>'))` |

`precision` wraps avg/sum/min/max in `ROUND(<expr>, <int>)`. Never wraps `count`.

Full subquery (alias the bridge table `b`; use a unique alias per rollup — `b0`, `b1`, … — so two
rollups in one SELECT never collide):

```sql
(SELECT ROUND(AVG(CAST(json_extract(b0.data, '$.score') AS NUMERIC)), 2)
   FROM entity_entries b0
  WHERE b0.entity_id = 15
    AND b0.customer_id = 49700484
    AND json_extract(b0.data, '$.student') = CAST(entity_entries.id AS TEXT))
```

**Filter values must be bound, not interpolated.** Because this string is embedded in a `select`
expression where bind params are awkward, quote via
`ActiveRecord::Base.connection.quote(value.to_s)` — this is the sanctioned escape and must be used
for the filter value and nothing else.

**Never raise.** Any resolution failure yields `nil` SQL for that field. `compile_all` still returns
an entry so callers can distinguish "defined but unresolvable" from "not defined". Rescue
`StandardError` at the per-field boundary as a backstop.

Every integer (`bridge_entity_id`, `customer_id`, `precision`) must go through `.to_i` before
interpolation. Every slug through `JsonPathValidator.safe_json_path!`.

## A2. `app/services/entities/rollup_loader.rb` (new)

```ruby
Entities::RollupLoader.call(entity:, customer_id:, entry_ids:)
# => { 12 => { "average_score" => 87.5 }, 13 => { "average_score" => nil }, ... }
```

One grouped query per rollup field (NOT per row). Returns `{}` for blank `entry_ids` or when the
entity has no rollup fields. Uses the same resolution logic as `RollupCompiler` — extract the shared
resolution into a small `Entities::RollupDefinition` value object (`bridge`, `join_slug`,
`source_slug`, `function`, `precision`, `filter`) that both services use, so the SQL semantics cannot
drift between the sort path and the display path.

```sql
SELECT json_extract(b.data, '$.<join_slug>') AS host_id, <agg_expr>
  FROM entity_entries b
 WHERE b.entity_id = ? AND b.customer_id = ?
   AND json_extract(b.data, '$.<join_slug>') IN (<quoted ids>)
 GROUP BY 1
```

Ids come from the caller as integers; compare as text to match storage. Every entry id in
`entry_ids` must be present as a key in the result hash, with the empty-set default
(nil for avg/min/max, 0 for sum/count) when the entry has no bridge rows.

## A3. `app/services/entities/rollup_options.rb` (new)

Builds the JSON the attribute modal needs. No new route — rendered into the form as a Stimulus Value.

```ruby
Entities::RollupOptions.call(entity:, customer_id:)
# => [
#   { "bridge_entity_id" => 15,
#     "bridge_role" => "source",
#     "related_entity_label" => "Class",
#     "bridge_label" => "assoc_student_class",
#     "attributes" => [ { "slug" => "score", "label" => "Score", "numeric" => true }, ... ] },
#   ...
# ]
```

- Forward entries: for each `entity.associations_list` item with a `bridge_entity_id`, load the
  bridge, role `"source"`, related label = target entity `display_label`.
- Reverse entries: bridges in this tenant where the host entity sits at schema index 1. Find them by
  scanning tenant bridges whose `property_schema_json[1]["entity_id"].to_s == entity.id.to_s`;
  role `"target"`, related label = the entity named at bridge schema index 0.
- `attributes` = bridge schema entries from index 2 onward. `numeric` is
  `%w[number range].include?(html_type)`.
- Returns `[]` for a new (unpersisted) or bridge entity.

## A4. `app/models/entity.rb`

- `ROLLUP_TYPE = "Rollup"` (or reuse a literal consistently).
- `data_fields` → `reject { |f| %w[Calculated Rollup].include?(f["type"]) }`
- add `rollup_fields` → `select { |f| f["type"] == "Rollup" }`
- `calculated_fields` unchanged.

## A5. `app/models/entity_entry.rb`

- `build_for`: `define_data_accessor(slug, writable: !%w[Calculated Rollup].include?(attr["type"]))`
- `valid_attribute_slugs`: reject `Rollup` as well as `Calculated`, so `validate_data_keys` rejects a
  forged `average_score` key in submitted data.

## A6. `app/models/concerns/entity_schema_validation.rb`

New `validate_rollup_definitions`, registered in the `included do` block. For each `Rollup` field:

- `config` present and a Hash
- `function` in `Entities::RollupCompiler::FUNCTIONS`
- `precision`, when present, an integer 0..`MAX_PRECISION`
- `bridge_entity_id` resolves to an entity in the same tenant with `category: :bridge`
- `bridge_role` is `"source"` or `"target"`, and the bridge's schema at the matching index has
  `entity_id` equal to this entity's id (i.e. the host really participates at that role).
  Skip this check when the entity is a new record (no id yet).
- `source_slug` exists on the bridge schema; required for every function except `count`;
  for avg/sum/min/max the referenced attribute must have `html_type` in `%w[number range]`
- filter, when present: `slug` exists on the bridge schema and `op` is in `FILTER_OPS`
- the entity is `type_customer_specific?` (shared entities cannot have associations)

All messages via `I18n.t("maint_core.errors.validations.<key>")`, added to `:property_schema`.

## A7. `app/services/flowchart_runtime/formula_compiler.rb`

`compile_all(schema_fields, resolved: {})` — new optional keyword.

- Seed the local `resolved` hash with the passed-in map before the sort loop.
- Include the seeded slugs in `all_slugs` so a formula referencing a rollup is recognised as a
  dependency rather than an unknown identifier.
- Seeded slugs are terminal: they are never themselves compiled, and a `Rollup` field is never
  treated as `Calculated`.
- Default `{}` keeps every existing caller and golden test byte-identical.

## A8. `app/services/flowchart_runtime/query_builder.rb`

In `inject_calculated_fields`:

1. `rollups = Entities::RollupCompiler.compile_all(@entity, customer_id: customer_id)`
2. Add each non-nil to `@computed_fields` and `@auto_calculated_fields`.
3. Pass the same map as `resolved:` into `FormulaCompiler.compile_all`.

Guard `FormulaCompiler.compile_all` with a rescue so a bad calculated formula degrades to "no
calculated fields" instead of 500-ing — the rollup work makes this path more reachable.

## A9. `app/services/admin/entities/columns_builder.rb`

- Keep `candidate_slugs` / `default_slugs` behaviour for data fields.
- Append rollup columns for every `entity.rollup_fields` whose compiled SQL is non-nil, respecting
  the same `setting.visible_column_keys` selection semantics as data columns (a rollup slug present
  in the preference list is shown; when the preference is nil, rollups are **not** in the default
  three but ARE offered as candidates).
- Column shape:

```ruby
{
  key: slug.to_sym,
  label: (field["display_label"].presence || field["name"].presence || slug).to_s.humanize,
  type: :number,
  align: :right,
  sortable: true,
  searchable: false,
  rollup: true,
  sql: compiled_sql,
  cell: ->(row) { ... }   # value injected by the controller via RollupLoader; "—" when nil
}
```

The `cell` lambda must read from a per-request lookup the controller populates. Simplest contract:
`ColumnsBuilder.call(entity:, setting:, values: {})` where `values` is the `RollupLoader` hash;
`cell` does `values.dig(row.id, slug)`. When `values` is empty the cell renders `—`.

## A10. `app/components/admin/entities/column_picker_component.rb`

Include rollup slugs in the pickable candidate list, labelled like data columns.

## A11. `app/services/page_field_populator.rb`

Extend the existing `Calculated` branch to also match `Rollup`:
`field["readonly"] = true; field["storage"] = "computed"`. Do not set `formula` for rollups.

## A12. `app/services/member/entity_surface_builder.rb`

Currently `reject { |f| f["type"] == "Calculated" }` in two places. Change so that:

- `Calculated` stays rejected (unchanged behaviour)
- `Rollup` is **included read-only**, but only when its `visibility["member"]` is not `false`
- rollup columns get `format: :number`, `align: :right`

---

# Work package B — Frontend (modal + Stimulus)

## B1. Carry `type` through the attribute row round-trip

Entity attributes currently lose any `type`. Add it everywhere the other scalar fields appear:

- `app/javascript/controllers/entity_form/template_builder.js` → `buildAttributeRowHtml`:
  destructure `type`, add `data-attr-type="${escapeHtml(type || "")}"` on the `<tr>` and
  `<input type="hidden" name="attributes[${index}][type]" ... data-input="type">`.
  Also render a small type badge next to the html_type badge when `type === "Rollup"`.
- `schema_manager.js` → `updateAttributeRow` accepts `type`, `setInput("type", type || "")`,
  sets `data-attr-type`; `extractAttributeFromRow` reads `type` and includes it in the returned
  object **only when non-empty** (so ordinary attributes keep their current shape exactly, and
  existing Vitest snapshots for data attributes stay valid).
- `app/views/admin/maintenance/entities/_attributes_table.html.erb` → server-rendered rows must emit
  the same `data-attr-type` and hidden `type` input so edit/reload round-trips.

For a `Rollup` attribute, `extractAttributeFromRow` must also emit `readonly: true` and
`storage: "computed"`.

## B2. Rollup section in the attribute modal

`app/components/admin/maintenance/entities/attribute_modal_component.html.erb`:

- A two-button mode toggle at the top of the modal: **Data** / **Rollup**
  (targets `modeDataBtn`, `modeRollupBtn`; action → `entity-form#selectDataMode` /
  `entity-form#selectRollupMode`). Style it exactly like the existing
  Manual entry / Use constant toggle in `selectionConfig` for visual consistency.
- A `rollupSection` block (hidden by default) containing:
  - `rollupRelation` select — options injected by Stimulus from the options Value
  - `rollupAttribute` select — dependent on the relation
  - `rollupFunction` select — avg / sum / count / min / max
  - `rollupPrecision` number input, default `2`, min 0 max 6
- In Rollup mode, hide the HTML-type select, the validators section, and the options/file config
  section (a rollup is always a read-only number).

All labels via `t(...)`. No hard-coded English in the ERB or the JS.

## B3. `app/javascript/controllers/entity_form/rollup_manager.js` (new)

Extends `BaseManager`, follows the sibling managers' style. Responsibilities:

- `selectDataMode()` / `selectRollupMode()` — toggle `this.c.attributeMode` (`"data"` | `"rollup"`),
  show/hide `rollupSection`, and show/hide the html-type + validators + options sections.
- `populateRelations()` — fill `rollupRelation` from `this.c.rollupOptionsValue`
  (array described in A3). Option `value` is the array index; keep the parsed array in memory.
- `relationChanged()` — repopulate `rollupAttribute` from the selected relation's `attributes`,
  filtered to `numeric === true` unless the selected function is `count`.
- `functionChanged()` — re-filter attributes; disable/blank the precision input when
  function is `count`.
- `getRollupConfig()` — returns
  `{ bridge_entity_id, bridge_role, source_slug, function, precision }` or `null` when incomplete.
- `applyRollupConfig(config)` — used by prefill when editing an existing rollup attribute.
- `validate()` — returns an error message key when relation/attribute/function is missing.

Register in `app/javascript/controllers/entity_form/index.js` and instantiate in
`entity_form_controller.js` alongside the other managers.

## B4. Wire into the existing controller flow

- `entity_form_controller.js`: add targets (`modeDataBtn`, `modeRollupBtn`, `rollupSection`,
  `rollupRelation`, `rollupAttribute`, `rollupFunction`, `rollupPrecision`), add the
  `rollupOptions` Array/Object Value plus String Values for every user-facing string with an English
  `default:`, add the `rollupManager` instance and delegating action methods.
- `attribute_manager.js` → `collectModalData()`: when mode is `rollup`, return
  `{ ...base, type: "Rollup", html_type: "number", readonly: true, storage: "computed",
     validators: [], config: rollupManager.getRollupConfig() }`.
  Validation must reject an incomplete rollup config with a translated message.
- `modal_manager.js`: `resetModalFields()` resets to Data mode and clears the rollup selects;
  `prefillModalWithAttribute()` switches to Rollup mode and calls `applyRollupConfig(config)` when
  `type === "Rollup"`.

## B5. Pass options into the form

`app/views/admin/maintenance/entities/_form.html.erb` — add to the `data:` hash:

```erb
entity_form_rollup_options_value: Entities::RollupOptions.call(entity: @entity, customer_id: current_customer_id).to_json,
```

plus the translated label Values for the rollup UI.

## B6. Vitest

`spec/javascript/controllers/entity_form/rollup_manager.test.js` — **100% lines and branches** for
the new file, and keep every touched file at 100%. Run `npx vitest run --coverage` and confirm.

---

# Work package C — Controller wiring

`app/controllers/admin/entities_controller.rb#show`:

1. Build columns once without values to get the SQL (needed for sorting), run `listable`.
2. After pagination, call
   `Entities::RollupLoader.call(entity: @entity, customer_id: current_customer.id, entry_ids: @rows.map(&:id))`
   and rebuild `@columns` with `values:` so the `cell` lambdas resolve.
   Only do the load when `@entity.rollup_fields.any?`.
3. CSV branch: same, over `result[:rows]`.

No route changes, no new controller, no auth change. Tenant scoping is already enforced by
`Entity.for_customer(current_customer.id)` and the explicit `customer_id` on the entries scope —
pass `current_customer.id` explicitly into both new services, never `Current` implicitly.

---

# Work package D — I18n

Both `en` and `zh-CN`, keys in parity, idiomatic professional zh-CN.

- `config/locales/maint_core.en.yml` / `maint_core.zh-CN.yml`
  - `maint_core.entities.rollup.*` — mode label, relation/attribute/function/precision labels,
    function names (avg/sum/count/min/max), empty hint
  - `maint_core.errors.validations.rollup_*` — one per validation branch in A6
- `config/locales/comp_admin.en.yml` / `comp_admin.zh-CN.yml`
  - `comp_admin.attribute_modal.rollup_*` — modal control labels and the incomplete-config message

Stimulus reads these as Values with English `default:`; never a literal in JS.

---

# Work package E — Specs

| File | Must cover |
|---|---|
| `spec/services/entities/rollup_compiler_spec.rb` | golden SQL for all 5 functions; both roles; precision applied/omitted; filter applied and dropped when invalid; unique table aliases for 2 rollups; injection attempts in `source_slug`, `bridge_role`, `function`, filter `slug`/`op`/`value`; missing / soft-deleted / cross-tenant bridge → nil SQL, never raises |
| `spec/services/entities/rollup_loader_spec.rb` | batching (one query per rollup, not per row); blank `entry_ids`; entries with zero bridge rows get the empty-set default; values keyed by entry id |
| `spec/models/entity_rollup_validation_spec.rb` | every branch of `validate_rollup_definitions`, valid and invalid |
| `spec/models/entity_entry_spec.rb` (append) | forged `average_score` key rejected by `validate_data_keys`; no writer generated for a Rollup slug |
| `spec/services/flowchart_runtime/formula_compiler_spec.rb` (append) | `compile_all(schema, resolved: {...})` — a Calculated formula referencing a rollup slug nests the subquery; existing behaviour unchanged with the default `{}` |
| `spec/services/admin/entities/columns_builder_spec.rb` (append) | rollup column shape, sortable, not searchable, `—` when no value, value from `values:` |
| `spec/services/member/entity_surface_builder_spec.rb` (append) | rollup included; excluded when `visibility.member == false`; Calculated still excluded |
| `spec/integration/rollup_fields_integration_spec.rb` (new) | the literal student/class/score scenario: forward avg on `student`, reverse avg on `class`, sum/count/min/max, cross-tenant isolation (another customer's bridge rows never counted), **and the rename regression** |

**The rename regression is the most important test in this change.** Shape:

```ruby
it "still resolves after the host entity is renamed" do
  student.update!(name: "Pupil")          # triggers rename_bridge_entities
  sql = Entities::RollupCompiler.compile(rollup_field, student.reload, customer_id: customer.id)
  expect(sql).to include("'$.pupil'")     # join slug followed the rename
  expect(loader_value_for(john)).to eq(87.5)
end
```

## Spec scope

Feature slice → run the touched layers, not the full suite:

```
bundle exec rspec spec/services/entities spec/models/entity_rollup_validation_spec.rb \
  spec/models/entity_entry_spec.rb spec/services/flowchart_runtime/formula_compiler_spec.rb \
  spec/services/admin/entities/columns_builder_spec.rb \
  spec/services/member/entity_surface_builder_spec.rb \
  spec/integration/rollup_fields_integration_spec.rb \
  spec/models/entity_spec.rb spec/services/page_field_populator_spec.rb
```

Plus `npx vitest run --coverage`.

## Non-goals

- No migration. No new table, no new column.
- No `storage: "cached"` implementation (the key is reserved, not honoured).
- No multi-hop rollups (`AVG(class.credits)`); single hop onto the bridge only.
- No new routes or controllers.
