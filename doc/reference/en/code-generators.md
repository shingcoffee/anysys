---
title: "Code generators"
summary: "How GeneratorRegistry discovers flowchart generators, how step actions and element types declare their fields with config_schema and export the action and element catalogs, which emission helpers and body rules they follow, how decisions, conditions and wiring compile, and how the platform UI edits those Ruby files."
---

## Summary

`CodeGenerators::GeneratorRegistry` is the catalog `ActivityGenerator` uses to compile a flowchart into a `Trailblazer::Activity::Railway` class. Each canvas element type and each process step action is a Ruby class under `app/services/code_generators/element_types`. The registry finds those classes by scanning directories at boot. There is no `register!` call and no graph interpreter. Execution of the compiled activity is [Flowchart runtime](flowchart-runtime). How the canvas stores the graph is [Flowchart builder](flowchart-builder). The per-action reference (every field, role, default and output) is [Flowchart step actions](flowchart-step-actions).

Every step action declares its configuration once with `config_schema ported: true`. That declaration drives validation, the editor's step form (through `CodeGenerators::ActionCatalog.export`), the assistant palette, and the Ruby the generator emits through a small set of helpers (`value`, `read`, `literal`, `assign`, `fail_with`, `attempt`, `body`). Labels, help text, option labels and validation messages live in `config/locales/flowchart_actions_<area>.{en,zh-CN}.yml`.

Element types (`start`, `end`, `decision`, `loop`, `subflow`) declare their fields the same way. `CodeGenerators::ElementCatalog.export` turns those schemas, the connection fields (`CodeGenerators::ConnectionSchema`) and the condition operators (`CodeGenerators::ConditionOperators`) into the catalog the element property forms read. Their text lives in `config/locales/flowchart_elements*.{en,zh-CN}.yml`.

The platform UI is `Admin::Maintenance::Platform::CodeGeneratorsController` at `/:customer_id/admin/maintenance/platform/code_generators`. It is `platform_owner?` only, because the path is under `/admin/maintenance/platform/`. Creating or updating a generator writes a `.rb` file, reloads Zeitwerk, and calls `GeneratorRegistry#reload!`.

Payment, captcha, and email vendors are a different rule: one new file under that module's provider directory. They are not rows in this registry. `ModelGenerator` and `ContractGenerator`, shown on the entity screen, are also outside it.

## Flow

```text
app/services/code_generators/element_types/
        |  start end decision loop subflow     (config_schema ported: true)
        |  process/<category>/*_generator.rb   (config_schema ported: true)
        v
GeneratorRegistry#discover!
        |  step_actions hash + element_types hash
        +--> ActionCatalog.export(locale:)     editor step form, assistant palette
        +--> ElementCatalog.export(locale:)    element + connection forms, operators
        v
ActivityGenerator#generate
        |  nil if flowchart.name blank or elements empty
        |  find_element_type / find_step_action
        |  validate_config -> generate_body
        v
Ruby source stored on Flowchart#activity

Platform owner UI
        |
        v
CodeGeneratorsController
        |  SourceAssembler + GeneratorValidator
        |  File.write under element_types/
        v
GeneratorRegistry#reload!

Preview / test
        |
        +-- PreviewsController     generate_step_method(sample_input)
        +-- TestRunsController     TestRunner.run
        +-- ValidationsController  GeneratorValidator.validate_source
        +-- IoParams / ElementTypeIoParams
```

`ActivityGenerator#generate` returns `nil` when the flowchart has no name or no elements. A missing generator does not return `nil`: it raises `ActivityGenerator::Error` with `:unknown_element_type` or `:unknown_step_action`.

## Implementation

### Registry

`CodeGenerators::GeneratorRegistry.instance` builds two hashes in `discover!`.

Element types are the subdirectories of `app/services/code_generators/element_types` whose names are in `SUPPORTED_ELEMENT_TYPES`: `start`, `end`, `decision`, `loop`, `subflow`. The `process` directory is skipped in that pass.

Step actions are every `*_generator.rb` under `element_types/process/<category>/`. The category directories are `background`, `caching`, `communication`, `concurrency`, `data_operations`, `file_operations`, `model_operations`, `outcome`, `payments`, `resilience`, `scheduling_time`, `security`, `service_invocation`, `utility`, and `validation`. A new category directory is picked up on the next `discover!` or `reload!`. Files that fail to load raise outside production and are logged and skipped in production.

A class is indexed only when it responds to `registered_names`. `GeneratorInterface#registered_names` returns the single `generator_name` from metadata, or the demodulized class name without the `Generator` suffix. There are no aliases: a stored `step.action` must equal a generator name. Duplicate names log a warning and the later class wins. `GeneratorRegistry.all` is the unique set of both hashes. `PathIdentity.find(slug)` matches `klass.name` without the `CodeGenerators::` prefix, underscored, to the URL slug.

`generator_kind` is `:step_action` when the class name includes `ElementTypes::Process`, and `:element_type` when it includes `ElementTypes`.

### Base class

`CodeGenerators::BaseGenerator` includes `GeneratorInterface`, `Shared::CtxReader`, `Shared::ConfigFieldReader`, `Shared::IdentifierSanitizer`, and `Shared::ExpressionSafety`. `#initialize` stores the element and a context hash. `extract_config` reads `properties` for an element type and `config` for a step action.

`generate_step_method` wraps `generate_body` in `def <step_name>(ctx, **)` and asserts the result parses (`Prism.parse`); otherwise it raises `CodeGenerators::GeneratorError` with `maint_core.flowcharts.generator_error`. Subclasses implement `generate_body`. `generator_metadata` records name, description, category, version, `presentation(icon:, color:, single_use:, privileged:)` and `error_strategy_default` through `MetadataDSL`.

`validate_config` delegates to the declared schema for a `ported: true` generator. All 78 step actions and all five element generators are ported. The unported branch (`GeneratorInterface#validate_config` plus `unsafe_ctx_expression_errors`) is still in `BaseGenerator`, but no registered generator takes it.

There are no step-level wrappers. `ActivityGenerator#generate_step_code` looks up `find_step_action(action)`, validates, and returns `generate_body`. A step has no condition, retry or timeout settings of its own: conditional execution is a Decision before the box, and transport retry and timeouts are fields of the HTTP-style actions that declare them (see Capabilities).

`StartGenerator` shows the smallest element type: metadata, an empty `config_schema ported: true` block (so any stored key other than the structural ones is `unknown_field`), and `generate_body` returning `nil` because start is skipped during traversal. `ActivityGenerator` treats `process`, `start`, and `end` as `STEP_CONTAINER_ELEMENT_TYPES`: a nil element-type body falls through to nested step actions.

### config_schema roles and options

`config_schema ported: true do … end` builds a `CodeGenerators::ConfigSchema`. Each statement is a role and a field name:

| Role | Stored value | Validation | `read(:field)` emits |
|------|--------------|------------|----------------------|
| `input` | ctx path, e.g. `params.email` | identifier path, at most 4 segments; root not reserved | `ctx[:root]` or `FlowchartRuntime::Step.dig(ctx[:root], :a, 0)` |
| `output` | ctx key | identifier; not an `OUTPUT_RESERVED` name | the key (use with `assign`) |
| `expression` | Ruby source | one statement, `safe_expression?` | `(source)` |
| `literal` | string | `max_length` | string literal |
| `template` | Liquid source | parses | `FlowchartRuntime::Template.render("…", ctx)` |
| `enum` | one of `values` | `not_in_list` | string literal |
| `flag` | JSON boolean | `not_boolean` | `true` / `false` |
| `integer` / `decimal` | number | `min` / `max` | `Integer` / `Float` literal |
| `list` | array; `item:` role | each item | array of string literals |
| `mapping` | `[{ "key", "value" }]`; `key:` / `value:` roles | each pair | hash literal |
| `conditions` | Decision-style condition group | `invalid_conditions` | condition expression |
| `entity_attribute` | attribute slug; `of: :bound` | against the bound entity when the generator context has one | string literal |
| `reference` | value from `source:` | presence only | string literal |
| `localized_text` | `{ "en", "zh-CN" }` | `en` required | hash literal |

Options per field: `default`, `required`, `example`, `visible` (a `{ field: value }` rule), `group` (`:main` or `:advanced`), `placeholder`, `max_length`, `multiline`, `min`, `max`, `values`, `item`, `key`, `value`, `of`, and `source`. An unknown option or an unknown statement raises `ArgumentError` when the class loads. `requires :field, when: { other: value }` makes a field conditionally required and also implies its visibility. `validate { |cfg, errors| errors.add(:field, :code, **vars) }` adds cross-field rules. A hidden field is neither validated nor read; `value(:field)` returns its default. `sample_input` is the defaults merged with each field's `example`.

Reserved names (`CodeGenerators::ConfigSchema`):

- `SEEDED_KEYS` — `params bound_entity customer_id authentication current_user_id current_user_role audience device_type request_ip user_agent locale request_id flowchart_id`, the keys a run starts with (see [Flowchart runtime](flowchart-runtime)).
- `OUTPUT_RESERVED` — `SEEDED_KEYS` plus `errors error_details submission_outcome result`. No `output` field may name one.
- `INPUT_FORBIDDEN_ROOTS` — `errors error_details submission_outcome result`. An `input` path may not start there.

### Capabilities: transport retry, timeouts, circuit breaker

Three statements add standard advanced fields to HTTP-style actions. The export lists them under `capabilities` so the step form can render one shared panel.

- `transport_retry(idempotent_when: { httpMethod: %w[GET HEAD PUT DELETE OPTIONS] }, or_present: :idempotencyKey)` adds `retryOnTransportError` (flag, default false) and `retryAttempts` (integer 1–2, default 1). Turning retry on for a request that is not idempotent and has no idempotency key fails validation with `retry_not_idempotent`. An empty `idempotent_when` means the action is always idempotent (`download_file`).
- `timeouts(open: 3, read: 7)` adds `connectTimeout` (1–5) and `readTimeout` (1–9). Their sum must stay within `RUN_LIMIT_SECONDS` (10), else `timeout_exceeds_run_limit` with `cap`.
- `circuit_breaker_option` adds `circuitBreaker` (flag), `breakerName` (default: the action key), `failureThreshold` (1–20, default 5) and `resetTimeoutSeconds` (10–3600, default 60).

`api_call` and `send_webhook` have all three; `download_file` has retry, timeouts and breaker; `ai_inference`, `currency_convert` and `geolocation_lookup` have timeouts and breaker only. The runtime side is `FlowchartRuntime::Http.request` on [Flowchart runtime](flowchart-runtime).

### Validation errors and I18n keys

`validate_config` returns `ConfigSchema::ConfigError(field, code, message)` objects. The message is looked up at call time as `flowchart_actions.<action>.errors.<code>`, then `flowchart_actions.shared.errors.<code>`. Shared codes: `required`, `invalid_identifier`, `reserved_name`, `invalid_expression`, `not_one_statement`, `too_long`, `invalid_template`, `not_in_list`, `not_boolean`, `invalid_integer`, `out_of_range`, `invalid_decimal`, `invalid_list`, `invalid_mapping`, `invalid_conditions`, `unknown_attribute`, `unknown_reference`, `en_required`, `retry_not_idempotent` and `timeout_exceeds_run_limit`. The flowchart server validator wraps each as `maint_core.flowcharts.config_problems.step_invalid`.

Element schemas use the prefix `flowchart_elements`: `flowchart_elements.<type>.errors.<code>`, then `flowchart_elements.shared.errors.<code>` (`required`, `unknown_field`, `unknown_reference`, `not_in_list`, `invalid_expression`, `not_one_statement`, `invalid_conditions`). The validator wraps them as `maint_core.flowcharts.config_problems.element_invalid` and forwards each error's `field` on the `element_config_invalid` problem.

Keys per action, in the area file that owns it (`config/locales/flowchart_actions_<area>.{en,zh-CN}.yml`):

```yaml
en:
  flowchart_actions:
    send_sms:
      label: Send SMS
      description: …
      fields:
        templateKey:
          label: …
          help: …
          placeholder: …
          options: { … }        # enum option labels, keyed by the normalized value
      errors: { … }             # action-specific validate codes
  flowchart_runtime:
    errors:
      send_sms:
        suppressed: …           # codes the emitted code passes to Step.fail
```

Field text falls back to `flowchart_actions.shared.fields.<field>`. Enum option keys are `value.to_s.downcase.gsub(/[^a-z0-9]+/, "_")`. Category labels are `flowchart_actions.categories.<key>` and the empty option label is `flowchart_actions.shared.none` (both in `flowchart_actions_catalog`). Generic runtime codes (`record_not_found`, `timed_out`, `http_status`, `circuit_open`, `blocked_destination`, …) live in `config/locales/flowchart_runtime.{en,zh-CN}.yml`. The area files are `background_file`, `cache_lock_schedule`, `catalog`, `communication`, `data_collections`, `data_text`, `data_values`, `model_queries`, `model_records`, `outcome_payments`, `records_new`, `resilience`, `security`, `service_utility`, `shared`, `sms_document`, `tables_new` and `validation`. See [Internationalization](internationalization).

### ActionCatalog export

`CodeGenerators::ActionCatalog.export(locale:)` returns:

- `locale`, `categories` (`[{ key, label }]`, only categories in use, in `CATEGORY_ORDER`: `model validation data communication security background file caching concurrency resilience scheduling payments outcome service utility`), and `actions`, sorted by category then key.
- per action: `key`, `category`, `label`, `description`, `icon`, `color`, `singleUse`, `privileged`, `fields`, `capabilities` (`transportRetry { idempotentWhen, orPresent, maxAttempts: 2 }`, `timeouts { open, read, cap }`, `circuitBreaker`).
- per field (`ActionCatalog::FieldPresenter`): `name`, `role`, `control`, `label`, `help`, `placeholder`, `default`, `required`, `group`, `options`, `min`, `max`, `visibleWhen`, `requiredWhen`, `variablePicker`, `source`, `itemRole`, `keyRole`, `valueRole`, `multiline`, `maxLength`. Optional enums get a leading `{ value: "", label: <none> }` option.
- `digest` — SHA-256 over the locale-independent payload (keys, categories, presentation, field structure, option values and capabilities). It changes when the schema changes and stays the same between `en` and `zh-CN`.

Metadata categories are folder-based; `CATEGORY_FROM_METADATA` maps `model_operations`→`model`, `data_operations`→`data`, `file_operations`→`file`, `scheduling_time`→`scheduling` and `service_invocation`→`service`. The `customer:` argument is accepted but unused. The JSON Schema is `app/services/code_generators/action_catalog.schema.json`; `action_catalog_contract_spec` validates the `en` and `zh-CN` exports and the fixture against it.

The editor embeds the export on the canvas mount in `app/views/admin/maintenance/flowcharts/_editor.html.erb` as `data-flowchart-canvas-action-catalog-value`, and `flowchart_canvas_controller.js` passes it to `setActionCatalog` (`flowchart/constants/action_registry`), which the step form reads. The assistant palette is built from the same catalog by `FlowchartDefinitions::Assistant::SchemaGenerator`.

Two tasks write snapshots that specs compare against:

- `bin/rails action_catalog:fixture` writes `spec/javascript/fixtures/action_catalog.sample.json` from `ActionCatalog.sample_export` (a test-only fixture generator plus `find_model`, `api_call`, `assign_value`, `send_template_email` and `query_models`). The Vitest suite reads it.
- `bin/rails ai_assistant:flowchart_schema` regenerates the assistant's `structure_schema.palette.json`.

### Element schemas and ElementCatalog

Element generators declare their `properties` with `config_schema ported: true`, using the same roles and options as step actions. Process has no element generator and no element fields; its single action is the Steps tab.

| Type | Field | Role | Default | Shown when | Notes |
|------|-------|------|---------|------------|-------|
| `start` | — | — | — | — | Label and Notes only |
| `end` | `responseType` | `enum` `none` / `value` | `none` | always | required; the default fills an omitted value |
| `end` | `returnValue` | `expression` | — | `responseType: value` | required when shown; written to `ctx[:response]` |
| `decision` | `routeBy` | `enum` `value` / `condition` | `condition` | always | required |
| `decision` | `subject` | `expression` | — | `routeBy: value` | required when shown |
| `decision` | `condition` | `conditions` | — | `routeBy: condition` | required when shown; flat group |
| `loop` | `loopType` | `enum` `while` / `for_each` | `while` | always | |
| `loop` | `runOnceFirst` | `flag` | `false` | `loopType: while` | |
| `loop` | `condition` | `conditions` | — | `loopType: while` | required when shown |
| `loop` | `collection` | `input` | — | `loopType: for_each` | required when shown; a path without `ctx.` |
| `loop` | `itemVariable` | `literal` | `item` | `loopType: for_each` | |
| `loop` | `maxIterations` | `integer` 1–10,000 | `100` | always | |
| `loop` | `stopWhen` | `conditions` | — | always | `group: :advanced` |
| `loop` | `skipWhen` | `conditions` | — | `loopType: for_each` | `group: :advanced` |
| `loop` | `indexVariable` | `literal` | `index` | `loopType: for_each` | `group: :advanced` |
| `loop` | `collectInto` | `output` | — | `loopType: for_each` | `group: :advanced` |
| `subflow` | `flowchartId` | `reference` (`source: :flowcharts`) | — | always | required |

Element schemas differ from step-action schemas in one rule: `ConfigSchema#validate_unknown_keys` reports every undeclared key as `unknown_field`, except `STRUCTURAL_CONFIG_KEYS` (`description label steps condition io_overrides inputs outputs`). Step actions ignore extra keys. Generators add cross-field rules in `validate` blocks: `DecisionGenerator` checks the branch topology (see "Decision generator") and `LoopGenerator` checks the collection path, `itemVariable` / `indexVariable` (`reserved_header_local`, `colliding_loop_variables`) and its condition groups.

Shared pieces:

- `CodeGenerators::ConnectionSchema` — `literal :label` and `literal :description, multiline: true` (label `flowchart_elements.connection.fields.*`). It describes the connection form only; the server does not validate connection properties against it. `matchValue` and `fromPort` are connection attributes the Branches tab writes, not schema fields.
- `CodeGenerators::ConditionOperators` — `BINARY` (`== != > >= < <= contains starts_with ends_with matches_regex in_range is_type`), `UNARY` (`is_true is_false is_empty is_not_empty is_nil`) and `COUNT` (`== != > >= < <=`, record-count comparisons). Labels are `flowchart_elements.operators.<key>`. Generated record-count conditions load the entity through `FlowchartRuntime::EntityResolver.find(id, customer_id: ctx[:customer_id])`, so another tenant's entity raises instead of being counted.
- `CodeGenerators::ConditionRules.errors(condition, field:, required:)` — validates a flat group for Decision `condition` and Loop `condition` / `stopWhen` / `skipWhen`, so a group that passes always builds. Codes under `flowchart_elements.conditions.errors`: `invalid_condition`, `empty_condition`, `invalid_row`, `nested_group`, `missing_entity`, `unknown_count_operator`, `missing_left`, `missing_operator`, `unknown_operator`, `missing_right`, `invalid_regex`. Blank and non-Hash values are left to the schema (`required`, `invalid_conditions`).
- `Shared::ConditionBuilder` compiles a group to Ruby. It raises `ArgumentError` on an unknown operator, an unknown count operator or a nested group; there is no `==` fallback. `is_true` → `!!left`, `is_false` → `!left`, `is_empty` / `is_not_empty` → `blank?` / `present?`, `is_nil` → `nil?`; `> >= < <=` go through `FlowchartRuntime::ConditionInput.compare`.

`CodeGenerators::ElementCatalog.export(locale:)` returns:

- `locale` and `types`, in `TYPE_ORDER` (`start end process decision loop subflow`); per type `type`, `label`, `defaultLabel`, `tabs` and `fields`.
- `tabs` — `general`, then `steps` (process) or `branches` (decision), then `io`, then `advanced` when any field has `group: "advanced"` (only Loop today).
- `fields` — the same `ActionCatalog::FieldPresenter` JSON as step fields (`name`, `role`, `control`, `label`, `help`, `placeholder`, `default`, `required`, `group`, `options`, `min`, `max`, `visibleWhen`, `requiredWhen`, `variablePicker`, `source`, …), built with `i18n_prefix: "flowchart_elements"`. Process exports `[]`.
- `connection.fields` (from `ConnectionSchema`), `operators` (`ConditionOperators.export`: `{ value, label, unary, count }`) and `chrome` (`label` and `notes`, whose stored `key` is `description`). The Notes label, for elements and for the connection `description` field, is the shared `common.labels.notes` key.
- `digest` — SHA-256 over the locale-independent shape (types, tabs, field structure, option values, connection fields, operator values); identical for `en` and `zh-CN`.

Export raises `ArgumentError` when a registered element generator is not `config_schema ported: true`. `app/views/admin/maintenance/flowcharts/_editor.html.erb` embeds the export once on the canvas root as `data-flowchart-canvas-element-catalog-value`; `flowchart_canvas_controller.js` passes it to `setElementCatalog` in `flowchart/constants/element_registry.js` (`elementFields`, `elementTabs`, `elementLabel`, `elementDefaultLabel`, `connectionFields`, `conditionOperators`, `chrome`). The canvas embeds it rather than the property editor because the canvas also seeds element defaults. The editor has no JavaScript schema file: the former JS schema copy, its Ruby mirror task and the CI parity step are gone, and the Ruby schemas are the only source. The Vitest suite reads `spec/javascript/fixtures/element_catalog.sample.json`, an `en` export. Regenerate it with `bin/rails element_catalog:fixture`; `element_catalog_spec.rb` fails while it differs from a fresh export.

The assistant uses the same schemas: its palette lists each element type's `config_fields` (role, required, default, options, min/max, `visibleWhen`) from the catalog, and `FlowchartDefinitions::Palette::ELEMENT_DOCS` adds only the behaviour a schema cannot express (connection rules, Decision branches on connections, the condition group shape, loop semantics). `FlowchartDefinitions::UiConfigSchema` seeds element defaults from `ConfigSchema#visible_defaults` (only fields visible under the defaults, so an End seeds `responseType: "none"` alone), and `FlowchartDefinitions::Normalizer` labels new elements with `flowchart_elements.<type>.defaultLabel` in the current locale.

Element text lives in four locale pairs, with identical keys and `%{}` variables in `en` and `zh-CN`:

- `flowchart_elements.{en,zh-CN}.yml` — `chrome`, `shared` (`none`, `errors`), per type `label` / `defaultLabel` and the Start / End / Subflow fields, `connection.fields`, `template_labels` and `trace`.
- `flowchart_elements_conditions.*` — `operators` and `conditions.errors`.
- `flowchart_elements_decision.*` and `flowchart_elements_loop.*` — that type's `fields` and `errors`.

Field keys are `flowchart_elements.<type>.fields.<field>.{label,help,placeholder,options.<value>}`. `element_i18n_keys_spec` checks every exported key in both locales; `spec/config/flowchart_elements_locale_spec.rb` checks key and `%{}` parity for every `flowchart_elements*.yml` pair. To change an element field: edit the generator's `config_schema`, add the keys to both locales, update the generator spec, then run `element_catalog_spec`, `element_i18n_keys_spec`, `flowchart_elements_locale_spec` and `bin/rails ai_assistant:flowchart_schema`, and refresh the JS fixture.

### Emission helpers

Ported generators build `generate_body` from helpers instead of string-splicing config:

- `value(:f)` — the raw stored value, or the default.
- `read(:f)` — the role-specific Ruby shown in the roles table. A value that cannot be emitted safely raises `GeneratorError` with `maint_core.flowcharts.generator_unsafe_value`.
- `literal(v)` — `v.inspect`.
- `assign(:outputField, expr)` — `ctx[:<stored key>] = expr`, after checking the key is a safe identifier.
- `fail_with(code, field:, unless:, **details)` — `return FlowchartRuntime::Step.fail(ctx, :code, field: :f, …) unless expr`. Action-scoped codes are passed quoted, e.g. `attempt('"clone_model.failed"', …)`, so the symbol becomes `:"clone_model.failed"`.
- `attempt(code, *error_classes) { lines }` — `FlowchartRuntime::Step.attempt(ctx, :code, Classes) do … end`; only the listed classes are rescued.
- `body(*lines)` — joins non-nil lines.

```ruby
# app/services/code_generators/element_types/process/payments/refund_payment_generator.rb
          def generate_body
            args = [
              "payment: #{read(:payment)}",
              "amount: #{read(:amount)}"
            ]
            args << "reason: #{read(:reason)}" if value(:reason).to_s.strip.present?
            body("FlowchartRuntime::Payments.refund(ctx, #{args.join(', ')})")
          end
```

### Body rules (BodyLint)

`CodeGenerators::BodyLint.check(body, outputs:)` is the catalog-wide rule set. It runs in specs (`ported_catalog_spec` lints every action's sample body, including every enum variant), not during generation:

- at most `MAX_LINES` (12) non-blank lines;
- forbidden: `ctx[:result]`, the retired private last-error key, `Timeout.timeout`, `sleep`, `rescue => e`, `rescue StandardError`, `rescue Exception`, `I18n.t`;
- no bare local `params` or `model` (detected with Prism); read them from `ctx`;
- `unchecked_fallible`: a body that ends in `true` after `.save`, `.destroy`, `.update`, `.deliver*`, `Http.request`, `Entries.save|upsert|destroy` or `Gateway.send`;
- `undeclared_output`: every `ctx[:key] =` must be a declared output or one of `STANDARD_WRITES` (`model contract errors error_details submission_outcome current_user`).

`runtime_facade_emission_spec` adds that a call to a runtime facade that raises (for example `FlowchartRuntime::Document.pdf`) must be wrapped in `Step.attempt` with that facade's `Error`.

### Reference sources

A `reference` field names a source from `CodeGenerators::ReferenceSources`: `email_templates`, `sms_templates`, `constants`, `entities`, `entity_associations`, `pages`, `flowcharts`, `job_classes` and `service_classes`. Each source implements `options(customer:, query:, limit: 50, **filters)` (`entity_associations` filters by `entity_id`; `flowcharts` drops `exclude_id`). `constants`, `entities`, `pages` and `flowcharts` go through `accessible(relation, customer)`, which is `where(customer_id: [customer.id, nil])` and `none` without a customer (`pages` and `flowcharts` list launched rows only). `flowcharts` backs the Subflow `flowchartId` picker and returns `{ value: id, label: name }`. `email_templates` lists the customer's active templates, `sms_templates` the active platform templates (by key), `job_classes` the `ApplicationJob` subclasses under `app/jobs`, and `service_classes` `Invocable::SERVICE_ALLOWLIST`.

The step form loads options from `GET /:cid/admin/maintenance/flowcharts/reference_options/:source.json` (platform prefix: `/81721200/admin/maintenance/platform/flowcharts/reference_options/:source.json`), served by `Admin::Maintenance::FlowchartReferenceOptionsController#show`. It is owner-only, like the rest of the editor (`RouteAuthorization` plus `FlowchartVisibility`). It answers JSON only (other formats 406), returns 404 with `maint_core.flowcharts.reference_options.unknown_source` for an unknown source, trims `q` to 100 characters, caps results at 50, accepts an Integer `entity_id` and an Integer `exclude_id` (only `flowcharts` reads it; the editor does not send it today), and responds `{ options: [{ value, label }] }`. The route constrains `source` to `/[a-z][a-z0-9_]*/`. The editor builds the URL from `urls.referenceOptions` with a `__SOURCE__` placeholder.

### How to add a step action

1. Add one file `app/services/code_generators/element_types/process/<category>/<action>_generator.rb`: a `BaseGenerator` subclass with `generator_metadata` (name, category, presentation), `config_schema ported: true`, and a `generate_body` built from the emission helpers that passes BodyLint.
2. Add the keys to one locale pair `config/locales/flowchart_actions_<area>.{en,zh-CN}.yml`: label, description, every field's label (and help, placeholder, option labels where used), every action `validate` code, and every runtime code the body passes to `Step.fail` under `flowchart_runtime.errors.<action>`. Keys and `%{}` variables must match across locales.
3. Add a generator spec, then run `action_i18n_keys_spec` (every catalog key exists in both locales with `fallback: false`; runtime codes must be literal or explicitly expanded), `runtime_facade_emission_spec`, `ported_catalog_spec`, `generator_inventory_spec` (the expected key list) and `action_catalog_contract_spec`.
4. Regenerate the snapshots when they include the action: `bin/rails action_catalog:fixture` and `bin/rails ai_assistant:flowchart_schema`.
5. Add the action to [Flowchart step actions](flowchart-step-actions).

The test environment sets `config.i18n.raise_on_missing_translations = true`, so a missing key fails the spec that renders it.

### How ActivityGenerator delegates

For a non-container element, `method_body` calls `find_element_type(type)`, builds `generator_class.new(element, context)`, and uses `generate_body`. For a process, `generate_process_body` maps `properties.steps`. `generate_step_code` looks up `find_step_action(action)` and then `validate_generator!`. A process holds at most one action (`StructureValidator` / `steps.maxItems: 1`). That action body becomes the step method body — no lambda wrapper. An empty Process emits `true`. A false or nil return from the action fails the Railway step.

`Flowchart#generate_activity` assigns the result and skips the assignment entirely when the save is a tenant override. See [Flowchart builder](flowchart-builder). The compiled Railway shape (one step per box, `CANVAS`, `collect_errors`) is [Flowchart runtime](flowchart-runtime).

### Decision generator

`DecisionGenerator` (version 2.0.0) reads `routeBy`: `condition` (default) compiles the `condition` group with `Shared::ConditionBuilder`; `value` compares `read(:subject)` with each branch's match value. Branch data is never read from the element: the branches are the outgoing connections, ordered by `fromPort` (`port_N`, then original order) by `ActivityGenerator::NameDeriver.outgoing_branches`.

Without flowchart topology (code-generator preview, standalone test run, I/O extraction) `generate_body` returns the evaluated condition or the subject `.to_s`:

```ruby
(!!ctx.dig(:vip) || FlowchartRuntime::ConditionInput.compare(ctx.dig(:total), ">=", 500))
(ctx[:tier]).to_s
```

With topology (`context[:flowchart_topology][:outgoing_branches]`, each `{ "signal", "semantic", "matchValue" }`) it returns the taken branch's signal. Yes / No mode emits a ternary to the `true` branch and the `false` branch (else Otherwise); value mode emits `case` / `when` with `else` the Otherwise branch (empty match value), else the last branch.

```ruby
  def is_vip(ctx, **)
    ((!!ctx.dig(:vip) || FlowchartRuntime::ConditionInput.compare(ctx.dig(:total), ">=", 500))) ? Routes::IsVip::Yes : Routes::IsVip::No
  end

  def tier(ctx, **)
    case (ctx[:tier]).to_s
    when "gold" then Routes::Tier::Gold
    else Routes::Tier::Otherwise
    end
  end
```

When topology is present, `validate` adds the branch rules, all on field `branches` with messages in `flowchart_elements.decision.errors`: `too_few_branches` (fewer than two), `multiple_otherwise`, `duplicate_match_value` (after trimming), and in Yes / No mode `invalid_condition_match` (only `true`, `false` or empty) and `missing_yes_branch` (Yes plus No or Otherwise). `ConfigValidator` passes the topology, so the editor's Validate reports them too.

### End and Subflow

`EndGenerator` reads `responseType` (`none` or `value`). `none` emits `true`, but `ActivityGenerator` skips that End entirely (`stepless_end?`) and wires incoming edges to `End(:success)`. `value` writes `ctx[:response]` from `returnValue` and is a real step.

`SubflowGenerator` declares one field, `flowchartId` (`reference`, `source: :flowcharts`, required). `generate_body` returns nil. `ActivityGenerator` emits `step Subprocess(<ChildActivity>), id: :<name>` and a header line `# Subflows: <Class> (#<id> "<name>"), …`. Two references to one child get distinct ids. `ActivityClassBuilder#load_subflow_activities` evaluates each child source once (`loaded_ids`).

### Generated header

`ActivityGenerator::HeaderBuilder` emits locale-independent English comments:

```text
# frozen_string_literal: true
#
# Generated from flowchart #<id> "<name>". Do not edit; regenerate it from the flowchart editor.
# Bound entity: <label>
```

No `#<id>` when the flowchart is unsaved (`# Generated from flowchart "…"`). Bound-entity variants: `# Bound entity: <label>`, `# Bound entity: supplied at runtime (shared flowchart)`, or `# No bound entity`. User text is sanitized (`ActivityGenerator.safe_comment_text`). There are no Trigger, Multi-source, Model class, or Contract class lines. Every step method is preceded by `# <element label>`.

### NameDeriver

`ActivityGenerator::NameDeriver` reserves Railway instance methods, Ruby keywords, and `collect_errors` (`initialize` → `initialize_step`). Labels with no ASCII letters become `<type>_<n>`. Class names split on `/[^A-Za-z0-9]+/`. The structure validator's `class_name_collision` rule compares the parent class name to each resolved subflow when both `flowchart:` and `subflow_lookup:` are supplied.

Branch identities from connection `matchValue`: `true` → `Yes` / `:yes`, `false` → `No` / `:no`, empty → `Otherwise` / `:otherwise`; any other match value → ASCII words camelized (`high` → `High` / `:high`, `value_3` → `Value3` / `:value_3`); a leading digit gets a `Value` prefix; no ASCII letters or digits → `Branch<n>` / `:branch_<n>` (1-based); semantics `success` and `failure` become `success_branch` / `failure_branch`; duplicates within a decision get a numeric suffix. Decision module names are the camelized step names, unique within `Routes`. Loop exits bind `Routes::<Loop>::Done` / `:done`.

### ConflictResolver

`CodeGenerators::ConflictResolver` renames an element's output only when another writer of the same pin is an ancestor in the dataflow graph (loop back-edges excluded). Writers on mutually exclusive branches, and terminal Ends, keep the original key. Rename format is `<pin>_<sha1(element_id:pin)[0..3]>` (longer prefix if that collides). The editor's computed overrides apply the same rule. Unsafe author `renamed_to` values are ignored and do not block the automatic rename.

### EmissionRewriter

`CodeGenerators::EmissionRewriter.call_element` resolves a `ctx[:pin]` read (B2):

1. Explicit input override (`override_key`).
2. Tombstone (`""`) — the read stays `ctx[:pin]`.
3. Candidate producers = the reader itself when it writes the pin, then upstream writers, latest first. One candidate → that candidate's effective key. Several → the latest candidate's key when it dominates the reader and is not the reader; otherwise `FlowchartRuntime::Outputs.latest(ctx, :key_a, :key_b, …)`.
4. `ctx.dig` / `fetch` / `key?(:pin)` follow the same decision: a single other key swaps the symbol; a selection replaces only the `ctx` receiver with `FlowchartRuntime::Outputs.view(ctx, :pin, …)`.
5. Implied `FlowchartRuntime::Entries.scope(ctx)` reads are tagged `implied: true` by `BodyAnalyzer` and are not rewritten.

Saved author `outputs.renamed_to` values that pass `safe_target?` are folded into the effective key map.

### WiringPlanner

`ActivityGenerator::WiringPlanner` is a pure planner. Input is the DFS-ordered step list; output is `magnetic` / `outputs` plus the `CANVAS` `routes` / `ends` maps.

- A step's success edge to its single successor is implicit only when the successor is the next declared step and is attracted by it; otherwise it is explicit `Output(:success) => Id(:<next>)`, or `Output(:success) => End(:success)` when the successor is a stepless End.
- A declared step whose previous declaration is a decision, or whose previous declaration does not flow into it implicitly, gets `magnetic_to: nil`.
- A terminal step that is not the last declaration gets `Output(:success) => End(:success)`.
- Every decision also gets `Output(:success) => Track(:failure)`.
- An edge into a loop header from its body is always explicit (`Output(:success) => Id(:<loop>)`). The header's Done signal is `Output(Routes::<Loop>::Done, :done) => Id(:<exit>)` (or `End(:success)`). An empty-body header (no canvas body) also gets `Output(:success) => Track(:failure)`.
- Successors that are element ids resolve only through the element-id map (a string is never treated as a step id first).

### Tenant-scoped model operations

Record actions call `FlowchartRuntime::Entries` (documented on [Flowchart runtime](flowchart-runtime)); none of them builds its own `EntityEntry` query:

- `new_model` — `Entries.scope(ctx).new(customer_id: ctx[:customer_id])` into `resultVar` (default `model`).
- `save_model` — `Entries.save(ctx, ctx[:contract].model)`; it has no fields and saves the model of the contract `build_contract` / `validate_contract` prepared.
- `update_model` — `ctx[:contract].sync` when a contract is present, else `Entries.assign(model, ctx[:params])`; then `Entries.save`. `changesVar` optionally captures `saved_changes`.
- `upsert_model` — `Entries.upsert(ctx, match: { … }, attributes: ctx[:params])` keyed by `matchFields`; writes `resultVar` and `createdVar`.
- `destroy_model` — `mode` `delete` (`Entries.destroy`) or `archive` (`Entries.archive`, stamping `archiveField` and optionally `archivedByField`).
- `clone_model` — `FlowchartRuntime::Clone.copy` inside `attempt("clone_model.failed")`.
- `query_models` — `Entries.query` with `conditions`, `select`, `returns` (`records` / `values`), pagination, `limit`, `orderBy` (checked with `ConditionInput.safe_column?`), `distinct`.
- `count_records` — `Entries.tally` with `resultAs` `count`, `exists` or `absent`.
- `aggregate_query` — `Entries.aggregate`; `having` must match `QueryBuilder::SAFE_HAVING_RE`.
- `bulk_import` — `FlowchartRuntime::BulkImport.run` (`MAX_ROWS` 1000, `onDuplicateKey` `update` / `skip`, `uniqueBy` may not name an internal column).
- `batch_operation` — `FlowchartRuntime::Batch.run`; an incompatible source fails with `batch_operation.incompatible_scope`.
- `find_model`, `set_record_fields`, `related_record`, `load_current_user` and `next_sequence_number` are listed on [Flowchart step actions](flowchart-step-actions).

### Expression safety and invocation

An `expression` field must be one statement that passes `ExpressionSafety#safe_expression?`; an `input` field must be a dotted identifier path. `ActivityGenerator` runs `validate_config` before every `generate_body`, so a value edited outside the editor is still validated, and `read` re-checks `input` / `output` identifiers before emitting them. Element types use the same roles: End `returnValue` and Decision `subject` are `expression` fields, Loop `collection` is an `input` path and `collectInto` an `output` key.

`FlowchartRuntime::Invocable` resolves allow-listed class names only. It rejects ActiveRecord model classes and `FORBIDDEN_METHODS` (`delete_all destroy_all update_all delete destroy update_column update_columns insert_all upsert_all find_by_sql connection`). `method!` requires an application-defined method whose `source_location` is under `Rails.root.join("app")` and whose owner is not Object / Kernel / BasicObject / Module / Class. `Class#new` is allowed only when `initialize` is application-defined. `invoke_service` and `enqueue_job` (`Invocable.job!`) use it at runtime.

### Seeded defaults

`authorize` reads its user from `userExpression` (default `current_user`). Only an `Authentication::User` is checked; anything else, including the plain Hash `load_current_user` writes, falls back to `FlowchartRuntime::Authentication.session(context: ctx[:authentication], customer_id: ctx[:customer_id])`. A loaded user Hash never grants access by itself. `send_template_email` looks up `Customer.find_by(id: ctx[:customer_id])`.

### Platform UI

`Admin::Maintenance::Platform::CodeGeneratorsController`:

- `index` / `show` — `IndexPresenter` over `step_action_generators` and `element_type_generators`, filtered by `category`, `kind`, and `element_type`.
- `new` / `create` — `FormDataExtractor` and `SourceAssembler` build the file. `build_file_path` rejects blank names, `..`, and slashes. Element types go to `element_types/<type>/<name>_generator.rb`. Step actions go to `element_types/process/<category>/<name>_generator.rb`. The path must stay under `app/services/code_generators`.
- `edit` / `update` — `FormDataExtractor#extract` reads the file. If `generate_body` changes, `MetadataDSL.bump_patch` rewrites the `version` string and the registry reloads again.
- `destroy` — deletes the file and reloads the registry.

`save_generator` runs `GeneratorValidator.validate_source` before `File.write`. Nested routes on the same resource:

- `CodeGenerators::ValidationsController#create` — `{ valid, errors }` for posted `source_code`.
- `CodeGenerators::PreviewsController#show` — `generate_step_method` from `sample_input`. A slug containing `..` is 400.
- `CodeGenerators::TestRunsController#create` — `CodeGenerators::TestRunner.run` with `sample_config` JSON.
- `CodeGenerators::SourcePreviewsController#create` — assembles source without writing it.
- `IoParamsController` and `ElementTypeIoParamsController` — POST inspection of generator I/O. The same inspection exists on the flowchart editor as read-only POSTs that do not execute generated code.

Slug constraint on the resource is `%r{[^.]+}`. `set_generator_info` 400s when the slug contains `..`, and 404s unless `PathIdentity.find` and the file both exist.

## Where to pay attention

:::attention
`CodeGenerators::GeneratorRegistry#discover!` is the registration mechanism. Classes are indexed from `registered_names` after the file is loaded. Do not look for a `register!` class method on `BaseGenerator`. A generator that is not under `element_types/<supported-type>/` or `element_types/process/<category>/` never enters the hash, and `ActivityGenerator` then raises `:unknown_element_type` or `:unknown_step_action`. Stored flowcharts that still name retired actions are not converted; they fail generation until the step is replaced in the editor.
:::

:::attention
`ActivityGenerator#generate` returns `nil` when `flowchart.name` is blank or `elements` is empty, before any generator runs. `Flowchart#generate_activity` stores that nil on `activity` (unless the save is an override, which returns first). A page bound to that flowchart fails later in `Pages::PublicSubmission` with an activity-not-generated result.
:::

:::attention
`Admin::Maintenance::Platform::CodeGeneratorsController#save_generator` writes Ruby onto disk under `app/services/code_generators` and reloads the autoloader. `build_file_path` rejects `..` and absolute segments; `set_generator_info` rejects a slug containing `..`. This screen is not a database CRUD screen, and it is not the single-file vendor drop for payments, captcha, or email.
:::

:::attention
`reference` fields are only checked for presence. `ReferenceSources::<Source>.valid?` exists but generation does not call it, so a stale template id or page id is caught at runtime by the helper the step calls, not at save. `entity_attribute` fields are checked against the bound entity only when the generator context has one (activity generation); the editor's Validate button and `validate_config` without context skip that check.
:::

:::attention
`read` on a `conditions` field emits the stored group as a Ruby data literal (`Hash#inspect`), never as Ruby source; the runtime query layer (`FlowchartRuntime::Entries.query`) interprets it. `ConfigSchema` rejects a non-Hash value (`invalid_conditions`) before generation. Decision and Loop elements build Ruby conditions through `Shared::ConditionBuilder` instead, after `ConditionRules` has validated the group; the builder raises on anything the rules would reject (unknown operator, unknown count operator, nested group).
:::

:::attention
Element-type generators read `properties`; step actions read `config`. Swapping those keys makes `extract_config` see an empty hash. Step actions read config only through `value` / `read` and fail only through `fail_with` / `attempt`; a body that reaches for `config[...]` or writes an undeclared ctx key fails the catalog specs.
:::

## Key code

```ruby
# app/services/code_generators/generator_registry.rb
    SUPPORTED_ELEMENT_TYPES = %w[start end decision loop subflow].freeze

    def discover!
      ELEMENT_TYPES_PATH.children.select(&:directory?).each do |type_dir|
        next if type_dir.basename.to_s == "process"
        next unless SUPPORTED_ELEMENT_TYPES.include?(type_dir.basename.to_s)

        scan_directory(type_dir, @element_types)
      end

      if PROCESS_PATH.exist?
        PROCESS_PATH.children.select(&:directory?).each do |category_dir|
          scan_directory(category_dir, @step_actions)
        end
      end
    end
```

```ruby
# app/services/code_generators/base_generator.rb
    def fail_with(code, field: nil, **details)
      unless_expr = details.delete(:unless)
      args = [":#{code}"]
      args << "field: :#{field}" if field
      details.each { |key, source| args << "#{key}: #{source}" }
      line = "return FlowchartRuntime::Step.fail(ctx, #{args.join(', ')})"
      unless_expr ? "#{line} unless #{unless_expr}" : line
    end
```

```ruby
# app/services/code_generators/element_types/end/end_generator.rb
        config_schema ported: true do
          enum :responseType, %w[none value], default: "none", required: true
          expression :returnValue, placeholder: true, visible: { responseType: "value" }
          requires :returnValue, when: { responseType: "value" }
        end
```

```ruby
# app/services/code_generators/action_catalog.rb
      def digest_for(catalog)
        payload = {
          "categories" => catalog["categories"].map { |category| { "key" => category["key"] } },
          "actions" => catalog["actions"].map { |action| digest_action(action) }
        }
        Digest::SHA256.hexdigest(JSON.generate(payload))
      end
```

```ruby
# app/services/code_generators/body_lint.rb
    MAX_LINES = 12
    STANDARD_WRITES = %w[
      model contract errors error_details submission_outcome current_user
    ].freeze
```

```ruby
# app/services/activity_generator.rb
    generator_class = @registry.find_step_action(action)
    unless generator_class
      raise Error.new(
        code: :unknown_step_action,
        message: I18n.t("maint_core.flowcharts.structure_errors.unknown_step_action", action: action.inspect),
        element_id: element_id,
        action: action
      )
    end

    generator = generator_class.new(step, ctx)
    validate_generator!(generator, step.fetch("config", {}), element_id: element_id, action: action)
    generator.generate_body
```

```ruby
# app/controllers/admin/maintenance/platform/code_generators_controller.rb
    def save_generator(file_path, source)
      validation_errors = ::CodeGenerators::GeneratorValidator.validate_source(source)
      if validation_errors.any?
        @errors   = validation_errors
        @kind     = params[:kind]
        @category = params[:category]
        @form_data = ::CodeGenerators::FormDataExtractor.new(params).form_data_from_params
        action     = File.exist?(file_path) ? :edit : :new
        render action, status: :unprocessable_entity
        return
      end

      FileUtils.mkdir_p(File.dirname(file_path))
      File.write(file_path, source)
      Rails.autoloaders.main.reload
      ::CodeGenerators::GeneratorRegistry.instance.reload!

      yield
    end
```

```ruby
# app/services/activity_generator/wiring_planner.rb
    def decision_outputs(descriptor)
      branches_for(descriptor).map { |branch|
        ["Output(#{branch[:signal]}, :#{branch[:semantic]})", wire_target(branch[:target])]
      } + [["Output(:success)", "Track(:failure)"]]
    end
```

```ruby
# app/services/code_generators/emission_rewriter.rb
        ast[:reads].each do |r|
          next if r[:implied]

          replacement = bracket_read_replacement(r[:pin], input_map)
          edits << splice(r, replacement) if replacement
        end
```

Related: [Flowchart step actions](flowchart-step-actions), [Flowchart builder](flowchart-builder), [Flowchart runtime](flowchart-runtime), [Internationalization](internationalization), [Page builder](page-builder), [Entity builder](entity-builder).
