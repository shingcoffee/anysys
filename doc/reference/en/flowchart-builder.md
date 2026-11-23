---
title: "Flowchart builder"
summary: "How the flowchart canvas stores a graph, validates it, versions it, and compiles it into a Trailblazer activity — templates, one action per Process, Decision/Loop-only forks, the element and step property forms (tabs, Decision branches on connections, the conditions control, inline errors), canvas editing (placement, saving and conflicts, undo, read-only subflow preview, shortcuts), the test panel, launch checks, and activity regeneration."
---

## Summary

A flowchart is the platform owner's process graph. Customers do not get the editor, the navigation entry, or the word "flowchart". A launched page still runs the compiled activity. Ask `FlowchartVisibility.allowed?` before adding chrome, assistant mentions, or editor links. HTTP enforcement is `RouteAuthorization`: any controller path matching `/flowchart/` and any URL under `/admin/maintenance/flowcharts` requires `Authentication::User#platform_owner?` (`owner?` on customer `81721200`). Tenant admin, including an admin of `81721200` who is not the owner, is denied before the action runs.

The graph is JSON on the versioned `configuration` attribute: `elements`, `connections`, and `metadata`. `Flowchart#generate_activity` runs on save and writes Ruby into the parent `activity` column. `ActivityGenerator` compiles that Ruby by walking the graph and delegating each node to `CodeGenerators::GeneratorRegistry`. There is no graph interpreter. Execution of the compiled class is [Flowchart runtime](flowchart-runtime).

Shared flowcharts (`customer_id` NULL) are created only on `/81721200/admin/maintenance/platform/flowcharts`. A tenant-path save, including customer `81721200`, writes that customer's override of `configuration` and does not rewrite the global `activity` column.

## Flow

```text
flowchart-form (new)          flowchart-canvas (edit)
        |                              |
        | template / entity binding    | PATCH configuration JSON
        |                              |   + expected_head_version_id
        v                              v
Admin::Maintenance::FlowchartsController
        |  stale head -> 409 Conflict (nothing saved)
        |  SharedResourceMode
        |  tenant override permits :configuration only
        v
Flowchart#save
        |  before_save generate_activity
        |    (skipped when override_customer_id is set)
        v
ActivityGenerator#generate
        |  nil if name blank or elements empty
        |  else DFS + GeneratorRegistry
        v
flowchart.activity   (Ruby source on the parent row)

configuration body
        |
        v
FlowchartConfigurationContent.store!
        |
        v
FlowchartVersion --> current_version_id
                 or flowchart_customer_heads

Validate button
        |
        v
POST .../flowcharts/:id/validation
        |
        v
FlowchartServerValidator  (in-memory copy, not saved)

Launch
        |
        v
FlowchartInputOutputValidator
        |
        v
FlowchartServerValidator  (any error blocks)
        |
        v
status = launched
```

The canvas (`flowchart_canvas_controller.js`) never builds tenant paths in JavaScript. `_editor.html.erb` passes route-helper URLs in `data-flowchart-canvas-urls-value` (`update`, `versions`, `validation`, `traces`, `document`, `list`, `implicitKeys`, `stepIoParams` with `__ACTION__`, `elementIoParams` with `__TYPE__`, `referenceOptions` with `__SOURCE__`). `flowchart/urls.js` reads that map (`flowchartUrl` / `flowchartShowUrl`). On the platform prefix, `PlatformPathHelper` rewrites those helpers so a save of a shared flowchart updates the global row. The reference-options template is the collection path plus `/reference_options/__SOURCE__.json` so the `__SOURCE__` token is not sent through the `:source` route constraint.

Validate POSTs the unsaved `elements` and `connections` to `urls.validation`. The test panel POSTs `{input, configuration}` to `urls.traces`: the server compiles the posted in-memory graph (`ActivityGenerator` on a `dup`, `status: :draft`) and traces it without saving a version. `FlowchartTracesController#create` then merges the same runtime keys as `Pages::PublicSubmission#build_context` after the posted input (`bound_entity` is the traced flowchart's entity, or nil for a shared flowchart without one; plus `customer_id`, `authentication`, `current_user_id`, `current_user_role`, `audience`, `device_type`, `request_ip`, `user_agent`, `locale`, `request_id`; `ActivityTracer` adds `flowchart_id`) so the JSON body cannot override them. Every trace runs inside `ActiveRecord::Base.transaction(requires_new: true)` that always raises `ActiveRecord::Rollback`, so test runs never persist database changes. External side effects (emails, webhooks, cache writes) are not suppressed. Oversize, malformed, or timed-out configuration is 422 (`FlowchartServerValidator::MAX_ELEMENTS` / `MAX_CONNECTIONS` / `DRY_RUN_TIMEOUT_SECONDS`). Restore POSTs `urls.versions` and reloads `data.configuration` onto the canvas. Documentation GET `urls.document` calls `FlowchartDocumenter`.

## Implementation

### Storage

`Flowchart` includes `Versionable` with `FlowchartVersion`, `FlowchartConfigurationContent`, snapshot `:configuration`, and `flowchart_customer_heads`. `reload_definition_from_head!` assigns `configuration` from `resolved_current_version.content.payload`.

`Flowchart::ConfigurationAccessors` reads `elements`, `connections`, `metadata`, and `canvas_size` (default width 1200, height 800). Required JSON keys are `elements`, `connections`, and `metadata`; the first two must be arrays and metadata must be an object. `status` is `draft`, `launched`, or `deleted` (soft delete). The model/manual creation default is `draft`; assistant-created flowcharts launch automatically after validation. `crud_type` is an optional string in `Flowchart::CRUD_TYPES` (`create`, `read`, `update`, `delete`), not an enum, so it does not clash with Active Record.

A customer-owned flowchart must have `entity_id`. A shared flowchart must not. `FlowchartsController#create` clears `entity_id` when the new row is shared. `Flowchart::TemplateBuilder.new_with_defaults` prefers a present `template` over a posted `configuration` (the new form no longer posts a hidden graph). `blank` is Start → End. `crud_create` is Start → New Model → Build Contract → Validate → Save Model → End. `crud_update` is Start → Find Model → Build Contract → Validate → Save Model → End. `crud_delete` is Start → Find Model → Destroy Model → End. Each process box holds one action. `Flowchart::TemplateBuilder::STEP_CONFIGS` writes `new_model { resultVar: "model" }`, `build_contract { contractClass: "EntityEntryContract", modelVariable: "model" }` and `validate_contract {}`, plus three configs that still carry keys the current generators do not declare: `find_model { findStrategy, idExpression, resultVar }`, `save_model { contractRef }` and `destroy_model { strategy, modelVariable }`. Generation ignores undeclared keys and uses the declared defaults (`findBy: "id"`, `idSource: "params.id"`, `mode: "delete"`), so the templates behave as intended. Labels come from `flowchart_elements.template_labels` in both locales.

`launched_edit_locked?` is true when the row is launched and the request is not writing an override line. `must_be_draft_to_edit` then blocks updates, unless `assistant_version_write` is set or `status` itself is changing. An override write is allowed while the global row is launched. `FlowchartCrudTypesController#update` uses `update_column` so reclassification does not trip that guard. Shared `crud_type` is still `guard_shared_global_writes`.

### Compilation

`ActivityGenerator#generate` returns `nil` when `flowchart.name` is blank or `elements` is empty. It also returns `nil` when `StructureValidator` reports problems that are not a loop-topology error or an unsupported structural type; those two cases raise `ActivityGenerator::Error`. Unknown element types and unknown step actions raise the same error (`:unknown_element_type`, `:unknown_step_action`).

Element types `process`, `start`, and `end` are step containers (`STEP_CONTAINER_ELEMENT_TYPES`). Their Ruby comes from nested `properties.steps`, each looked up with `GeneratorRegistry#find_step_action`. Other types use `find_element_type`. See [Code generators](code-generators).

`Flowchart#generate_activity` assigns `self.activity` from `#generate`. It returns immediately when `override_customer_id` is present, so a tenant fork does not overwrite the global activity. `ActivityGenerator::Error` is re-raised in test and logged elsewhere, leaving the previous activity in place. Other exceptions are re-raised in test; outside test the activity column becomes a one-line failure comment. `diagram` is separate: `ActivityDiagramGenerator` builds a picture from the activity source. It is not the stored graph.

`FlowchartDefinitions::Persist` and `GraphValidator` are the assistant apply path (name, CRUD type, ActionCatalog actions, graph shape). The canvas save path is the controller update. The assistant palette, step-action enum, and `UiConfigSchema` defaults come from `CodeGenerators::ActionCatalog.export` (`FlowchartDefinitions::Assistant::SchemaGenerator`). `bin/rails ai_assistant:flowchart_schema` writes `structure_schema.palette.json`; the spec fails when that snapshot differs from a fresh generation. Prompt few-shots use `validate_contract` (empty config), `build_contract` (`contractClass` / `modelVariable`, writes `ctx[:contract]`), and `save_model` (saves `ctx[:contract].model`).

### One action per Process

`ActivityGenerator::StructureValidator` rejects a process whose `properties.steps` has more than one action (`maint_core.flowcharts.structure_errors.process_multiple_actions`). `structure_schema.json` documents `steps.maxItems: 1` and injects the ActionCatalog canonical keys onto `step.action.enum`. `FlowchartDefinitions::ProcessSplitter` turns a multi-step process into a chain of single-action process boxes (first keeps the id and incoming edges; extras become `{id}_2`, `{id}_3`, …; the last takes the outgoing edges; later elements with a greater `y` shift down). `Normalizer` applies the splitter so assistant output conforms, keeps each step's action as `Palette.canonical_key(action) || action` (a catalog key maps to itself; there are no aliases), and merges `UiConfigSchema.defaults_for(action)` under the step's config. There is no conversion task for stored flowcharts: a stored graph with several actions in one process or with retired step keys fails validation and generation until it is fixed in the editor.

`ActivityGenerator::NameDeriver` reserves every method a Railway instance responds to (plus Ruby keywords and `collect_errors`). A reserved label becomes `"#{name}_step"`. Labels with no ASCII letters become `<type>_<n>` (`process_1`, `end_1`). Class names split words on any non-alphanumeric character (`entity-entry` → `EntityEntryActivity`). The fallback is `Flowchart#{id}Activity` or `UnsavedFlowchartActivity` (no random characters). When both `flowchart:` and `subflow_lookup:` are passed, the structure validator rejects a parent whose class name equals a resolved subflow's, and two different subflow children that derive the same class name (`class_name_collision`); two references to the same child are allowed. Naming and branch constants are documented on [Code generators](code-generators).

### Outgoing connections

`ActivityGenerator::StructureValidator::MULTI_OUTGOING_EXEMPT_TYPES` is `decision` and `loop`. Any other element with more than one outgoing connection is rejected (`maint_core.flowcharts.structure_errors.multiple_outgoing`, naming the element). The registry's supported element types are `start`, `end`, `decision`, `loop`, and `subflow`. A stored box of any other structural type fails as `unsupported_type` and does not generate. Delayed work uses a background-job step action.

### Test panel

The test panel POSTs `{input, configuration}` to `urls.traces`. `FlowchartTracesController#create` compiles a `dup`, seeds PublicSubmission runtime keys after the posted input, traces the run, and always rolls back. The JSON includes `errors` (`ctx[:errors]`, strings, non-blank, unique). The failure banner lists those messages; `error` is a translated generic message and never carries exception text. Each decision row shows the branch taken (`node.branch`). The overlay matches canvas boxes only by `element_id`; nodes without one (`End.failure`) highlight nothing. Order badges number distinct elements in first-execution order (1, 2, 3 …); an element's colour is its last status. Repeated loop visits reuse the first badge. When `trace_truncated` is true (more than 500 nodes), the step list starts with a notice (`maint_core.flowcharts.editor.test_trace_truncated_format`). Any canvas edit (`canvas.onchange`) clears the overlay, so it never describes a graph that has since changed. Run times use `Intl.DateTimeFormat` with the app locale (`data-flowchart-canvas-app-locale-value`), and query durations use `testQueryDurationFormat` (`{duration} ms`). Public submissions do not draw this overlay.

### Step form

A Process box holds one step action, chosen from the action picker in the property panel. The picker lists the catalog from `CodeGenerators::ActionCatalog.export` (embedded as `data-flowchart-canvas-action-catalog-value`), grouped by category in catalog order — Records, Validation, Data, Communication, Security, Background, File, Caching, Concurrency, Resilience, Scheduling, Payments, Submission outcome, Service, Utility — and searches label, description and category in both locales (`step_picker_search_placeholder`, `step_picker_no_match_label`). A `singleUse` action already used in the list is disabled and marked `step_picker_already_used_label`. Every action, field, role and default is listed on [Flowchart step actions](flowchart-step-actions).

The form renders one control per catalog field (see "Generator/UI schema checks" below). `visibleWhen` hides a field until its rule matches against the current config, and the server neither validates nor reads a hidden field. Validate reports config problems per step as `maint_core.flowcharts.config_problems.step_invalid` with the field's message; the step is named by its box label (else the translated action name) and the action by its translated name, never its key.

Conditional execution is a Decision before the box: a step has no condition, retry or timeout of its own. A step `conditions` field (for example the `query_models` filter) uses the same conditions control as Decision and Loop (see "Conditions control" below).

HTTP-style actions (`api_call`, `send_webhook`, `download_file`, `ai_inference`, `currency_convert`, `geolocation_lookup`) show the shared advanced fields their capabilities declare:

- **Retry on transport error** (`retryOnTransportError`, `retryAttempts` 1–2) is enabled only when the current config is idempotent — `httpMethod` is GET, HEAD, PUT, DELETE or OPTIONS, or `idempotencyKey` is set; `download_file` is always idempotent. Otherwise the toggle is disabled and unchecked, with the hint `step_retry_not_idempotent_hint`. The server enforces the same rule (`retry_not_idempotent`).
- **Timeouts** (`connectTimeout` 1–5 s, `readTimeout` 1–9 s; sum at most 10) show the hint `step_timeout_gives_up_format`, "Gives up after N s", where N is `min(10, (connectTimeout + readTimeout) × (1 + retryAttempts))` and retry attempts count only while retry is on.
- **Circuit breaker** (`circuitBreaker`, `breakerName`, `failureThreshold`, `resetTimeoutSeconds`).

`send_sms` replaces the SMS channel of the old notify action: `templateKey` is a searchable reference to a platform SMS template, `to` defaults to `model.phone`, `vars` is a key/value mapping (literal keys, expression values), `idempotencyKey` is optional, and the message id is written to `resultVar` (default `sms_message_id`). Credentials and provider codes stay on the platform SMS surface. Runtime behaviour and error codes are on [Flowchart runtime](flowchart-runtime); delivery is on [SMS](sms).

### Element property forms

Every element (Start, End, Process, Decision, Loop, Subflow) and every connection is edited in the property sidebar (`w-full sm:w-[420px]`). The form is built from `CodeGenerators::ElementCatalog.export(locale: I18n.locale)`, which `_editor.html.erb` embeds once on the canvas root as `data-flowchart-canvas-element-catalog-value`. `flowchart_canvas_controller.js` installs it with `setElementCatalog` (`flowchart/constants/element_registry`); the tabs, field controls, header label, automatic labels, client rules and canvas defaults all read that registry. There is no JavaScript copy of the element schemas. The catalog shape and the Ruby declarations are on [Code generators](code-generators).

**Tabs.** Each type lists its tabs in the catalog: General, then Steps (Process) or Branches (Decision), then I/O, then Advanced only when the type declares a `group: :advanced` field. The editor also hides Advanced while none of those fields is visible for the current settings. The form opens on Steps for a Process, on Branches for a Decision, and on General otherwise.

| Type | Tabs | General | Advanced |
|------|------|---------|----------|
| Start | General, I/O | Label, Notes | — |
| End | General, I/O | Label, Response Type, Return Value, Notes | — |
| Process | General, Steps, I/O | Label, Notes | — |
| Decision | General, Branches, I/O | Label, Route by, Subject or Condition, Notes | — |
| Loop | General, I/O, Advanced | Label, Loop type, Run once before checking, Condition or Collection + Item name, Max iterations, Notes | Stop early when, Skip item when, Index name, Collect items into |
| Subflow | General, I/O | Label, Flowchart, Notes | — |

Label and Notes are catalog `chrome`, not config fields. Notes is stored under `description` and renders as a collapsed `<details>` at the end of General that opens when it has content. The element form is one column; condition rows and branch rows take the full width. Element fields render through the same role controls as step fields (`controls/field_renderer.js`): help text under every input, an empty "None" option on optional enums, the reference picker, and the conditions control.

**Per element.**

- **Start** — Label and Notes only; there is no trigger setting.
- **End** — Response Type `none` ("Nothing", default) or `value` ("Return a value"). Return Value is shown and required only for `value` (an expression, placeholder `ctx.result`); the End then writes `ctx[:response]`. A `none` End is not a step.
- **Process** — no element fields; its single action is chosen on the Steps tab (see "Step form").
- **Decision** — Route by `condition` ("Yes / No", default) or `value` ("Value"). Value mode shows Subject, an expression compared with each branch's match value; Yes / No mode shows Condition, a conditions group. Branches are edited on the Branches tab (below).
- **Loop** — Loop type `while` ("Repeat while", default) or `for_each` ("For each item"). While shows Run once before checking (`runOnceFirst`) and Condition (required). For each shows Collection (required context path without `ctx.`, e.g. `items` or `params.modes`) and Item name (`itemVariable`, default `item`). Max iterations (`maxIterations`) is 1–10,000, default 100, for both types. Advanced holds Stop early when (`stopWhen`, both types) and, for each only, Skip item when (`skipWhen`), Index name (`indexVariable`, default `index`) and Collect items into (`collectInto`). Run-time behaviour is on [Flowchart runtime](flowchart-runtime).
- **Subflow** — Flowchart (`flowchartId`) is a searchable reference picker on the `flowcharts` source: launched flowcharts the URL customer can use (its own plus shared). It stores the numeric id and shows the name. The editor's reference-options URL carries `exclude_id` set to the flowchart being edited, so a flowchart never lists itself; a stored self-reference is still flagged by the `subflow_self_reference` rule.
- **Connection** — Label (the connection's `label`) and Notes (`properties.description`), from the catalog's `connection.fields`. There is no priority setting.

**Round trip.** A cleared number field stays empty and shows its default in the placeholder (`default_placeholder_format`, "Default: 100"); nothing is stored and the generator default applies. While the form is open, values of fields hidden by the current mode are kept, so switching back restores them. Save stores only the visible catalog fields plus `description`, `io_overrides`, `steps` and `condition` (when visible) (`persistableProperties` in `flowchart/element_config.js`). On every type except Process, the server reports any other key as `unknown_field` ("… is not a recognized setting").

**Automatic labels.** A label follows the settings only while it is blank, equals the translated `defaultLabel`, or equals the label derived from the previous settings. The header shows the translated type label from the catalog.

### Decision branches

A Decision's branches are its outgoing connections; nothing about them is stored on the element. Each connection carries `label` (the branch name), `matchValue`, and `fromPort` (`port_N`). The Branches tab lists one row per outgoing connection in port order:

- **Name** — the connection label. New branches get the translated `Branch {index}` label.
- **Match value** — free text in value mode; a Yes / No select (`true` / `false`) in Yes / No mode.
- **Otherwise** — a checkbox that stores an empty `matchValue` and hides the match control. Ticking it on one row clears it on the others.

Add Branch creates a Process box and a connection to it with no match value. Remove drops only that connection: the box stays on the canvas (the validator reports it if it becomes unreachable), so no confirmation is asked. Drawing or deleting any edge out of a Decision renumbers the remaining ports `port_0`…`port_N`. Switching Route by clears every match value except Otherwise and shows a notice with Undo, which restores them.

The same rules run in the browser (`flowchart/validation/element_rules.js`) and in `DecisionGenerator`, all addressed to the `branches` field, with messages in `flowchart_elements.decision.errors.*`:

| Code | Rule |
|------|------|
| `too_few_branches` | at least two outgoing connections |
| `duplicate_match_value` | match values unique after trimming |
| `multiple_otherwise` | at most one Otherwise (empty match value) |
| `invalid_condition_match` | Yes / No mode: match values are only `true`, `false` or empty |
| `missing_yes_branch` | Yes / No mode: a Yes branch plus No or Otherwise |

In value mode the generator emits `case subject.to_s` with one `when` per match value and `else` the Otherwise branch (else the last branch); in Yes / No mode it emits a ternary that returns the Yes signal or the No (else Otherwise) signal.

### Conditions control

Decision `condition`, Loop `condition` / `stopWhen` / `skipWhen`, and every step `conditions` field share one control (`controls/conditions.js` plus the nested Stimulus controller `property-editor--controls--conditions`). It edits one flat group:

```json
{
  "type": "group",
  "joins": ["OR"],
  "conditions": [
    { "kind": "field", "leftOperand": "ctx.vip", "operator": "is_true", "rightOperand": "" },
    { "kind": "query_count", "queryConfig": { "entityId": 7, "conditions": { "operator": "AND", "rules": [{ "field": "status", "op": "==", "value": "open" }] } }, "countOperator": ">=", "countValue": 1 }
  ]
}
```

- **Field rows** — left operand, operator, right operand. The left operand accepts any context path and suggests upstream outputs and bound-entity fields. The right operand is a literal unless it starts with `ctx.`. Unary operators (`is_true`, `is_false`, `is_empty`, `is_not_empty`, `is_nil`) hide the right operand. Every row needs an operator; there is no blank option.
- **Count rows** — an entity (from the `entities` reference source), optional WHERE filters, a count comparison limited to `== != > >= < <=`, and a count value.
- **Joins** — an AND / OR select in each gap writes `joins` (one entry per gap). Nested groups cannot be built and are rejected by the server.

Operators and their translated labels come from the catalog (`operators`, each `{ value, label, unary, count }`). On the server, `CodeGenerators::ConditionRules` checks the rows and reports `flowchart_elements.conditions.errors.*` codes (`empty_condition`, `nested_group`, `missing_left`, `missing_operator`, `unknown_operator`, `missing_right`, `invalid_regex`, `missing_entity`, `unknown_count_operator`, …) against the group's field.

### Inline errors

Client rules (`element_rules.js`) and server `element_config_invalid` problems both carry `field`. `applyElementFieldProblems` paints a `data-field-error` message under the matching `[data-element-field]` wrapper, and sets `aria-invalid="true"` on its input; editing the field clears the error. Opening the editor paints the current problems without leaving the opening tab (a Decision with an empty condition still opens on Branches, with the error under Condition on General). Save, when it is blocked, switches to the tab and opens the `<details>` or step disclosure that holds the field. Save is blocked while this element has a field problem of severity `error`; warnings (for example an empty Process) never block. Rule messages are field-level and translated: the canvas mount passes them as `data-flowchart-canvas-validation-*-value` attributes (from `flowchart_elements.*.errors` and the shared `required` message). The editor shows them unprefixed under the field, and the problems panel prefixes them with the element through `maint_core.flowcharts.config_problems.element_invalid` ("{label} ({type}): {message}"), the same format the server uses. A problems-panel row with a `field` navigates to the same wrapper, revealing its tab and any collapsed section; branch problems open the Branches tab. The client rules are:

- End `value` without Return Value (`end_no_return_value`, field `returnValue`).
- Process without a step (`empty_process`, warning).
- Decision: the branch codes above; with `routeBy: "condition"`, a required condition group (`condition_invalid`, `condition`).
- Loop: a while loop without condition rows (`empty_loop_condition`, `condition`); a for-each loop without a collection (`loop_no_collection`) or with a `ctx.` / `ctx[` path (`loop_invalid_collection`), both on `collection`; `itemVariable` / `indexVariable` set to a loop-header name (`loop_reserved_variable`) or to the same name (`loop_colliding_variables`).
- Condition groups (Decision `condition`, Loop `condition` / `stopWhen` / `skipWhen`) mirror `CodeGenerators::ConditionRules` as `condition_invalid` on the owning field: a flat group, then per row the first of `invalid_row`, `nested_group`, `missing_entity`, `unknown_count_operator`, `missing_left`, `missing_operator`, `unknown_operator`, `missing_right`. Messages come from `flowchart_elements.conditions.errors` with `{index}` / `{operator}`; known, unary and count operators come from the catalog. Regular-expression syntax is Ruby's, so `invalid_regex` is reported by the server only.
- Subflow without a target (`subflow_no_target`) or pointing at the flowchart being edited (`subflow_self_reference`), both on `flowchartId`.

Server messages use `maint_core.flowcharts.config_problems.element_invalid` with the element label, the translated type label and the generator's translated message.

### Generator/UI schema checks

Step-action and element-type schemas both live on the generators (`config_schema ported: true`). Step actions are exported by `CodeGenerators::ActionCatalog` (field reference: [Flowchart step actions](flowchart-step-actions)); element types, connections and condition operators by `CodeGenerators::ElementCatalog` (see [Code generators](code-generators)). There is no JavaScript schema copy and no mirror task. The step and element forms render every catalog `control` kind: `toggle` (flag switch), `list` (add/remove rows; `entity_attribute` item role uses the bound-entity column select), `mapping` (key/value rows with role-aware key/value controls), `conditions` (structured `{type:"group",joins,conditions}` rows), `attribute_picker` (bound-entity columns), `reference_picker` (searchable combobox; fetches `urls.referenceOptions` once per source), and `localized_text` (`en` required, `zh-CN` optional). Help text sits under every input. Optional enums get an empty None option; required enums show their default and never silently take the first option. Fields with `variablePicker: false` have no insert-variable picker. Mapping and condition rows are one column on mobile and pair from `sm:`.

```sh
bundle exec rspec spec/services/code_generators/element_catalog_spec.rb spec/services/code_generators/element_i18n_keys_spec.rb spec/config/flowchart_elements_locale_spec.rb
bundle exec rspec spec/scripts/audit_generator_ui_spec.rb spec/services/code_generators/contract_parity_spec.rb spec/services/code_generators/generator_inventory_spec.rb spec/services/code_generators/generator_conformance_spec.rb spec/services/code_generators/element_types/process/communication/semantic_conformance_spec.rb spec/services/flowchart_runtime/facade_contract_spec.rb
```

`GeneratorUiAudit` compares serialized defaults for the opted-in `json_or_expression` editor. An optional field with no UI default is omitted when blank, so the declared backend default applies; the audit does not require the editor to seed `{}`. An object default and object JSON text compare as the same typed value. Explicit conflicting defaults, malformed JSON, arrays that serialize as strings, ordinary text fields and required blank fields still report drift. Static schema extraction preserves `{}` as a hash rather than a string. Conformance probes exercise both typed objects and context expressions under valid dependent configurations instead of skipping the new field type or counting a missing SMS template as a meaningful field change.

SMS's public runtime facade delegates its error boundary to `Sms::Errors::Error` and preserves gateway exceptions and their recorded acceptance facts. It does not define an SDK-specific error wrapper or alias. Semantic conformance executes real gateway admission, replay, module/credential failures, conflicts and suppression against the shared ledger. The audit specs use disposable output files; they do not rewrite the tracked report artifact during verification.

### Validation and launch

The editor's local checks live in `ValidationMixin` and `flowchart/validation_service.js` (start and end, reachability, unsupported structural types), with the per-element rules in `flowchart/validation/element_rules.js` (see "Inline errors"). Server checks are `Admin::Maintenance::Flowcharts::ValidationsController#create`, which passes the posted hash to `FlowchartServerValidator` on an in-memory copy (`assign_attributes` plus `configuration_json=`). The validator does not save. While a subflow is expanded, both the local and the server checks run on the stored collapsed graph (see "Subflow preview"). How the panel merges the two sources is under "Validation panel".

`FlowchartServerValidator` caps the payload at 1,000 elements and 5,000 connections, then runs subflow existence (same message for a missing id and another tenant's id) and config checks, all inside a 10 second timeout. The `ActivityGenerator` dry run runs only when those checks return no problem of severity `error`: a dry run means something only on an otherwise valid graph, and skipping it keeps one fault from being reported again as `codegen_failed`. Over the cap the result is one `server_check_unavailable` warning (`maint_core.flowcharts.server_validation.payload_too_large`); a timeout is one `codegen_check_timeout` warning (`check_timeout`, with `%{seconds}`). Those messages and the structure-validator strings they wrap are `I18n.t` calls under `maint_core.flowcharts.structure_errors` and `maint_core.flowcharts.server_validation`, so the panel follows the request locale. The inaccessible-subflow wording stays the same for a missing id and another tenant's id.

Launch is `FlowchartLaunchesController#create`. It refuses an already-launched row, runs `FlowchartInputOutputValidator` (pins from `CodeGenerators::IoExtractor`; alert `maint_core.flash.flowchart_launches.launch_failed`), then `FlowchartServerValidator` on a freshly loaded copy of the stored configuration (the validator writes the configuration onto the record it is given, so the launched record is never handed to it). Any problem of severity `error` blocks the launch with `maint_core.flash.flowchart_launches.problems_found` ("Fix the %{count} problems in the editor before launching.", pluralised). A blocked launch redirects to the editor with `show_validation=true`, which sets `data-flowchart-canvas-auto-validate-value` so the editor runs Validate on load and lists the problems. Only then does it `update!(status: :launched)`. `destroy` sets `status` back to `draft`. Both actions use `guard_shared_global_writes`, so taking a shared flowchart online or offline is platform-prefix only.

Forms depend on launched flowcharts. `Flowchart#soft_delete` refuses while `Page.bound_to_flowchart(id).launched` exists, whether the flowchart is launched or a draft, and lists the forms (`maint_core.errors.validations.flowchart_in_use`). `FlowchartsController#destroy` redirects with that alert. `Page.bound_to_flowchart` compares `form_settings.flowchart_id` as text, through the global head or any tenant's override head. A customer-owned flowchart reaches only shared pages and its own tenant's. Taking a flowchart offline still works, and the notice appends `maint_core.flash.flowchart_launches.forms_stopped` with the number of launched forms that can't accept submissions until it is launched again. Those forms show **Can't be submitted**, and a form can't be launched while its flowchart is offline; see [Page builder](page-builder).

Versions are `FlowchartVersionsController` (`index`, `show`, `create`, `edit`, `destroy`, `PUT default`). The canvas version panel fetches `urls.versions`. The line shown is `current_line_versions`. `MAX_VERSIONS` is 50. `getConfiguration()` does not stamp a fresh `created_at`; it round-trips loaded metadata. `Versionable#commit_version!` no-ops when the content-addressed payload hash matches the head, so saving an unchanged flowchart creates no version. Restore asks `restore_version_confirm_format`: "Restore version {version}? This creates a new head version with its content; the current head stays in the version history." Restoring takes no extra snapshot: `restore_as_new!` writes the restored content as a new head, and the previous head remains in the list. Restore (`POST …/versions`) returns the restored `configuration` (`resolved_current_version.content.payload`) and `version_id` (the new line head). The canvas leaves subflow preview, adopts `version_id` as the expected head (see "Saving and conflicts"), calls `loadConfiguration` (which resets zoom and pan), clears unsaved state, and resets the undo baseline. A read-only canvas does not restore. Errors toast the server `message` when the body is JSON, else `restore_failed_http_format` ("Restore failed (HTTP {status})"); a network failure toasts `network_error_format`.

Assistant creation uses `FlowchartDefinitions::Persist::Writer#create!`: assign the normalized graph to an unsaved customer-owned candidate, run `FlowchartInputOutputValidator`, then run `FlowchartServerValidator` on a separate in-memory record with a deep-copied configuration. The mutating validator's copy is not saved. Missing inputs and server problems of severity `error` become translated `Persist::Result#errors`, so the processor can use its existing bounded repair loop (at most two repairs). Warnings do not block. Only after validation does the writer set `status: :launched` and save the candidate, compiled activity and first version; invalid creates leave no record/version. A false save returns errors even if a callback supplied none (`ai_assistant.assistant.apply_errors.flowchart_save_failed`). Updates keep their existing status and still require confirmation; the model never supplies `status`. This policy applies only to tenant-owned assistant creations and does not change manual defaults or the platform-prefix requirement for shared global launch. See [AI assistant](ai-assistant).

### Controllers and Stimulus

`Admin::Maintenance::FlowchartsController` is mounted at both `/:customer_id/admin/maintenance/flowcharts` and `.../platform/flowcharts`. Update permits `name`, `description`, and `configuration` on a normal save, and only `configuration` for `tenant_override?`. Nested routes cover copy, restoration, trash, implicit keys, step and element I/O params, reference options, traces, and document. `GET …/flowcharts/reference_options/:source` (`FlowchartReferenceOptionsController#show`) is JSON-only and owner-gated like the editor; it lists `{value, label}` rows from `CodeGenerators::ReferenceSources` for the URL customer.

`flowchart_canvas_controller.js` (`flowchart-canvas` on `app/views/admin/maintenance/flowcharts/_editor.html.erb`) owns the canvas. It delegates to `SubflowManager`, `UndoRedoManager`, `ExportManager`, `SearchManager`, `MinimapManager`, `TestRunnerManager`, and the validation, version-history, search, and bottom-panel mixins. `readOnlyValue` makes `save` a no-op. A save already in flight is ignored so two PATCHes do not create two versions.

### Editor canvas

Opening the property panel snapshots `{label, properties, elements, connections}`. Cancel, the close button, and Escape restore that snapshot; graph drift uses `canvas.replaceGraph` (no zoom/pan reset). A no-edit close does not update the canvas, add an undo entry, or set the unsaved dot. `unsavedChangesCache` is gone.

Double-click opens the property panel for every element, including a subflow. A small expand/collapse toggle (`[data-subflow-toggle]`) on a subflow that has a target expands it inline as a read-only preview (see "Subflow preview"); the toggle is not drawn on a read-only (launched) flowchart. In-app navigation (`turbo:before-visit`) with unsaved changes confirms `unsavedChangesConfirm` and stays on the page when declined.

Shortcuts are listed under "Shortcuts and selection". Paste `structuredClone`s each clipboard element before remapping ids. A new edge out of a decision becomes a branch with the translated `Branch {index}` label and no match value (so it is Otherwise until one is set). It is placed right after the branch of the port it was dragged from (`port_k` → index k+1; `orderedDecisionBranches` in `flowchart/dynamic_ports.js`), so earlier branches keep their ports; the decision's outgoing edges are then renumbered `port_0`…`port_N`. Insert-between keeps the edge's port, label, match value, and properties on the upstream edge and re-syncs the decision's branches. Connections into a Start or out of an End are rejected on create, reconnect, and endpoint retarget (`connectionIntoStartRejected` / `connectionOutOfEndRejected`). Document drag listeners are unbound on destroy and on Escape. Condition rows start with an empty left operand; an unconfigured decision fails validation with no condition.

`Flowcharts::ToolbarComponent` keeps editor controls inside the viewport: below Tailwind's `sm` breakpoint, the truncated flowchart name occupies its own row and the zoom, action, and save/undo/redo groups wrap as needed. Save stays fully visible and right-aligned; the decorative divider is hidden on mobile. From `sm` upward, the toolbar uses a single row. At 320px and 1440px, browser geometry checks cover Save, all visible toolbar controls, and the header, editor, palette, and canvas regions without horizontal page overflow.

`flowchart_form_controller.js` (`flowchart-form`) shows or hides entity binding from its `shared` value and selects a template card (`blank` by default). `flowchart_list_controller.js` filters the index client-side.

The validations controller comment says the admin path is admin-or-owner. `RouteAuthorization#flowchart_namespace?` still requires `platform_owner?` first, because the controller path contains `flowchart`.

### Placement and layout

Connections stay straight. `AlignmentMixin` (`flowchart/connection_manager/alignment.js`) moves the target of a vertical edge (bottom→top or top→bottom) onto its source's X and the target of a horizontal edge (right→left or left→right) onto its source's Y; a diagonal pairing such as bottom→left is left alone. It runs on `loadConfiguration` (`alignAllElements`), on every `createConnection` (drawing, auto-connect, drop, insert), on endpoint retarget, and at drag end. A new edge out of a decision also snaps its box onto the row shared by the decision's other branch boxes (`_alignNewBranchToRow`: the most common Y, ties to the topmost; only the new box moves).

Placement by gesture:

- **Palette drop on empty canvas** — the box lands where it is released, snapped to the 15 px grid (`GRID_SIZE`), and is not connected.
- **Palette drop onto a box** — the new box is placed one spacing (`DEFAULT_ELEMENT_SPACING`) from the target on the drop side, in line with it, and connected. If the target already has a connection on that side, the new box is inserted into it and the far end shifts away with its sub-tree (`shiftElementAndSubTree`) to make room.
- **Palette double-click** — the canvas stacks the box one spacing below the last element and connects the last element to it, unless the last element is an End or already has an outgoing edge.
- **Drag** — a single element carries its downstream sub-tree. Released onto another box it is placed next to that box and connected (inserted into an existing edge on that side, pushing the far end and its sub-tree away by the dragged group's extent); released elsewhere it snaps into line with its incoming edge. Its children are realigned behind it. A multi-selection moves rigidly by one grid-snapped delta, then every edge is realigned. Escape restores the element and its sub-tree.

The Tidy layout, align and distribute buttons, and the Branches tab (Add Branch lays out the branch row and carries each branch's downstream chain with it) remain explicit commands. The palette drop indicator is positioned from client coordinates relative to the canvas container.

Paste cascades: the n-th paste of the same clipboard is offset by 30 px × n (snapped to the grid), and Copy resets n, so Duplicate (copy, then paste) always offsets by 30 px. `ZoomPanManager` observes the SVG with a `ResizeObserver` and recomputes the viewBox whenever the container changes size (a panel opening or closing, a window resize); `destroy()` disconnects it.

**Edge "+".** Hovering a connection shows a "+" button at its midpoint (`edge_insert_button`, "Insert an element"; Enter or Space also opens it). It opens a menu (`edge_insert_menu`) of the palette types except Start and End — Process, Decision, Loop, Subflow — labelled with `elementLabel(type)`; arrow keys move through it and Escape closes it. Choosing a type places the box one spacing from A on the edge's side, shifts B and its sub-tree away to make room, and rewires A→new→B through the insert-between path (the edge's port, label, match value and properties stay on the first leg), then selects the box and opens its property editor. One undo entry. The button is not shown while `canMutate()` is false.

**Tidy layout** (`comp_misc.toolbar.tidy_layout`; `LayoutManager#autoLayout`) is a layered top-down layout from Start. Layers are the longest path from Start with loop back-edges ignored, so a merge point sits below every branch that reaches it; children follow the source port index (decision branch order); a parent is centred over its first and last branch. Start keeps its position, elements not reachable from Start go in a row below, and the view then fits the content. One undo entry.

### Saving and conflicts

`_editor.html.erb` renders `data-flowchart-canvas-head-version-id-value` = `@flowchart.current_line_head_version_id` (the line head, so tenant override lines work). Every canvas save PATCHes `expected_head_version_id` with that value, plus `based_on_version_id` in version-edit mode. When the param is present and differs from `current_line_head_version_id` (another tab or user saved since), `FlowchartsController#update` saves nothing and answers `409 Conflict` with `{ status: "conflict", message:, head_version_id: }` (`maint_core.flash.flowcharts.save_conflict`; an HTML request redirects back with the same alert). A request without the param is not checked.

Success JSON adds `version_id`, the new line head. The canvas stores it in `headVersionIdValue` and, in version-edit mode, in `basedOnVersionIdValue`, so the next save has the right lineage and still hits the unchanged-payload no-op. For the same reason the controller ignores a `based_on_version_id` equal to the head.

On 409 the editor shows the conflict banner (`saveConflictBanner`, `role="alert"`) with the server message and two buttons. Reload (`save_conflict_reload`) drops the unsaved-changes guard and reloads the page. Overwrite (`save_conflict_overwrite`) resends with `expected_head_version_id` set to the returned `head_version_id`. A successful save hides the banner.

An error body is parsed only when `content-type` contains `json`; otherwise the error is `save_failed_http_format` ("Save failed (HTTP {status})"), so a proxy or crash page never surfaces as a script error. A fetch exception reports `network_error_format`. Ctrl/Cmd+S saves from anywhere on the editor page, including property fields, and suppresses the browser's Save Page dialog; on a read-only flowchart it shows `readOnlySaveToast` instead. While a subflow is expanded, Save writes the stored collapsed graph.

### Undo and redo

`UndoRedoManager` keeps full graph snapshots in canvas order (50 entries; the last 10 survive a reload in `sessionStorage`, keyed per flowchart and edited version). Element and connection edits both go through `onBeforeChange` / `onchange`: `updateConnectionProperties` (the sidebar's connection label and notes, branch rows) is undoable and sets the unsaved dot, like `updateElementProperties`.

Consecutive commits with the same coalesce key (`canvas.undoCoalesceKey`) replace the top snapshot instead of pushing a new one; when the edit returns to its "before" state, the entry is dropped. The property editor sets the key to `<elementOrConnectionId>:<field>` on `focusin` and clears it on `focusout`, so typing in one focused field is one entry and a paragraph no longer evicts the history. Arrow-key nudges use `nudge:<selection ids>`, and a burst ends after 500 ms idle or on any other key. "Add an End" uses one key for the new End and its connection.

Undo and redo restore through `canvas.restoreGraph`: a silent swap of elements and connections that keeps zoom, pan, loaded metadata, connection routing and the selection of elements that still exist. It does not realign, merge defaults or fire change hooks. Undo, redo and Clear leave subflow preview first; on a read-only canvas undo and redo do nothing. An open property editor is discarded before the restore so it cannot write a stale element back.

### Subflow preview

An expanded subflow is a read-only preview of the whole canvas. On the first expansion the controller stores the collapsed configuration (`_collapsedPreviewConfiguration`, a clone of `getConfiguration()`) and sets `canvas.previewMode`. While previewing, Save, validation (client and server) and undo snapshots use that stored graph, never the expanded one (`_previewAwareConfiguration`). Folding the last expansion restores it exactly, positions included, through `restoreGraph`. Expanding and folding add no undo entry and do not mark the flowchart unsaved. The notice `preview_subflow_notice` ("Previewing a subflow — fold it to edit"; target `previewNotice`, `role="status"`) shows while previewing. Clear, undo, redo and version restore leave preview mode first and put the collapsed graph back, so a cancelled Clear, an empty undo stack or a failed restore never leaves the expansion live. A subflow that points at the flowchart being edited does not expand (`subflowSelfReferenceToast`).

One guard covers every editing command: `canvas.canMutate()` is `!isReadOnly && !previewMode`. Drag, resize, connect, endpoint retarget, delete, paste, duplicate, arrow nudge, inline connection-label edit, align/distribute, Tidy layout, routing cycle, palette drop and double-click, edge "+", autofix (row and Fix all), undo/redo, version restore, and the property editor's save and live sync all check it. The alignment toolbar, autofix buttons and edge "+" are hidden while it is false. What stays available: the expand/fold toggle and the fold icon (they check only `isReadOnly`, so a preview can always be folded), selection, copy, select all, zoom, pan, search, Validate and Save.

### Shortcuts and selection

Shortcuts listen on `document`. Apart from Ctrl/Cmd+S, they are ignored while focus is in an input, textarea, select or contenteditable element, and run only when the event target is `document.body` or inside the canvas container. Single-character keys are compared in lower case, so Caps Lock does not matter; Ctrl and Cmd are interchangeable.

| Keys | Action |
|------|--------|
| Ctrl/Cmd+S | Save (also from property fields; a read-only flowchart shows a toast) |
| Ctrl/Cmd+Z | Undo |
| Ctrl/Cmd+Y, Ctrl/Cmd+Shift+Z | Redo |
| Ctrl/Cmd+C | Copy the selected elements and the connections between them |
| Ctrl/Cmd+V | Paste (cascading offset) |
| Ctrl/Cmd+D | Duplicate the selection |
| Ctrl/Cmd+A | Select all elements |
| Ctrl/Cmd+F | Search |
| Ctrl/Cmd+= or +, Ctrl/Cmd+-, Ctrl/Cmd+0 | Zoom in, zoom out, fit to content |
| Delete, Backspace | Delete the selected connection, else the selected elements |
| Arrow keys | Nudge the selection by one grid step (15 px); with Shift, 5 steps |
| Space (hold) | Pan by dragging |
| Escape | Cancel an element drag |

Paste, duplicate, delete, nudge, undo and redo need `canMutate()`; copy, select all, zoom, search and pan do not. A nudge burst is one undo entry and ends after 500 ms idle, on any other key, or on destroy.

Shift+click, like Ctrl/Cmd+click, toggles an element in the selection; Shift, Ctrl or Cmd held while drawing a marquee adds to it. Deleting hides the resize handles. Jumping to a problem from the panel selects the element through the canvas selection helpers and clears any selected connection, so Delete then removes that element rather than a stale edge; a connection problem selects the connection (`selectConnection`) and fits both ends in view.

### Validation panel

Each fault is listed once. `validate()` drops a server problem that a client problem already covers — same `elementId` and `field`, or, for an element-level problem with no field, the same `elementId` and `type` — then removes duplicates by `(elementId, connectionId, type, field)`. Together with the server skipping the dry run on an invalid graph, a bad step config is no longer listed as the client rule, `element_config_invalid` and `codegen_failed` at once.

New elements get unique default names. `uniqueLabel(elements, base, format)` (`flowchart/labels.js`) returns `base` when no element uses it (case-insensitive), else the first free name counting from 2 in the translated `maint_core.flowcharts.editor.unique_label_format` (`{label} {n}`: "End 2", "End 3"); a base already in that format restarts from its root ("End 2" → "End 3"). Palette add and drop, insert-next-to, edge "+" and paste/duplicate all use it — requested names too, such as a second drop of the same subflow — so a new box is never flagged as a duplicate label. The "Rename uniquely" autofix uses the same helper.

The End autofixes pick their source from the terminal elements: elements reachable from Start, other than Start, End and Decision, with no outgoing connection, in breadth-first order from Start. "Add an End" (`missing_end`) creates an End one spacing below the last terminal and connects that element to it, as one undo entry. "Connect from the last step" (`orphan_end`) connects the last terminal to the orphan End. Neither fix is offered when there is no terminal, and no autofix is offered while `canMutate()` is false.

### Readability

Node labels are 11 px (Decision 10 px). `truncateLabel` shortens a label to the box width using a width estimate (CJK and full-width characters count as 1 em, others 0.6 em) and ends it with "…"; a truncated label carries the full text in an SVG `<title>`, shown on hover. After an element edit, `_rerenderElement` redraws the whole group (shape, label, comment dot, subflow toggle, size) and keeps its stacking position, selection and search classes, validation ring and fold icon.

Version timestamps use `Intl.DateTimeFormat(appLocale, { dateStyle: "medium", timeStyle: "short" })` and the label `version_label_format` (`v{number}`). The Elements tab shows the translated type name (`elementLabel(type)`) and `element_connections_format` (`{incoming} in / {outgoing} out`), and escapes label, type and id. The minimap sizes its SVG from its container with a `ResizeObserver` (160×120 px below `sm`, 200×140 px from `sm`) and sits at `z-30`, above the bottom panel. The oversize and timeout server warnings are translated (see "Validation and launch"). The canvas JavaScript carries no inline English fallbacks: every message is a Stimulus value with an English default, overridden by a translated `data-flowchart-canvas-*-value` from the editor.

## Where to pay attention

### Route audit: runtime boundary

The generator/UI report harness in `spec/scripts/audit_generator_ui_spec.rb` runs the real audit in a fresh subprocess with `OUTPUT_PATH` redirected to a per-example `Tempfile`. It checks the report and defect gate, then automatically removes the temporary output. Test runs do not delete or replace `docs/superpowers/specs/2026-04-19-generator-ui-audit-data.yml`; the standalone audit command retains its normal destination.

Public submission now compiles shared overrides from the effective version without changing the global stored artifact, and requires accessible launched runtime children. Editor writes remain owner-only; the protected platform prefix also requires actual outer CID `81721200` and the owner's pinned email/customer identity. See [Flowchart runtime](flowchart-runtime), [Shared resources](shared-resources), [Tenancy and roles](tenancy-and-roles).

:::note
These are shared authorization/runtime source changes. Builder routes and generated execution were excluded from the October 11 audit; authored runtime regressions have not been run here.
:::

:::attention
`FlowchartVisibility.allowed?` is `platform_owner?` only. `RouteAuthorization#enforce_route_role!` applies that gate to the tenant flowchart URLs and to the platform prefix. Do not add a second role filter on `FlowchartsController`, and do not expose the editor to a tenant admin. Bound pages still submit; they never need this screen. See [Page builder](page-builder).
:::

:::attention
`ActivityGenerator` compiles. `#generate` returns `nil` when the flowchart has no name or no elements, and also when structural validation fails without raising. `Flowchart#before_save` stores that return value in `activity`. A blank `activity` later makes `Pages::PublicSubmission` reject the page. Runtime does not walk `elements` to decide the next step.
:::

:::attention
`Flowchart#generate_activity` returns before compilation when `override_customer_id` is present. The override line stores configuration on `flowchart_customer_heads` via `resolved_current_version`. The global `activity` column stays the platform default. `launched_edit_locked?` blocks definition edits on the global launched row; it does not block an override write.
:::

:::attention
`FlowchartServerValidator#call` mutates an in-memory copy and returns problem hashes. `ValidationsController` renders them as JSON and rescues unexpected errors to an empty problem list with status 422. Launch runs `FlowchartInputOutputValidator`, then the same server checks on a separate copy of the stored configuration, and persists `status` only when neither reports an error. Passing validation in the editor does not launch the flowchart, and Launch checks the saved graph, not unsaved canvas edits.
:::

:::attention
A new canvas editing command must check `canvas.canMutate()` (`!isReadOnly && !previewMode`), not `isReadOnly`, and hide its button while it is false. While a subflow is expanded the live canvas is a preview: anything that saves, validates or snapshots reads `_previewAwareConfiguration()` (the stored collapsed graph), never `canvas.getConfiguration()` directly.
:::

:::attention
A canvas save sends `expected_head_version_id`; a stale head is `409 Conflict` and nothing is saved. A PATCH without the param skips the check. After every save or restore, adopt the returned `version_id`: a stale `headVersionIdValue` makes the next save conflict with the editor's own previous save.
:::

:::attention
A process box holds one action. `StructureValidator` reports `process_multiple_actions` when `steps` has more than one entry. The assistant Normalizer runs `ProcessSplitter` before persist. Stored multi-action graphs are not converted; they fail validation.
:::

:::attention
Decision branches live only on the outgoing connections (`label`, `matchValue`, `fromPort`); an empty match value is Otherwise. Removing a branch row removes the connection, never the target box. On Start, End, Decision, Loop and Subflow, `properties` may hold only the catalog fields plus `description`, `label`, `steps`, `condition`, `io_overrides`, `inputs` and `outputs`; any other key fails validation and generation as `unknown_field`.
:::

:::attention
After a generator change, run `DRY_RUN=1 bin/rails flowcharts:regenerate_activities`, then the same rake without `DRY_RUN`. Stored activity source must match the current class shape (`CANVAS`, `Routes`, `collect_errors`); an owner test run of a class without `CANVAS` stops with "Activity must be regenerated".
:::

:::attention
The test panel traces the posted in-memory `configuration`. `FlowchartTracesController` compiles a `dup`, seeds the PublicSubmission runtime keys after the posted input, and always rolls back the `requires_new` transaction. It never `save`s a version. External side effects are not suppressed. Restore returns `configuration` so the canvas can `loadConfiguration` without a second fetch. Builder fetches use `data-flowchart-canvas-urls-value`; they do not hard-code `/:cid/admin/maintenance/flowcharts`.
:::

## Key code

```ruby
# app/services/flowchart_visibility.rb
  def allowed?(user)
    user.respond_to?(:platform_owner?) && user.platform_owner?
  end
```

```ruby
# app/models/flowchart.rb
  def generate_activity
    # `activity` is a compiled column on the parent row. A tenant override
    # must not overwrite the global default; runtime still reads this column.
    return if override_customer_id.present?

    self.activity = ActivityGenerator.new(self).generate
  rescue ActivityGenerator::Error => e
    # Invalid generator config must never wipe a prior activity or persist a
    # failure stub as activity source. Raise in test; elsewhere leave the
    # previous activity untouched so the configuration edit can still save.
    raise if Rails.env.test?

    Rails.logger.error("[Flowchart##{id || 'new'}] ActivityGenerator::Error: #{e.message}")
  rescue StandardError => e
    # Unexpected codegen bugs must never block save — otherwise the user loses
    # in-progress edits. Preserve the raise in test so we still catch
    # regressions; elsewhere annotate the activity field and move on.
    raise if Rails.env.test?

    Rails.logger.error("[Flowchart##{id || 'new'}] ActivityGenerator raised: #{e.class}: #{e.message}")
    self.activity = "# ActivityGenerator failed: #{e.class}: #{e.message}"
  end
```

```ruby
# app/services/activity_generator.rb
  def generate
    return nil if flowchart.name.blank? || elements.empty?
```

```ruby
# app/services/activity_generator.rb
    generator_class = @registry.find_element_type(type)
    if generator_class
      generator = generator_class.new(element, generator_context(element, ctx))
      result = generator.generate_body
      return rewrite_element_body(element, result) if result
    elsif !STEP_CONTAINER_ELEMENT_TYPES.include?(type)
      raise Error.new(
        code: :unknown_element_type,
        message: I18n.t("maint_core.flowcharts.structure_errors.unknown_element_type", type: type.inspect),
        element_id: element["id"],
        element_type: type
      )
    end
```

```ruby
# app/models/flowchart/configuration_accessors.rb
  def elements
    configuration_json&.dig("elements") || []
  end

  def connections
    configuration_json&.dig("connections") || []
  end

  def metadata
    configuration_json&.dig("metadata") || {}
  end
```

```ruby
# app/services/flowchart_server_validator.rb
  def call
    elements = Array(@configuration["elements"])
    return [] if elements.empty?
    return [payload_too_large_problem] if payload_too_large?(elements)

    Timeout.timeout(DRY_RUN_TIMEOUT_SECONDS) do
      apply_submitted_configuration!

      problems = subflow_validator.call(elements) +
                 config_validator.call(elements, Array(@configuration["connections"]))
      # The dry run only means something on an otherwise valid graph.
      next problems if problems.any? { |problem| problem[:severity] == "error" }

      problems + codegen_validator.call(@flowchart)
    end
  rescue Timeout::Error
    [validation_timeout_problem]
  end
```

```ruby
# app/controllers/admin/maintenance/flowcharts_controller.rb
    def stale_head?
      params.key?(:expected_head_version_id) &&
        params[:expected_head_version_id].to_s != @flowchart.current_line_head_version_id.to_s
    end
```

```js
// app/javascript/flowchart/canvas.js
  canMutate() {
    return !this.isReadOnly && !this.previewMode
  }
```

```ruby
# app/models/flowchart/template_builder.rb
    def new_with_defaults(attributes = {})
      attributes = attributes.to_h.dup
      template_key = attributes.delete("template") || attributes.delete(:template)
      if template_key.present?
        attributes.delete("configuration")
        attributes.delete(:configuration)
      end
```

```ruby
# app/services/activity_generator/structure_validator.rb
    MULTI_OUTGOING_EXEMPT_TYPES = %w[decision loop].freeze
```

```ruby
# app/services/code_generators/element_catalog.rb
      def tabs_for(type, fields)
        tabs = ["general"]
        tabs << "steps" if type == "process"
        tabs << "branches" if type == "decision"
        tabs << "io"
        tabs << "advanced" if fields.any? { |field| field["group"] == "advanced" }
        tabs
      end
```

```ruby
# app/services/activity_generator/structure_validator.rb
        if el["type"] == "process" && process_steps(el).size > 1
          errors << I18n.t("maint_core.flowcharts.structure_errors.process_multiple_actions", label: el["label"])
        end
        if !MULTI_OUTGOING_EXEMPT_TYPES.include?(el["type"]) &&
           @connections.count { |connection| connection["from"] == el["id"] } > 1
          errors << I18n.t("maint_core.flowcharts.structure_errors.multiple_outgoing", label: el["label"])
        end
```

Related: [Code generators](code-generators), [Flowchart runtime](flowchart-runtime), [Shared resources](shared-resources), [Entity builder](entity-builder).
