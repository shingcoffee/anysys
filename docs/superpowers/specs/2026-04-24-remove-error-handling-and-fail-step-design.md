# Remove Error Handling and `fail` Step from Generated Activity Code

## Overview

Refactor all code generators under `app/services/code_generators/` and their property-editor configuration + UI to stop emitting error-handling scaffolding in generated Trailblazer Activity code. Remove the `error_handler` flowchart element, the `process` element's `errorHandling` / `onStepFailure` advanced fields, and the per-action failure-strategy enums on ~17 leaf generators.

All unhandled exceptions thrown from step bodies propagate to `DynamicController#execute_activity`, which is already the single, authoritative error boundary (it wraps activity execution in a `rescue StandardError` block inside an `ActiveRecord::Base.transaction`).

## Guiding Principle

**`DynamicController#execute_activity` is the only place error handling lives.** Generated step methods return `true` on success and `false` to signal flow failure; they never `rescue` and never emit `fail :handler` tracks. Exceptions propagate untouched to the controller, which rescues, rolls back the transaction, logs, and renders `422`.

This principle does not apply to elements whose **purpose** is in-flow failure semantics — `saga` compensations, `transaction` commit/rollback, `signal_wait` timeouts, and the four `process/resilience` primitives. Those are business-flow decisions, not error plumbing, and keep their existing configuration.

## Persisted-Data Handling

- Existing flowcharts that contain `error_handler` nodes continue to load. When `ActivityGenerator` encounters one after the generator directory is deleted, it falls through the existing "no registered generator" branch in `method_body` and emits a visible `# TODO: unknown element type 'error_handler'` marker plus a `true` no-op body (see `activity_generator.rb:631-638`). Users see the TODO and re-edit the flowchart. No DB migration, no data cleanup — consistent with the project's "no backwards-compatibility" rule.
- Existing flowcharts whose `process` elements carry `errorHandling` / `onStepFailure` values in their properties JSON continue to load. The generator silently ignores those keys because the code paths that read them are deleted.

## Scope

### Category A — Full Deletion of the `error_handler` Element

| Layer | Touchpoints |
|---|---|
| Ruby | Delete `app/services/code_generators/element_types/error_handler/` directory (generator + spec). |
| Ruby | Delete `app/components/flowchart_elements/error_handler_element_component.rb` + its spec. |
| Ruby | `app/services/activity_generator.rb`: remove the `when "error_handler" then "fail"` branch in `derive_step_type`; remove the `error_handlers` collection, the `build_error_handler_method` method, and the `fail :handle_error_in_*` append in `step_declarations`. |
| Ruby | `app/components/flowchart_elements/base_element_component.rb`: remove `error_handler_icon` method and its `when 'error_handler'` dispatch. |
| Ruby | `app/components/admin/code_generators/index_component.rb` + `sidebar_component.rb`: remove `error_handler` icon/color entries. |
| JS | `app/javascript/flowchart/constants/elements.js`: remove `error_handler` from `ELEMENT_COLORS` and `DEFAULT_LABELS`. |
| JS | `app/javascript/flowchart/constants/schemas.js`: delete the entire `error_handler: { ... }` schema block. |
| JS | `app/javascript/flowchart/element_renderer.js`: remove `_createErrorHandlerShape` method and its dispatch entry. |
| JS | `app/javascript/controllers/property_editor/form_builder.js`: remove `error_handler` icon path. |
| JS | `app/javascript/controllers/property_editor/tab_manager.js`: remove all three `error_handler` entries from `elementTypes` arrays and the `error_handler: "advanced"` default-tab mapping. |
| JS | `app/javascript/controllers/property_editor_controller.js`: remove `_deriveLabelForErrorHandler` and the `case "error_handler"` in the label-derivation dispatch. |
| Validation | No new validator logic. `ActivityGenerator#method_body` already emits a `# TODO: unknown element type '<type>'` marker for element types with no registered generator (`activity_generator.rb:631-638`); once the `error_handler` generator is deleted, persisted `error_handler` nodes hit that path automatically. Verify via a regression spec. |

### Category B — Removal of `process` Element's `errorHandling` + `onStepFailure`

| Layer | Touchpoints |
|---|---|
| JS | `schemas.js` `process:` block: delete `onStepFailure` and `errorHandling` keys. |
| JS | `form_builder.js`: delete the `error_handling` field-type branch. |
| JS | `templates.js`: delete `buildErrorHandlingFieldTemplate` export. |
| JS | `property_editor_controller.js`: delete `handleErrorHandlingModeChange`, `_collectErrorHandling`, the `errorHandling[` entry in `skipPrefixes`, and the `_collectErrorHandling()` call + merge. |
| Ruby | `activity_generator.rb`: delete the `errorHandling` branch in `step_declarations` (the `fail :handle_error_in_*` append). Delete `apply_process_scope_options` method entirely and its caller in `build_method` / `method_body`. |

### Category C — Per-Leaf-Generator Failure-Strategy Deletion

For each generator below, strip the failure enum field from the matching `action_configs/*.js` file, delete the corresponding enum constant + generation branches + `validate_config` check + `sample_input` entry from the generator, and update the matching generator spec + UI-config spec.

| Generator | Field(s) Removed |
|---|---|
| `process/communication/api_call_generator.rb` | `errorStrategy` |
| `process/communication/notify_generator.rb` | `errorStrategy` |
| `process/communication/send_webhook_generator.rb` | `errorStrategy` |
| `process/file_operations/upload_file_generator.rb` | `errorStrategy` |
| `process/file_operations/download_file_generator.rb` | `errorStrategy` |
| `process/file_operations/decompress_files_generator.rb` | `errorStrategy` |
| `process/file_operations/generate_file_generator.rb` | `errorStrategy` |
| `process/security/authenticate_generator.rb` | `failAction` |
| `process/security/authorize_generator.rb` | `onFailure` |
| `process/security/decrypt_data_generator.rb` | `onFailure` |
| `process/security/verify_token_generator.rb` | `onFailure` |
| `process/validation/build_contract_generator.rb` | `errorStrategy` |
| `process/validation/validate_contract_generator.rb` | `onFailure` |
| `process/caching/cache_fetch_generator.rb` | remaining error-strategy residue |
| `process/concurrency/acquire_lock_generator.rb` | `failAction` |
| `process/data_operations/type_cast_generator.rb` | `onCastFailure` + legacy `onFailure` |
| `process/utility/i18n_translate_generator.rb` | `errorStrategy` |

After this pass, each leaf generator emits a single happy-path body. When the underlying Ruby operation raises, the exception propagates untouched to `dynamic_controller`.

### Category D — Explicitly Kept

| Element / Generator | Reason |
|---|---|
| `saga_generator` — `onCompensationFailure` | Core saga semantic: what to do when a compensation step itself fails during rollback. |
| `transaction_generator` — `errorStrategy` | Controls DB transaction commit/rollback on inner failure — this IS the transaction's purpose. |
| `signal_wait_generator` — `errorStrategy` | Timeout / signal-error handling is the element's purpose. |
| `process/resilience/*` (`retry_with_backoff`, `circuit_breaker`, `rate_limiter`, `idempotency_check`) | These elements exist to handle failures in-flow. |

## Phasing

Five phases, each a self-contained vertical slice (UI + Ruby + specs) that leaves the test suite green. Phase boundaries align with review / commit points per AGENTS.md (no auto-commits).

**Phase 1 — Delete `error_handler` element.** All Category A touchpoints. Delete the generator directory, the ViewComponent, the element-renderer shape, the JS schema, the palette / tab / icon / color entries, and the activity-generator `fail`-branch handling. Delete matching specs; add a regression spec asserting a persisted `error_handler` node produces the `# TODO: unknown element type 'error_handler'` marker in generated activity code.

**Phase 2 — Delete process `errorHandling` + `onStepFailure`.** All Category B touchpoints. `apply_process_scope_options`, `build_error_handler_method`, and the `fail :handle_error_in_*` declaration append are deleted from `activity_generator.rb`. The custom `error_handling` form field type, its template, its collector, and the mode-change handler are deleted from JS. ActivityGenerator specs updated to expect plain step bodies with no `begin/rescue` wrapper.

**Phase 3 — Strip failure enums from leaf generators.** Category C, split into three sub-phases to keep each diff reviewable:
- **3a** — communication (3) + file_operations (4)
- **3b** — security (4) + validation (2)
- **3c** — caching (1), concurrency (1), data_operations (1), utility (1)

Per generator: delete enum constant, delete field branch(es) in `generate_body`, delete enum check in `validate_config`, simplify `sample_input`, remove matching JS field in `action_configs/*.js`, update generator spec and UI-config spec.

**Phase 4 — Regenerate mirror + run audit.** `rake config_schemas:mirror` refreshes `spec/support/config_schemas.rb` to match the new JS schemas. `scripts/audit_generator_ui.rb` must come back clean; fix any residue.

**Phase 5 — Full-suite sweep.** Run the targeted spec tree below, confirm 0 failures and an expected drop in example count from 4331 as deleted tests come off.

## Testing Strategy

**Deleted test files (expected)**:
- `spec/services/code_generators/element_types/error_handler/error_handler_generator_spec.rb`
- `spec/components/flowchart_elements/error_handler_element_component_spec.rb`

**Deleted examples (expected)**:
- `activity_generator_spec` examples asserting `fail :handle_error_in_*` declarations
- `activity_generator_spec` examples asserting `begin/rescue` wrappers around process bodies (from `apply_process_scope_options`)
- Per-leaf-generator examples asserting `errorStrategy: "continue"` → rescue-block emission, `onFailure: "raise"` → raise emission, and sibling variants

**Rewritten examples**:
- Leaf generator specs: replace the "when errorStrategy is X, emits Y" matrix with a single happy-path assertion
- `activity_generator_spec`: assert process steps emit plain `def method_name(ctx, **); <body>; end` with no `begin/rescue` scaffolding

**New examples**:
- `activity_generator_spec`: assert a flowchart containing a persisted `error_handler` node generates activity code with a `# TODO: unknown element type 'error_handler'` marker (existing unknown-element-type code path; no new validator logic)
- `dynamic_controller_spec`: integration example — a flowchart whose step raises an uncaught exception propagates to the controller's rescue, rolls back the transaction, and returns `422`. This is the load-bearing guarantee of the whole refactor.

**Full-suite target command**:
```
bundle exec rspec \
  spec/services/code_generators \
  spec/services/activity_generator_spec.rb \
  spec/components/flowchart_elements \
  spec/controllers/dynamic_controller_spec.rb \
  spec/services/flowchart_topology_analyzer_spec.rb
```

All green. Example count drops from the 4331 baseline as deleted tests come off.

## Out of Scope

- DB migrations or data cleanup for existing flowcharts with `error_handler` nodes (persisted data is left alone per the "no backwards-compatibility" rule).
- Changes to `dynamic_controller.rb` itself — its existing rescue + transaction + render pipeline is the intended destination and is already in place.
- Any refactor of `saga`, `transaction`, `signal_wait`, or `process/resilience/*` generators (Category D).
- `parse_csv` and other generators whose error-strategy fields were already removed in recent commits (`7ee829e`, `3fa9fbe`, etc.).
