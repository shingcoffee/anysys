---
title: "Operations API"
summary: "Versioned, schema-described operations the assistant calls as tools (entities, domains, journeys, page processing and background sub-system builds): registry and DSL, schema conventions, violations, outcomes, confirmation, idempotency and the audit table."
---

## Summary

An operation is one named, versioned unit of work with a published input contract. It is a subclass of `Operations::Base` in `app/services/operations/<key>.rb`, paired with a JSON Schema 2020-12 file in `app/services/operations/schemas/<key>.json`. A caller passes a key, an input hash and an `Operations::Context` to `Operations::Activities::Execute` and gets back an `Operations::Outcome`. Every caller goes through the same pipeline. `Operations::Context::CHANNELS` lists `assistant`, `api` and `system`, but today only the AI assistant calls operations; there is no HTTP endpoint yet.

Eight operations are registered. Three are for entity schemas: `create_entity` applies immediately, `update_entity` always waits for an administrator's approval, and `get_entity` is read-only. They replace the assistant's former free-form entity document. Five finish a sub-system around those entities and apply immediately: `create_domain`, `list_journey_options` (read-only), `generate_journeys`, `set_page_processing` and `start_subsystem_build` (see *Domain, journey, page and build operations* below). See [Entity builder](entity-builder) for the stored model and [AI assistant](ai-assistant) for the chat flow.

The design follows the common way of exposing a capability to a language model as a tool:

| Stage | Common practice | Anysys |
| --- | --- | --- |
| Contract | One JSON Schema per tool (MCP `inputSchema`, function-calling `parameters`); `verb_noun` names | `schemas/<key>.json` resolved by `Operations::Schema`; keys such as `update_entity` |
| Descriptions | Every property and enum value is documented, because the schema is the model's manual | `description`, `x-enum-descriptions` and registry-backed `x-vocabulary`, enforced by `Operations::SchemaLint` |
| Validation | Structural first, then semantic; errors point into the input with an RFC 6901 JSON Pointer | `json_schemer`, then the operation's `validate`; each failure is an `Operations::Violation` |
| Perform | An anti-corruption mapper in front of the domain writer, in one transaction | `perform` calls `EntityDefinitions::Api::Mapper` and `EntityDefinitions::Persist` under the customer lock |
| Invocation | Native tool calling; a human approves destructive actions (MCP `destructiveHint`) | `AiAssistant::Assistant::Tools::OperationTool`, a JSON fallback, and `confirmation: :always` with `Operations::Activities::Confirm` |
| Triage | Machine-readable errors with a suggested next step; RFC 9457 problem details | `resolution`, `next_step` and `attempts_remaining`; `Outcome#to_problem` |

Every call is scoped to `context.customer`. `Operations::Authorization.allowed?` admits an active platform owner or an active `admin` of that customer, and always refuses members. The entity operations then read and write only customer-owned, active, non-bridge entities.

## Flow

```text
Caller (assistant tool call; api and system channels reserved)
        |  Operations::Context: customer, actor, channel, conversation,
        |  generation, idempotency_key, dry_run, confirmed, around_write
        v
Operations::Activities::Execute.call(operation:, input:, context:)
        |  resolve             Operations.for(key)          -> invalid   operation.unknown
        |  authorize           Authorization + available?   -> forbidden permission.denied
        |  replay              idempotency key + digest     -> stored outcome | invalid idempotency.key_reused
        |  validate_schema     JSON Schema (+ defaults)     -> invalid   schema.*
        |  validate_semantics  #validate                    -> invalid   entity.*, attribute.*, ...
        |  plan_and_snapshot   #plan, #snapshot
        |  gate                dry_run                      -> dry_run (plan only)
        |                      confirmation :always         -> confirmation_required (row parked)
        |  perform             around_write { customer.with_lock(requires_new: true) { #perform } }
        |  record!             operation_invocations row
        v
Operations::Outcome -> #to_tool_payload (model) / #to_problem (RFC 9457)

Administrator approves (assistant: Apply button or a bare "yes")
        v
Operations::Activities::Confirm.call(invocation:, context:)
        |  require_pending -> resolve (same version) -> authorize
        |  revalidate: schema -> stale?(snapshot) ? conflict -> #validate (confirmed) -> conflict.* ? conflict : invalid
        |  apply: customer lock { stale?(snapshot) ? conflict : #perform }
        v
Parked row finished: status, result, violations, confirmed_by_id, confirmed_at
```

## Implementation

### Registry and DSL

`Operations` (`app/services/operations.rb`) extends `PluginRegistry.build(label: "operation", dir: "app/services/operations", defaults: false)`. `ensure_loaded!` constantizes every `app/services/operations/*.rb` except `base.rb`; framework files such as `outcome.rb` load but do not register. `Operations.for(key)` returns the class and raises `ArgumentError` for an unknown key. `Operations.keys` and `Operations.all` list the registered operations. The assistant builds its tool list from `Operations.all`, so a new operation needs no assistant change.

Class-level DSL on `Operations::Base`:

| DSL | Meaning |
| --- | --- |
| `key "update_entity"` | Tool name and audit key. Must match `/\A[a-z][a-z0-9_]{2,63}\z/`; use `verb_noun`. |
| `version 1` | Contract version, default 1. Part of the schema `$id` and stored on every invocation. `Confirm` refuses a proposal parked under another version (`operation.version_changed`). |
| `title "Update entity"` | Short title for people. Required by `SchemaLint`. |
| `summary "…"` | The tool description the model reads. Say when to use the operation and what it does not do. |
| `schema "update_entity.json"` | Input contract under `app/services/operations/schemas/`; `schema_root` changes the directory. |
| `shared_defs "entity.defs.json"` | Files whose `$defs` are merged in first. The operation's own `$defs` win. |
| `vocabulary EntityDefinitions::Api::Vocabulary` | Resolves the `x-vocabulary` and `x-vocabulary-max` slots. |
| `insert_defaults false` | Stops validation from inserting schema defaults into the input; the default is on (`insert_defaults?`). `update_entity` declares it because its input carries merge patches, where an inserted default would overwrite a stored value. |
| `annotations destructive: true, confirmation: :always` | `read_only`, `destructive` and `idempotent` hints, plus `confirmation` (`:never` or `:always`). |
| `register!` | Adds the class to the registry. |
| `available?(context)` | Class method, default `true`. `false` removes the tool from the assistant and makes `Execute` return `forbidden`. |

Instance hooks run with `context` set. They receive the **normalized** input, with schema defaults filled in unless the operation declares `insert_defaults false`:

| Hook | Default | Contract |
| --- | --- | --- |
| `validate(input)` | `[]` | Return an Array of `Operations::Violation` for cross-field, reference, policy and quota rules. |
| `plan(input)` | `nil` | The reviewable plan, returned with `dry_run` and `confirmation_required`. |
| `snapshot(input)` | `nil` | Version pins stored on the parked invocation. |
| `stale?(snapshot)` | `false` | `true` when the target moved after `snapshot`. `Confirm` checks it under the lock. |
| `perform(input)` | raises `NotImplementedError` | Write through the domain service and return an `Operations::Outcome`. |

In `Execute`, `read_only` skips idempotent replay and the audit row, and `confirmation: :always` parks every unconfirmed call. `destructive` and `idempotent` are recorded hints; no code branches on them yet.

### Schema conventions

`Operations::Schema#document` loads the operation's file, merges the shared `$defs`, resolves the vocabulary slots, then sets `$id` to `urn:anysys:operation:<key>:v<version>` and `$schema` to `https://json-schema.org/draft/2020-12/schema`. Only the parsed JSON files are cached, keyed by path and mtime (`Schema.parsed_files`, cleared by `reset_cache!`), and the slots are resolved on every call, so an edited schema file takes effect without a restart. `#validate(input)` runs `json_schemer` with `insert_property_defaults` set to the operation's `insert_defaults?` and returns `[violations, normalized]`. For `create_entity` the hooks therefore receive create-shaped defaults such as `kind: "input"`, `html_type: "text"` and group `icon: "folder"`; `update_entity` declares `insert_defaults false`, so its patches arrive exactly as sent.

A list that comes from a registry is never written into the JSON. A slot names the list, and `vocabulary.resolve(name, context)` fills it in each time the document is resolved:

- `"x-vocabulary": "<slot>"` becomes `enum` plus `x-enum-descriptions`. A nullable type such as `["string", "null"]` also gets `null` appended. `extends` is nullable, so a tenant without extendable models gets `"enum": [null]`, and `null` means no base model.
- `"x-vocabulary-max": "<slot>"` becomes `maximum`; the slot must resolve to an Integer.
- An unknown slot raises `ArgumentError`.

`EntityDefinitions::Api::Vocabulary` serves the entity slots:

| Slot | Values | Source |
| --- | --- | --- |
| `html_types` | 21 controls, `text` to `color` | `HtmlTypeOptions::GROUPED_HTML_TYPES` |
| `selection_html_types` | `select`, `radio`, `checkbox` | `HtmlTypeOptions::SELECTION_TYPES` |
| `attribute_kinds` | `input`, `calculated`, `computed` | `Vocabulary::ATTRIBUTE_KINDS` |
| `rule_types` | 19 rule types, `presence` to `acceptance` | `ValidatorRegistry::VALIDATOR_LABELS` |
| `rule_types_single_value`, `rule_types_range`, `rule_types_pattern`, `rule_types_list` | 8, 1, 1 and 2 rule types | `ValidatorRegistry::VALIDATOR_CONFIG_TYPES` |
| `group_icons`, `group_colors` | 12 icons, 8 colour tokens | `EntityAttributeGroupOptions` |
| `option_sources` | `static`, `constant`, `entity_entries` | `Vocabulary::OPTION_SOURCES` |
| `aggregate_functions`, `filter_operators` | `avg sum count min max`; `= != > >= < <=` | `Entities::ComputedCompiler` |
| `aggregate_directions` | `source`, `target` | `Vocabulary::AGGREGATE_DIRECTIONS` |
| `extendable_models` | Per tenant | `ExtendableModelRegistry.for_customer` |
| `aggregate_max_precision` (`x-vocabulary-max`) | 6 | `Entities::ComputedCompiler::MAX_PRECISION` |

`rule.type` uses `"x-vocabulary": "rule_types"`, so every rule type is listed. Each description is generated as "meaning, takes value fields, and is allowed on html types", ending in "every html_type" for a rule such as `presence`. For `length_maximum` the model reads: "Requires the text to be at most the given length, takes `value`, and is allowed on text, textarea, search, password, email, tel, and url." The semantic validator reports a rule outside its html_type's list as `rule.not_allowed` with `allowed`.

Titles, summaries and descriptions are model-facing API documentation and stay in English. They are not UI text and are not translated; violation messages are.

**Projection.** `tool_definition(context)` returns `{name:, description: summary, parameters:}`, where `parameters` is `Operations::SchemaProjection.call(document)`. Vendor tool dialects disagree on `$ref`, `if`/`then` and `allOf`, so the model receives a flat, conservative copy while the server still validates against the full document. The projection:

- inlines every `#/$defs/...` `$ref`; keys beside the `$ref`, such as its `description`, override the target's;
- drops `$schema`, `$id`, `$defs`, `$comment`, `examples` and every `x-*` key;
- appends the enum descriptions to the description, each without its trailing period, for example ``Allowed values: `input` — A stored field the user fills in on the form; `calculated` — …``;
- merges unconditional `allOf` items, and folds the descriptions of conditional `allOf` items, `if`/`then`/`else`, `not` and `dependentRequired` into the parent description before deleting them;
- renames `oneOf` to `anyOf`;
- raises `SchemaProjection::TooLarge` above `DEFAULT_BUDGET`, 32,000 bytes of JSON. The entity write tools are close to it: about 25 KB for `create_entity` and 26.5 KB for `update_entity`. `get_entity` is about 0.5 KB.

**Lint.** `Operations::SchemaLint.call(operation_class, context)` returns a list of problems, and `spec/services/operations/contract_lint_spec.rb` requires an empty list for every registered operation. It checks that:

- `title`, `summary` and a root `description` are present;
- every documented position has a `description`: the root, each entry under `properties`, `patternProperties`, `$defs` and `dependentSchemas`, and array `items` and `prefixItems`. Branches of `allOf`, `anyOf` and `oneOf` inherit their parent's description;
- every `enum` value except `null` has an `x-enum-descriptions` entry;
- every conditional `allOf` item has a `description`;
- every object schema declares `additionalProperties: false`; a `then` or `else` branch itself is exempt;
- every root `examples` entry validates;
- the projection fits the budget.

### Violations

An `Operations::Violation` has four fields:

- `pointer` is an RFC 6901 JSON Pointer into the input, built with `Operations::Pointer.join` (`~` and `/` are escaped as `~0` and `~1`), for example `/updates/0/changes/2/slug`. A semantic violation found on the changed document points at the change that introduced the item.
- `code` is a stable dotted identifier such as `schema.enum`, `entity.not_found` or `conflict.version_changed`.
- `details` carries interpolation values and machine hints: `allowed`, `candidates` (up to three `DidYouMean` suggestions), `expected`, `property`.
- `resolution` tells the caller what to do next (table below).

`Violation#message` is `I18n.t("operations.violations.<code>")` with `details` interpolated, falling back to `operations.violations.generic`. For any code whose `details["candidates"]` is not empty, it appends `operations.violations.did_you_mean` (" Did you mean: %{candidates}?"), so `schema.unknown_property` reads "Unknown property." or "Unknown property. Did you mean: color?". Framework messages live in `config/locales/operations.{en,zh-CN}.yml`, entity messages in `config/locales/operations_entity.{en,zh-CN}.yml`, and journey, page-processing and build messages in `operations_journey`, `operations_page` and `operations_subsystem` (`.{en,zh-CN}.yml`). `as_json` is what callers receive:

```json
{
  "pointer": "/entities/0/attributes/0/html_type",
  "code": "schema.enum",
  "message": "Value must be one of: text, textarea, search, password, hidden, select, radio, checkbox, number, range, date, time, datetime-local, month, week, email, tel, url, file, image, color.",
  "resolution": "fix_payload",
  "allowed": ["text", "textarea", "search", "password", "hidden", "select", "radio", "checkbox", "number", "range", "date", "time", "datetime-local", "month", "week", "email", "tel", "url", "file", "image", "color"]
}
```

| Resolution | Next step | Default for | Also set on |
| --- | --- | --- | --- |
| `fix_payload` | Correct the call and retry without involving the user | Every code not listed below, including `schema.*` | `entity.not_found`, `attribute.not_found`, `group.not_found` and `association.not_found` when there are candidates |
| `ask_user` | Ask the user in one round, one question per item (the assistant shows a question card) | — | `entity.name_in_trash`, and the four `not_found` codes when there are no candidates |
| `refresh` | Re-read the target with `get_entity` and rebuild the call | `conflict.*` | — |
| `blocked` | Explain and stop; do not retry | `permission.*`, `quota.*` | `entity.not_editable`, `attempts.exhausted`, `proposal.already_pending` |

Schema errors map by keyword:

- `required` becomes `schema.required`, with the pointer extended to the missing property and `property` in `details`;
- `enum` and `const` become `schema.enum` with `allowed`;
- `type` becomes `schema.type` with `expected`;
- `additionalProperties: false` becomes `schema.unknown_property` with `candidates` from the sibling property names;
- `pattern`, `format`, `minLength`, `maxLength`, `minItems`, `maxItems`, `minimum`, `maximum`, `uniqueItems`, `minProperties` and `maxProperties` become `schema.<keyword in snake_case>` with `expected`;
- anything else becomes `schema.invalid`.

Errors reported through `allOf`, `if` and `then` wrappers are reduced to the deepest specific ones. Duplicates by pointer and code are dropped, and the list is capped at `Operations::Schema::MAX_VIOLATIONS` (25). The semantic validators use the same cap.

### Outcomes and the tool payload

| Status | `ok?` | HTTP | Payload key | Produced when |
| --- | --- | --- | --- | --- |
| `succeeded` | yes | 200 | `data` | `perform` succeeded |
| `confirmation_required` | yes | 202 | `plan` | `confirmation: :always` and not yet confirmed; the row is parked |
| `dry_run` | yes | 200 | `plan` | `context.dry_run` is true; nothing is written |
| `invalid` | no | 422 | `errors` | Unknown operation, reused key, schema or semantic violations, `domain.invalid` |
| `conflict` | no | 409 | `errors` | `Confirm` found `stale?` true, or revalidation reported a `conflict.*` code |
| `forbidden` | no | 403 | `errors` | `Authorization` or `available?` refused the call |
| `failed` | no | 500 | `errors` | An unexpected exception (`internal.error`) |

`Outcome#to_tool_payload(attempts_remaining:)` is the JSON the model gets back (abridged):

```json
{
  "ok": false,
  "status": "invalid",
  "operation": "create_entity",
  "errors": [
    {
      "pointer": "/entities/0/attributes/0/html_type",
      "code": "schema.enum",
      "message": "Value must be one of: text, textarea, search, …",
      "resolution": "fix_payload",
      "allowed": ["text", "textarea", "search", "…"]
    }
  ],
  "attempts_remaining": 2,
  "next_step": "Correct the fix_payload items and call create_entity again; do not mention them to the user. Attempts remaining: 2."
}
```

`next_step` comes from `operations.guidance.*`. For `invalid` it joins one sentence per distinct resolution (`guidance.fix_payload`, `guidance.ask_user` and so on), falls back to `guidance.invalid`, and appends `guidance.attempts_remaining` when an attempts count is given. Every other status uses `guidance.<status>`. `%{operation}` is interpolated into the sentences and `%{attempts}` into the attempts sentence.

`Outcome#to_problem` renders the same outcome as an RFC 9457 problem document for a future HTTP channel: `type` (`urn:anysys:problem:<status>`), `title` (`operations.problems.<status>`), `status` (the HTTP code), `detail` (the `next_step` text, without an attempts sentence), `operation` and `errors`. No controller serves it yet.

### Execute, Confirm and the audit table

`Operations::Activities::Execute` is a `Trailblazer::Activity::Railway`. A failing step stores an outcome and leaves the railway; `record!` always runs afterwards.

1. `resolve` looks up `Operations.for(key)`; a class is also accepted. An unknown key gives `invalid` with `operation.unknown` and `available`.
2. `authorize` requires `Authorization.allowed?(actor:, customer:)` and `available?(context)`, otherwise `forbidden` with `permission.denied`.
3. `replay` handles idempotency (below). It is skipped for `read_only` operations and blank keys.
4. `validate_schema` runs `input_schema(context).validate(input)`.
5. `validate_semantics` runs the operation's `validate(normalized)`.
6. `plan_and_snapshot` stores `plan(normalized)` and `snapshot(normalized)`.
7. `gate` returns the plan for `dry_run`. For `confirmation: :always` without `context.confirmed`, it creates the `awaiting_confirmation` row and returns `confirmation_required`.
8. `perform` calls `Execute.perform_atomically`.

**Idempotency.** When `context.idempotency_key` is set, `replay` looks up `OperationInvocation.find_by(customer_id:, idempotency_key:)`. If the stored `input_digest` (SHA-256 of the input as JSON, with keys sorted recursively) matches, the stored outcome comes back with `replayed: true` and nothing is written. A different digest gives `invalid` with `idempotency.key_reused`. Only a succeeded or parked row keeps the key (`Execute.replayable?`); a rejected or failed call is recorded with a nil key, so the same call runs again later, for example once the entity it was missing exists. The unique index `idx_operation_invocations_idempotency` on `(customer_id, idempotency_key)` backs this; when two overlapping calls with one key both pass the lookup, `create_audit!` records the second without the key instead of raising `RecordNotUnique`. The assistant uses `gen-<generation id>-<operation key>-<input digest>`, so a retried reply job cannot write twice.

**Optimistic concurrency.** `update_entity` has two checks:

- `expected_version` is the `version` that `get_entity` returned (`display_current_version.version_number`). `validate` compares it with the live version and reports a mismatch at `/updates/<i>/expected_version` with `expected` and `got`. This runs when the proposal is made. On approval `validate` runs with `context.confirmed` and skips it, because the snapshot below is the stricter check. The field is optional.
- `snapshot` stores `{entity name => current_line_head_version_id}` on the parked row. `Confirm` calls `stale?` before revalidating and again inside the customer lock, immediately before `perform`, and returns `conflict` with `conflict.version_changed` if any head moved.

**Atomicity.** `Execute.perform_atomically` runs `context.around_write`; the assistant passes `GenerationWriteGuard.wrap(write_guard)`. Inside it takes `context.customer.with_lock(requires_new: true)`, sets `Current.with_customer` and runs `perform`. `rescue_into_outcome` turns `ActiveRecord::RecordInvalid` into `invalid` with `domain.invalid` (`errors` in `details`), and any other `StandardError` into `failed` with `internal.error`, after logging it. A non-ok outcome raises `ActiveRecord::Rollback`, so a partial write never commits. `Confirm#apply` uses the same method. The steps before it (schema validation, `validate`, `plan` and `snapshot`) run inside `Execute.guarded`, which logs a `StandardError` and returns `failed` with `internal.error`.

**Confirm.** `Operations::Activities::Confirm.call(invocation:, context:)` runs five steps:

1. `require_pending`: the row is `awaiting_confirmation`, belongs to `context.customer` and, if it was parked inside a conversation, is approved from that conversation; otherwise `invalid` with `proposal.not_pending`.
2. `resolve`: the class still exists (`operation.unknown`) and its version equals the parked `operation_version` (`operation.version_changed`).
3. `authorize`: as in `Execute`, for the approving actor.
4. `revalidate`: the schema runs again on the stored input, then `stale?(invocation.snapshot)`, then `validate` with `confirmed: true`. A schema failure finishes the row as `invalid`. A moved target finishes it as `conflict` before `validate` runs, so a parked change that no longer applies because the target moved (an attribute to remove is already gone) is a `conflict`, not `invalid`. A semantic failure finishes it as `conflict` when any code starts with `conflict.`, otherwise as `invalid`.
5. `apply`: `perform_atomically` with `confirmed: true`. Inside the lock, `stale?(invocation.snapshot)` gives `conflict`; otherwise `perform` runs.

The parked row is finished with `status`, `result`, `violations`, `confirmed_by_id` and `confirmed_at`. `Confirm.supersede!(invocation)` marks a parked row `superseded` when a newer proposal replaces it. `Confirm.decline!(invocation, actor:)` marks it `declined` when the admin discards it, stamping `confirmed_by_id` and `confirmed_at`.

**Audit table.** `OperationInvocation` (`operation_invocations`, `TenantScoped`) has one row per recorded call:

| Column | Content |
| --- | --- |
| `customer_id`, `user_id` | Tenant and acting user |
| `operation`, `operation_version`, `channel` | What ran, under which contract, from which channel |
| `status` | `awaiting_confirmation`, `succeeded`, `invalid`, `conflict`, `forbidden`, `failed`, `superseded` or `declined` |
| `idempotency_key`, `input_digest` | Replay identity; the key is kept only on succeeded or parked rows |
| `input`, `plan`, `snapshot` | Normalized input, reviewable plan, version pins |
| `result`, `violations` | `Outcome#as_stored_result` and the violation list |
| `conversation_id`, `generation_id` | Assistant provenance, without foreign keys |
| `confirmed_by_id`, `confirmed_at` | Who settled a parked proposal (approved or declined), and when |
| `duration_ms` | Wall time of `Execute` |

Besides the idempotency index there are `idx_operation_invocations_directory` on `(customer_id, operation, created_at)` and indexes on `conversation_id` and `generation_id`. No page renders the table yet.

### Entity operations

The entity operations speak a public vocabulary. `EntityDefinitions::Api::Mapper` is the anti-corruption layer between it and the stored definition that the form and the runtime read, so the model never sees `property_schema`, `validators` or `bridge_entity_id`.

| Public field | Stored definition |
| --- | --- |
| `name`, `display_label`, `description` | The same columns on `Entity` |
| `extends` (class name, or `null` for none) | `extended_model` |
| `settings.icon`, `settings.color`, `settings.default_values` | `icon`, `color`, `default_properties` |
| `attribute_groups[].key` | `attribute_groups[].id` |
| `attributes[]` | `property_schema[]` |
| `slug` | `name_slug`; derived from `name` with `parameterize(separator: "_")` when omitted, immutable afterwards |
| `group` | `group_id` |
| `kind: "input"` | No `type` |
| `kind: "calculated"` with `formula` | `type: "Calculated"`, `formula`, `readonly: true`, `storage: "computed"` |
| `kind: "computed"` with `aggregate` | `type: "Computed"`, `html_type: "number"`, `readonly: true`, `storage: "computed"` and `config` |
| `aggregate.related_entity`, `source_attribute`, `direction`, `filter` | `config.target_entity_name`, `source_slug`, `bridge_role`, `filter` (`attribute`, `operator` become `slug`, `op`) |
| `rules[]`: `type` with `value`, `min`/`max`, `pattern` or `values` | `validators[]`: `type` with `config` |
| `access.visible_to`, `access.rules_apply_to` | `visibility`, `validator_apply` (stored as the intersection with `visibility`); a new attribute without `access` gets every flag `true` |
| `options` with `source: "static"` and `values` | `config.source: "manual"` and `config.options` of `{label, value, default}` |
| `options` with `source: "constant"` and `constant` | `config.source: "constant"`, `constant_id`, `constant_name`, `options`; a customer-owned constant wins over a shared one |
| `options` with `source: "entity_entries"`, `entity`, `label_field` (required) | `config.options_source: "entity_entries"`, `entity_id` (resolved from `entity` on write) and `label_field`; the stored value is always the record id |
| `owner` (boolean; omit when false) | `property_schema[].owner` when true. Valid only on an `entity_entries` reference whose target is a person entity, at most once per entity. `Serializer` echoes it only when true. `update_attribute` accepts `set.owner`; `false` clears the flag. Invalid on person entities, bridges, non-references and non-person targets. |
| `file.accept`, `file.multiple` | `config.accept`, `config.multiple` (always written, default `false`) |
| `associations[]`: `related_entity`, `display_field`, `display_field_label`, `bridge_attributes` | `associations[]`: `associated_entity_name`, `display_field`, `display_field_label` (default: the titleized display field), `additional_attributes`; the write adds the bridge entity |

`create_entity` and `update_entity` are at contract version 2: `options.value_field` no longer exists (`schema.unknown_property`), and `label_field` is required with `source: "entity_entries"` (`schema.required`). A proposal parked under version 1 is refused with `operation.version_changed`. `label_field` and an association's `display_field` must name a text, search, email, tel, url, number or date attribute (`options.label_field_not_labelable`, `association.display_field_not_labelable`). On update, a display field that other entities or launched forms rely on can't be deleted, retyped (`attribute.display_field_in_use`) or hidden from those forms' audiences (`attribute.display_field_hidden`).

`get_entity` and the assistant's `list_catalog` return `Mapper#from_entity`: the same shape plus `version` and each association's `bridge_entity`.

**Create.** `create_entity` takes 1 to 10 entities that may refer to each other by name, through associations, `entity_entries` option sources and aggregates. `SemanticValidator.for_create` checks them, `Mapper#to_definition` maps each one, and `EntityDefinitions::Persist` writes them all in one transaction. A realistic call, the first example in `create_entity.json`:

```json
{
  "entities": [
    {
      "name": "Course",
      "attribute_groups": [{ "key": "basics", "name": "Basics", "icon": "folder", "color": "indigo" }],
      "attributes": [
        { "name": "Title", "group": "basics" },
        {
          "name": "Level",
          "html_type": "select",
          "group": "basics",
          "options": { "source": "static", "values": ["Beginner", "Intermediate", "Advanced"] }
        }
      ]
    },
    {
      "name": "Student",
      "attributes": [
        { "name": "Email", "html_type": "email" },
        { "name": "Courses Taken", "kind": "computed", "aggregate": { "related_entity": "Course", "function": "count" } }
      ],
      "associations": [
        {
          "related_entity": "Course",
          "display_field": "title",
          "bridge_attributes": [{ "name": "Enrolled On", "html_type": "date" }]
        }
      ]
    }
  ]
}
```

Validation fills in `kind: "input"` and `html_type: "text"` for `Title`, and the mapper adds an `inclusion` rule listing the three levels. On success `data` has `created` (each entity's `name`, `slug`, `version` and `attributes` as `{name, slug}`) and `bridges`, here `["assoc_student_course"]`.

**Update.** `update_entity` takes 1 to 10 `updates`. Each has `entity`, an optional `expected_version` and 1 to 100 `changes` applied in order. The first example in `update_entity.json` adds a field, hides one from the public and removes another:

```json
{
  "updates": [
    {
      "entity": "Student",
      "expected_version": 7,
      "changes": [
        { "op": "add_attribute", "attribute": { "name": "Phone", "html_type": "tel" }, "position": { "after": "email" } },
        { "op": "update_attribute", "slug": "email", "set": { "access": { "visible_to": { "public": false } } } },
        { "op": "remove_attribute", "slug": "fax" }
      ]
    }
  ]
}
```

`validate` locates each entity, compares `expected_version`, applies the change set to the entity's `EntityDefinitions::Catalog` document with `EntityDefinitions::Api::ChangeSet` and validates the result. Untouched attributes stay byte-identical. Validation inserts no defaults here (`insert_defaults false`), so a patch carries only what was sent and every omitted key keeps its stored value; the defaults for anything the change set creates come from the mapper. When a patch changes `kind` or `html_type`, inherited `options`, `file`, `formula` or `aggregate` that no longer apply are dropped, as the editor does. If the patch itself sets one of them for a shape it does not fit, the change is reported as `options.not_applicable`, `file.not_applicable`, `formula.not_applicable` or `aggregate.not_applicable`. The mapper also prunes any config family the final kind and html_type no longer use. The call parks and returns the `ChangePlan` (illustrative; `id` and rows depend on what is stored):

```json
{
  "ok": true,
  "status": "confirmation_required",
  "operation": "update_entity",
  "plan": [
    {
      "name": "Student",
      "id": 42,
      "breaking": true,
      "rows": [
        { "kind": "attribute", "action": "added", "name": "Phone", "html_type": "tel", "breaking": false },
        { "kind": "attribute", "action": "modified", "name": "Email", "field": "visibility", "before": { "admin": true, "member": true, "public": true }, "after": { "admin": true, "member": true, "public": false }, "breaking": false },
        { "kind": "attribute_removed", "action": "removed", "name": "Fax", "breaking": true }
      ],
      "omitted_rows": 0
    }
  ],
  "next_step": "Wait for the administrator to review and apply the plan. Do not claim the change is applied."
}
```

On approval, `perform` re-reads the catalog document, applies the same change set and writes through `Persist` with `replace: true`: the attribute and group lists are written as given, computed fields go back to their original positions, and associations keep their bridge ids. `data` has `updated` (`name`, `slug`, `version`) and `bridges`.

The 16 change ops. Items are addressed by slug, group key or related entity name, never by array index; `set` is a JSON Merge Patch (RFC 7396), where `null` clears a field and arrays replace wholesale.

| Op | Fields | Editor equivalent | Behaviour |
| --- | --- | --- | --- |
| `set_details` | `display_label`, `description`, `extends` | Basic information card | Changes only the keys sent; `extends: null` removes the base model. |
| `set_settings` | `icon`, `color`, `default_values` | — | `default_values` replaces the whole defaults map. |
| `add_attribute` | `attribute`, `position` | Add attribute | Appends, or inserts `before` or `after` an attribute slug. |
| `update_attribute` | `slug`, `set` | Edit attribute | Merge-patches the public form of the attribute; omitted keys keep their stored values and the slug never changes. Changing `kind` or `html_type` drops options, file settings, formula or aggregate that no longer apply; setting one explicitly gives `<field>.not_applicable`. `set.owner` is the replacement owner flag (`false` clears it). |
| `remove_attribute` | `slug` | Remove attribute | Refused with `attribute.in_use` while a sibling formula references the slug. Its entry in `settings.default_values` is removed with it. |
| `move_attribute` | `slug`, `to_group`, `position` | Drag a row | `to_group: null` ungroups the attribute. |
| `add_group` | `group`, `position`, `attributes` | New group | Inserts the group; `attributes` are created in it and appended. |
| `update_group` | `key`, `set` | Edit group | Merge-patches `name`, `description`, `icon`, `color`. The key never changes. |
| `remove_group` | `key`, `move_attributes_to` | Delete group | Moves the group's attributes to `move_attributes_to`, or ungroups them. |
| `reorder_groups` | `order` | Drag a group | Must list every existing key exactly once, otherwise `group.order_mismatch`. |
| `add_association` | `association` | Add association | Adds the association; the write creates its bridge entity. |
| `update_association` | `related_entity`, `set` | Edit association | Changes `display_field` or `display_field_label`; `bridge_attributes` replaces the whole bridge field list. |
| `remove_association` | `related_entity` | Remove association | The write soft-deletes the bridge entity, which holds the link rows. |
| `add_bridge_attribute` | `related_entity`, `attribute`, `position` | Association attribute modal | Adds an input field to the bridge. |
| `update_bridge_attribute` | `related_entity`, `slug`, `set` | Association attribute modal | Same merge rules as `update_attribute`. |
| `remove_bridge_attribute` | `related_entity`, `slug` | Association attribute modal | Removes the bridge field. Refused with `attribute.in_use` while a computed attribute aggregates through this association (direction `source`) and reads the slug as its source or filter attribute. |

A `position` names exactly one of `before` or `after`; an unknown target gives `change.position_target_not_found`.

**Scope rules.** `SemanticValidator.locate` resolves every target by name inside the customer:

- an active, non-bridge, customer-owned entity is editable;
- the same name in the trash gives `entity.name_in_trash` (`ask_user`);
- a bridge entity or a shared entity (`customer_id` NULL) gives `entity.not_editable` (`blocked`);
- anything else gives `entity.not_found` with `candidates`.

`create_entity` also refuses a name used twice in the request (`entity.duplicate_in_request`), a name starting with `assoc_` (`entity.name_reserved`), an existing name (`entity.already_exists`) or a name in the trash, and new entities beyond the quota (`quota.exceeded`, from `Billing::Quota.for(customer).allow?("entity", by:)`). `Persist` checks the quota again at write time with `Billing::Quota::Guard`. Its `perform` checks the names again under the customer lock and writes with `create_only: true`, so a name another writer took after validation is refused with `entity.already_exists` instead of being updated. `update_entity` refuses a second change set for an entity already in the request (`entity.duplicate_in_request` at `/updates/<i>/entity`).

**Person entity.** A business domain has at most one person entity (Student, Patient, Volunteer), and it is the primary entity. `EntityDefinitions::Capabilities::PERSON_MODEL` (`Authentication::User`) is the base model it extends; `Capabilities.person_model(customer_id)` returns it only when the tenant may extend it. On `create_entity`, the first entity with `extends: "Authentication::User"` is the person entity:

- a second entity extending it in the same call is refused with `extends.person_not_unique` at `/entities/<i>/extends`;
- the person entity must be at index 0, else `entity.person_not_first` at `/entities/<i>`;
- the call's links are declared on it, so another new entity whose `associations` name it is refused with `association.person_not_primary` at `/entities/<i>/associations/<j>/related_entity`. A link to a person entity that already exists in the catalog is allowed.

Every `create_entity` entity with `extends` also refuses an attribute whose slug is a column of that base model (`attribute.reserved_by_base_model`), the same columns the entity editor reserves through `base_model_fields`. Both read `Capabilities.base_model_fields(customer_id, class_name)`. `update_entity` applies the same column check to the updated entity; the person-entity ordering and uniqueness checks above are create-only. The slugs `id` and `user_id` are reserved on every entity (`attribute.reserved_slug`).

**Owner flag.** `owner: true` on a reference attribute marks which person a row belongs to (`People::Ownership`). `EntityDefinitions::Api::SemanticValidator#validate_owner_flags` reports:

- `attribute.owner_invalid` (`%{slug}`): "The attribute %{slug} can mark the record's owner only when it references a person entity." Pointer is the attribute's `owner` field. The same cases as the editor: a non-reference, a non-person target, any attribute of a person entity, or a `bridge_attributes` field (bridges infer; Enrollment is `:owned` because `bridge_property_schema` already has a single person reference).
- `entity.owner_multiple` (`%{name}`): "The entity %{name} marks more than one attribute as the owner. Keep one."

`owner: false` and a missing key are equivalent. See [Person linking](person-linking) for kinds and [Entity builder](entity-builder) for the editor switch.

**Editor parity.** The mapper writes what the entity editor would:

- For `select`, `radio` and `checkbox` with static or constant options, any authored `inclusion` rule is replaced by one that lists the option values (`value`, else the label).
- A static value may be a bare string or `{label, value, default}`; it is stored as the full object.
- A calculated field is read-only with computed storage; a computed field is also forced to `html_type: "number"`.
- A rule applies only where the field is visible: `validator_apply` is stored as the intersection of `rules_apply_to` and `visible_to`.
- A new attribute without `access` is visible to, and validated for, every audience, because the editor writes all three flags. A `file` object always stores `multiple` (default `false`), and `AttributeGrouper` fills a missing or unknown group icon or colour with `folder` or `slate`.

### Domain, journey, page and build operations

These five operations let the assistant finish a sub-system once its entities exist. Every admin of the customer may call them (none overrides `available?`); `Authorization` refuses members and other tenants. Their contracts and messages say "form processing", never "flowchart", because tenant admins read what the model repeats from them.

| Operation | Confirmation | What it does | `data` on success |
| --- | --- | --- | --- |
| `create_domain` | never | Creates a customer-owned `EntityDomain` through `EntityDomains::Activities::Save`; `create_entity` needs an existing domain. A taken name is `entity_domain.already_exists`. | `domain`: `name`, `description`, `color` |
| `list_journey_options` | read-only | Lists the `EntityDomains::JourneyPlanner` candidates for one domain (`Journeys::DomainCandidates`). | `domain`, `journeys` (rows below) |
| `generate_journeys` | never | Builds the chosen options with `Journeys::Activities::Generate`, creating or reusing their pages, and launches each one whose launch checks pass. | `domain`, `journeys`: `key`, `name`, `status`, `reused`, `audiences`, `pages` (action keys), `launch_blockers` |
| `set_page_processing` | never | Sets the processing a customer-owned page runs on submit, through `Pages::Activities::BindFlowchart`. | `page`, `audience`, `processing` |
| `start_subsystem_build` | never | Records an `AiAssistant::SubsystemBuild` and enqueues `AiAssistant::SubsystemBuildJob`, which generates the journeys, writes and binds the processing, launches what is ready and reports in the conversation. | `build`, `status`, `domain`, `journeys`, `processing` (names), `warnings` |

**Journey options.** A `list_journey_options` row has:

- `key`, for example `create-12`, which `generate_journeys` and `start_subsystem_build` take;
- `kind`: `create` (an admin creates a record and the rows that hang off it), `record` (an admin adds one kind of related row from an existing record's page), `member` (a signed-in member adds records they own) or `public` (a visitor signs up);
- `audience`, `name`, `starts_with`, `adds` (the step labels), `continues_to` and `generated`.

`generate_journeys` takes `domain`, 1 to 10 `journeys` keys and `launch` (default `true`). An unknown key is `journey.option_not_found` with `candidates`; a refusal from the generator is `journey.generation_failed` (`blocked`). A key generated before is reported with `reused: true`, and a draft is launched if its checks now pass. A `public` option stays a draft while the tenant's sign-up setting is off (`operations.journeys.sign_up_disabled` in `launch_blockers`).

**Page processing.** `set_page_processing` takes `page` (an action key `generate_journeys` reported), `audience` and `processing`, a name: the customer's own processing, which the assistant's `list_catalog` returns under `processing`, or a shared one such as "Save page record". The customer's own wins a name clash. The codes are `page.not_found`, `processing.not_found` (with `candidates`) and `page.processing_refused` when `Pages::ProcessingContract` refuses. The refusal's `errors` detail depends on the actor:

- the platform owner gets `BindFlowchart::Result#errors`, the code generator's reasons, which name the flowchart and its steps;
- anyone else gets `#reasons`: "This page can't use that form processing." (`maint_core.errors.validations.page_processing_unavailable`), the offline message, or `Flowcharts::Compatibility.errors`.

**Sub-system build.** `start_subsystem_build` takes `domain`, 1 to 10 unique `journeys` keys and up to 5 `processing` needs, each `{name, journey, step, purpose, values: [{label, value}]}`; `step` is optional. `validate` stops at the first group that fails:

1. `subsystem.conversation_required` without a conversation of this customer, and `subsystem.build_active` while the conversation has a running or waiting build (both `blocked`);
2. `entity_domain.not_found`;
3. `journey.option_not_found`;
4. per need: `subsystem.journey_not_chosen`, `subsystem.signup_processing` (a `public` option keeps the shared sign-up flowchart), `subsystem.step_not_found` (`step` must be a label from `adds`; omitted means the option's first page), `subsystem.duplicate_processing`, and `subsystem.processing_name_taken` (a customer-owned or shared flowchart already has the name);
5. `subsystem.preflight_blocked` (`blocked`), one per `AiAssistant::Subsystems::Preflight` blocker: the page quota, or user accounts that can't be enabled for a `member` option.

`perform` checks again for an active build, stores the blueprint (domain id, keys, and each need's resolved `page_index`, `audience` and entity) and the pre-check warnings, then enqueues the job; `enqueue_after_transaction_commit` holds it until the write commits. The build itself is described under *Sub-system builds* in [AI assistant](ai-assistant).

### Adding a new operation

Example: a `create_flowchart` operation.

1. **Contract.** Add `app/services/operations/schemas/create_flowchart.json`. The root needs `title`, `description`, `type: "object"`, `additionalProperties: false`, `required`, a `description` on every property and enum value, and valid `examples`. Use `"x-vocabulary": "<slot>"` for any registry-backed enum instead of a literal list, and put definitions shared by several operations in a `<area>.defs.json` file:

   ```json
   {
     "title": "Create flowchart",
     "description": "Create one customer-owned flowchart. Applies immediately.",
     "type": "object",
     "additionalProperties": false,
     "required": ["name"],
     "properties": {
       "name": { "type": "string", "minLength": 1, "maxLength": 100, "description": "Unique flowchart name in this tenant." },
       "first_step": { "type": "string", "x-vocabulary": "step_actions", "description": "Palette action the flowchart starts with." }
     },
     "examples": [{ "name": "Enrol student", "first_step": "build_contract" }]
   }
   ```

2. **Vocabulary.** If the contract has slots, add a class such as `FlowchartDefinitions::Api::Vocabulary` whose `self.resolve(name, context)` returns `{values:, descriptions:}` (or an Integer for `x-vocabulary-max`) read from the registry, here `FlowchartDefinitions::Palette.canonical_keys`, and raises `ArgumentError` for an unknown name.

3. **Class.** Add `app/services/operations/create_flowchart.rb`:

   ```ruby
   module Operations
     class CreateFlowchart < Base
       key "create_flowchart"
       version 1
       title "Create flowchart"
       summary "Create one customer-owned flowchart. Use for new flowcharts only. Applies immediately."
       schema "create_flowchart.json"
       vocabulary FlowchartDefinitions::Api::Vocabulary
       annotations destructive: false, confirmation: :never

       register!

       def self.available?(context)
         FlowchartVisibility.allowed?(context.actor)
       end

       def validate(input)
         # Cross-field, reference and quota rules -> [Operations::Violation, ...]
       end

       def perform(input)
         # Call the domain writer; return Outcome.succeeded(operation: self.class.key, data:, effects:)
         # or Outcome.invalid(...) for a refused write.
       end
     end
   end
   ```

   `perform` delegates to the existing domain writer and never reimplements it. For a destructive change, declare `destructive: true, confirmation: :always` and implement `plan`, `snapshot` and `stale?` so the administrator approves a reviewable plan and a stale approval is refused. If the input carries merge patches, declare `insert_defaults false`. `available?` keeps the tool away from callers who must not see it; flowcharts are visible to the platform owner only.

4. **Messages.** Add each new code under `operations.violations.<area>` in `config/locales/operations_<area>.en.yml` and `.zh-CN.yml`, with the same keys and the same `%{...}` variables in both locales, and pass every variable in `details`. Extend the parity check in `contract_lint_spec.rb` to the new files.

5. **Specs.** The contract lint already covers every registered operation. Add an operation spec that goes through `Operations::Activities::Execute.call`: success, every violation code, `forbidden` for a member and for another tenant's admin, tenant isolation, idempotent replay and `dry_run`. For a parked operation also cover `Confirm`: approval, `conflict` after a concurrent edit, and `operation.version_changed`.

6. **Assistant integration.** From the registry alone, the operation is offered as a native tool (and listed for JSON-convention vendors), validated, triaged, retried within the budget, made idempotent, parked and approved, and audited. Do not change `OperationTool`, `Execute`, `Confirm`, `PendingConfirmation` or the audit table. Add only what is specific to the feature:
   - **Prompt guidance:** a domain document and section under `app/services/ai_assistant/assistant/prompt/` explaining how to model the feature, with `{"tool": …, "arguments": …}` examples that `tool_examples_contract_spec.rb` validates against the schema. List it together with `Sections::OperationTools` in the prompt mode that handles the feature in `Prompt::Composer::OUTLINES`; the operations section ships in the `entity` mode only.
   - **Plan rows**, for a parked operation: `plan(input)` returns `[{ "name", "breaking", "rows" => [{ "kind", "action", "name", "field", "before", "after", "breaking" }] }]`. Add each new row kind to `AiAssistant::ProposedChangesComponent::ACTIONS` with `ai_assistant.assistant.plan.rows.<kind>_<action>` in both locales; an unknown row falls back to the entity-worded `plan.rows.other` label ("Another change to this entity").
   - **Progress label** (optional): map the key to a progress step in `Tools::Session`; today only the entity operations report the entity step.

   Results of a non-entity operation reach the admin through the model's final reply, and approvals answer with the generic `operation_applied` or `operation_stale` text. Page generation and the entity change list run for `Tools::Session::ENTITY_OPERATIONS` only.

## Where to pay attention

:::attention
An edited schema file takes effect at once, including for proposals that are already parked: `Confirm` revalidates them against the current file. Bump `version` when a change alters what an input means, so `Confirm` refuses proposals parked under the old contract with `operation.version_changed`.
:::

:::attention
An operation whose input carries merge patches must declare `insert_defaults false`. `update_entity` does, so `{"access": {"visible_to": {"public": false}}}` changes only `public` and every omitted key keeps its stored value. Defaults for what a change set creates come from the mapper instead: a new attribute without `access` gets every audience flag `true`, `file` always stores `multiple` (default `false`), and `AttributeGrouper` fills a missing group icon or colour with `folder` or `slate`.
:::

:::attention
Give every `$ref` position its own `description`. The lint treats each named property as a documented position, and in the projection a description beside the `$ref` replaces the target's. Descriptions, titles and summaries are model-facing English and are not translated.
:::

:::attention
`conflict.version_changed` arrives with two statuses. When the proposal is made, an `expected_version` mismatch is a `validate` violation, so the outcome is `invalid` with resolution `refresh`. On approval that check is skipped, and `Confirm` returns `conflict` from `stale?` under the lock or from any `conflict.*` violation found while revalidating; the assistant answers with its "changed since proposed" reply. Branch on `code` or `resolution`, not only on `status`.
:::

:::attention
`UpdateEntity#snapshot` pins `current_line_head_version_id` by entity name. An edit that adds no definition version, such as a display label change, does not make a proposal stale; a rename does. `perform` re-reads the catalog document and applies the change set again, so the write is based on the head at approval time, not the document the model saw.
:::

:::attention
Only errors raised by `around_write` itself, such as `GenerationWriteGuard::Rejected`, propagate. A `StandardError` from validation or planning becomes `failed`. Inside the lock, a `StandardError` from `perform`, including a return value that is not an `Outcome`, becomes `failed` or `invalid` and rolls back. `NotImplementedError` (an operation without `perform`) is not a `StandardError`: it escapes `Execute.call` and leaves no audit row. Keep `requires_new: true` on the customer lock. The assistant's guard already holds a transaction, and `ActiveRecord::Rollback` inside a joined transaction undoes nothing.
:::

:::attention
No `operation_invocations` row is written for a replay, `idempotency.key_reused`, `operation.unknown`, a read-only operation such as `get_entity`, or a dry run. Only a succeeded or parked call keeps its idempotency key, so repeating a rejected or failed call runs it again instead of replaying the rejection.
:::

:::attention
Every `%{name}` in an `operations.violations.*` message must be in the violation's `details`; a missing one raises `I18n::MissingInterpolationArgument` while the tool payload is built. Array details are joined with ", ". Hash details are not interpolated, and values that are not JSON-safe are left out of `as_json`.
:::

:::attention
Entity rules that surprise: the quota is checked at validation and again at write; names starting with `assoc_` belong to bridge entities; `remove_attribute` is refused while a sibling formula uses the slug, and `remove_bridge_attribute` while an aggregate through that association reads it; and for selection controls with static or constant options, the mapper replaces an authored `inclusion` rule with the option values.
:::

:::attention
In the assistant, `Tools::Session::MAX_ATTEMPTS` (3) counts rejected calls of an operation in one turn. Successful calls do not count, including `get_entity` reads and a parked `update_entity`, and only a rejected payload carries `attempts_remaining`. After three rejections the next call gets `attempts.exhausted` without running. After `update_entity` parks, any other call to an operation with `confirmation: :always` gets `proposal.already_pending`, even for another entity. See [AI assistant](ai-assistant).
:::

:::attention
Tenant admins read what the model repeats from `set_page_processing`, `start_subsystem_build` and `list_catalog`, so their summaries, contracts and violation messages never say "flowchart". Shared defs count: `entity.defs.json` is part of `create_entity`. `spec/services/ai_assistant/assistant/tools/session_spec.rb` fails if any tool a tenant admin receives contains the word, and `prompt_builder_spec.rb` fails if their entity prompt does. Detailed binding reasons go to the platform owner only.
:::

## Key code

```ruby
# app/services/operations/create_entity.rb
key "create_entity"
version 2
title "Create entity"
summary "Create one or more related customer-owned entities atomically. Use for new entities only. Associations, option sources, and aggregates may name other entities in the same call. Applies immediately."
schema "create_entity.json"
shared_defs "entity.defs.json"
vocabulary EntityDefinitions::Api::Vocabulary
annotations destructive: false, confirmation: :never

register!
```

```ruby
# app/services/operations/activities/execute.rb
def self.perform_atomically(context:, operation_key:)
  outcome = nil
  context.around_write.call do
    context.customer.with_lock(requires_new: true) do
      outcome = Current.with_customer(context.customer) { rescue_into_outcome(operation_key) { yield } }
      raise ActiveRecord::Rollback unless outcome.ok?
    end
  end
  outcome
end
```

```ruby
# app/services/operations/activities/confirm.rb
def apply(ctx, invocation:, context:, instance:, normalized:, operation_class:, **)
  outcome = Execute.perform_atomically(context: confirmed_context(context), operation_key: operation_class.key) do
    if instance.stale?(invocation.snapshot)
      Outcome.conflict(operation: invocation.operation, violations: [Violation.new(code: "conflict.version_changed")])
    else
      instance.perform(normalized)
    end
  end

  finish_row!(invocation, context, outcome)
  outcome.invocation = invocation
  ctx[:outcome] = outcome
  outcome.ok?
end
```

```ruby
# app/services/operations/schema.rb
def apply_vocabulary_slot!(schema)
  source = vocabulary_source(schema["x-vocabulary"])
  unless source.is_a?(Hash)
    raise ArgumentError, "vocabulary #{schema['x-vocabulary'].inspect} must resolve to values/descriptions"
  end

  values = Array(source[:values] || source["values"]).dup
  descriptions = (source[:descriptions] || source["descriptions"] || {}).stringify_keys
  values << nil if nullable?(schema) && !values.include?(nil)
  schema["enum"] = values
  schema["x-enum-descriptions"] = descriptions
end
```

```ruby
# app/services/operations/violation.rb
def default_resolution(code)
  name = code.to_s
  return "blocked" if name.start_with?("permission.", "quota.")
  return "refresh" if name.start_with?("conflict.")

  "fix_payload"
end
```

```ruby
# app/services/operations/activities/confirm.rb (revalidate)
instance = operation_class.new(context: confirmed_context(context))
if instance.stale?(invocation.snapshot)
  outcome = Outcome.conflict(operation: invocation.operation, invocation: invocation,
                             violations: [Violation.new(code: "conflict.version_changed")])
  finish_row!(invocation, context, outcome)
  ctx[:outcome] = outcome
  return false
end

semantic = Array.wrap(instance.validate(normalized))
if semantic.any?
  builder = semantic.any? { |violation| violation.code.start_with?("conflict.") } ? :conflict : :invalid
  outcome = Outcome.public_send(builder, operation: invocation.operation, violations: semantic, invocation: invocation)
  finish_row!(invocation, context, outcome)
  ctx[:outcome] = outcome
  return false
end
```

```ruby
# app/services/operations/activities/execute.rb
def self.replayable?(outcome)
  outcome.nil? || outcome.ok?
end
```

```ruby
# app/services/operations/outcome.rb
def next_step(attempts_remaining: nil)
  interpolations = { operation: operation }
  return I18n.t("operations.guidance.#{status}", **interpolations) unless status == "invalid"

  resolutions = violations.map(&:resolution).uniq.select { |item| Violation::RESOLUTIONS.include?(item) }
  text = if resolutions.empty?
    I18n.t("operations.guidance.invalid", **interpolations)
  else
    resolutions.map { |item| I18n.t("operations.guidance.#{item}", **interpolations) }.join(" ")
  end
  return text if attempts_remaining.nil?

  text + I18n.t("operations.guidance.attempts_remaining", attempts: attempts_remaining)
end
```

Related: [Entity builder](entity-builder), [AI assistant](ai-assistant), [Module framework](module-framework), [Billing](billing).
