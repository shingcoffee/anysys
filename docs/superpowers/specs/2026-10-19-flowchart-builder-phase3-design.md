# Flowchart builder — Phase 3: step-action platform

Date: 2026-10-19 · Parent: `2026-10-16-flowchart-builder-refactor-design.md` · Handoff:
`docs/2026-10-16-flowchart-builder-remaining-work.md` §4, §7, §8 · Builds on Phase 2 (complete and
verified 2026-10-19: one Railway step per box, `Routes` signals, back-edge loops, `fail :collect_errors`
with `FlowchartRuntime::Errors.collect`, `CANVAS`, B1/B2 merge reads, I/O pins from
`CodeGenerators::IoExtractor` / `BodyAnalyzer`).

Phase 3 turns the step-action catalog into a platform: every action declares its fields once, in Ruby,
and the editor, validation, sample input, emitted code and translations all derive from that
declaration. Failures reach the submitter as translated messages, side effects are not repeated, runs
stay inside the 10 s cap, and the catalog shrinks to non-overlapping actions plus the business actions
customers need. Each requirement has an id and the check that proves it.

Owner decisions (§8 of the handoff, binding): the per-step guard is **removed** and the migration
inserts a Decision before the box; retry exists **only for transport errors on HTTP-style actions the
schema marks idempotent**; `render_response` / `redirect_response` are replaced by **Set submission
outcome**; `raw_sql_query` is **removed**; `circuit_breaker` is **folded into the HTTP actions** as an
advanced option; `publish_event` / `broadcast` are **removed**; the other §4.3 removals and merges are
**approved**; approval / wait-for-person is a **separate project**; **`ctx[:contract]` stays**.

## 0. Baseline (measured on the working tree, 2026-10-19)

Measured with a throwaway probe spec (`TEST_ENV_NUMBER=45`, deleted afterwards), the Node extractors in
`lib/tasks/`, and `rg` over `app/services/code_generators/**`.

| Problem (§4.1) | Measured |
|---|---|
| Registered step-action names / generator classes / distinct editor actions | 102 / 100 / 100 (aliases `API_call`↔`api_call`, `validate`↔`validate_contract`) |
| Actions failing `validate_config({})` | 83 of 102 registered names |
| Actions failing `validate_config(<editor defaults from the JS catalog>)` | 74 of 102 — the editor's own defaults are invalid |
| Hand-written `self.sample_input` | 100 (all valid; a fourth copy of the defaults) |
| Field declarations: editor (JS) vs Ruby `config_schema` | 835 UI fields vs 185 `field` declarations; 92 generators also carry `validate do` blocks |
| Inline `config["x"] \|\|` fallbacks in generators | 138 (plus 108 `fetch_enum`, 114 `safe_ident(config…)`) |
| Optional selects without an empty option | 231 fields in 94 actions |
| Booleans modelled as `"true"`/`"false"` selects | 83 fields in 53 actions |
| Output field names in use | `resultVar` 35, `outputKey` 24, `targetVariable` 17, `targetKey`, `targetField`, `matchedKey`/`unmatchedKey` |
| Input field names in use | `sourceVariable` 19, `sourceKey` 13, `collectionKey` 5, `modelVariable` 4, `dataVariable` 4, `dataKey`, `leftKey`/`rightKey`, … |
| Editor defaults that write `ctx[:result]` | 14 actions (`aggregate_query`, `any_all_none_check`, `base64_encode_decode`, `calculate`, `chunk_collection`, `coalesce_value`, `flatten_collection`, `hash_manipulate`, `map_value`, `math_operation`, `reduce_collection`, `regex_extract`, `string_manipulate`, `type_cast`); 22 generator files hard-code a `"result"` fallback |
| `ctx[:_last_error]` | 81 occurrences in 45 generator files; 37 actions (38 names) emit `rescue … => e; ctx[:_last_error] = e.message; false` in their sample body |
| Sample bodies ending in a literal `true` | 63 of 102 (e.g. `destroy_model` ignores the result of `destroy`) |
| Sample bodies over 12 lines | 21 (max 77: `business_hours_check`) |
| Failure conventions | five: `_last_error` + `false`; raise (e.g. `retry_with_backoff` exhausted, `send_email` invalid recipients); falsy expression (`find_model`); literal `true` regardless; side channels (`ctx[:_signal]` in `deadline_check`, outcome hashes) |
| Timeouts | `BaseGenerator#wrap_with_timeout` wraps the body in `Timeout.timeout(n)` from the step `timeout`, else `config["timeoutSeconds"]`, else `supports_timeout` defaults: `api_call` 30, `acquire_lock` 30, `ai_inference` 60, `download_file` 120, `notify` 30, `send_webhook` 30 s — all above `ActivityTracer::EXECUTION_TIMEOUT_SECONDS = 10` |
| Retry | `BaseGenerator#wrap_with_retry`: `rescue => e` (everything) and re-runs the whole body, `sleep` up to 60 s per attempt, inside the submission transaction; plus `sleep` in `api_call` (status retry), `send_webhook` (`retryPolicy`), `rate_limiter` (`onExceed: wait`), `retry_with_backoff`, and `FlowchartRuntime::Lock.acquire` retries |
| Guard | `BaseGenerator#wrap_with_guard` emits `if <guardCondition> … else true end` (raw Ruby, `safe_single_expression?`); `ActivityGenerator#validate_guard_condition!`; editor inputs in `templates/step.js`, `step_manager.js`, `step_manager/config_fields.js` |
| Broken model actions | `soft_delete_model` writes a `deleted_at` that entity entries do not have; `transition_state` calls `<event>!` (no such method); `find_model` with `findValue: "params.email"` emits bare `params.email` (NameError) |
| JS catalog English literals | 2,393 walkable strings (labels, descriptions, placeholders, option labels) + 140 key/value placeholders (not walked) = 2,533 |
| `flowchart_actions.*` keys | 2,707 flat dotted keys per locale; 34 walk keys missing in both locales; 332 stale keys (117 belong to the removed human-workflow actions `approval_gate`, `assign_task`, `escalation`, `user_input_request`); 35 `en` values differ from the JS English source. Flat dotted keys cannot be resolved by `I18n.t("flowchart_actions.<a>.<b>")` |
| Generator / runtime I18n keys | 134 literal `I18n.t("…")` keys in `code_generators/**`, `flowchart_runtime/**`, `flowchart_server_validator/**`; 49 missing in both locales (e.g. all of `flowchart_actions.rate_limiter.errors.*`) |
| Hard-coded English validation messages | 279 `errors << "…"` + 14 literal `message:` / `required_message:` in step generators; `ConfigValidator` wraps every message in English (`Step "…" (…): …`, two English fix hints) |
| `raise_on_missing_translations` in test | off (commented out in `config/environments/test.rb:49`); `config.i18n.fallbacks = true` hides missing `zh-CN` keys |

## A. One field declaration per generator

**A1 The `config_schema` DSL.** Every step-action generator declares each config field exactly once
inside `config_schema do … end` (`CodeGenerators::ConfigSchema`, rewritten). A declaration is a role
plus options:

| Role | Stored value | Validation | Emitted by `read(:f)` | Editor control |
|---|---|---|---|---|
| `input :f` | ctx path string (`model`, `params.email`, `order.items`) | identifier segments, ≤ 4 segments, no reserved root except seeded keys | `ctx[:a]`, or `FlowchartRuntime::Step.dig(ctx[:a], :b, :c)` | text + variable picker |
| `output :f, default:` | ctx key | identifier, not reserved (C5), not Ruby reserved, never `result` | key for `assign` | text, no variable picker |
| `expression :f` | Ruby expression | `ExpressionSafety` + exactly one statement (`Prism.parse`) | the source, parenthesised | code text |
| `literal :f` | string | `max_length:` | `"…".inspect` | text / textarea (`multiline: true`) |
| `template :f` | Liquid template | parses with `Liquid::Template.parse` | `FlowchartRuntime::Template.render("…", <vars>)` | textarea |
| `enum :f, values` | one of `values` | membership | literal | select; optional enums get an empty option |
| `flag :f` | `true` / `false` (JSON booleans) | boolean | `true` / `false` | toggle |
| `integer :f, min:, max:` / `decimal :f, min:, max:` | number | range | literal | number |
| `list :f` | array of strings | per-item `item:` role (`literal` or `entity_attribute`) | array literal | list editor |
| `mapping :f, key:, value:` | `[{ "key", "value" }]` (today's key/value shape) | key role (`literal` / `entity_attribute`), value role (`input` / `expression` / `literal`) | hash literal | key/value editor |
| `conditions :f` | structured condition group (Decision / query shape) | `ConditionBuilder` rules | predicate source | condition builder |
| `entity_attribute :f, of: :bound` | attribute slug | exists on the bound entity (or the entity chosen in `of:`) at generation | literal slug | attribute picker |
| `reference :f, source:` | record id / key | resolvable for the flowchart's customer (A8) | literal | searchable picker |
| `localized_text :f` | `{ "en" => …, "zh-CN" => … }` | `en` required, others optional (Open question Q2) | hash literal | one input per available locale |

Options on any role: `default:`, `required: true`, `example:` (sample value for required fields with
no default), `visible: { other_field => value | [values] }` (all keys must match; a hidden field is
neither validated nor read — `value(:f)` returns its default), `group: :advanced`, `placeholder: true`,
`max_length:`. Statements: `requires :f, when: { … }` (conditional requirement; also makes the field
visible under that condition), `validate { |cfg, errors| errors.add(:field, :code, **vars) }` for
genuinely cross-field rules. Capability statements: `transport_retry idempotent_when: { … }, or_present:
:field` (C3), `timeouts open:, read:` (C3), `circuit_breaker_option` (C3).

```ruby
config_schema do
  input  :sourceVariable, required: true, example: "order.items"
  enum   :operation, %w[sum avg min max count], default: "sum"
  flag   :skipNil, default: true
  output :resultVar, default: "total"
  requires :fixedRate, when: { rateSource: "fixed" }
end
```

Check: `config_schema_spec.rb` covers every role (valid, invalid, blank, hidden-by-`visible`,
conditional requirement, default) and the generated messages; a generator using an undeclared role or
option fails at class load.

**A2 Derived defaults, sample input and validation.**
- `value(:f)` is the only way generator code reads config (typed, defaults applied, hidden fields
  ignored). `config[...]`, `fetch_with_default`, `fetch_ident`, `fetch_enum`, `fetch_int_positive` and
  `SchemaReader` are deleted from step generators.
- `sample_input` = declared defaults + `example:` values; no generator defines `self.sample_input`.
- `validate_config(config)` returns `Array<CodeGenerators::ConfigError>`
  (`Data.define(:field, :code, :message)`, `#to_s` = `message`), derived from the schema plus `validate`
  blocks. Messages come from `flowchart_actions.shared.errors.<code>` or
  `flowchart_actions.<action>.errors.<code>` (both locales).

Checks (catalog-wide specs over every registered step action):
1. `validate_config(schema.defaults)` returns only `:required` errors, and only for required fields
   without a default (the editor's defaults never produce an enum / range / format error).
2. `validate_config(sample_input)` is empty and `generate_body` compiles (`RubyVM::InstructionSequence`).
3. `rg "def self.sample_input|fetch_with_default|fetch_enum|fetch_ident|config\[" app/services/code_generators/element_types/process` → no matches.

**A3 I18n keys.** Nested YAML under `flowchart_actions` (the flat dotted keys are deleted):

```yaml
en:
  flowchart_actions:
    categories:
      model: Records
    find_model:
      label: Find record
      description: Load one record of the bound entity by id or by an attribute.
      fields:
        findBy:
          label: Find by
          help: Look the record up by its id or by one of its attributes.
          options:
            id: Id
            attribute: Attribute
      errors:
        unknown_attribute: "%{attribute} is not an attribute of %{entity}"
    shared:
      fields:
        resultVar:
          label: Save result as
          help: Name of the variable later steps read.
      errors:
        required: "%{field} is required"
```

Required per action: `label`, `description`, and per field `label` and `help`; per enum option
`options.<key>`; `placeholder` when declared; `errors.<code>` for every code the generator adds.
Lookup order for field text: `flowchart_actions.<action>.fields.<field>.<part>`, then
`flowchart_actions.shared.fields.<field>.<part>`. Option keys are derived from the value:
`value.to_s.downcase.gsub(/[^a-z0-9]+/, "_")` (`GET` → `get`, `find_by!` → `find_by_`). Runtime
messages live under `flowchart_runtime.errors.<code>` (generic) or `flowchart_runtime.errors.<action>.<code>`.
Locale files are split by area, `config/locales/flowchart_actions_<area>.{en,zh-CN}.yml`, so parallel
tasks never share a file (plan: shared-locale rule). Check: G3 key-existence spec.

**A4 Catalog export (reverses the JS → Ruby mirror).** `CodeGenerators::ActionCatalog.export(locale:)`
returns the editor's catalog as JSON, translated in the requested locale, ordered by category:

```json
{
  "digest": "<sha256 of the locale-independent part>",
  "locale": "zh-CN",
  "categories": [{ "key": "model", "label": "记录" }],
  "actions": [{
    "key": "find_model", "category": "model", "label": "查找记录", "description": "…",
    "icon": "<svg path>", "color": "blue", "singleUse": false, "privileged": false,
    "fields": [{
      "name": "findBy", "role": "enum", "control": "select", "label": "…", "help": "…",
      "placeholder": null, "default": "id", "required": true, "group": "main",
      "options": [{ "value": "id", "label": "…" }, { "value": "attribute", "label": "…" }],
      "min": null, "max": null, "visibleWhen": null, "requiredWhen": null,
      "variablePicker": false, "source": null, "itemRole": null, "keyRole": null, "valueRole": null
    }],
    "capabilities": { "transportRetry": { "idempotentWhen": { "httpMethod": ["GET","HEAD","PUT","DELETE","OPTIONS"] }, "orPresent": "idempotencyKey", "maxAttempts": 2 },
                      "timeouts": { "open": 3, "read": 7, "cap": 10 }, "circuitBreaker": true }
  }]
}
```

- Icon, colour, `singleUse` and `privileged` move from the JS files into `generator_metadata`
  (`presentation icon:, color:, single_use:, privileged:`).
- The editor page embeds the export as one Stimulus value
  (`data-property-editor-action-catalog-value`, plus the canvas controller where it needs labels)
  rendered in the request locale; `action_registry.js` becomes a store installed with
  `setActionCatalog(json)`. `app/javascript/flowchart/constants/action_configs/*.js` (8,278 lines),
  `action_i18n.js`, the `actionI18n` overlay value, `lib/code_generators/config_schemas.rb` (action
  half), `rake config_schemas:mirror/check` (action half), `lib/tasks/extract_config_schemas.mjs`
  (action half) and `lib/tasks/extract_action_i18n_keys.mjs` are deleted. Consumers of
  `CONFIG_SCHEMAS` for actions (`SchemaReader`, `GeneratorConformance.ui_fields`,
  `FlowchartDefinitions::UiConfigSchema` / `Palette` / `Normalizer`, the assistant structure prompt)
  read `ActionCatalog` instead (English, model-facing).
- 100 % Vitest is kept by testing the store and every control against a committed fixture
  `spec/javascript/fixtures/action_catalog.sample.json`; `app/services/code_generators/action_catalog.schema.json`
  (JSON Schema) is the contract, and an RSpec contract spec validates both the live export (en and
  zh-CN) and the JS fixture against it, so neither side can drift.
- Transitional rule: until every category is ported (plan Waves 2–4), the exporter builds unported
  actions from the old mirror and flat keys (`ActionCatalog::LegacyFields`). That adapter is deleted in
  the legacy-removal task; Phase 3 is not done while `rg "LegacyFields|CONFIG_SCHEMAS" app lib` matches
  anything for step actions.

Checks: the export validates against the JSON Schema in both locales; the editor renders the palette and
every control from the fixture; `rg -n "action_configs|action_i18n|setActionI18n" app/javascript` → 0.

**A5 Parity and lint specs.** Catalog-wide specs, each iterating every ported action:
defaults-validate (A2.1), sample-compiles (A2.2), export-schema (A4), key-existence (G3), body lint (B2).

**A6 Reference sources.** `reference` fields name a source registered in
`CodeGenerators::ReferenceSources` (`email_templates`, `sms_templates`, `constants`, `entities`,
`entity_associations`, `pages`, `job_classes`, `service_classes`). Each source lists options for a
customer (owner-gated JSON endpoint `GET /:cid/admin/maintenance/flowcharts/reference_options/:source`,
same guard as the flowchart editor) and validates a stored value at generation. Check: request spec —
owner 200 with the URL customer's options only; admin/member/anonymous rejected per the existing
flowchart guard; unknown source 404.

## B. Emitted code

**B1 Emission helpers on `BaseGenerator`.** Config reaches emitted code only through helpers:
- `read(:f)` — Ruby source for the field's value per role (A1 table).
- `assign(:resultVar, expr)` → `ctx[:<output>] = <expr>`.
- `fail_with(:code, field: :f, unless: expr, **details)` →
  `return FlowchartRuntime::Step.fail(ctx, :code, field: :f, key: <source>) unless <expr>`;
  detail values are Ruby source (use `read` / `literal(value)`).
- `attempt(:code, *error_classes) { lines }` → `FlowchartRuntime::Step.attempt(ctx, :code, <classes>) do … end`.
- `body(*lines)` joins non-nil lines; `generate_body` must return `body(...)`. `generate_step_method`
  asserts the result parses (`Prism.parse(...).success?`) and raises
  `CodeGenerators::GeneratorError` (translated, names the action) otherwise.
- `I/O`: because `read` emits `ctx[:a]` (also for nested paths, through `Step.dig(ctx[:a], …)`),
  `IoExtractor` reports `a` as an input pin; `OperandConverter` emits the same shape, which fixes the
  backlog item "decision operands `ctx.dig(:x)` have no input pins".

**B2 Body rules (lint).** For every ported action's sample body and for each `enum` value variant:
- ≤ 12 lines; longer logic lives in a `FlowchartRuntime` helper.
- No `ctx[:_last_error]`, `ctx[:result]`, `Timeout.timeout`, `sleep`, `rescue => e`,
  `rescue StandardError`, `rescue Exception`, `I18n.t` (messages are resolved at runtime by `Step.fail`,
  so the stored artifact stays locale-independent), bare `params` / `model` locals.
- The last statement is the operation's own success value; a literal `true` is allowed only when no
  earlier statement is an unchecked fallible call (`save`, `destroy`, `update`, `deliver*`,
  `FlowchartRuntime::Http.request`, `Entries.save/upsert/destroy`, `Gateway.send`, …). The lint
  rejects `<fallible call>\ntrue`.
- Output names come from `output` fields; no action writes a key it does not declare as an output
  (except the standard keys of C5 that the action is documented to write).

Example (`find_model`, by attribute):

```ruby
# Find student
def find_student(ctx, **)
  ctx[:student] = FlowchartRuntime::Entries.find_by(ctx, "email" => ctx[:params][:email])
  return FlowchartRuntime::Step.fail(ctx, :record_not_found, field: :findValue) unless ctx[:student]
  true
end
```

**B3 Step-level wrappers are gone.** `BaseGenerator#apply_wrappers`, `wrap_with_timeout`,
`wrap_with_retry`, `wrap_with_guard`, `MAX_RETRY_BACKOFF_SECONDS`, `supports_timeout`,
`ActivityGenerator#validate_guard_condition!` and the call `generator.apply_wrappers(code)` in
`ActivityGenerator#generate_step_code` are deleted, together with the downcase action lookup
(`find_step_action(action.downcase)`) in `ActivityGenerator` and `ConfigValidator`. A step is
`{ "action", "config" }` (plus editor metadata such as `id`); `retryCount`, `retryBackoff`, `timeout`
and `guardCondition` are not read anywhere. Conditional execution is a Decision before the box (H2);
retry and timeouts are action config on HTTP-style actions (C3).
Check: `rg -n "guardCondition|retryCount|retryBackoff|apply_wrappers|Timeout\.timeout" app/services/code_generators app/services/activity_generator* app/javascript/controllers/property_editor` → 0;
`activity_generator_guard_spec.rb` is deleted; the composition spec keeps "a false Validate stops Save".

## C. Runtime

**C1 `FlowchartRuntime::Step`.**
- `Step.fail(ctx, code, field: nil, **details)` appends
  `I18n.t("flowchart_runtime.errors.#{code}", **details)` (request locale) to `ctx[:errors]` — keeping
  Phase 2's `Array<String>` contract, so `collect_errors`, the public flash and the test panel work
  unchanged — appends `{ "code" => code.to_s, "field" => field&.to_s, "details" => details.transform_values(&:to_s) }`
  to `ctx[:error_details]` (an Array of Hashes), and returns `false`.
- `Step.fail_message(ctx, localized, code: :business_error)` appends the author's localized message
  (request locale, `en` fallback) instead of a key.
- `Step.attempt(ctx, code, *error_classes) { … }` returns the block's value; when the block raises one
  of `error_classes` it calls `Step.fail(ctx, code, reason: <error class demodulized>)` and returns
  `false`. Exception text never enters `ctx[:errors]`; it goes to `error_details[…]["diagnostic"]`,
  which only the owner test panel shows. Other exceptions propagate (the run raises; the public flash
  shows the generic message, as in Phase 2 C4).
- `Step.dig(value, *keys)` — indifferent nested read (Symbol or String keys, Arrays by Integer index).
- `ctx[:_last_error]` disappears: no generator writes it, `Errors.collect` no longer mentions it.

Checks: `step_spec.rb` (append order, dedup with `Errors.collect`, zh-CN messages, details stringified,
`attempt` rescues only the listed classes); a public submission whose step calls `Step.fail` shows the
translated message in the flash (en and zh-CN) and never exception text; the traces JSON carries
`error_details` and the test panel shows them under the failing step.

**C2 `FlowchartRuntime::Entries` (JSON-aware).** Entity attributes live in the JSON `data` column; every
helper is scoped by `customer_id` and entity:
- `scope(ctx)` (exists); `scope_for(ctx, entity)` — another entity accessible to the customer
  (customer-owned or shared), raising `Entries::Error` otherwise.
- `find_by(ctx_or_scope, conditions)` / `where(ctx_or_scope, conditions)` — `id` → column, other keys →
  `json_extract(entity_entries.data, '$.<slug>') = ?` (via `JsonPathValidator`); an unknown slug raises
  `Entries::UnknownAttribute`.
- `assign(entry, attributes, strict: false)` — writes through the entity accessors; `strict: true`
  raises on keys that are not writable attributes.
- `save(ctx, entry)` → `true`, or appends `entry.errors.full_messages` to `ctx[:errors]` (code
  `record_invalid` in `error_details`) and returns `false`.
- `upsert(ctx, match:, attributes:)` → `[entry, created]` or `false`; runs under `FlowchartRuntime::Lock`
  keyed `CacheKey.scoped(customer_id, "upsert", entity_id, digest(match))`.
- `destroy(ctx, entry)` → `true` or `Step.fail(ctx, :record_not_destroyed)`;
  `archive(ctx, entry, field:, by_field: nil)` sets a date-time attribute (and optionally the actor) and saves.

Checks: `entries_spec.rb` with real `EntityEntry` rows of two tenants — no helper ever returns or writes
another tenant's row; `find_by` on a JSON attribute; unknown attribute; upsert creates once under
concurrency (two threads, one row).

**C3 HTTP-style actions: transport-only retry, library timeouts, circuit breaker.**
`FlowchartRuntime::Http.request(ctx, method, url, headers:, query:, body:, form:, open_timeout:,
read_timeout:, retries: 0, breaker: nil, follow_redirects:, max_redirects:, max_bytes:)` wraps
`OutboundHttp` and returns the response, or `false` after `Step.fail`:
- Retry only on `OutboundHttp::TransportError` (DNS, refused, TLS, connect/read timeout), never on an
  HTTP status; immediate (no `sleep`); at most 2 extra attempts; only while
  `FlowchartRuntime::RunContext.remaining` covers another full attempt.
- The schema marks idempotency: `transport_retry idempotent_when: { httpMethod: %w[GET HEAD PUT DELETE OPTIONS] }, or_present: :idempotencyKey`
  declares the advanced fields `retryOnTransportError` (flag, default `false`) and `retryAttempts`
  (integer 1–2, default 1); validation rejects `retryOnTransportError` on a non-idempotent config
  (`flowchart_actions.shared.errors.retry_not_idempotent`).
- `timeouts open: 3, read: 7` declares `connectTimeout` (1–5) and `readTimeout` (1–9) with
  `connectTimeout + readTimeout ≤ 10` (`timeout_exceeds_run_limit`, message names the 10 s cap). At
  runtime both are clipped to `RunContext.remaining`; with less than 1 s left the request is not sent
  (`Step.fail(ctx, :timed_out)`).
- `circuit_breaker_option` declares `circuitBreaker` (flag), `breakerName` (literal, default the action
  key), `failureThreshold` (1–20, default 5), `resetTimeoutSeconds` (10–3600, default 60); state lives in
  `Rails.cache` through the existing `FlowchartRuntime::CircuitBreaker` under a tenant-scoped
  `CacheKey.scoped(customer_id, "breaker", name)`; an open breaker fails with `:circuit_open` without a
  request; transport errors and 5xx count as failures.
- Non-2xx responses fail with `:http_status` (`status:` detail).
- HTTP-style actions: `api_call`, `send_webhook`, `download_file` (retry-capable when idempotent);
  `ai_inference`, `geolocation_lookup`, `currency_convert` (external rates) use `Http` with timeouts and
  the breaker but no retry unless the schema marks them idempotent.
- `FlowchartRuntime::RunContext` (`ActiveSupport::CurrentAttributes`-style, thread-safe) holds the run
  deadline; `ActivityTracer` sets it around every run (traced and untraced) from
  `EXECUTION_TIMEOUT_SECONDS`; `remaining` defaults to the full cap when unset (specs, previews).
- Database work has no per-step timeout: the app runs SQLite (`config/database.yml`), which has no
  statement timeout; the run-level 10 s cap in `ActivityTracer` remains the bound (Open question Q13).
- No `sleep` anywhere in emitted code or in helpers called inside a run (`Lock.acquire` retries,
  `rate_limiter` "wait", `acquire_lock` "wait" are removed).

Checks: `http_spec.rb` (WebMock): GET retried once after a connect timeout then succeeds; POST without an
idempotency key never retried; 503 never retried; budget exhaustion stops retries; open breaker sends
nothing; timeouts passed to `OutboundHttp`; generation rejects 6 + 6 s; a send_webhook run that times
out delivers once.

**C4 Helpers that replace long inline algorithms** (each a `FlowchartRuntime` facade with `class Error`,
per `facade_contract_spec.rb`):
- `Idempotency.claim(ctx, key, ttl:)` → `:claimed` / `:duplicate` (atomic `Rails.cache.write(…, unless_exist: true)` under `CacheKey.scoped`).
- `RateLimiter.allow?(ctx, name, capacity:, window:)` → Boolean (token bucket; never sleeps).
- `BusinessHours.open?(schedule:, at:, timezone:, holidays:)` → `{ open:, next_open_at: }`.
- `CacheKey.scoped(tenant, *parts)` → `"flowchart:<tenant>:<parts>"`; literal parts are validated at
  generation (no wildcards, ≤ 200 bytes), runtime parts are stringified and length-checked.
- `Json.parse(text, max_bytes:)` → value or `Json::Error`.

**C5 Runtime ctx contract.** Keys every run receives (public submission and owner test run):
`params`, `bound_entity`, `customer_id`, `authentication`, `current_user_id`, `current_user_role`,
`audience`, `device_type` (today) plus `request_ip`, `user_agent`, `locale`, `request_id` (new; audit and
idempotency defaults read them). Standard keys written by steps: `model`, `contract` (kept, §8.5),
`errors`, `error_details`, `submission_outcome`, `current_user` (written by Load current user). Output
fields may not name a seeded key, `errors`, `error_details` or `submission_outcome`; `model` / `contract`
are allowed. Defaults of `input` fields read only seeded or standard keys.
Check: a spec walks every `input` default in the catalog and asserts its root is seeded or standard;
`PublicSubmission` and the traces controller seed the four new keys.

## D. Catalog consolidation

**D1 Verdicts for the 100 current actions.** Failure convention: `L` = `rescue … => e; ctx[:_last_error] = e.message; false`;
`T` = literal `true` regardless; `L/T` both; `M` = returns the model/contract result; `F` = falsy expression.
"Q1" marks the additional merges proposed to reach the owner's target (Open question Q1); without Q1
those actions are kept (ported, not merged). Field renames in the last column apply to every survivor
and are performed by the migration (H).

| # | Key (current) | Cat | Inputs → outputs today | Fail | Verdict | Stored-data mapping |
|---|---|---|---|---|---|---|
| 1 | new_model | model | → resultVar=model | T | keep | — |
| 2 | find_model | model | idExpression / findField, findValue → resultVar=model | F / T | keep; `Entries.find_by`; not found → `:record_not_found` | findStrategy find/find_by!/first/take → `findBy: id`, find_by/where_first → `findBy: attribute`; where_many → `query_models`; idExpression → idSource |
| 3 | save_model | model | contractRef=contract | M | keep; `Entries.save` | contractRef dropped (blocker if ≠ `contract`) |
| 4 | destroy_model | model | modelVariable; strategy | T | keep; `Entries.destroy`; gains `mode: delete \| archive` (Q14) | strategy dropped |
| 5 | update_model | model | modelVariable; updateStrategy; returnChanges | M | keep | updateStrategy dropped; returnChanges true → `changesVar: "saved_changes"` |
| 6 | query_models | model | conditions, pageVariable → resultVar=models | T | keep (+ Q1: `select` + `returns: records \| values`) | queryType dropped |
| 7 | soft_delete_model | model | sourceKey; deletedAtField; deletedByField | T (broken) | merge → destroy_model `mode: archive` | sourceKey→modelVariable, deletedAtField→archiveField, deletedByField→archivedByField |
| 8 | upsert_model | model | matchFields → outputKey, createdKey | T | keep; `Entries.upsert` | outputKey→resultVar, createdKey→createdVar; method dropped |
| 9 | check_existence | model | conditions → resultVar=exists | T | merge → count_records `resultAs: exists` | negated → `resultAs: absent`; checkMethod, withTransaction dropped |
| 10 | count_records | model | conditions → resultVar=count | T | keep; gains `resultAs: count \| exists \| absent` | — |
| 11 | pluck_model_fields | model | fields, conditions → resultVar=values | T | keep (file renamed to `pluck_model_fields_generator.rb`); Q1 → query_models `returns: values` | fields→select |
| 12 | clone_model | model | sourceKey → outputKey | L | keep; association options dropped (entries have none) | sourceKey→modelVariable, outputKey→resultVar; cloneAssociations, depth, deepClone dropped |
| 13 | transition_state | model | event; modelVariable | T (broken) | **remove** | blocker (no survivor) |
| 14 | batch_operation | model | sourceVariable=items … | L | keep | — |
| 15 | bulk_import | model | dataKey → outputKey=import_result | L | keep | dataKey→sourceVariable, outputKey→resultVar |
| 16 | aggregate_query | model | conditions → resultVar=**result** | T | keep | default `result` → `aggregates` (old default materialized) |
| 17 | raw_sql_query | model | sqlTemplate → outputKey=results | T | **remove** (§8.3) | blocker |
| 18 | build_contract | validation | modelVariable → resultVar=contract | T | keep; always writes `ctx[:contract]` | resultVar dropped (blocker if ≠ `contract`) |
| 19 | validate (= validate_contract) | validation | contractRef=contract | M | **rename** → validate_contract | contractRef dropped (blocker if ≠ `contract`) |
| 20 | assign_value | data | valueType, … → resultVar | T | keep (+ Q1 coalesce: `valueType: first_present`) | — |
| 21 | transform | data | sourceField → targetField | T | **remove**, split by mode | mapFields/rename_fields → hash_manipulate `rename_keys`; remove_fields → hash_manipulate `omit`; convertType → type_cast; formatDate → date_time_calc `format`; custom → assign_value expression; add_computed_fields → hash_manipulate `set_keys`; flatten_nested → hash_manipulate `flatten` |
| 22 | calculate | data | collectionExpression, fieldName → resultVar=**result** | T | keep (absorbs reduce) | collectionExpression→sourceVariable (blocker when not a ctx path); default → `total` |
| 23 | log | data | messageTemplate … | T | keep | logger `audit` → audit_log |
| 24 | compare_data | data | leftKey, rightKey → outputKey=diff | T | keep | leftKey→sourceVariable, rightKey→otherVariable, outputKey→resultVar |
| 25 | merge_data | data | sourceVariable, mergeVariable → targetVariable | T | keep; Q1 → hash_manipulate `merge` | targetVariable→resultVar |
| 26 | map_value | data | sourceVariable → targetVariable=**result** | T | keep | targetVariable→resultVar; default → `mapped_value` |
| 27 | coalesce_value | data | candidates → outputKey=**result** | T | keep; Q1 → assign_value `first_present` | outputKey→resultVar |
| 28 | format_string | data | template, variablePaths → targetVariable | T | merge → template_render | mustache/liquid → template_render (variablePaths→variables); printf / ruby_interpolation → blocker |
| 29 | string_manipulate | data | sourceKey → outputKey=**result** | T | keep (+ Q1 base64 ops) | sourceKey→sourceVariable, outputKey→resultVar; default → `text` |
| 30 | regex_extract | data | sourceVariable → targetVariable=**result** | T | keep | targetVariable→resultVar; default → `match` |
| 31 | hash_manipulate | data | sourceKey, otherHashVariable → outputKey=**result** | T | keep (+ transform modes, + Q1 merge_data) | sourceKey→sourceVariable, otherHashVariable→otherVariable, outputKey→resultVar; default → `hash` |
| 32 | base64_encode_decode | data | sourceKey → outputKey=**result** | T | keep; Q1 → string_manipulate `base64_encode/decode` | sourceKey→sourceVariable, outputKey→resultVar |
| 33 | serialize_data | data | sourceVariable → targetVariable | T | keep; csv format removed | format csv → generate_file csv (`outputDestination: ctx_var`); targetVariable→resultVar |
| 34 | parse_data | data | sourceVariable → targetVariable=data | L | keep (+ parse_csv options) | targetVariable→resultVar |
| 35 | generate_id | data | → outputKey=id | L | keep | outputKey→resultVar |
| 36 | date_time_calc | data | sourceVariable, endVariable → targetVariable | T | keep (+ Q1 timezone_convert) | targetVariable→resultVar |
| 37 | math_operation | data | sourceKey, secondaryKey → outputKey=**result** | T | keep | sourceKey→sourceVariable, secondaryKey→otherVariable, outputKey→resultVar; default → `number` |
| 38 | filter_collection | data | sourceVariable → targetVariable=filtered | T | keep; gains `returns: items \| split \| first \| last \| index \| count \| any \| all \| none` (one `Collections.filter` helper) | targetVariable→resultVar |
| 39 | map_collection | data | → targetVariable=mapped | T | keep; Q1 → collection_manipulate `map` | targetVariable→resultVar |
| 40 | reduce_collection | data | collectionKey → outputKey=**result** | T | merge → calculate | collectionKey→sourceVariable, field→fieldName, outputKey→resultVar (old default materialized) |
| 41 | sort_collection | data | → targetVariable | T | keep; Q1 → collection_manipulate `sort` | targetVariable→resultVar |
| 42 | group_collection | data | → targetVariable=grouped | T | keep; Q1 → collection_manipulate `group` | targetVariable→resultVar |
| 43 | uniq_collection | data | → targetVariable=unique | T | keep; Q1 → collection_manipulate `unique` | targetVariable→resultVar |
| 44 | flatten_collection | data | collectionKey → outputKey=**result** | T | keep; Q1 → collection_manipulate `flatten` | collectionKey→sourceVariable, outputKey→resultVar |
| 45 | chunk_collection | data | sourceVariable → resultVar=**result** | T | keep; Q1 → collection_manipulate `chunk` | default → `chunks` |
| 46 | partition_collection | data | collectionKey → matchedKey, unmatchedKey | T | merge → filter_collection `returns: split` | collectionKey→sourceVariable, matchedKey→resultVar, unmatchedKey→rejectedVar |
| 47 | zip_collections | data | collectionKeys → outputKey=zipped | T | keep; Q1 → collection_manipulate `zip` | collectionKeys→sources (list), outputKey→resultVar |
| 48 | any_all_none_check | data | collectionKey → outputKey=**result** | T | merge → filter_collection `returns: any/all/none` | collectionKey→sourceVariable, checkType→returns, outputKey→resultVar |
| 49 | find_in_collection | data | sourceVariable → resultVar=found | T | merge → filter_collection | returnMode first/last/index/count/all → returns first/last/index/count/items |
| 50 | type_cast | data | sourceKey → outputKey=**result** | T | keep (+ transform convertType) | sourceKey→sourceVariable, outputKey→resultVar; default → `cast_value` |
| 51 | pluck_fields | data | sourceVariable → targetVariable=plucked | T | keep; Q1 → collection_manipulate `pluck` | targetVariable→resultVar |
| 52 | API_call (= api_call) | communication | url, headers … → resultVar | L (+ status retry with sleep; `Timeout` 30 s) | **rename** → api_call ("HTTP request"); `Http`; transport retry; breaker option | retryOnStatus, retryOnStatusAttempts dropped (reported) |
| 53 | send_email | communication | toExpression, subject, body … | L | merge → send_template_email | blocker (a template must be chosen; Q4) |
| 54 | send_template_email | communication | templateId, toExpression, vars | L | keep; template picker | toExpression→to |
| 55 | send_webhook | communication | url, payloadExpression → resultVar | L (+ retryPolicy sleep; 30 s) | keep; `Http`; retry only with idempotencyKey | retryPolicy ≠ none → `retryOnTransportError: true` when idempotencyKey present, else dropped (reported) |
| 56 | notify | communication | channel, recipientExpression, messageTemplate … | L (30 s) | **remove** | sms → send_sms (smsTemplateKey→templateKey, smsVars→vars, recipientExpression→to, smsIdempotencyKey→idempotencyKey); slack → send_webhook (slackWebhookUrl→url, payload `{ text: messageTemplate }`); in_app → create_notification (recipientExpression→recipient, messageTemplate→body.en); email → blocker |
| 57 | authorize | security | userExpression=ctx[:current_user] … | L/T | keep (default reads `current_user` written by Load current user) | — |
| 58 | authenticate | security | sourceVariable, userVariable, secretVariable → targetVariable | L | keep; JWT method removed | authMethod jwt → verify_token; targetVariable→resultVar |
| 59 | encrypt_data | security | sourceVariable → targetVariable | L | keep (encrypt only) | action decrypt → decrypt_data; targetVariable→resultVar |
| 60 | decrypt_data | security | sourceKey → outputKey=decrypted | L | keep | sourceKey→sourceVariable, outputKey→resultVar |
| 61 | hash_data | security | sourceVariable → targetVariable=hashed | T | keep | targetVariable→resultVar |
| 62 | mask_data | security | sourceKey → outputKey=masked | T | keep | sourceKey→sourceVariable, outputKey→resultVar |
| 63 | sanitize_input | security | sourceKey → outputKey | L | keep | sourceKey→sourceVariable, outputKey→resultVar |
| 64 | generate_token | security | dataVariable, payloadVariable, secretVariable → targetVariable | L | keep (jwt, hmac, numeric_otp) | random tokenTypes (uuid, hex, base58, urlsafe_base64, secure_random) → generate_id; targetVariable→resultVar |
| 65 | verify_token | security | tokenKey, secretKey → outputKey=claims | L | keep | tokenKey→sourceVariable, outputKey→resultVar |
| 66 | enqueue_job | background | jobClass, jobArgs, performMode | L | keep as "Run background job" with `when: now \| at \| after \| recurring` | performMode later → now; performMode now (inline) → now (reported); waitUntil → `when: at` |
| 67 | schedule_job | background | scheduleType, cronExpression, runAt … | L | merge → enqueue_job | scheduleType at_time → at, recurring/cron → recurring; fields carried |
| 68 | generate_file | file | fileType, dataExpression → resultVar | T | keep (+ generate_csv options) | dataExpression→sourceVariable when a ctx path, else blocker |
| 69 | upload_file | file | sourceExpression, fileVariable, … | T | keep | — |
| 70 | download_file | file | url / urlVariable → resultVar (120 s) | L | keep; `Http`; retry (GET) | timeoutSeconds → readTimeout (clipped to 9, reported) |
| 71 | generate_csv | file | collectionKey, columns → outputKey | T | merge → generate_file csv | collectionKey→sourceVariable, outputKey→resultVar, csv options carried |
| 72 | parse_csv | file | sourceKey → outputKey=rows | L | merge → parse_data csv | sourceKey→sourceVariable, outputKey→resultVar, delimiter→csvDelimiter, headerRow→csvHeaders, quoteChar/skipRows/encoding/colTypes carried |
| 73 | compress_files | file | entries → outputKey | L | keep | outputKey→resultVar |
| 74 | decompress_files | file | sourceKey → outputKey=extracted | L | keep | sourceKey→sourceVariable, outputKey→resultVar |
| 75 | publish_event | realtime | eventName, payloadExpression | T | **remove** (§8.3) | box removed, predecessor reconnected (reported) |
| 76 | broadcast | realtime | streamName … | T | **remove** | box removed (reported) |
| 77 | circuit_breaker | resilience | breakerName … → resultVar | L | **fold** into HTTP actions | adjacent HTTP action gets circuitBreaker fields; box removed (reported) |
| 78 | rate_limiter | resilience | limiterName, capacity … → resultVar | L/T (wait sleeps) | keep; `RateLimiter.allow?` | onExceed wait → fail (reported) |
| 79 | idempotency_check | resilience | keyStrategy … → resultVar | L | keep; `Idempotency.claim` | storeName dropped |
| 80 | retry_with_backoff | resilience | maxRetries … → resultVar | L (+ sleep, raise) | **remove** | box removed; an idempotent HTTP predecessor gets `retryOnTransportError` (attempts = min(maxRetries, 2)); reported |
| 81 | render_response | response | → resultVar=response (inert) | T | **remove** → set_submission_outcome | flashMessage or redirect format → set_submission_outcome; otherwise box removed |
| 82 | redirect_response | response | url, flashMessage → resultVar=response (inert) | T | **remove** → set_submission_outcome | flashMessage → message.en; url dropped (reported; Q11) |
| 83 | deadline_check | scheduling | deadlineVariable → resultVar, breachedVar | T (+ `ctx[:_signal]`) | keep; signal mode removed | behaviorOnBreach signal → mark |
| 84 | business_hours_check | scheduling | schedule → resultVar (77-line body) | T | keep; `BusinessHours.open?` | — |
| 85 | timezone_convert | scheduling | sourceTimeVariable → resultVar | T | keep; Q1 → date_time_calc `convert_timezone` | sourceTimeVariable→sourceVariable |
| 86 | invoke_service | service | serviceClass, args → resultVar | T | keep | — |
| 87 | audit_log | utility | eventType … persistTo=log | T | keep; persisted (E10) | persistTo dropped |
| 88 | ai_inference | utility | provider, promptTemplate → resultVar (60 s) | L | keep; `Http`, no retry | step timeout → readTimeout (clipped) |
| 89 | i18n_translate | utility | key … → resultVar | T | keep | — |
| 90 | currency_convert | utility | amount, rateSource → resultVar | L | keep; external rates via `Http` | — |
| 91 | geolocation_lookup | utility | sourceKey → targetKey, resultVar | L | keep; `Http` | sourceKey→sourceVariable; targetKey→resultVar when resultVar blank |
| 92 | barcode_generate | utility | dataVariable → resultVar | L | keep (+ Q1 qr) | dataVariable→sourceVariable |
| 93 | qr_code_generate | utility | dataVariable → resultVar | L | keep; Q1 → barcode_generate `format: qr` | dataVariable→sourceVariable |
| 94 | template_render | utility | template, variables → resultVar | L | keep (+ format_string) | — |
| 95 | cache_read | caching | cacheKey, mode → resultVar=cached | T | keep (read only) | mode fetch → cache_fetch |
| 96 | cache_write | caching | cacheKey, sourceVariable, action | T | keep (write, write_if_absent) | action delete → cache_delete |
| 97 | cache_delete | caching | scope, cacheKey, tags | T | keep | — |
| 98 | cache_fetch | caching | cacheKey, fallbackExpression → resultVar | L/T | keep | — |
| 99 | acquire_lock | concurrency | lockKey … onConflict=wait (30 s) | L | keep; never waits | onConflict wait → fail; lockRetryCount, retryDelay, backoffStrategy, jitter dropped (reported) |
| 100 | release_lock | concurrency | lockKey … | L | keep | — |

Mode trims inside survivors (no count change): `cache_read` fetch, `cache_write` delete, `encrypt_data`
decrypt, `authenticate` JWT, `serialize_data` csv, `deadline_check` signal, `generate_token` random
types, `notify` in-app.

**D2 Field-name normalization.** The primary data input is `sourceVariable` (a second operand
`otherVariable`), a record input is `modelVariable`, the primary output is `resultVar`, secondary outputs
are `<thing>Var` (`createdVar`, `rejectedVar`, `changesVar`). `outputKey`, `targetVariable`, `targetKey`,
`targetField`, `sourceKey`, `collectionKey`, `dataVariable`, `dataKey`, `matchedKey`, `unmatchedKey`
disappear. Boolean selects become `flag` fields stored as JSON booleans.

**D3 Output defaults.** Every `output` has an action-specific default; none is `result`. When a default
changes, the migration writes the old effective value into stored configs that relied on the implicit
default, so downstream reads keep working.

**D4 Final catalog (with Q1).** 66 consolidated survivors + 12 new = **78** actions (without Q1: 79 + 12 =
**91**), in these categories (export order):

| Category | Actions |
|---|---|
| model (Records) | new_model, find_model, save_model, update_model, destroy_model, query_models, upsert_model, count_records, aggregate_query, clone_model, batch_operation, bulk_import, **set_record_fields**, **load_current_user**, **related_record**, **next_sequence_number** |
| validation | build_contract, validate_contract, **fail_with_error** |
| data | assign_value, calculate, filter_collection, collection_manipulate (Q1), hash_manipulate, compare_data, map_value, string_manipulate, regex_extract, type_cast, date_time_calc, math_operation, generate_id, serialize_data, parse_data, log, **read_setting** |
| communication | api_call, send_webhook, send_template_email, **send_sms**, **create_notification** |
| security | authorize, authenticate, encrypt_data, decrypt_data, hash_data, mask_data, sanitize_input, generate_token, verify_token |
| background | enqueue_job |
| file | generate_file, upload_file, download_file, compress_files, decompress_files, **generate_document** |
| caching | cache_read, cache_write, cache_delete, cache_fetch |
| concurrency | acquire_lock, release_lock |
| resilience | rate_limiter, idempotency_check |
| scheduling | deadline_check, business_hours_check |
| payments | **request_payment**, **refund_payment** |
| outcome | **set_submission_outcome** |
| service | invoke_service |
| utility | audit_log, ai_inference, i18n_translate, currency_convert, geolocation_lookup, barcode_generate, template_render |

The `realtime` and `response` categories disappear. `GeneratorRegistry` registers exactly one name per
class (no `registered_names` aliases). Check: `generator_inventory_spec.rb` pins the final key list and
categories; `rg -n "API_call|\"validate\"|registered_names" app/services/code_generators` → 0 outside
the registry's default implementation.

## E. New business actions (priority order; §4.4 item 11, approval, is out of scope)

All follow A–C: schema with roles and both locales, emission helpers, `Step.fail` codes, behaviour specs
on two tenants, ≤ 12-line bodies.

**E1 Set record fields** (`set_record_fields`, model). `modelVariable` (input, default `model`),
`assignments` (mapping: key `entity_attribute`, value `expression`). Emits
`FlowchartRuntime::Entries.assign(ctx[:model], { … }, strict: true)`; unknown attribute rejected at
generation. Does not save (Save record does). Check: writes JSON attributes on a real entry; unknown
slug → `unknown_attribute` validation error naming the attribute.

**E2 Load current user** (`load_current_user`, model). `resultVar` (default `current_user`), `required`
(flag, default true). `FlowchartRuntime::CurrentUser.load(ctx)` returns a read-only Hash
(`id`, `email`, `name`, `role`, `member_profile_id` when present) for `ctx[:current_user_id]` within
`ctx[:customer_id]`; missing and required → `:not_signed_in`. Never loads another tenant's user.

**E3 Set submission outcome** (`set_submission_outcome`, outcome). `preset` (enum `submitted | saved |
thank_you | custom`, default `submitted`), `message` (`localized_text`, required when `custom`),
`flash` (enum `notice | alert`, default `notice`), `target` (enum `form | page`, default `form`),
`page` (`reference source: :pages`, required when `target: page`). Writes `ctx[:submission_outcome]`
(`{ "preset", "message", "flash", "target" => { "type", "page_id" } }`). `PublicPagesController` /
`Pages::PublicSubmission` honour it on success: flash text = the localized message (request locale,
`en` fallback) or `public_views.flash.outcomes.<preset>`; redirect to the page only when it is launched,
belongs to the same customer and is visible to the viewer, else the default post-submit path. Order:
payment handoff (E9) > page handoff > outcome target > default. No free-form URLs (Q11). Check: request
specs for each preset, a custom zh-CN message, a cross-tenant page id ignored, an invisible page ignored.

**E4 Fail with a business error** (`fail_with_error`, validation). `message` (`localized_text`,
required), `field` (literal, optional — highlights a form field in `error_details`). Emits
`return FlowchartRuntime::Step.fail_message(ctx, { … })`; the run ends on the failure track with the
message in the public flash. Typically placed after a Decision.

**E5 Send SMS** (`send_sms`, communication). `templateKey` (`reference source: :sms_templates`), `to`
(input, default `model.phone`), `vars` (mapping literal → expression), `idempotencyKey` (expression,
optional), `resultVar` (default `sms_message_id`). Wraps `FlowchartRuntime::Sms.send_template`;
gateway rejections map to `flowchart_runtime.errors.send_sms.*` codes. Check: suppression and quota
errors produce translated messages; tenant ledger row created for the run's customer only.

**E6 Related record** (`related_record`, model). `association` (`reference source: :entity_associations`
of the bound entity), `operation` (enum `find | create | update`), `modelVariable` (default `model`),
`conditions` (find), `assignments` (create/update), `resultVar` (default `related_record`). Uses
`Entries.scope_for` and the association's bridge entity (`FlowchartRuntime::JoinResolver`); create
writes the target entry and the bridge entry in the run's transaction. Check: two tenants; a shared
entity's related rows stay per-customer.

**E7 Read a Constant** (`read_setting`, data). `constant` (`reference source: :constants`), `returns`
(enum `options | label`), `value` (expression, required for `label`), `resultVar` (default
`constant_options`). Resolves the customer's override head, else the global default
(`FlowchartRuntime::Constants.options(ctx, id)`, using `ctx[:customer_id]`, not `Current`). Customer
settings beyond Constants: Q10.

**E8 Sequence number** (`next_sequence_number`, model). `sequenceName` (literal identifier), `prefix`
(literal), `padding` (integer 1–12, default 6), `resetEvery` (enum `never | year | month`),
`resultVar` (default `sequence_number`). New table `flowchart_sequences` (`customer_id`, `name`,
`period`, `last_value`; unique on the three keys). Increment is `UPDATE … SET last_value = last_value + 1`
followed by a read inside the run's transaction (SQLite serializes writers), so a failed submission
rolls the number back and numbers have no gaps. Check: 20 concurrent increments → 20 distinct
consecutive values; another tenant's sequence of the same name is independent.

**E9 Payments** (`request_payment`, `refund_payment`, payments). See Q5 for the recommended design:
`request_payment` creates a pending `Payments::Order` (amount, currency, subject from expressions) and
writes `ctx[:submission_outcome]["handoff"]`, which the public controller turns into the existing
`FeatureModules::Invocation` handoff to the Payment module checkout; no charge runs inside the
submission transaction. `refund_payment` calls `Payments::Activities::Refund.call(customer:, payment:,
amount:, reason:)` for a payment of the run's customer and fails with translated codes.

**E10 Persisted audit event** (`audit_log`, utility — upgraded, not a new key). Writes a row to the new
tenant-scoped table `flowchart_audit_events` (`customer_id`, `flowchart_id`, `event_type`,
`resource_type`, `resource_id`, `actor_user_id`, `ip`, `user_agent`, `severity`, `metadata` JSON,
`created_at`) and logs it; defaults read `current_user_id`, `request_ip`, `user_agent`. The row is part
of the run's transaction (a rolled-back submission leaves no audit row). Read surfaces: Q6.

**E12 Persisted in-app notification** (`create_notification`, communication). `recipient` (expression,
default `ctx[:current_user_id]`), `title` and `body` (`localized_text`), `page` (optional reference).
New table `flowchart_notifications` (`customer_id`, `user_id`, `title` JSON, `body` JSON, `page_id`,
`read_at`, timestamps); the recipient must belong to the run's customer (`:recipient_not_found`).
Read surfaces: Q6.

**E13 Document from a template** (`generate_document`, file). `title` (template), `body` (template;
paragraphs and `##` headings), `table` (optional: `sourceVariable` + `columns` mapping), `filename`
(template, default `document.pdf`), `attachTo` (optional `entity_attribute` of html type
`file_upload`, see Q7), `resultVar` (default `document`). Renders with Prawn through
`FlowchartRuntime::Document.pdf(...)` and stores an ActiveStorage blob. Check: PDF text contains the
rendered Liquid values; CJK text renders with a bundled CJK-capable font (or the task reports that none
is available).

## F. Step form UX (§4.5; the guard is removed, not redesigned)

- **F1** The action picker shows every category expanded with a visible one-line description per
  action and a search box (label, description, category; both locales); keyboard and touch usable.
- **F2** Every field shows its help text under the input (not hover-only).
- **F3** Optional `enum` fields have an empty option (translated "None"); required enums show their
  default; no select silently takes its first option.
- **F4** Change / Remove for a step are always visible buttons (no hover-only), ≥ 40 px touch targets.
- **F5** Controls for every role in A1: toggle (`flag`), list, mapping, conditions, entity attribute
  picker, reference picker (A6 endpoint, searchable), localized text (one input per locale).
- **F6** Field-level server errors: `ConfigValidator` problems carry `field`; the step form shows the
  message under that field with `aria-invalid="true"`, and the step header shows an error badge.
- **F7** Retry is a toggle in the advanced group, shown only for actions with `transportRetry` and only
  enabled when the current config is idempotent (otherwise a hint explains why).
- **F8** HTTP-style actions show the effective timeout: "Gives up after N s" with
  N = min(10, (connect + read) × (1 + retries)), as a Stimulus-value template.
- **F9** Output fields (`variablePicker: false`) have no "insert variable" picker.
- **F10** Output auto-suggest never renames `model` or `contract`.
- **F11** One column on mobile; two columns only for explicit pairs from `sm:`; all text through
  Stimulus values with English defaults and server-passed translations.

Checks: Vitest at 100 % on every touched file; Playwright: search the picker in zh-CN, add an action,
see help text, clear an optional enum, trigger a server field error, toggle retry on an HTTP GET.

## G. I18n

- **G1** The catalog is rendered from keys in both locales (A3/A4); `en` goes through keys too (no
  English-in-JS overlay). The 140 key/value placeholders become `fields.<f>.key_placeholder` /
  `value_placeholder` keys.
- **G2** The 34 missing JS keys and the 49 missing generator/runtime keys are covered by the new keys;
  the 2,707 flat keys (including the 332 stale ones) are deleted with the flat files.
  `ConfigValidator` messages and fix hints are translated
  (`maint_core.flowcharts.config_problems.{step_invalid,element_invalid,fix_step,fix_element}`); the
  279 literal generator messages become `errors.<code>` keys.
- **G3** Key-existence spec: for every ported action, every required key (A3) and every `Step.fail` /
  `errors.add` code the generator can emit exists in **each** locale looked up without fallbacks
  (`I18n.exists?(key, locale, fallback: false)`), with identical `%{}` variables in `en` and `zh-CN`.
- **G4** `config.i18n.raise_on_missing_translations = true` in `config/environments/test.rb`; the full
  suite passes with it (missing keys elsewhere are fixed in the same task; Q12).
- **G5** zh-CN is idiomatic (terse, full-width punctuation, canonical terms); generated Ruby source stays
  locale-independent English.

## H. Stored data: `flowcharts:migrate_step_actions`

**H1 Task shape.** `bin/rails flowcharts:migrate_step_actions` — dry run by default, `APPLY=1` saves a
new version and regenerates the activity; iterates global lines and every `FlowchartCustomerHead`
override line (same structure as `Flowcharts::SplitMultiActionProcesses`). Per flowchart line it prints
the changes (`<element id> <old action> → <new action>`, renamed keys, dropped fields, inserted
elements) and blockers. Lines with blockers are not saved; the task exits non-zero when any line is
blocked or fails to regenerate. A second run reports no changes (idempotent). Logic lives in
`Flowcharts::StepActionMigration` (pure, spec-driven) with one mapper per removed / merged / renamed
action; no alias is registered anywhere.

**H2 Guard → Decision.** For each process step with a non-blank `guardCondition`:
- `FlowchartDefinitions::GuardTranslator` (Prism) converts the expression into a Decision condition:
  `ctx[:a]` / `ctx.dig(:a, :b)` / `ctx[:a][:b]` paths; comparisons `== != > >= < <=` against
  string / number literals; `== true` → `is_true`, `== false` → `is_false`, `.nil?` / `== nil` →
  `is_nil`, `.present?` → `is_not_empty`, `.blank?` → `is_empty`, `!x` → `is_false`, a bare path →
  `is_true`; one level of `&&` / `||` (joins) and parentheses. Anything else is a blocker (Q3).
- A Decision `<box id>_guard` is inserted at the box's position (the box and everything below shift down
  by one row, as `ProcessSplitter` does); every incoming connection of the box is retargeted to the
  Decision; the Decision gets `Yes` (`matchValue: "true"`) → the box and `No` (`matchValue: "false"`) →
  the box's successor (a loop header counts: the No edge is then a back-edge), or → a new stepless End
  when the box had no successor. Label: `maint_core.flowcharts.migration.guard_decision_label`
  ("Run %{label}?") in the default locale.
- Check: compiled circuit equals the new canvas edges; behaviour equals the old guard for true / false /
  nil inputs; a guarded box inside a loop body iterates correctly; `WiringPlanner` accepts a decision
  branch as a back-edge.

**H3 Step-level fields.** `timeout` on an HTTP-style action → `readTimeout` (clipped to the cap, reported);
`retryCount > 0` on an idempotent HTTP-style config → `retryOnTransportError: true`,
`retryAttempts: min(retryCount, 2)`; every other `timeout` / `retryCount` / `retryBackoff` is dropped and
reported; `guardCondition` is removed after H2.

**H4 Actions and keys.** D1's mapping column, applied per action; boolean strings → booleans, numeric
strings → integers for `flag` / `integer` fields; key/value lists used as lists → arrays; old implicit
defaults materialized (D3). Removed inert boxes (`render_response` without outcome data,
`publish_event`, `broadcast`, `retry_with_backoff`, standalone `circuit_breaker`) are deleted and each
predecessor is connected to the box's successor. Blockers: `raw_sql_query`, `transition_state`,
`send_email`, `notify` email channel, `format_string` printf / ruby_interpolation, non-default
`contractRef` / contract `resultVar`, a non-path `collectionExpression` / `dataExpression`, an
untranslatable guard.

Checks: `step_action_migration_spec.rb` — one example per mapper and blocker, guard shapes, a box with
two incoming connections, a terminal guarded box, a guarded loop-body box, override lines, idempotence,
dry run writes nothing; task spec: `APPLY=1` saves one version per changed line and the regenerated
activity compiles. Deploy checklist gains step 3: `bin/rails flowcharts:migrate_step_actions`, review,
then `APPLY=1`, before serving traffic (after the Phase 1 split and Phase 2 regeneration).

## I. Developer docs (en and zh-CN in lockstep)

- `code-generators.md`: the `config_schema` roles and options, conditional rules, I18n key layout,
  `ActionCatalog` export and the JSON Schema, emission helpers, body rules and lint, how to add an action
  (one generator file + one locale pair + specs), reference sources; remove guard / retry / timeout
  wrappers and the mirror.
- `flowchart-runtime.md`: `Step.fail` / `fail_message` / `attempt` / `dig`, `ctx[:error_details]`,
  `Entries`, `Http` (transport retry, timeouts, breaker, `RunContext`), the C4 helpers, the ctx contract
  (C5), submission outcome handling, the three new tables.
- `flowchart-builder.md`: final catalog and categories, the step form, conditional execution via a
  Decision (guard removed), retry / timeout settings, migration and deploy note.
- New page `flowchart-step-actions.md` (catalog reference: every action, its fields and outputs),
  registered under `builders` in `DeveloperDocs::Catalog`; cross-linked from the three pages above.
- Cross-module pages for the new actions: `payments.md` (E9), `sms.md` (E5 replaces Notify SMS),
  `email.md` (send_template_email), `constants.md` (E7), `background-jobs.md` (Run background job),
  `internationalization.md` (`flowchart_actions` layout, `raise_on_missing_translations`).
- Check: developer-docs specs pass; `rg -n "guardCondition|retry_with_backoff|render_response|raw_sql_query|API_call|config_schemas:mirror|_last_error" doc/reference` → 0.

## J. Verification

Targeted specs per task; the full parallel suite at the end (generation, I18n and runtime are
cross-cutting); `npm run coverage` 100/100/100/100; the Playwright builder journey extended with F;
`flowcharts:migrate_step_actions` dry run on development (dev data is deleted by the owner, so the run
must report zero lines or only the owner's new flowcharts); dev server restart with `SKIP_AUTH=1` and a
smoke of the editor (palette, a ported action of each category, a test run with a failing step showing
its translated message).

## Open questions (recommended defaults are applied unless the owner says otherwise)

- **Q1 Further merges to approach "about 60".** §4.3 alone gives 79 consolidated actions. Proposed
  additionally: one `collection_manipulate` (map, pluck, group, sort, unique, chunk, flatten, zip — the
  same operation-selector pattern as `string_manipulate` / `hash_manipulate`), `merge_data` →
  `hash_manipulate`, `coalesce_value` → `assign_value`, `base64_encode_decode` → `string_manipulate`,
  `timezone_convert` → `date_time_calc`, `pluck_model_fields` → `query_models`, `qr_code_generate` →
  `barcode_generate`. **Default: apply** (66 + 12 new = 78). If declined, the category tasks port those
  actions unmerged (79 + 12 = 91).
- **Q2 Author-written messages** (outcome, business error, notification). **Default:** a
  `localized_text` role storing `{ "en", "zh-CN" }` (en required, request locale with en fallback), plus
  translated presets where a standard message fits.
- **Q3 Untranslatable guards and other blockers.** **Default:** report them, leave that flowchart line
  unchanged and exit non-zero; the owner edits it (flowcharts are owner-only).
- **Q4 Email templates are per-customer ids.** A shared flowchart cannot reference one portably.
  **Default:** keep the id reference; the picker lists the editing customer's templates; on a shared
  flowchart the step gets a validation warning; key-addressed email templates are a follow-up. Migrated
  `send_email` steps are blockers.
- **Q5 Payments inside a submission.** **Default:** `request_payment` creates a pending order and hands
  off to the Payment module checkout through the outcome (no charge inside the transaction);
  `refund_payment` is synchronous through `Payments::Activities::Refund`. Alternative: refund only.
- **Q6 Surfaces for audit events and notifications.** **Default:** tables, models and actions only;
  admin/member read surfaces are a follow-up module (documented as such).
- **Q7 Attaching a document to a record.** **Default:** write the blob reference into a `file_upload`
  entity attribute in the format the page form stores for that type; if that format is not established,
  ship generation (blob in ctx) and leave attachment as a follow-up.
- **Q8 Element-type half of the mirror.** Element schemas (`schemas.js`) belong to Phase 4. **Default:**
  keep `config_schemas:mirror` for element types only until Phase 4 moves them to Ruby.
- **Q9 Catalog delivery.** **Default:** embed the export as one Stimulus value on the owner-only editor
  (the page already embeds a 2,707-key map); alternative: a cached JSON endpoint keyed by digest.
- **Q10 "Customer setting".** No generic per-customer settings store exists. **Default:** E7 reads
  Constants only.
- **Q11 Outcome redirects.** **Default:** stay on the form or go to a launched, same-customer, visible
  page chosen in a picker; no free URLs (open-redirect risk). `redirect_response.url` is dropped and
  reported.
- **Q12 `raise_on_missing_translations` exposing gaps outside flowcharts.** **Default:** fix them in the
  guardrail task (they are bugs); if more than about 50 unrelated keys appear, stop and report before
  continuing.
- **Q13 Database timeouts.** §4.2 asked for a database statement timeout; SQLite has none. **Default:**
  no per-step database timeout; the run-level 10 s cap is the bound.
- **Q14 Soft delete.** **Default:** `destroy_model` gains `mode: archive` (date-time attribute picker and
  optional "archived by"), and `soft_delete_model` migrates to it, instead of a hard delete.

## Out of scope

Approval / wait for a person (separate project); element property editor and element schemas (Phase 4);
canvas polish (Phase 5); read surfaces for audit events and notifications; key-addressed email
templates; per-step database timeouts.
