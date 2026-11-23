---
date: 2026-04-22
status: draft
topic: Remove Skip Validation, Customer Scoped, and process Step-tab I/O section
---

# Remove Skip Validation, Customer Scoped, and process Step-tab I/O section

## Overview

Strip three obsolete concepts from the flowchart editor's property editor and the Ruby code generators:

1. **Skip Validation** — the `skipValidation` toggle on the `new_model` action, plus the generator logic that conditionally emits `ctx[:…].valid?`.
2. **Customer Scoped** — the modern `customerScoped` toggle on `new_model` AND the legacy `scopeByCustomerId` field on all 6 customer-scoped model-operation actions, plus the generator logic that conditionally applies customer scoping.
3. **Process Step tab "I/O" section** — the per-step I/O pane (Inputs / Outputs) inside expanded process steps, plus the `step.io_overrides` data plumbing on both sides.

No backward compatibility: this is a brand-new app (per `AGENTS.md`). Stale keys in saved flowcharts are silently ignored by the new generators and the new UI. No data migration.

---

## Task 1 — Remove Skip Validation

### Frontend

`app/javascript/flowchart/constants/action_configs/model_actions.js`
- Delete the `skipValidation` field entry (lines 27–35) from the `new_model` action's `configSchema`.

### Backend

`app/services/code_generators/element_types/process/model_operations/new_model_generator.rb`
- Drop `"skipValidation" => "false"` from `sample_input` (line 25).
- Delete the `skip_validation = fetch_enum(...)` local (line 32).
- **Delete the `lines << "ctx[:#{result_var}].valid?" unless skip_validation` line entirely** (line 43). Generated code no longer emits `.valid?` at all — validation becomes the caller's responsibility (e.g. a subsequent `validate_contract` step).
- Drop `skipValidation` from the `validate_config` loop (line 56).

### Specs

`spec/services/code_generators/element_types/process/model_operations/new_model_generator_spec.rb`
- Delete the entire `describe "skipValidation"` block (lines 77–93).
- Update/remove any other test in this file that asserts the presence of `.valid?` in generated output — the new expectation is that `.valid?` is **never** emitted.
- Remove `skipValidation` entries from `validate_config` test cases.

`spec/support/config_schemas.rb` — regenerated via `rake config_schemas:mirror`.

### Behavior change

`new_model` generator never emits `ctx[:#{result_var}].valid?`. The UI drops the "Skip Validation" select. Stale `skipValidation` keys in saved configs are ignored.

---

## Task 2 — Remove Customer Scoped (modern + legacy)

### Frontend

`app/javascript/flowchart/constants/action_configs/model_actions.js` — delete:

| Action | Field | Approx. line |
|---|---|---|
| `new_model` | `customerScoped` | 37 |
| `new_model` | `scopeByCustomerId` | 54 |
| `check_existence` | `scopeByCustomerId` | 136 |
| `find_model` | `scopeByCustomerId` | 517 |
| `pluck_model_fields` | `scopeByCustomerId` | 768 |
| `query_models` | `scopeByCustomerId` | 833 |
| `count_records` | `scopeByCustomerId` | 877 |

### Backend

Customer scoping becomes unconditional across the board:

`app/services/code_generators/element_types/process/model_operations/new_model_generator.rb`
- Drop `"customerScoped" => "true"` from `sample_input`.
- Delete the `customer_scoped` local and the private `customer_scoped?` method (lines 33, 72–79).
- Replace the conditional `attr_pairs.unshift("customer_id: ctx[:customer_id]") if customer_scoped` with unconditional `attr_pairs.unshift("customer_id: ctx[:customer_id]")`.
- Delete the `validate_config` method entirely (it only validated `skipValidation`/`customerScoped`, both gone).
- Delete the `BOOL_VALUES` constant (no longer used).

`app/services/code_generators/element_types/process/model_operations/find_model_generator.rb`
- Remove `scope_customer = config["scopeByCustomerId"] != false` and unconditionally emit `.where(customer_id: ctx[:customer_id])`.

`app/services/code_generators/element_types/process/model_operations/query_models_generator.rb`
- Remove the `config["scopeByCustomerId"] != false` branch; unconditionally scope by customer.

`app/services/code_generators/element_types/process/model_operations/check_existence_generator.rb`
- Remove `scope = config["scopeByCustomerId"] != false`; unconditionally scope.

`app/services/code_generators/element_types/process/model_operations/count_records_generator.rb`
- Remove `scope = config["scopeByCustomerId"] != false`; unconditionally scope.

`app/services/code_generators/element_types/process/model_operations/pluck_fields_generator.rb`
- Remove `scope = config["scopeByCustomerId"] != false`; unconditionally scope.

### Specs

- `spec/services/code_generators/element_types/process/model_operations/new_model_generator_spec.rb` — delete the `describe "customerScoped"` block (lines 60–75), the legacy `scopeByCustomerId` tests (lines 24–31), and the `validate_config` describe block.
- `find_model_generator_spec.rb`, `query_models_generator_spec.rb`, `check_existence_generator_spec.rb`, `count_records_generator_spec.rb`, `pluck_fields_generator_spec.rb` — delete tests that pass `scopeByCustomerId => false` and assert `customer_id` *omission*; keep the customer-scoped assertions. Where an assertion currently expects `customer_id` omission, update to expect `customer_id` presence.
- `spec/services/activity_generator_spec.rb` line 2074 — remove `scopeByCustomerId => false` from the fixture and update the expected output to include customer scoping.
- `spec/support/config_schemas.rb` — regenerated via `rake config_schemas:mirror`.

### Behavior change

All 6 model-operation actions (`new_model`, `find_model`, `query_models`, `check_existence`, `count_records`, `pluck_model_fields`) now always scope by `customer_id`. No opt-out in UI; no opt-out in generator. Stale `customerScoped` / `scopeByCustomerId` keys are silently ignored.

---

## Task 3 — Remove Process Step tab I/O section

### Frontend — delete entirely

- `app/javascript/controllers/property_editor/step_io_manager.js`
- `app/javascript/controllers/property_editor/step_io/override_computer.js`
- `app/javascript/controllers/property_editor/step_io/reachability.js`

### Frontend — keep (used for autocomplete, element I/O, conflict resolution)

- `app/javascript/controllers/property_editor/step_io/io_params_client.js` — still imported by `flowchart_canvas_controller.js` (`primeAllStepPins`) and transitively feeds `context_variable_provider.js` autocomplete via `canvas.stepPins`.

The `step_io/` directory keeps `io_params_client.js` only.

### Frontend — edit

`app/javascript/controllers/property_editor_controller.js`
- Remove `import { StepIoManager } from "controllers/property_editor/step_io_manager"` (line 8).
- Remove `this.stepIoManager = new StepIoManager(this)` (line 71).
- Remove the step-expand callsite that invokes `this.stepIoManager.openForStep(...)` (around line 479).

`app/javascript/controllers/property_editor/step_manager.js`
- Remove the `pane = stepItem.querySelector("[data-step-io-pane]")` lookup and the `StepIoManager` invocation in `handleStepToggle` (around lines 400, 418).
- In `collectSteps` (around lines 773–784): drop the `[data-step-io-overrides]` read and the `stepData.io_overrides = ...` assignment.
- Remove the `ioOverrides` handling in `buildStepItemHTML` / step rendering (lines 938–1060): drop the `ioOverrides` parameter, the `storedIoOverrides` parse, and the downstream propagation to the template.

`app/javascript/controllers/property_editor/templates.js`
- Remove `<div data-step-io-pane></div>` from the step-details block (line 544).
- Remove the `<input type="hidden" name="steps[${index}][ioOverrides]" ... data-step-io-overrides>` line (line 597).
- Remove the `ioOverrides` parameter from `buildStepItemHTML` and the surrounding comments that describe the I/O pane (around lines 526–540).

`app/javascript/flowchart/context_variable_provider.js`
- Remove `getStepEffectiveOutputs`'s override lookup (lines 70–88). Step outputs become the raw pins; the function simplifies to returning `pins.outputs.map(p => p.pin)`.

### Backend — edit

`app/services/activity_generator.rb`
- `step_effective_keys` (around line 719): drop the `overrides = (step["io_overrides"] || {})["outputs"] || []` line and the `rename_index`; return raw pin names.
- Step-body rewrite callsite (around line 851): drop `io_overrides: step["io_overrides"] || {}` from the hash passed to `EmissionRewriter`.
- Update surrounding comments to reflect that step-level overrides no longer exist.

`app/services/code_generators/emission_rewriter.rb`
- Remove the step-level `call` API (the non-element `self.call` entry point, around lines 84–112) and its `ActionRewriter` worker. Only `call_element` (element-level) remains.
- Update the top-of-file comments to describe element-level rewriting only.

### Backend — keep unchanged

- Element-level `io_overrides` (`element.properties.io_overrides`) — still drives the Element I/O tab, `ConflictResolver`, `flowchart_input_output_validator`, and `EmissionRewriter.call_element`.
- `CodeGenerators::IoExtractor` service and the `POST /code_generators/:action_name/io_params` endpoint — still seed `canvas.stepPins` for autocomplete.
- `canvas.stepPins`, `setStepPins`, `getStepPins` — still used by autocomplete.

### Specs

- `spec/services/code_generators/emission_rewriter_spec.rb` — delete the step-level describe blocks testing the non-element `call` API (the fixtures at lines 9, 17, 25, 33, 41, 52, 62, 72, 80); keep only `call_element` tests.
- `spec/services/activity_generator_spec.rb` — any test that sets `step.io_overrides` on input fixtures and asserts rewritten output gets adjusted; where the assertion depends on step-level rewriting, update to the un-rewritten output.
- Any system spec interacting with the Step I/O pane is removed. `spec/system/property_editor/element_io_tab_spec.rb` (Element I/O tab) is untouched.

### Behavior change

**Step-to-step output collisions within a single process are no longer auto-renamed.** If two steps in the same process emit the same ctx key (e.g. both emit `model`), the second overwrites the first in ctx. Users disambiguate by setting the `resultVar` field on each step (already supported by every relevant action: `new_model`, `find_model`, `query_models`, `pluck_fields`, `count_records`, `check_existence`).

**Element-level collisions are unchanged** — `ConflictResolver` still auto-renames element outputs via `element.properties.io_overrides`.

---

## Execution order

1. **Task 1 — Skip Validation** (smallest, self-contained). Run `rake config_schemas:mirror`, then `bundle exec rspec spec/services/code_generators/element_types/process/model_operations/new_model_generator_spec.rb`.
2. **Task 2 — Customer Scoped** (6 generators + specs). Run `rake config_schemas:mirror`, then the model-operations spec directory, then `activity_generator_spec.rb`.
3. **Task 3 — Step I/O** (frontend + backend + shared files). Run the emission_rewriter and activity_generator specs, plus system specs for the property editor.

Tasks 1 and 2 both touch `model_actions.js` and `new_model_generator.rb`/spec; running them sequentially avoids merge thrash.

## Verification

- `rake config_schemas:mirror` — after Tasks 1 & 2.
- `bundle exec rspec spec/services/code_generators/` — all generator specs.
- `bundle exec rspec spec/services/activity_generator_spec.rb spec/services/flowchart_input_output_validator_spec.rb`.
- `bundle exec rspec spec/system/property_editor/` — system tests.
- `bundle exec rspec` — full suite (baseline 4331+ examples, 0 failures).
- `scripts/audit_generator_ui.rb` — canonical UI↔generator schema audit (per memory).

### Manual browser checks (after Task 3)

Open the flowchart edit page, pick a process element, go to the Step tab:
- The I/O pane no longer appears inside expanded step items.
- The `ioOverrides` hidden input is absent from the DOM.
- The Element-level I/O tab still renders Inputs / Outputs with producer dropdowns and rename badges.
- Autocomplete on config fields still lists upstream step outputs.

## Out of scope

- Migration of saved flowcharts (stale keys silently ignored).
- Any refactor of `ConflictResolver` — element-level logic is unchanged.
- Renaming or removing the `step_io/` directory (`io_params_client.js` stays there).
