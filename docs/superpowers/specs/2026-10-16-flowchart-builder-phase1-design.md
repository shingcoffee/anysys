# Flowchart builder — Phase 1: safety and correctness

Date: 2026-10-16 · Parent: `2026-10-16-flowchart-builder-refactor-design.md`

Phase 1 fixes verified defects without redesigning generated code (Phase 2) or the step-action
catalog (Phase 3). Every item below was reproduced in the browser or confirmed in code. Each item
lists its requirement and the acceptance check that proves it.

## A. Tenant and expression safety

**A1 Entry scoping helper.** Add `FlowchartRuntime::Entries` with:
- `scope(ctx)` → `EntityEntry.build_for(entity).where(customer_id: ctx[:customer_id], entity_id: entity.id)`
  for `entity = ctx[:bound_entity]`; `EntityEntry.none` when no entity is bound.
- `assign(entry, attributes)` → writes only the bound entity's writable attribute slugs (via the
  generated accessors); internal columns (`id customer_id entity_id entity_version_number data
  created_at updated_at`) and unknown keys are ignored.
- `where_attributes(relation, conditions)` → JSON-aware predicates for entity attribute slugs
  built as `FlowchartRuntime::WhereClauseBuilder` rules on `data.<slug>` (json_extract), plain column
  predicates only for `id`.
Acceptance: unit specs for each method, including an entry of another customer and another entity
that `scope` never returns.

**A2 Model-operation generators use A1.** `find_model`, `upsert_model`, `check_existence`,
`count_records`, `pluck_model_fields`, `clone_model`, `batch_operation`, `bulk_import`,
`update_model`, `aggregate_query` and `query_models` emit lookups through
`FlowchartRuntime::Entries.scope(ctx)`; attribute conditions go through `where_attributes`.
- `upsert_model` never re-stamps `customer_id` on an existing record; `on_duplicate: :update_all`
  becomes valid Rails 8.1 (`:update`).
- `update_model` contract-less path assigns through `Entries.assign`; `update_all` strategy removed.
- `bulk_import` stops passing `validate:` to `insert_all`/`upsert_all`.
- `find_model` gains `idExpression` (default `params.id`); the default strategy finds by that id
  inside the scope and fails the step (returns false, `ctx[:_last_error]` set) when nothing matches.
- `save_model` drops `bang`; it always emits `ctx[:contract].save`.
Acceptance: generator specs assert scoped emission; behaviour specs run emitted code against real
rows of two customers/entities: another tenant's row is never found, moved or updated, and params
containing `customer_id`, `id` or `entity_id` never change those columns.

**A3 Expression safety everywhere.** Every config value that is pasted into emitted Ruby as an
expression passes `ExpressionSafety#safe_expression?` (rejected by `validate_config` otherwise),
including the `start_with?("ctx[")` passthroughs, `string_manipulate` regex patterns (emitted as
`Regexp.new(<literal>)`), and `api_call` cookie values (emitted as literals).
Acceptance: a spec feeds `ctx[:a]; Kernel.exit!(1)` and `ctx[:a] == (` into each previously bypassing
field and expects a validation error; valid `ctx[:...]` expressions still generate.

**A4 Guard condition validated.** `guardCondition` must be a single safe expression
(`safe_expression?` and a single-statement `Prism` parse); otherwise generation raises
`ActivityGenerator::Error` with code `:invalid_guard_condition`, the element id and the action, and
the server validator reports it in the problems panel.

**A5 Dangerous invocation surfaces removed.**
- `assign_value` loses the `env_var` and `credential` value types (generator and editor).
- `query_models` loses the `scope` query type (generator and editor).
- `FlowchartRuntime::Invocable` rejects ActiveRecord model classes and destructive methods
  (`delete_all destroy_all update_all delete destroy update_column update_columns insert_all
  upsert_all find_by_sql connection`); `invoke_service` validation reports them at authoring time.

**A6 Elements tab escapes HTML.** `bottom_panel_mixin.js` escapes label, type and id.

**A7 Keyboard shortcuts are canvas-scoped.** Canvas shortcuts run only when the event target is
`document.body` or inside the canvas container; Space is not blocked elsewhere; Ctrl+C/V/D act on
elements only when the canvas has focus. Typing or pressing Backspace in the property panel, on its
buttons or tabs never deletes an element.

## B. Runtime correctness

**B1 Params are indifferent-access.** `ActivityTracer#call` converts `input[:params]` to a
`HashWithIndifferentAccess`, so emitted readers (`ctx.dig(:params, :amount)`) work for public
submissions (string keys) and the test runner alike.

**B2 Numeric comparisons coerce form strings.** Decision/loop conditions using `> >= < <=` compare
numerically when both sides are numeric or numeric strings (`"150" > 100` is true); a non-numeric
side makes the comparison false instead of raising.

**B3 Runtime implicit keys.** `config/flowchart_validation.yml` lists every key `PublicSubmission`
seeds: `params bound_entity customer_id authentication current_user_id current_user_role audience
device_type`. The validator no longer reports `audience` as a missing input.

**B4 Defaults read seeded keys.** `authorize` resolves its default user through the session facade
`FlowchartRuntime::Authentication.session(context: ctx[:authentication], customer_id: ctx[:customer_id])`
(never by looking a user up from an id), and `send_template_email` resolves the customer from
`ctx[:customer_id]` instead of the never-seeded `ctx[:customer]`.

**B5 Safe step and class names.** `ActivityGenerator::NameDeriver` reserves every method a Railway
instance responds to (public or private, e.g. `initialize method send sleep raise class hash freeze
puts`) in addition to Ruby keywords, labels with no ASCII letters become `<type>_<n>`
(`process_1`, `end_1`), class names split words on any non-alphanumeric character
(`entity-entry` → `EntityEntry`), the fallback class name never uses random characters, and the
structure validator rejects a parent whose class name equals a subflow's.

**B6 Contracts build for length validators.** `EntityEntryContract` passes Integer values to
`length_minimum` / `length_maximum`.

## C. Editor workflow

**C1 Templates apply.** The new-flowchart form no longer posts a hidden configuration; creating with
a template uses that template.

**C2 Graphs that generate.** `blank` is Start → End. `crud_create` is Start → New Model → Build
Contract → Validate → Save Model → End; `crud_update` is Start → Find Model → Build Contract →
Validate → Save Model → End; `crud_delete` is Start → Find Model → Destroy Model → End. Each process
box holds one action with a configuration that validates; labels come from I18n (both locales).
Acceptance: each template generates an activity; `crud_create` traced with valid params creates the
entry; `crud_update` with `params.id` updates it; `crud_delete` deletes it.

**C3 Open/Cancel never dirties.** Opening the property panel takes a snapshot; Cancel and the close
button restore it; closing without edits causes no canvas update, no undo entry and no unsaved dot.
The per-element `unsavedChangesCache` is removed.

**C4 One version per real change.** `getConfiguration()` no longer stamps `created_at`; saving an
unchanged flowchart creates no version.

**C5 Restore works.** `POST …/versions` (restore) returns the restored `configuration`; the canvas
reloads it, clears the unsaved state and resets the undo baseline; errors show the server `message`.

**C6 Platform-aware URLs.** The editor passes builder endpoints from route helpers in
`data-flowchart-canvas-urls-value` (update, versions, validation, traces, document, list,
implicit keys, step/element I/O params). On the platform prefix every builder request goes to the
platform path, so saving a shared flowchart there updates the global row.

**C7 Test runs do not save.** The test panel sends the in-memory configuration with the trace
request; the server traces an unsaved in-memory copy and creates no version.

**C8 Paste copies are independent.** Paste deep-clones each element before remapping ids.

**C9 Decision branches stay stable.** A new branch's auto match value is the first of
`true`, `false`, `value_3`, `value_4`, … not already used by that decision. Inserting an element on a
decision edge keeps the edge's port, label, match value and properties on the upstream edge and
re-syncs the decision's branches.

**C10 Predictable adding and connecting.** A positioned palette drop never auto-connects. Palette
double-click appends below the last element and connects from it only when that element is not an
End or a Decision and has no outgoing connection. Connections into a Start or out of an End are
rejected with a translated toast. A→B and B→A may both exist. Drop-to-reconnect requires a drag of
more than 8 px; drags keep tracking when the pointer leaves the SVG.

**C11 Undo history belongs to this flowchart state.** Stored undo stacks are discarded when their
latest snapshot differs from the loaded configuration; version-edit pages use a key that includes the
version id.

**C12 Navigation guard.** In-app navigation (`turbo:before-visit`) with unsaved changes asks for
confirmation (translated) and stays on the page when declined.

**C13 Subflow properties reachable.** Double-click opens the subflow's property panel like any other
element; a small expand/collapse toggle on subflow nodes with a target performs inline expansion.

**C14 Accurate unsaved indicator.** After a save, the dot reflects whether edits happened during
the save.

**C15 Condition rows start empty.** The condition builder no longer injects a `signal` left operand;
an unconfigured decision fails validation with "no condition".

**C16 Step defaults chain.** Build Contract starts with `contractClass: EntityEntryContract`,
`resultVar: contract`, `modelVariable: model`; Validate with `contractRef: contract` (`default:` key,
not `defaultValue:`). Output auto-suggest never renames `model` or `contract`.

## D. One action per Process box

**D1 Server enforcement.** `ActivityGenerator::StructureValidator` rejects a process element with
more than one step (translated message naming the element).

**D2 Assistant output conforms.** `FlowchartDefinitions::ProcessSplitter` turns a multi-step process
into a chain of single-action process elements (first keeps the id and incoming edges; the last
takes the outgoing edges; labels from the action's human label; downstream elements shift down).
`Normalizer` applies it; `structure_schema.json` documents `steps.maxItems: 1`; prompt examples use
chains.

**D3 Stored data migrated.** `bin/rails flowcharts:split_multi_action_processes` reports affected
flowcharts (dry run by default) and with `APPLY=1` saves each split configuration as a new version
(restorable) and regenerates its activity. Run on development after verification.

## E. Verification and documentation

- Playwright app-backed regression spec `spec/e2e/flowchart_builder_journey.app.spec.js` covering:
  template creation, palette drag and double-click, action picking with default configs, save (one
  version per real change), open/cancel without dirtiness, restore, paste independence, Backspace in
  the panel, validation clean for template flows, test run without a new version.
- `bundle exec rake config_schemas:mirror` after editor schema changes; parity specs green.
- Targeted RSpec per layer, full parallel suite (tenant scoping is cross-cutting), Vitest 100% for
  touched JS, Playwright on the isolated server.
- Docs: `doc/reference/{en,zh-CN}/flowchart-builder.md`, `code-generators.md`,
  `flowchart-runtime.md`.

## Out of scope (later phases)

Lambda removal and wiring (2), Timer removal (2), schema single source and catalog consolidation (3),
element editor redesign including End HTTP mode removal (4), placement/insert-on-edge, save conflict
(409) and validation de-duplication (5).
