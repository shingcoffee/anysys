# Generator ↔ Property Editor Alignment Audit and Refactor

**Date:** 2026-04-19
**Status:** Approved — ready for planning

## Summary

Every Ruby code generator under `app/services/code_generators/element_types/` reads a configuration hash that originates from the flowchart edit page's property editor. Over time, generators have grown new config keys, new enum options, and new conditional branches without corresponding updates to the UI `configSchema`. The result: users cannot configure behavior that the generator actually implements.

This project audits all 113 in-scope generators against their UI property-editor schemas, produces a machine-readable gap report, and then refactors the property editor in phased batches so every generator config path is reachable from the UI.

## Scope

### In scope (113 generators)

**Element-level (9)** — each has an entry in `ELEMENT_SCHEMAS` in `app/javascript/flowchart/constants/schemas.js`:

- `start`, `end`, `process`, `decision`, `loop`, `join`, `subflow`, `error_handler`, `timer`

**Step-action (103)** — Ruby generators grouped under 16 action categories at `app/services/code_generators/element_types/process/<category>/`. Their UI counterparts live in `app/javascript/flowchart/constants/action_configs/<category>_actions.js`. Generator counts per category:

- `data_operations` (32), `model_operations` (17), `security` (9), `utility` (8), `file_operations` (7), `resilience` (4), `caching` (4), `human_workflow` (4), `communication` (4), `scheduling_time` (3), `background` (2), `concurrency` (2), `realtime` (2), `response` (2), `validation` (2), `service_invocation` (1)

A small set of generators have **naming/aliasing mismatches** with the UI rather than cleanly matching on filename:

- `api_call_generator.rb` ↔ UI key `"API_call"` (casing mismatch)
- `validate_contract_generator.rb` ↔ UI key `"validate"` (alias)
- `pluck_fields_generator.rb` exists under both `data_operations/` and `model_operations/`; UI has one entry keyed `"pluck_fields"` in `data_actions.js` — which generator it pairs with needs resolution at audit time

A separate gap category (`action_key_mismatch`, see below) tracks these. All other 100 step-action generators have direct filename ↔ UI `value:` key matches.

### Out of scope

**Element types without existing UI schema** — `fork`, `parallel_for_each`, `saga`, `signal_wait`, `switch`, `transaction`. These have Ruby generators but no entry in `ELEMENT_SCHEMAS`. Creating UI schemas for them is a separate initiative.

**Wrapper fields at element level** — `timeout`, `retryCount`, `retryBackoff`, `guardCondition` are read by `BaseGenerator#apply_wrappers` for every element, but are only surfaced in the step modal's Advanced section. Auditing their presence on element-level property editors is deferred.

## What "fully support" means

For every in-scope generator, the property editor must expose every config key the generator reads, with every enum value the generator recognizes, under visibility rules that mirror the generator's conditional branches, with defaults consistent with the generator's fallbacks.

Concretely, four gap categories are tracked:

1. **`action_key_mismatch`** — the Ruby generator maps to an existing UI entry under a different `value:` string. Audit records the pair; no UI change is required, but the audit metadata lists the mapping so downstream gap rows are attributed to the correct UI entry.
2. **`missing_enum_option`** — the UI `select` field exists but omits one or more values the generator's constant (e.g. `VALUE_TYPES = %w[…]`), `fetch_enum` whitelist, or `case … when "…"` branch recognizes.
3. **`missing_field`** — the generator reads `config["xyz"]` but the UI `configSchema` has no entry with `key: "xyz"`.
4. **`mismatched_visibility_or_default`** — the UI has the field but lacks `visibleWhen` that matches the generator's conditional branching, is missing a `default` the generator implicitly assumes, or is missing a `required: true` flag that `validate_config` enforces as non-blank.

## Deliverables

1. **Audit artifact** — a single YAML file at `docs/superpowers/specs/2026-04-19-generator-ui-audit-data.yml` listing every generator, its UI schema reference, and every gap (with the fix shape pre-computed).
2. **Phased UI refactor** — 25 phases, each a single focused change touching one UI file, guided by the audit artifact.

## Design

### Audit methodology

For each generator, extract its config contract deterministically from source:

1. **Keys read** — every `config[…]` / `fetch_with_default` / `fetch_enum` / `fetch_int_positive` / `fetch_*` access in `generate_body` and its helpers.
2. **Enum values recognized** — `%w[…]`/`%i[…]` constants referenced by the generator (e.g. `VALUE_TYPES`, `RANDOM_TYPES`), `fetch_enum(…, allowed, …)` allowed list, and `case value; when "…"` branches.
3. **Required fields** — keys that `validate_config` treats as blank-invalid.
4. **Conditional fields** — keys only read inside a `case`/`if` guarded by another key's value. These drive `visibleWhen`.
5. **Defaults** — literal fallbacks: `config[k] || "…"`, `fetch_with_default(k, …)`, `fetch_enum(k, _, default: …)`.

Extraction uses a lightweight Ruby Ripper-based walker combined with regex passes for constants. Manual verification of a ~10% sample validates accuracy; any systematic false positives prompt a walker refinement before the report is finalized.

Compare extracted contract against the UI `configSchema` (for step actions) or `ELEMENT_SCHEMAS[type]` (for element types). Emit one gap row per mismatch.

### Audit output format

```yaml
# docs/superpowers/specs/2026-04-19-generator-ui-audit-data.yml
- generator: CodeGenerators::ElementTypes::Process::DataOperations::AssignValueGenerator
  kind: step_action                                    # or element_type
  ui_ref: action_configs/data_actions.js::assign_value # or schemas.js::process
  phase: data                                          # maps to batch id
  gaps:
    - type: missing_enum_option
      field: valueType
      missing: [float, array, hash, "null"]
    - type: missing_field
      field: floatValue
      input_type: number
      visible_when: { field: valueType, value: float }
    - type: missing_field
      field: arrayValue
      input_type: key_value_list
      visible_when: { field: valueType, value: array }
    # …
```

The audit artifact is the single source of truth. All phased plans consume it without re-interpreting generator source.

**Leveraging existing mirror infrastructure:** The repo already has `spec/support/config_schemas.rb` — a Ruby-parseable mirror of the JS `configSchema` arrays regenerated by `rake config_schemas:mirror`. The audit script reads this mirror for UI data (reliable, already-parsed) rather than re-parsing JS. After every UI fix phase, the plan runs `rake config_schemas:mirror` and verifies `rake config_schemas:check` reports no drift.

### Refactor pattern (per-gap fix rules)

| Gap type | Fix |
|---|---|
| `action_key_mismatch` | No UI change. Audit records the canonical generator ↔ UI mapping (e.g. `api_call` ↔ `API_call`). Downstream `missing_*` gaps for that generator target the matched UI entry. |
| `missing_enum_option` | Append `{ value, label }` to the select's `options` array. Label = value verbatim (matches existing convention: `"float"` → `"float"`). |
| `missing_field` | Append new field entry to the `configSchema` array, placed after the most semantically related existing field (typically adjacent to the `visibleWhen` anchor). `type` follows mapping below; `label` is Title Case from key; `placeholder` describes expected input. |
| `mismatched_visibility_or_default` | Patch the existing field's `visibleWhen`, `default`, or `required` in place. |

**Input-type mapping from config key semantics:**

- `*Expression`, `customExpression`, `*Template`, `responseBody` → `textarea`
- `*Value` + numeric generator read (`to_i`/`to_f`) → `number`
- `*Value` + `true`/`false` branches → `select` with `{ value: "true" }`/`{ value: "false" }`
- `*Value` + array literal → `key_value_list`
- `*Value` + hash literal → `key_value_list`
- `*List`, `*Fields`, `*Mappings`, `*Tags`, `*Operations` → `key_value_list`
- Enum-backed (value appears in a `case`/`%w[…]`) → `select` with options drawn from the generator's constant/whitelist
- All others → `text`

The step-config field renderer (`buildStepConfigFieldsHTML` in `templates.js`) already supports all of `text | textarea | number | select | key_value_list`. No new field types are expected to be required.

### Phasing

25 phases, one per file:

| # | Phase | UI file |
|---|---|---|
| 1–9 | Element types | `app/javascript/flowchart/constants/schemas.js` (one phase per element type in that file) |
| 10–25 | Action categories | `app/javascript/flowchart/constants/action_configs/<category>_actions.js` (one phase per category) |

Phases are independent: each PR touches one element-type block or one category file and only the generators in that phase. Phases with zero gaps are marked skipped in the plan.

### Verification

Per phase:

1. **JS build** — `yarn build` must succeed (parses all configSchema changes).
2. **RSpec spot check** — run the phase's generator specs: `bundle exec rspec spec/services/code_generators/element_types/<area>` — must remain green.
3. **Visual smoke** — open the flowchart edit page, open one representative element/action from the phase, confirm the new fields render and `visibleWhen` toggles behave.
4. **Baseline invariant** — after all phases, `spec/services/code_generators/` must still report 1735 examples, 0 failures (snapshot per MEMORY, 2026-04-17).

## Assumptions & risks

- **Assumption:** `buildStepConfigFieldsHTML` already handles every UI input type the audit will need. Verified against template source; if a gap surfaces a novel type, the plan gains a small prerequisite task to extend the renderer.
- **Assumption:** The 1735-examples baseline is stable. If the baseline has changed, re-snapshot before starting.
- **Risk:** Audit extraction may misread metaprogramming or dynamic key access. Mitigation: manual ~10% sample review before finalizing the report; any ambiguous generator is flagged for human review rather than auto-added.
- **Risk:** Adding fields changes saved-element payload shape when users later edit. Mitigation: `collectStepConfig` in `step_manager.js` already handles arbitrary keys; stored-value merge behavior (`{ ...storedConfig, ...liveConfig }`) preserves unknown keys, so existing saved flowcharts are unaffected.

## Non-goals

- No changes to any generator's Ruby code.
- No creation of new element-type UI schemas for `fork`/`parallel_for_each`/`saga`/`signal_wait`/`switch`/`transaction`.
- No changes to the `property_editor` controller or step-manager business logic beyond whatever `buildStepConfigFieldsHTML` already supports.
- No changes to how wrapper fields (`timeout`/`retryCount`/`retryBackoff`/`guardCondition`) are surfaced at element level.
