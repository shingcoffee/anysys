# Model-step data source + process-element error simplification — Design

**Date:** 2026-04-23
**Status:** Design approved; plan pending.

## Summary

Two related simplifications to the code-generation side of the Anysys:

1. **Model-step data source.** Remove `attributes`, `associations`, and `fieldMappings` inputs from the property editor for the model actions `new_model`, `update_model`, and `upsert_model`. The generated code derives attribute values from `ctx[:contract]` (Reform) when a contract is in scope, or from `ctx[:params]` (column-sliced) otherwise. `customer_id` remains pinned to `ctx[:customer_id]`.
2. **Process-element error handling.** Delete the per-step `errorStrategy` feature entirely: remove the UI field from every action config, delete `shared/error_wrapper.rb`, and strip the `wrap_with_error_strategy` branch from every process-element step generator. Step bodies become plain code; Trailblazer's Railway owns failure routing via its existing failure track.

## Goals

- Drop `attributes` / `associations` from `new_model` UI config.
- Drop `fieldMappings` from `update_model` UI config.
- Drop `attributes` from `upsert_model` UI config.
- Generators for the three model-assigning actions infer data from `ctx[:contract]` when present (using Reform's `sync`) or from a column-scoped `ctx[:params]` slice otherwise.
- Multi-tenancy invariant: `customer_id` is always set from `ctx[:customer_id]`, never from user-supplied params, regardless of which data path is taken.
- Delete `errorStrategy` from every process-element step generator and every action config.
- Delete `shared/error_wrapper.rb`, its include in `BaseGenerator`, and its emitted `ctx[:_last_error]` payload.
- Model-operation generators become thinner and more idiomatic for the Reform / Trailblazer / dry-rb stack.

## Non-goals

- No change to the process element's UI-only `onStepFailure` / `errorHandling` fields, and no wiring them up to activity-level error routing. Those remain UI-only for now.
- No change to non-model step generators' config schemas beyond dropping the `errorStrategy` field.
- No change to `find_model` / `query_models` / `check_existence` / any query-predicate fields. Query keys and values stay user-specified because they describe query constraints, not data assignments.
- No change to element-level wrappers (`wrap_with_timeout`, `wrap_with_retry`, `wrap_with_guard`) in `BaseGenerator`.
- No data migration for existing saved flowcharts. Per AGENTS.md, backward compatibility with stored config is not required.

## Architecture

### Runtime data flow — model-assigning steps

```
[HTTP request params] → ctx[:params]
                          │
                          ▼
            build_contract (existing step)
                          │
            ctx[:contract] ← Reform::Form wrapping ctx[:model]
                          │
                          ▼
           validate_contract (existing step)
                          │
                    [validated]
                          │
                          ▼
    new_model / update_model / upsert_model
                          │
      ┌───── ctx[:contract] present? ─────┐
      │                                   │
     yes                                  no
      │                                   │
      ▼                                   ▼
 contract.sync                     allowed = ctx[:params].slice(*EntityEntry.build_for(
 (Reform copies validated            ctx[:bound_entity]).attribute_names)
  attrs → model; nested              ctx[:model].assign_attributes(allowed)
  associations handled by            ctx[:model].customer_id = ctx[:customer_id]
  nested form definitions)
      │                                   │
      └──────────────┬────────────────────┘
                     ▼
              ctx[:model].save
```

### Runtime data flow — step failures

```
Step body raises
        │
        ▼
Trailblazer::Activity::Railway
catches and routes to failure track
        │
        ▼
Activity's End.failure terminus
```

No per-step `begin/rescue`. No `ctx[:_last_error]`. Element-level `wrap_with_timeout` / `wrap_with_retry` / `wrap_with_guard` in `BaseGenerator` are untouched and still orthogonal to this change.

### Component changes

| Component | Change |
|---|---|
| `app/services/code_generators/shared/model_assignment_builder.rb` | **New.** Emits the contract-vs-params branch as a string fragment. Reused by `new_model`, `update_model`, `upsert_model`. |
| `app/services/code_generators/element_types/process/model_operations/new_model_generator.rb` | Rewrite: drop `attribute_pairs` / `association_pairs` / `normalize_pairs`. Emit two-branch body via the new builder. Remove `ErrorWrapper` include and `error_strategy` branch. |
| `app/services/code_generators/element_types/process/model_operations/update_model_generator.rb` | Drop `fieldMappings`, `safe_ident?`, and the mass-assignment-bypass defense (no more user-typed column names). Derive assignments via the new builder. Keep strategy logic (`save`, `update`, `update_columns`, `update_all`), `lockVersion`, `returnChanges`, `runCallbacks`. Remove `ErrorWrapper`. |
| `app/services/code_generators/element_types/process/model_operations/upsert_model_generator.rb` | Replace the `attributes` hash source: build payload from contract-synced model OR column-sliced `ctx[:params]`. Keep `matchFields`, `uniqueBy`, `onConflict`, `returning`, `timestamps`, `createdKey`. Remove `ErrorWrapper`. |
| All other step generators under `app/services/code_generators/element_types/process/**/*_generator.rb` | Remove `include CodeGenerators::Shared::ErrorWrapper`; remove `error_strategy = config["errorStrategy"]` read; replace the `if error_strategy.present? ... else "#{inner}\ntrue" end` branch with the plain body (and a trailing `true` only where the last expression isn't already meaningful). |
| `app/services/code_generators/shared/error_wrapper.rb` | **Delete.** |
| `app/services/code_generators/base_generator.rb` | Remove `require_relative "shared/error_wrapper"`, remove `include Shared::ErrorWrapper`, remove `current_error_strategy` helper. |
| `app/javascript/flowchart/constants/action_configs/model_actions.js` | Delete `attributes` and `associations` fields from `new_model`. Delete `fieldMappings` from `update_model`. Delete `attributes` from `upsert_model`. |
| `app/javascript/flowchart/constants/action_configs/*.js` (all 16 files, 8 of which currently reference `errorStrategy`) | Delete every `errorStrategy` field entry. |
| `spec/services/code_generators/element_types/process/model_operations/*_generator_spec.rb` | Remove fixtures and contexts that set `attributes` / `associations` / `fieldMappings` / `errorStrategy`. Add new contract-path and params-path contexts. Preserve all non-assignment coverage (strategies, flags, match keys, etc.). |
| `spec/services/code_generators/element_types/process/**/*_generator_spec.rb` | Remove every `errorStrategy` context and every `ctx[:_last_error]` assertion. |
| `spec/services/code_generators/shared/error_wrapper_spec.rb` (if present) | **Delete.** |
| `spec/services/code_generators/shared/model_assignment_builder_spec.rb` | **New.** Table-driven tests across `{contract-present, no-contract} × {write strategy}`. |

## Generated-code examples

### `new_model`

**Before:**

```ruby
begin
  ctx[:model] = EntityEntry.build_for(ctx[:bound_entity]).new(
    customer_id: ctx[:customer_id],
    name: ctx[:user_name],
    profile_attributes: ctx[:profile_attrs]
  )
rescue => e
  ctx[:_last_error] = { source: "new_model", message: e.message, class: e.class.name, at: Time.current }
  true
end
```

**After:**

```ruby
_model_class = EntityEntry.build_for(ctx[:bound_entity])
ctx[:model] = _model_class.new
if ctx[:contract]
  ctx[:contract].sync
else
  _allowed = ctx[:params].to_h.with_indifferent_access.slice(*_model_class.attribute_names)
  ctx[:model].assign_attributes(_allowed)
end
ctx[:model].customer_id = ctx[:customer_id]
true
```

The trailing `customer_id` assignment is the single source of truth for the tenant invariant. It runs after both branches so it overrides anything a contract or params slice might have written.

`ctx[:contract].sync` is called with no arguments: `build_contract` already bound the contract to `ctx[:model]`, so `sync` copies validated form state back to that already-bound model in place.

### `update_model` (strategy `update`, `run_callbacks: true`)

```ruby
if ctx[:contract]
  ctx[:contract].sync
  ctx[:model].save
else
  _allowed = ctx[:params].to_h.with_indifferent_access.slice(*ctx[:model].class.attribute_names)
  ctx[:model].update(_allowed)
end
```

Other strategy branches (`update_columns`, `update_all`, `save`) retain their existing structure — only the source of the `assignments` hash changes. `lockVersion` and `returnChanges` logic is preserved as-is.

### `upsert_model` (method `upsert`)

```ruby
_model_class = EntityEntry.build_for(ctx[:bound_entity])
_payload = if ctx[:contract]
  ctx[:contract].sync
  ctx[:contract].model.attributes.symbolize_keys.slice(*_model_class.attribute_names.map(&:to_sym))
else
  ctx[:params].to_h.symbolize_keys.slice(*_model_class.attribute_names.map(&:to_sym))
end
_payload[:email] = ctx[:email]  # matchFields values pinned from ctx, as today
_result = _model_class.upsert(_payload, unique_by: [:email], on_duplicate: :update_all, record_timestamps: true)
ctx[:model] = _result
```

`matchFields`, `uniqueBy`, `onConflict`, `returning`, `timestamps`, and `createdKey` behavior are unchanged.

### A non-model step — `save_model`

**Before:**

```ruby
begin
  ctx[:model].save
rescue => e
  ctx[:_last_error] = { source: "save_model", message: e.message, class: e.class.name, at: Time.current }
  true
end
```

**After:**

```ruby
ctx[:model].save
```

## Testing

### Model-generator specs

**`new_model_generator_spec.rb`**
- Delete all contexts that stub `attributes` / `associations` config.
- Delete all `errorStrategy` contexts (including those asserting the `begin/rescue` wrapper).
- Add `context "when ctx[:contract] is present"` — expect emitted code contains `ctx[:contract].sync` and does **not** contain `ctx[:params]`.
- Add `context "when no contract"` — expect emitted code contains `_allowed = ctx[:params].to_h.with_indifferent_access.slice(*_model_class.attribute_names)` and `ctx[:model].assign_attributes(_allowed)`.
- Keep: `customer_id: ctx[:customer_id]` assertion, `resultVar` default `"model"`.
- Add: multi-tenancy invariant test — given `ctx[:params]` contains `customer_id: "attacker"`, the emitted code's final `customer_id` assignment comes from `ctx[:customer_id]`.

**`update_model_generator_spec.rb`**
- Delete all `fieldMappings` fixtures and the mass-assignment-bypass tests (the attack surface no longer exists).
- Delete all `errorStrategy` contexts.
- Preserve strategy-branch coverage (`save`, `update`, `update_columns`, `update_all`), `lockVersion`, `returnChanges`, `runCallbacks`.
- Add contract-path and params-path assertions for each strategy branch.

**`upsert_model_generator_spec.rb`**
- Delete the `attributes` fixtures.
- Delete all `errorStrategy` contexts.
- Preserve `matchFields`, `uniqueBy`, `onConflict` (update / skip / raise), `returning`, `timestamps`, `createdKey`.
- Add contract-path and params-path assertions for each of the four `method` branches (`find_or_create_by`, `find_or_initialize`, `upsert`, `upsert_all`).

### All other process step generator specs

- Delete every `errorStrategy` context and every `ctx[:_last_error]` / `wrap_with_error_strategy` assertion.
- Keep everything else.

### New helper spec

- `spec/services/code_generators/shared/model_assignment_builder_spec.rb` — table-driven across `{contract-present, no-contract} × {write strategy}`, asserting emitted string fragments.

### Deletions

- `spec/services/code_generators/shared/error_wrapper_spec.rb` (if present).
- Any fixture files or shared examples referencing `errorStrategy` or `_last_error`.

### Integration / smoke

- `spec/services/code_generators/activity_generator_spec.rb` (and any flowchart-level generator spec) — verify that a generated activity with a `build_contract → validate_contract → new_model → save_model` chain runs end-to-end against a real contract-validated request and lands a row in the DB.

### Baseline

- `spec/services/code_generators/` currently reports 4331 examples, 0 failures. After this work we expect a net decrease in example count (removed error-strategy paths outweigh added contract/params paths), still 0 failures.

## Risks & edge cases

1. **Stored flowchart data still contains dropped keys.** Existing flowcharts may have `attributes`, `associations`, `fieldMappings`, or `errorStrategy` in `element.properties.config`. After this change the UI won't render them and generators ignore them — silent drop, not an error. Acceptable per AGENTS.md's no-backward-compatibility directive.
2. **Contracts without `sync` semantics in scope.** The contract-path branch assumes the standard `build_contract → validate_contract → new/update/upsert` chain has been exercised so that `ctx[:contract]` is populated and its fields are valid. Custom chains that populate `ctx[:contract]` without running `validate_contract` are treated the same as if the contract were absent — the emitted branch will still call `sync`, moving whatever is currently on the form to the model. Pipelines that want the params path should leave `ctx[:contract]` nil.
3. **`customer_id` mass-assignment protection.** The column-slice path includes `customer_id` in `attribute_names`, so `ctx[:params][:customer_id]` could land on the model via `assign_attributes`. The trailing `ctx[:model].customer_id = ctx[:customer_id]` assignment enforces the tenant invariant regardless. Covered by an explicit spec.
4. **`find_model` / `query_models` unchanged.** Query predicate fields (`findField`, `findValue`, etc.) still take user-typed ctx expressions. Intentional — those describe query constraints, not data assignments — but flagged here so readers don't assume the asymmetry was an oversight.
5. **Railway semantics after removing `errorStrategy`.** Any exception raised from a step now routes the activity to its failure track (or propagates, depending on step definition). Steps that previously used `fail_track` already returned `false` — equivalent outcome. Steps that previously used `continue` silently swallowed errors — no longer possible. That is the intended simplification; integration coverage must confirm the happy path still succeeds.
6. **`apply_wrappers` pipeline order.** `BaseGenerator#apply_wrappers` continues applying `wrap_with_timeout → wrap_with_retry → wrap_with_guard`. The retry wrapper has its own `begin/rescue` and is opt-in (`element["retryCount"] > 0`). Unchanged.
7. **`upsert_all` with no contract.** `upsert_all` takes an array of rows; the contract-path produces a single record. When no contract is present, the params path honors today's single-row semantics. Covered by spec.
8. **Calculated attributes.** `EntityEntry.build_for` skips setters for `Calculated`-type properties, so `assign_attributes` ignores them. Existing behavior preserved.

## Migration steps (for the plan executor)

1. Add `app/services/code_generators/shared/model_assignment_builder.rb` and its spec.
2. Refactor `new_model_generator.rb`, `update_model_generator.rb`, `upsert_model_generator.rb` to use the new builder; update their specs.
3. Sweep all `app/services/code_generators/element_types/process/**/*_generator.rb` files to delete the `ErrorWrapper` include, `error_strategy` config read, and the `wrap_with_error_strategy` branch. Replace with the plain body.
4. Sweep all corresponding specs to delete `errorStrategy` contexts and `ctx[:_last_error]` assertions.
5. Delete `app/services/code_generators/shared/error_wrapper.rb` and its spec; remove the require and include from `base_generator.rb`.
6. Sweep all `app/javascript/flowchart/constants/action_configs/*.js` files to delete every `errorStrategy` schema entry and the three model-action `attributes` / `associations` / `fieldMappings` entries.
7. Run the full `spec/services/code_generators/` suite; confirm 0 failures.
8. Manually exercise the flowchart edit page for `new_model`, `update_model`, and `upsert_model` to confirm the UI no longer shows the dropped fields.
