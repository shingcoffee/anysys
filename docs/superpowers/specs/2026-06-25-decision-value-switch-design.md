# Decision element → value-switch property editor refactor

- **Date:** 2026-06-25
- **Status:** Approved (brainstorming) — ready for implementation plan
- **Area:** Flowchart editor (Decision element), property editor JS + Ruby code generator
- **Type:** Tremendous / cross-cutting change (model-data + generator + view + specs)

## Problem / current state

The Decision element's property editor has two competing, confusing condition mechanisms:

1. **Element-level `condition`** (`ConditionBuilderMixin`) — a group of *field-condition* rows joined by a **single, group-wide** AND/OR. Used by the generator only as a **binary** test: `(cond) ? :branch_0 : :branch_1`. No query-count support.
2. **Per-branch `condition`** (branch modal) — each branch carries its *own* field-condition OR query-count. The generator turns these into an `if/elsif/else` chain.

This is redundant (two places to express routing logic) and the element-level condition only ever yields a 2-way split. The branch modal duplicates the whole condition builder.

## Goal — the new model

Turn the Decision into a **value switch**:

- The **Condition** section computes one **subject value `V`**.
- Each **branch** declares a **Match Value**; the branch whose Match Value `== V` is selected.
- A **default branch** handles "no match".

The per-branch condition UI is deleted; branches only carry a Match Value (+ name + description).

### Subject kind decides everything

`V`'s kind is **deterministic from the condition's shape**, and it drives both the generated code and the branch-modal input:

| Condition shape | `subject_kind` | `V` is | Branch Match Values | Generated Ruby |
|---|---|---|---|---|
| 1 field row, **operator blank** (e.g. `ctx.model.status`) | `:value` | the operand's raw value | free text (`active`, `pending`, …) | `case` / `when` |
| 1 field row **with operator**, OR a query-count row, OR **2+ rows** joined by AND/OR | `:boolean` | a boolean | `true` / `false` | ternary `(cond) ? a : b` |

This is the graceful answer to "a `case` over true/false is ugly": **boolean subjects emit a ternary** (reconnecting to today's clean binary form, but with branch indices resolved by Match Value instead of position); **value subjects emit `case`/`when`** (the existing `SwitchGenerator` pattern).

## Detailed design

### Data model — Decision `properties`

```jsonc
"condition": {
  "type": "group",
  "joins": ["AND", "OR"],          // per-join operators; length = conditions.length - 1; [] for single row
  "conditions": [
    { "kind": "field",       "leftOperand": "ctx.model.status", "operator": "", "rightOperand": "" },
    { "kind": "field",       "leftOperand": "ctx.model.age",    "operator": ">", "rightOperand": "18" },
    { "kind": "query_count", "queryConfig": { "entityId": 3, "entityName": "Orders",
                                              "conditions": { "rules": [ … ] } },
                             "countOperator": ">", "countValue": 0 }
  ]
},
"branches": [
  { "name": "active", "matchValue": "active", "description": "",
    "branchKey": "branch_0", "elementId": "el_…" }
],
"defaultBranchIndex": -1,
"_route_index": 0
```

Changes vs. today:
- `condition` group gains **`joins`** (per-join array, replaces the single group-wide `operator`) and each member carries **`kind`** (`field` | `query_count`).
- Branch objects carry **`matchValue`** instead of **`condition`**.
- `firstMatchOnly` is **removed** (a `case`/ternary is inherently first-match).

### Connection / pipeline storage

- The connection from Decision → branch element stores **`conn.matchValue`** (replacing `conn.condition`); `conn.label` stays the branch name.
- `FlowchartTopologyAnalyzer#analyze` (currently `condition: conn["condition"]` at ~line 46-47) → emits **`matchValue: conn["matchValue"]`** per branch.
- `ActivityGenerator#build_method` (~line 329-342) → injects **`_connection_match_values`** (`[{ "branch" => branch_key, "matchValue" => … }]`) instead of `_connection_conditions`.

### Condition section UI (reqs a, b, c)

File: `condition_builder.js` (+ template/handlers).

- **Per-row type toggle** (req a): each condition row gets a compact **Field condition / Query count** segmented control (ported from the branch modal's `data-condition-type-toggle`).
  - **Field row:** left operand select/manual · operator select · right operand select/custom (as today). The operator dropdown gains an explicit **"— (use value) —"** blank option; choosing it makes the row value-yielding.
  - **Query-count row:** entity select · WHERE rows · count operator/value, rendered **inline inside the condition row** (logic reused from `QueryCountMixin`, generalized off the `data-branch-qc-*` selectors).
- **Condition group** (req b): multiple rows; "Add Condition" appends a row.
- **Per-join independent AND/OR** (req c): each connector between two consecutive rows stores **its own** operator. Clicking a connector toggles **only that connector** (today's `toggleConditionOperator` flips one group-wide value and rewrites *every* pill — that behavior is removed). Each toggle reads/writes its own `data-join-operator` state.
- `collectCondition()` returns the new shape `{ type: "group", joins: [...], conditions: [{ kind, … }] }`.
- New helper `_subjectKind()` derived from the live rows: `value` iff exactly one field row with a blank operator; else `boolean`.

### Branch editor UI (req d)

Files: `templates/branch.js`, `modal_lifecycle.js`, `branch_manager.js`, `query_count.js`.

- **Remove** from the branch modal: the Field/Query-count toggle, both condition panels, all per-branch condition prefill/collect, and the **preset chips** (Yes/No/Otherwise/Custom — they prefilled conditions and are now obsolete).
- **Add** a **Match Value** input that **adapts to the current condition's subject kind** (read once on modal open via the property editor's live condition):
  - `:boolean` → a **`true` / `false` `<select>`**; Branch Name auto-fills `true`/`false`.
  - `:value` (or no condition yet) → a **free-text** input; Branch Name auto-fills from it.
- **Branch Name** auto-fills from Match Value and stays editable; the auto-sync stops once the user manually edits the name.
- **Empty Match Value ⇒ this branch is the default ("Otherwise") branch** (the `else` arm) — preserves today's "always matches" concept without a separate field; reconciles with `defaultBranchIndex`.
- Branch card subtitle shows the **Match Value** (replacing the condition summary); empty match value shows the "default / otherwise" badge.
- `collectBranches()` reads `matchValue` (not `condition`); `addBranchFromModal` / `saveBranchEdits` write `conn.matchValue`.

### Generator (dual shape)

Files: `decision_generator.rb`, `shared/condition_builder.rb`.

`ConditionBuilder` additions:
- `subject_kind(condition)` → `:value` | `:boolean` (mirrors the JS rule).
- `build_subject_value(condition)` → for `:value`, `condition_operand_to_ruby(leftOperand)` of the single bare row.
- `build_condition_group` updated to honor the **per-join `joins`** array, generated **left-to-right with explicit parentheses** for determinism: `(((a OP1 b) OP2 c) OP3 d)`. Query-count members (`kind: "query_count"`) handled via the existing `build_query_count_condition`.

`DecisionGenerator#generate_body` rewrite:

```ruby
# :value subject  → case/when
ctx[:_route_0] = case ctx.dig(:model, :status)
when "active"  then :branch_0
when "pending" then :branch_1
else :branch_2          # defaultBranchIndex / catch-all
end
true

# :boolean subject → ternary, indices resolved by match value "true"/"false"
ctx[:_route_0] = (ctx.dig(:model,:status).present? && _orders.total_count > 0) ? :branch_0 : :branch_1
true
```

Rules:
- **Match-value literal** conversion reuses `OperandConverter` / `SwitchGenerator#case_literal` semantics so `"true"`→`true`, `"5"`→`5`, `"active"`→`"active"`.
- **Boolean subject:** truthy arm = branch whose match value ∈ {`true`,`"true"`}; falsy arm = {`false`,`"false"`}; a missing side routes to the default/catch-all. Extra branches with other match values are ignored (soft-validate, don't raise).
- **Default:** `defaultBranchIndex` if set; else the branch with empty match value; else the trailing `:branch_N` (matching `SwitchGenerator`'s `cases.size` convention).
- Remove `firstMatchOnly` / `generate_fan_out_branch` / `generate_multi_branch` (the if/elsif chain) and the old binary path.
- `validate_config`: require a `condition`; for `:boolean` subjects, soft-warn on >2 branches or non-true/false match values; validate `defaultBranchIndex`.

## Affected files

**JS**
- `app/javascript/flowchart/constants/schemas.js` — Decision schema: new `condition` semantics, drop `firstMatchOnly`, keep `defaultBranchIndex`, update labels/help, drop `_connection_conditions` internal field (or rename).
- `app/javascript/controllers/property_editor/branch_manager/condition_builder.js` — per-row type toggle, per-join independent operators, blank-operator value mode, new `collectCondition` shape, `_subjectKind`.
- `app/javascript/controllers/property_editor/branch_manager/query_count.js` — generalize QC-row build/collect for use inside condition rows; drop branch-modal QC.
- `app/javascript/controllers/property_editor/branch_manager/modal_lifecycle.js` — strip condition toggle/panels/prefill; add adaptive Match Value + name auto-fill; simplify reset.
- `app/javascript/controllers/property_editor/branch_manager.js` — `collectBranches` (matchValue), add/save branch write `conn.matchValue`, remove preset methods + branch-condition helpers.
- `app/javascript/controllers/property_editor/branch_manager/canvas_operations.js` — store `conn.matchValue`, drop `conn.condition`.
- `app/javascript/controllers/property_editor/templates/branch.js` — modal template (remove condition/presets, add adaptive Match Value); branch item subtitle = match value.
- `app/javascript/controllers/property_editor/templates/conditions.js` — match-value summary helper.
- `app/javascript/controllers/property_editor_controller.js` — new actions (per-join toggle = self only, per-row type toggle, matchValue↔name sync); remove obsolete branch-condition actions; save path collects new shapes.

**Ruby**
- `app/services/code_generators/element_types/decision/decision_generator.rb` — dual-shape `generate_body`, new `validate_config`, `sample_input`.
- `app/services/code_generators/shared/condition_builder.rb` — `subject_kind`, `build_subject_value`, per-join `joins`, query-count members in groups.
- `app/services/flowchart_topology_analyzer.rb` — per-branch `matchValue` (was `condition`).
- `app/services/activity_generator.rb` — inject `_connection_match_values` (was `_connection_conditions`).

**Specs** (TDD — write/adjust before/with code)
- `spec/services/code_generators/element_types/decision/decision_generator_spec.rb` — value (`case`) + boolean (ternary) shapes, default branch, per-join groups, query-count subject.
- `spec/services/code_generators/shared/condition_builder_spec.rb` — `joins`, `subject_kind`, `build_subject_value`, query-count members.
- `spec/services/flowchart_topology_analyzer_spec.rb` + `spec/services/activity_generator_spec.rb` — match-value plumbing.
- Any flowchart request/system specs that assert decision routing.

## Locked decisions

1. **Empty Match Value = the default ("Otherwise") branch** (the `else` arm).
2. **`firstMatchOnly` removed** from Decision (a switch is inherently first-match); `defaultBranchIndex` kept.
3. **Branch Name auto-fills but stays editable** (sync stops after manual edit).
4. **Boolean subject → adaptive `true`/`false` `<select>`** in the branch modal (not free text).
5. **Boolean subject → ternary; value subject → `case`/`when`.**
6. Per-join AND/OR generated **left-to-right with explicit parentheses**; no nested-group UI.

## Out of scope

- The standalone **Switch** element (unchanged; the Decision now overlaps it for `:value` subjects — acceptable, not a merge).
- Backward-compatible migration of existing saved flowcharts (per AGENTS.md: treat as a brand-new application; no compat shims).
- Reactive re-validation of every branch's Match Value when the condition's subject kind flips after branches exist (branches keep their stored value; the generator degrades gracefully).

## Testing strategy

Per AGENTS.md this is a "tremendous change" (auth/routing untouched, but generator + multi-file): run the **full suite** via `bin/rails parallel:spec` at the end, plus targeted generator specs during TDD. JS has no meaningful unit coverage (per project memory); verify the property editor behavior in a real browser (flowchart canvas debugging) for: per-row type toggle, independent per-join AND/OR, blank-operator value mode, adaptive Match Value, and name auto-fill.
