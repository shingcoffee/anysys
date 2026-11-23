# Operations API — implementation plan

Design (read first): `docs/operations-api-design.md`. This plan fixes names, file ownership,
interfaces and acceptance criteria. Work packages (WP) in the same phase run in parallel and
own disjoint files; a WP must not edit a file owned by another WP. If a WP needs a change in
a file it does not own, it reports that in its RETURN block instead of editing.

## Ground rules (every WP)

- Ruby 3.2 / Rails 8.1. Multi-step flows are Trailblazer Railway activities. No backward
  compatibility shims or aliases for removed classes.
- I18n hard rule: every user-visible string (violation messages, `next_step` guidance,
  plan row labels, apply errors) goes through `I18n.t` with matching `en` and `zh-CN` keys.
  **Exception, by design:** JSON Schema `title`/`description` text and vocabulary value
  descriptions are API contract documentation read by the model — English only, like the
  existing prompt documents under `app/services/ai_assistant/assistant/prompt/documents/`.
- Multi-tenancy: every query is scoped by the context customer. `OperationInvocation` has
  `customer_id`.
- Specs: RSpec, TDD. Run only your WP's specs; never claim a pass without real output.
- Do not commit. Do not touch `app/services/page_layout_templates/templates/`.

## Shared names (fixed)

| Name | Kind |
| --- | --- |
| `Operations` (`app/services/operations.rb`) | Registry: `extend PluginRegistry.build(label: "operation", dir: "app/services/operations", defaults: false)` → `Operations.for(key)`, `.keys`, `.all`. Framework files in the same directory are constantized harmlessly by `ensure_loaded!`. |
| `Operations::Base` | Operation superclass + DSL. |
| `Operations::Context` | `Struct(:customer, :actor, :channel, :conversation, :generation, :idempotency_key, :dry_run, :confirmed, :around_write, keyword_init: true)`. `channel` ∈ `assistant api system`. `around_write` is a callable taking a block (default: yields). |
| `Operations::Schema` | Loads + resolves a schema for a context; validates. |
| `Operations::SchemaProjection` | Provider-safe tool parameter rendering. |
| `Operations::SchemaLint` | Contract completeness checks. |
| `Operations::Violation` | `Struct(:pointer, :code, :details, :resolution)`. |
| `Operations::Pointer` | RFC 6901 helpers: `join(*tokens)`, `escape(token)`. |
| `Operations::Outcome` | Result value + tool / problem renderings. |
| `Operations::Authorization` | `allowed?(actor:, customer:)`. |
| `Operations::Activities::Execute` / `Confirm` | Pipelines. |
| `OperationInvocation` | Audit + parked proposals model. |
| `EntityDefinitions::Api::Vocabulary` | Registry-backed enum sources + English descriptions. |
| `EntityDefinitions::Api::Mapper` | Public vocabulary ⇄ stored definition. |
| `EntityDefinitions::Api::ChangeSet` | Applies `update_entity` changes to a stored-shape document. |
| `EntityDefinitions::Api::SemanticValidator` | Cross-field / reference rules → violations. |
| `Operations::CreateEntity` / `UpdateEntity` / `GetEntity` | Keys `create_entity` / `update_entity` / `get_entity`. |
| `AiAssistant::Assistant::Tools::OperationTool` | One `RubyLLM::Tool` adapter for any operation. |
| `AiAssistant::Assistant::ReplyEnvelope` | Parses the final `{"intent","reply"}` envelope (replaces the entity `Extraction`). |

---

## Phase A (parallel)

### WP-A1 — Framework core (anysys-backend-developer)

Owns (create): `app/services/operations.rb`; `app/services/operations/{base,context,schema,
schema_projection,schema_lint,violation,pointer,outcome,authorization}.rb`;
`app/services/operations/activities/{execute,confirm}.rb`; `app/services/operations/schemas/`
(directory, `.keep` only); `app/models/operation_invocation.rb`;
`db/migrate/20261015120000_create_operation_invocations.rb` (+ `db/schema.rb` via migrate);
`config/locales/operations.en.yml`, `config/locales/operations.zh-CN.yml`;
`spec/services/operations/**` (framework specs only), `spec/models/operation_invocation_spec.rb`,
`spec/factories/operation_invocations.rb`, `spec/support/operations/fake_operations.rb`.

**`Operations::Base` DSL** (class methods; readers when called without args):
`key`, `version` (default 1), `title`, `summary`, `schema(file)`, `shared_defs(*files)`,
`vocabulary(mod)` (object responding to `resolve(name, context)` → `{ values: [...],
descriptions: { value => text } }` for enum slots or an Integer for `x-vocabulary-max`),
`annotations(read_only: false, destructive: false, idempotent: false, confirmation: :never)`,
`read_only?`, `destructive?`, `idempotent?`, `confirmation` (`:never` | `:always`), `register!`
(→ `Operations.register(self)`), `available?(context)` (default true),
`input_schema(context)` → resolved `Operations::Schema`,
`tool_definition(context)` → `{ name:, description:, parameters: }` where `description` is
`summary` and `parameters` is the projection.
Instance: `initialize(context:)`, `validate(input) → []`, `plan(input) → nil`,
`snapshot(input) → nil`, `stale?(snapshot) → false`, `perform(input)` (abstract; returns
`Operations::Outcome`).

**`Operations::Schema`**
- Reads `app/services/operations/schemas/<file>`; merges each `shared_defs` file's `$defs`
  into the schema's `$defs` (operation-local `$defs` win); sets `$id` to
  `urn:anysys:operation:<key>:v<version>` and `$schema` to 2020-12.
- Resolves slots recursively: `x-vocabulary: name` → `enum` (+ `null` appended when `type`
  includes `"null"`) and `x-enum-descriptions`; `x-vocabulary-max: name` → `maximum`.
  Unknown slot name raises `ArgumentError` (a contract bug, not a runtime violation).
- `#document` (resolved Hash), `#validate(input)` → `[violations, normalized]`: deep-dup +
  deep-stringify input; `JSONSchemer.schema(document, insert_property_defaults: true)`;
  map every json_schemer error to a Violation: `pointer` = error `data_pointer` (root → `""`),
  `code` from the failing keyword (`required` → `schema.required` with
  `details: { property: }` and pointer extended by the missing property;
  `enum`/`const` → `schema.enum` with `allowed`; `type` → `schema.type` with `expected`;
  `additionalProperties`/`unevaluatedProperties` → `schema.unknown_property` with pointer of
  the unknown key and `candidates` from the sibling property names; `pattern`, `format`,
  `minLength`, `maxLength`, `minItems`, `maxItems`, `minimum`, `maximum`, `uniqueItems`,
  `minProperties`, `maxProperties` → `schema.<snake_case>` with `expected`; anything else →
  `schema.invalid`). For `anyOf`/`oneOf`/`if-then` failures report the most specific nested
  error (deepest `data_pointer`), not the wrapper. De-duplicate by (pointer, code). Cap 25.
- Cache resolved documents per (operation, version, vocabulary digest) — the digest is
  computed from the resolved slot values so tenant-dependent enums never leak across tenants.

**`Operations::SchemaProjection`** — `call(document, budget: 32_000)` → Hash: inline local
`$ref`s (cycle-safe), drop `$schema`/`$id`/`$defs`/`$comment`/`examples` and every `x-*` key,
fold `x-enum-descriptions` into `description` as ``"… Allowed values: `a` — text; `b` — text."``,
remove `if`/`then`/`else`/`allOf`/`not`/`dependentRequired` while appending each removed
conditional's `description` to the parent `description`, rewrite `oneOf` → `anyOf`.
If the JSON exceeds `budget` bytes, raise `Operations::SchemaProjection::TooLarge` (lint
catches it).

**`Operations::SchemaLint`** — `call(operation_class, context)` → array of problem strings
(empty = clean): `title`/`summary` present; schema `description` present; every property
schema (recursively, including `$defs`, array `items`, `anyOf` branches) has a
`description`; every resolved `enum` has an `x-enum-descriptions` entry for every non-null
value; every `allOf` conditional has a `description`; every object schema declares
`additionalProperties: false`; every `examples[]` entry validates; projection is within
budget.

**`Operations::Violation`** — `RESOLUTIONS = %w[fix_payload ask_user refresh blocked]`;
default resolution by code (`permission.*`, `quota.*` → `blocked`; `conflict.*` → `refresh`;
others → `fix_payload`) unless given. `#message` → `I18n.t("operations.violations.#{code}",
**interpolations)` where interpolations are the scalar `details` (arrays joined with ", ");
missing key falls back to `operations.violations.generic` with `code`. `#as_json` →
`{ "pointer", "code", "message", "resolution" }` merged with JSON-safe `details`.
Helper `Violation.candidates(word, dictionary)` → up to 3 suggestions via
`DidYouMean::SpellChecker` (+ case-insensitive exact match first).

**`Operations::Outcome`** — `Struct(:status, :operation, :data, :plan, :violations,
:effects, :invocation, :replayed, keyword_init: true)`; constructors `succeeded`,
`confirmation_required`, `dry_run`, `invalid`, `conflict`, `forbidden`, `failed`; `ok?`
(succeeded / confirmation_required / dry_run); `http_status` (200/202/200/422/409/403/500);
`to_tool_payload(attempts_remaining: nil)` → Hash `{ "ok", "status", "operation",
("data" | "plan" | "errors"), "attempts_remaining"?, "next_step" }` where `next_step` is
`I18n.t("operations.guidance.<status>")` and, for `invalid`, built from the resolutions
present (`operations.guidance.fix_payload` / `ask_user` / `refresh` / `blocked`, joined),
interpolating `operation` and `attempts`; `to_problem` → RFC 9457 Hash `{ "type" =>
"urn:anysys:problem:<status>", "title" => I18n.t("operations.problems.<status>"), "status"
=> http_status, "detail", "operation", "errors" }`.

**`Operations::Authorization.allowed?(actor:, customer:)`** — `actor&.active?` and
(`actor.platform_owner?` or (`actor.admin?` and `actor.customer_id == customer.id`)). Mirror
`AiAssistant::Assistant::ExecutionPolicy#authorized_user?`; members always false.

**`Operations::Activities::Execute.call(operation:, input:, context:)` → Outcome**
(Railway; `operation` is a class or key). Steps: resolve (unknown key or class not
inheriting `Base` → invalid `operation.unknown`, `details: { available: keys }`); authorize
(→ forbidden `permission.denied`); replay (non-read-only with `idempotency_key`: same key +
same SHA-256 digest of canonical JSON input → stored outcome with `replayed: true`; same key
+ different digest → invalid `idempotency.key_reused`); validate_schema; validate_semantics
(`operation.new(context:).validate(normalized)`); plan + snapshot; gate (dry_run →
`dry_run` outcome; `confirmation == :always && !context.confirmed` → create invocation
`awaiting_confirmation` and return `confirmation_required` with `invocation`); perform
(`context.around_write { customer.with_lock { ActiveRecord::Base.transaction { Current.with_customer(customer) { perform } } } }`;
`ActiveRecord::RecordInvalid` → invalid `domain.invalid` with `details: { errors: }`; any
other `StandardError` → `failed` `internal.error`, logged with backtrace; let
`AiAssistant::Assistant::GenerationWriteGuard::Rejected` — or any exception class listed in
`Operations::Activities::Execute::PASSTHROUGH` — propagate). record (non-read-only only):
one `OperationInvocation` per call (the `awaiting_confirmation` row is the record for gated
calls), with `duration_ms`.

**`Operations::Activities::Confirm.call(invocation:, context:)` → Outcome** — requires
`invocation.awaiting_confirmation?` and `invocation.customer_id == context.customer.id`
(else invalid `proposal.not_pending`); operation by key, same version (else invalid
`operation.version_changed`); authorize; re-run schema + semantics on `invocation.input`;
under `customer.with_lock`: `stale?(invocation.snapshot)` → conflict
`conflict.version_changed` and mark row `conflict`; else perform (same wrapper as Execute,
with `confirmed: true`) and update the row (`status`, `result`, `violations`,
`confirmed_by` = actor, `confirmed_at`). Also `Operations::Activities::Confirm.supersede!(invocation)`
→ `superseded` (used when a newer proposal replaces it).

**`OperationInvocation`** (table `operation_invocations`): `customer_id` (not null, FK,
index), `user_id` (FK `users`, null; `belongs_to :user, class_name: "Authentication::User"`), `operation` (string, not null), `operation_version`
(integer, not null), `channel` (string, not null), `status` (string, not null), `idempotency_key`
(string; unique index on `[customer_id, idempotency_key]` where not null), `input_digest`
(string), `input`, `plan`, `snapshot`, `result`, `violations` (`t.json`, `null: false`
with `{}`/`[]` defaults, as in recent migrations), `conversation_id`,
`generation_id` (bigint, null, indexed; no FK so audit survives deletes), `confirmed_by_id`
(FK users, null), `confirmed_at`, `duration_ms` (integer), timestamps. Index
`[customer_id, operation, created_at]`. Statuses: `awaiting_confirmation succeeded invalid
conflict forbidden failed superseded`. Thin model: associations, status predicates/scopes,
validations of presence/inclusion. Include the project's tenant concern if models use it.

**Locales** `operations.*`: `violations.*` for every framework code (`generic`,
`schema.*`, `operation.unknown`, `operation.version_changed`, `permission.denied`,
`conflict.version_changed`, `idempotency.key_reused`, `proposal.not_pending`,
`proposal.already_pending`, `attempts.exhausted`, `domain.invalid`, `internal.error`,
`quota.exceeded`), `guidance.*`, `problems.*`.

**Specs** — use fake operations defined in `spec/support/operations/fake_operations.rb`
(classes passed to `Execute` directly; do not register them globally): schema resolution
(vocabulary slots, nullable enum, max, unknown slot raises, caching per digest), violation
mapping per keyword including nested `anyOf`/`if-then` and unknown properties with
candidates, defaults insertion, projection (refs inlined, x-* stripped, enum descriptions
folded, conditionals folded, size budget), lint (each rule), outcome payloads (each status;
next_step per resolution), authorization matrix (owner cross-tenant, admin same/other
tenant, member, inactive), Execute (each railway exit; idempotent replay and key reuse;
confirmation gate creates `awaiting_confirmation`; dry run; domain error; around_write
called; passthrough exception propagates), Confirm (happy path, stale → conflict, wrong
customer, wrong status, version changed), model validations/scopes.

Test command: `bundle exec rspec spec/services/operations spec/models/operation_invocation_spec.rb`

### WP-A2 — Entity domain layer (anysys-backend-developer)

Owns: `app/services/entity_definitions/api/vocabulary.rb`, `app/services/entity_definitions/api/mapper.rb`
(create); `app/services/entity_definitions/normalizer.rb`, `definition_assignment.rb`,
`persist.rb`, `catalog.rb`, `assistant/change_plan.rb` (modify);
`spec/services/entity_definitions/api/{vocabulary,mapper}_spec.rb` (create);
`spec/services/entity_definitions/{normalizer,definition_assignment,persist,catalog}_spec.rb`,
`spec/services/entity_definitions/assistant/change_plan_spec.rb` (modify / extend);
locale keys under `ai_assistant.assistant.apply_errors.*` in the existing ai_assistant locale
files only if a new apply error is required.

**`EntityDefinitions::Api::Vocabulary.resolve(name, context)`** — sources (values from the
live registries; English one-sentence description per value; a spec asserts every registry
value has a description so a new registry value without one fails CI):

| Source | Values from |
| --- | --- |
| `html_types` | `HtmlTypeOptions::GROUPED_HTML_TYPES` values (21) |
| `selection_html_types` | `HtmlTypeOptions::SELECTION_TYPES` |
| `attribute_kinds` | `input calculated computed` |
| `rule_types` | `ValidatorRegistry::VALIDATOR_LABELS` keys (16) — description says which value fields the rule takes and which `html_type`s allow it (from `HTML_TYPE_VALIDATORS`) |
| `rule_types_single_value` / `rule_types_range` / `rule_types_pattern` / `rule_types_list` | `ValidatorRegistry::VALIDATOR_CONFIG_TYPES` grouped |
| `group_icons` / `group_colors` | `EntityAttributeGroupOptions::ICONS` / `COLORS` |
| `option_sources` | `static constant entity_entries` |
| `aggregate_functions` | `Entities::ComputedCompiler::FUNCTIONS` |
| `filter_operators` | `Entities::ComputedCompiler::FILTER_OPS` |
| `aggregate_directions` | `source target` |
| `aggregate_max_precision` (max) | `Entities::ComputedCompiler::MAX_PRECISION` |
| `extendable_models` | `ExtendableModelRegistry.for_customer(context.customer.id)` class names; description = label + module |

Also `Vocabulary.descriptions_for(name)` and `Vocabulary.rule_config_kind(type)`.

**`EntityDefinitions::Api::Mapper`** (`Mapper.new(customer:)`; pure apart from lookups):
- `to_definition(spec)` → definition document consumed by `Persist` (keys: `name`,
  `display_label`, `description`, `extended_model`, `icon`, `color`, `default_properties`,
  `attribute_groups` (`key`→`id`), `property_schema`, `associations`
  (`associated_entity_name`, `display_field`, `display_field_label` defaulted to the
  titleized `display_field`, `additional_attributes`)). Only keys present in `spec` are
  emitted (update safety).
- `attribute_to_stored(attr, base: nil)` → stored attribute in the exact shape the entity
  editor writes: `name`, `name_slug` (given or `name.parameterize(separator: "_")`),
  `display_label` (default name), `description`, `html_type`, `validators`
  (`[{ "type", "config" => {…} }]` — match what `entity_form` JS writes; check
  `app/javascript/controllers/entity_form/validator_manager.js`), `visibility`
  (`visible_to`), `validator_apply` (`rules_apply_to` ∩ `visible_to`), `group_id`, `config`
  (static → `{ "source" => "manual", "options" => [{ "label", "value", "default" }] }`;
  constant → `{ "source" => "constant", "constant_id", "constant_name", "options" }` looked
  up among `Constant.where(customer_id: [customer.id, nil])` inside
  `Current.with_customer(customer)`, customer-owned wins on a name tie; entity_entries →
  `{ "options_entity_name", "label_field", "value_field" }` for Persist to resolve; file →
  `{ "accept", "multiple" }`), `type` (`Calculated` + `formula`; `Computed` + computed config
  `{ "target_entity_name", "function", "source_slug", "precision", "filter" =>
  { "slug", "op", "value" }, "bridge_role" => direction }`, `html_type: "number"`,
  `readonly: true`, `storage: "computed"`). Verify each stored key against the editor JS
  and `EntitySchemaValidation` before finalizing. `base:` keeps unmodeled stored keys.
  Validators are `{ "type" }` or `{ "type", "config" => { "value" | "min","max" |
  "pattern" | "values" } }` (`validator_manager.js`). **Editor parity:** for
  select / radio / checkbox with static or constant options, the editor keeps exactly one
  `inclusion` rule whose `values` are the option values (`value`, else `label`) —
  `syncInclusionValidator` in `validator_manager.js`; the mapper does the same, replacing any
  authored `inclusion` rule. Entity-entry option lists get no synced rule.
- `from_entity(entity)` / `attribute_from_stored(stored)` → public vocabulary (inverse;
  round-trip spec: `from(to(x)) == x` for every field), including `version`
  (`display_current_version&.version_number`), `slug`, and per association `bridge_entity`.

**Normalizer** — extend `INPUT_CONFIG_KEYS` with `source constant_id constant_name accept
multiple`, keep option `default`, and add the computed `filter`/`bridge_role` handling the
mapper emits. **ChangePlan** — `attribute_fields` derived from `Normalizer::ATTRIBUTE_KEYS`
(not from `StructureSchema`), so WP-B2 can delete `StructureSchema`.

**Replace mode** — `Persist.call(customer:, entities:, replace: false)`; `Writer` and
`DefinitionAssignment#assign_body(record, definition, replace:)`: when `replace`,
`property_schema` is written exactly as given (input attributes in order; computed
attributes held back with their original index and re-inserted at that index after
resolution), groups replace wholesale (`AttributeGrouper` with `existing_groups: []`),
associations already replace wholesale. Remove `expected_snapshot` and every
`Assistant::IdentitySnapshot` reference from `Persist`/`Writer` (concurrency moves to the
operation layer). Return value unchanged otherwise (`created`, `updated`, `bridges`,
`errors`).

**Computed direction** — `resolve_computed` supports `bridge_role: "target"`: the bridge is
the related entity's association whose target is this entity (see
`Entities::ComputedOptions.reverse_options`). `Catalog#computed_config` echoes
`target_entity_name` for both directions.

**ChangePlan** — `ChangePlan.call(entities:, customer:, replace: false)`; in replace mode
simulate with `replace: true` and emit a removed-attribute row (`{ "kind" =>
"attribute_removed", "name" => <attribute name> }` — follow the existing row shape) for
attributes present before and absent after, flagged breaking; html_type/kind changes stay
breaking.

**Specs** — vocabulary completeness + tenant-scoped extendable models; mapper round trips
for every attribute kind/option source/file/rules/access/computed both directions; stored
shape equals what the editor writes for a representative attribute of each kind; normalizer
keeps new keys; persist replace mode (removal, reorder, group replacement, computed position
preserved, association removal drops bridge link); merge mode unchanged; change plan removed
rows; computed target direction.

Test command: `bundle exec rspec spec/services/entity_definitions`

---

## Phase B (parallel, after A)

### WP-B1 — Entity operations (anysys-backend-developer)

Owns (create): `app/services/operations/schemas/{entity.defs,create_entity,update_entity,get_entity}.json`;
`app/services/operations/{create_entity,update_entity,get_entity}.rb`;
`app/services/entity_definitions/api/{change_set,semantic_validator,merge_patch}.rb`;
`config/locales/operations_entity.en.yml`, `config/locales/operations_entity.zh-CN.yml`
(`operations.violations.entity.*`, `attribute.*`, … codes below);
`spec/services/operations/{create_entity,update_entity,get_entity}_spec.rb`,
`spec/services/operations/contract_lint_spec.rb` (lint every registered operation),
`spec/services/entity_definitions/api/{change_set,semantic_validator,merge_patch}_spec.rb`.

**Schemas** — exactly the vocabulary in design §4.1–4.4. `entity.defs.json` `$defs`:
`entityName`, `slug`, `entitySpec`, `entitySettings`, `attributeGroup`, `attribute`,
`attributePatch`, `bridgeAttribute`, `bridgeAttributePatch`, `rule`, `access`,
`audienceFlags`, `options`, `optionValue`, `file`, `aggregate`, `aggregateFilter`,
`association`, `associationPatch`, `position`, `groupPatch`. Every property described;
enum slots via `x-vocabulary`; conditionals: selection html_type ⇒ `options` required;
`kind: calculated` ⇒ `formula`; `kind: computed` ⇒ `aggregate`; rule kind ⇒ its value
fields; options source ⇒ its fields. Limits: entities 1..10 per call, attributes ≤ 150,
groups ≤ 30, associations ≤ 20, rules ≤ 20, option values ≤ 200, changes 1..100 per entity,
updates 1..10. `update_entity.json`: `updates[]` of `{ entity, expected_version?, changes[] }`;
each change is one of the 16 ops (design §4.3, field names exactly as in that table). The
change item declares the **union** of all op fields in `properties` (each description names
the ops that use it) with `additionalProperties: false`, `required: ["op"]`, and an `allOf`
of `if: {properties: {op: {const: …}}, required: ["op"]}` / `then: {$ref: "#/$defs/<op>Change"}`
branches; each `<op>Change` def lists that op's properties (including `op` as `const`),
its `required`, `additionalProperties: false`, and narrows `set` / `attribute` to the right
def. The projection drops the conditionals, so providers see one flat, fully described
change object. Include 2+ `examples` per schema (they are linted).

**Operations**
- `CreateEntity`: `annotations destructive: false, confirmation: :never`. `validate` →
  `SemanticValidator.for_create`. `perform` → mapper → `Persist.call(customer:, entities:)`;
  data `{ created: [{ name, slug, version, attributes }], bridges: [...] }`; effects
  `[{ kind: "entity", action: "created", name: }]`.
- `UpdateEntity`: `annotations destructive: true, confirmation: :always`. `validate` →
  target checks + `ChangeSet` dry application + `SemanticValidator.for_update` on the
  resulting documents (pointers attributed to `/updates/i/changes/j/...`). `plan` →
  `ChangePlan.call(entities: documents, customer:, replace: true).as_json`. `snapshot` →
  `{ entity name => current_line_head_version_id }`; `stale?` compares. `perform` →
  re-applies the change set to fresh documents and `Persist.call(..., replace: true)`; data
  `{ updated: [{ name, slug, version }], bridges: [...] }`.
- `GetEntity`: `read_only: true`. Input `{ entity }`. Data `{ entity: Mapper#from_entity }`.
  Not found → invalid `entity.not_found` with candidates, resolution `ask_user` when no
  candidate.

**Semantic codes** (namespaced; resolution `fix_payload` unless noted):
`entity.name_reserved`, `entity.already_exists`, `entity.name_in_trash` (ask_user),
`entity.duplicate_in_request`, `entity.not_found` (ask_user if no candidates),
`entity.not_editable` (blocked: bridge / shared / inactive), `attribute.duplicate_name`,
`attribute.duplicate_slug`, `attribute.reserved_slug`, `attribute.not_found`,
`attribute.unknown_group`, `attribute.in_use` (removal referenced by a formula, aggregate
or default value), `rule.not_allowed` (`allowed` = per html_type list), `rule.invalid_range`,
`rule.invalid_pattern`, `options.not_applicable`, `options.duplicate_values`,
`options.constant_not_found` (ask_user if no candidates), `options.entity_not_found`,
`options.field_not_found`, `file.not_applicable`, `formula.not_applicable`,
`formula.unknown_reference`, `aggregate.association_missing`, `aggregate.source_required`,
`aggregate.source_not_found`, `aggregate.source_not_numeric`,
`aggregate.filter_attribute_not_found`, `group.duplicate_key`, `group.duplicate_name`,
`group.not_found`, `group.order_mismatch`, `association.target_not_found` (ask_user if no
candidates), `association.self_reference`, `association.duplicate`,
`association.not_found`, `association.display_field_not_found`,
`association.bridge_slug_conflict`, `settings.unknown_default_key`, `extends.not_allowed`,
`quota.exceeded` (blocked, via `Billing::Quota::Guard.check(customer:, item_key: "entity")`
per new entity), `change.position_target_not_found`.
Every code gets `en` + `zh-CN` messages with the same interpolation variables.

**ChangeSet** — applies ops in order to the stored-shape document from
`EntityDefinitions::Catalog` (lossless, name-based); untouched attributes stay
byte-identical; `update_attribute` = public merge patch (`MergePatch.apply`, RFC 7396) on
`Mapper#attribute_from_stored` then `attribute_to_stored(base: stored)`; slug immutable;
`remove_group` moves attributes to `move_attributes_to` or ungroups; removing an attribute
also drops it from `default_properties`; violations carry the change pointer.

Test command: `bundle exec rspec spec/services/operations spec/services/entity_definitions/api`

### WP-B2 — Assistant integration (anysys-backend-developer)

Owns: `app/services/ai_assistant/assistant/tools/{operation_tool,session}.rb`,
`app/services/ai_assistant/assistant/{turn_processor,pending_confirmation,reply_envelope,
streaming_text,finalizer}.rb`, `app/services/ai_assistant/activities/reply.rb`,
`app/services/ai_assistant/assistant/prompt/**` (sections, documents, `composer.rb`,
`context.rb`), `app/services/ai_assistant/scripted_completion.rb`,
`app/services/ai_assistant/assistant/document_repair.rb` (drop entity mode only),
`config/locales/ai_assistant*.yml` (assistant keys only); deletes
`app/services/entity_definitions/assistant/{processor,extraction,schema_validator,update_policy,identity_snapshot}.rb`,
`app/services/entity_definitions/structure_schema.{rb,json}`, prompt `entity_contract`
section + document, `entity_repair.md`, and their specs; updates every spec under
`spec/services/ai_assistant/**`, `spec/jobs/**`, `spec/requests/**` that exercised the old
protocol (rewrite stale specs to the new behaviour).

- **OperationTool** `< RubyLLM::Tool`: `initialize(session:, operation:)`; `name` =
  operation key; `description` = summary; `params_schema` = projection for the session's
  context; `execute(**args)` → `JSON.generate(session.call(key, args))`.
- **Session**: `initialize(customer:, write_guard: nil, progress: nil, viewer: nil,
  conversation: nil, generation: nil)`; `native_tools` adds one `OperationTool` per
  `Operations.all` entry whose `available?(context)` holds; `call` dispatches operation keys
  to `Execute` with context (`channel: "assistant"`, `around_write:` wrapping
  `GenerationWriteGuard.wrap(write_guard)`, `idempotency_key:
  "gen-#{generation.id}-#{key}-#{digest}"` when a generation exists); progress step
  `:entity` for entity operations; retry budget `MAX_ATTEMPTS = 3` per operation per turn
  (4th call → invalid `attempts.exhausted`, resolution blocked); one parked proposal per
  turn (a second `confirmation_required` → invalid `proposal.already_pending` asking to
  combine into one call — supersede nothing); exposes `operation_outcomes` and
  `pending_proposal` (`{ "kind" => "operation", "operation", "invocation_id",
  "customer_id", "plan" }`). Entity outcomes are NOT appended to `effects` (Finalizer
  derives entity changes from the entity result; appending would duplicate them).
- **ReplyEnvelope**: parses `{"intent": "chat"|"clarify", "reply": "…"}`; tolerant of fenced
  JSON; plain text → chat with the text as reply; any other intent (incl. `apply_entities`)
  → invalid.
- **TurnProcessor**: after the loop, website branch unchanged; otherwise parse the envelope
  and synthesize `EntityTurn` (`Struct(:body, :status, :intent, :applied, :created,
  :updated, :bridges, :proposal)`) from session outcomes: `applied` = any succeeded entity
  operation, `created`/`updated`/`bridges` from outcome data, `proposal` = session pending
  proposal, `status` `complete` (or `failed` when the envelope is invalid). Flowchart
  follow-on only when complete, no proposal, and (applied or intent chat).
  `apply_proposal`: kind `"operation"` → `Operations::Activities::Confirm` on the
  invocation, mapping succeeded → applied entity result with an I18n confirmation body,
  conflict → I18n "changed since proposed, ask again" body, invalid/failed → failed.
  Kind `"entity"` removed; `"flowchart"` unchanged.
- **PendingConfirmation**: `SUPPORTED_KINDS = %w[operation flowchart]`; operation
  proposals validated by invocation existence (`customer_id`, `conversation_id`,
  `awaiting_confirmation`); `retire_open!` also supersedes the invocation; keep conversation
  + customer locks; remove `IdentitySnapshot`.
- **Reply** activity passes `conversation:`/`generation:` into the session.
- **Prompt**: new `Sections::OperationTools` + `documents/operation_tools.md` (how to use
  tools: read with `get_entity` before updating; create vs update; send the full corrected
  call on `fix_payload`; one consolidated question for `ask_user`; `refresh` → re-read;
  `blocked` → explain; never claim an update is applied before approval; one
  `update_entity` call per turn; final reply envelope). For vendors without native tools
  (`Prompt::Context#native_tools?` false) the section also lists each operation's projected
  schema and the JSON `{"tool": …, "arguments": …}` convention. Rewrite
  `entity_authoring.md` / `entity_examples.md` for tools and the public vocabulary (keep
  the domain-modeling guidance); `EntityCatalog` renders `Mapper#from_entity` documents;
  `role.md` keeps "every final reply is one JSON object" and drops `apply_entities`.
- **ScriptedCompletion**: emits `{"tool": "create_entity"/"update_entity", "arguments": …}`
  when the last message is not a tool result, else the final envelope.
- `StreamingText`: update comments/constants referencing the entity `Extraction`.

Test command: `bundle exec rspec spec/services/ai_assistant spec/jobs spec/requests/admin/assistant* spec/services/operations`

---

## Phase C (parallel, after B)

### WP-C1 — Proposed changes UI (anysys-frontend-developer)
Owns `app/components/ai_assistant/proposed_changes_component.{rb,html.erb}`, its spec, and
the `ai_assistant.assistant.plan.*` keys in the ai_assistant locale files. Render
`attribute_removed` rows (breaking style), accept proposals of kind `operation`, remove any
reliance on `EntityDefinitions::StructureSchema`. No JS change expected; if any, keep Vitest
at 100%.
Test: `bundle exec rspec spec/components/ai_assistant/proposed_changes_component_spec.rb`

### WP-C2 — Developer docs (generalPurpose, docs only)
Owns `doc/reference/{en,zh-CN}/operations-api.md` (new), `doc/reference/{en,zh-CN}/ai-assistant.md`,
`doc/reference/{en,zh-CN}/entity-builder.md`, the `DeveloperDocs::Catalog` slug entry, and
an `AGENTS.md` section "Operations API — Adding a New Operation". Locale parity required.
Test: `bundle exec rspec spec/services/developer_docs`

### WP-C3 — QA (anysys-qa-engineer)
Owns new specs only: `spec/integration/operations/**` (assistant turn → tool call → entity
created; update → proposal → apply → persisted; conflict when the entity changes between
proposal and apply; tenant isolation: admin of customer B cannot read/update customer A's
entity through operations, owner can operate on its own context customer only via that
context; member/inactive actors forbidden; idempotent replay inside one generation), and
the e2e fixtures `spec/e2e/support/provider_server.rb`, `spec/e2e/helpers/provider_backend{,.test}.js`,
`spec/e2e/assistant_entity_create.app.spec.js`, `spec/e2e/README.md` (provider returns
OpenAI `tool_calls` for `create_entity`/`update_entity` validated against the exported
operation schemas, then the final envelope).

## Phase D

1. anysys-release-engineer: targeted specs per WP, then the full suite
   (`bin/rails parallel:prepare && bin/rails parallel:spec`), `npx vitest run --coverage`,
   dev server restart + smoke of `/81721200/admin/assistant` and
   `/81721200/admin/maintenance/entities/new`.
2. anysys-tech-lead + anysys-code-reviewer in parallel on the diff; fix findings.

## Acceptance criteria

- Every registered operation passes `Operations::SchemaLint` (every field and enum value
  described).
- `create_entity` can express everything the entity editor can author: attributes of
  every html_type, rules, access, groups, choice lists (static / constant / entity entries),
  file settings, calculated and computed attributes, associations with bridge attributes,
  and the API-only settings (icon, colour, default values).
- A create through the API produces the same stored definition as the same create in the
  editor (spec compares stored attribute shapes).
- `update_entity` supports all 16 change ops, always parks for approval, applies exactly the
  reviewed plan, and rejects stale proposals.
- Invalid payloads never reach the database; every violation has a pointer, code, I18n
  message (en + zh-CN) and resolution.
- The assistant self-corrects `fix_payload` errors within 3 attempts and asks the customer
  only for `ask_user` items.
- Tenant isolation and role checks hold for every operation and for confirmation.
- Developer docs updated in both locales.
