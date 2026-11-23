# Flowchart Builder Phase 1 (Safety and Correctness) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the verified safety and correctness defects of the flowchart builder and enforce one action per Process box end to end.

**Architecture:** Surgical fixes in place. New runtime helper `FlowchartRuntime::Entries` centralises tenant + entity scoping for emitted model lookups; `FlowchartDefinitions::ProcessSplitter` converts multi-action processes into chains for the assistant and a data task. Editor fixes stay inside the existing Stimulus modules; builder endpoints come from route helpers via one `urls` Stimulus value.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, trailblazer-activity 0.17 + dsl-linear 1.2.6, Reform 2.6.2, Stimulus, Tailwind, ViewComponent, RSpec, Vitest (happy-dom), Playwright.

Spec: `docs/superpowers/specs/2026-10-16-flowchart-builder-phase1-design.md` (requirement ids A1–E below refer to it).

## Global Constraints

- No hard-coded user-facing strings. Every new key exists in both `en` and `zh-CN` (idiomatic zh-CN, full-width punctuation). JS text: Stimulus Value with English `default:` and server-passed `data-*-value`. An English value replacing a literal is byte-identical to it.
- No backward-compatibility shims, aliases or dual code paths.
- Every emitted entity lookup goes through `FlowchartRuntime::Entries.scope(ctx)` (customer + bound entity).
- Do NOT run `git commit`. Leave changes in the working tree. `git add -N <new file>` is allowed so diffs include new files.
- Only edit files your task owns (ownership table below). If you need a change in another task's file, report NEEDS_CONTEXT.
- RSpec isolation for parallel agents: use `TEST_ENV_NUMBER=<20 + task number>`; prepare once with `RAILS_ENV=test TEST_ENV_NUMBER=<n> bin/rails db:schema:load`; run `TEST_ENV_NUMBER=<n> bundle exec rspec <files>`.
- Vitest: `npx vitest run --config config/javascript/vitest.config.js <spec files>`; coverage for touched files: add `--coverage --coverage.include=<app file> --coverage.reporter=text`. Touched `app/javascript/**` files stay at 100% lines and branches. No `v8 ignore` pragmas for testable logic.
- Never claim tests pass without pasting real command output into your report.

## Waves and file ownership

| Wave | Task | Agent | Owns (exclusive within the wave) |
|---|---|---|---|
| 1 | 1 Entries + model-op generators | anysys-backend-developer | `app/services/flowchart_runtime/entries.rb`, `app/services/code_generators/element_types/process/model_operations/**`, their specs, new `config/locales/code_generator_model_operations.{en,zh-CN}.yml` |
| 1 | 2 Expression safety + seeded defaults | anysys-backend-developer | `base_generator.rb`, `activity_generator.rb`, `shared/expression_safety.rb`, non-model process generators, `flowchart_runtime/invocable.rb`, `config/locales/code_generator_*.yml` |
| 1 | 3 Runtime context | anysys-backend-developer | `activity_tracer.rb`, `shared/condition_builder.rb`, `shared/operand_converter.rb`, `flowchart_runtime/condition_input.rb`, `config/flowchart_validation.yml`, `app/contracts/entity_entry_contract.rb` |
| 1 | 4 Names + class-name collision rule | anysys-backend-developer | `activity_generator/name_deriver.rb`, `activity_generator/structure_validator.rb`, `config/locales/maint_core.{en,zh-CN}.yml` (structure_errors keys only) |
| 1 | 6 Action configs + picker + condition rows | anysys-frontend-developer | `action_configs/{validation,model,data}_actions.js`, `property_editor/step_manager/action_picker.js`, `property_editor/branch_manager/condition_builder.js`, `config/locales/flowchart_actions.{en,zh-CN}.yml`, `lib/code_generators/config_schemas.rb` |
| 1 | 7 Canvas persistence + navigation | anysys-frontend-developer | `flowchart/canvas/serialization.js`, `flowchart_canvas_controller.js`, `flowchart_canvas/{version_history_mixin,validation_mixin,undo_redo_manager}.js`, `flowchart_canvas/subflow_manager/expansion_mixin.js`, `flowchart/{test_runner_manager,context_variable_provider,input_output_validation_service,element_renderer}.js`, `toolbar_controller.js`, `element_palette_controller.js`, `property_editor/{step_io,element_io}/io_params_client.js` |
| 1 | 9 Property panel open/cancel | anysys-frontend-developer | `property_editor_controller.js`, `property_editor/canvas_sync.js` |
| 2 | 5 Templates + one-action rule + splitter + assistant + fixtures + data task | anysys-backend-developer | `app/models/flowchart/template_builder.rb`, `app/services/flowchart_definitions/**`, `activity_generator/structure_validator.rb`, `lib/tasks/flowcharts.rake`, `config/locales/flowchart_elements.{en,zh-CN}.yml`, multi-step spec fixtures, `maint_core` key `structure_errors.process_multiple_actions` |
| 2 | 8 Canvas editing correctness | anysys-frontend-developer | `flowchart/{clipboard_manager,connection_manager,drag_handler,canvas}.js`, `flowchart/canvas/{external_drop,element_management}.js`, `flowchart_canvas/bottom_panel_mixin.js`, `flowchart_canvas_controller.js` (label values only) |
| 2 | 10 Controllers + views + UI locales | anysys-security-engineer | `base_versions_controller.rb`, `flowchart_traces_controller.rb`, `flowcharts/new.html.erb`, `flowcharts/_editor.html.erb`, `config/locales/maint_core.{en,zh-CN}.yml` |
| 3 | 11 Playwright journey | anysys-qa-engineer | `spec/e2e/flowchart_builder_journey.app.spec.js`, `spec/e2e/helpers/builder_fixtures.{js,rb}` |
| 3 | 12 Reference docs | anysys-backend-developer | `doc/reference/{en,zh-CN}/{flowchart-builder,code-generators,flowchart-runtime}.md` |
| 3 | 13 Verification + data migration + release | anysys-release-engineer (controller runs the write steps) | none (runs commands) |

---

### Task 1: Entry scoping helper and model-operation generators (A1, A2, A5 query_models)

**Files:**
- Create: `app/services/flowchart_runtime/entries.rb`
- Create: `spec/services/flowchart_runtime/entries_spec.rb`
- Create: `spec/services/code_generators/element_types/process/model_operations/tenant_isolation_behaviour_spec.rb`
- Modify: `app/services/code_generators/element_types/process/model_operations/{find_model,upsert_model,check_existence,count_records,pluck_fields,clone_model,batch_operation,bulk_import,update_model,aggregate_query,query_models,save_model}_generator.rb`
- Create: `config/locales/code_generator_model_operations.{en,zh-CN}.yml`
- Modify: matching specs in `spec/services/code_generators/element_types/process/model_operations/` (rewrite assertions that pinned the old unscoped/broken strings: `upsert_model_generator_spec.rb`, `bulk_import_generator_spec.rb`, `save_model_generator_spec.rb`, `find_model_generator_spec.rb`, `update_model_generator_spec.rb`, `query_models_generator_spec.rb`)

**Interfaces:**
- Produces: `FlowchartRuntime::Entries.scope(ctx)` → `ActiveRecord::Relation`; `FlowchartRuntime::Entries.assign(entry, attributes)` → `entry`; `FlowchartRuntime::Entries.where_attributes(relation, conditions, ctx)` → `Relation` (`conditions` is a Hash of attribute slug or `"id"` → value); `FlowchartRuntime::Entries::INTERNAL_COLUMNS`.
- Produces config contract used by Task 5 templates and Task 6 editor: `find_model.idExpression` (default `"params.id"`, ctx-path syntax as other expression fields); `save_model` has no `bang`; `query_models` has no `scope` queryType, no `scopeName`, no `scopeArgs`; `update_model.updateStrategy` options are `save`, `update` only.

- [ ] **Step 1: Write the failing Entries spec**

```ruby
# spec/services/flowchart_runtime/entries_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Entries do
  let(:customer) { create(:customer) }
  let(:schema) do
    [
      { "name" => "Email", "name_slug" => "email", "data_type" => "string" },
      { "name" => "Status", "name_slug" => "status", "data_type" => "string" }
    ]
  end
  let(:entity) { create(:entity, customer: customer, property_schema: schema.to_json) }
  let(:other_entity) { create(:entity, customer: customer, property_schema: schema.to_json) }
  let(:other_customer) { create(:customer) }
  let(:ctx) { { bound_entity: entity, customer_id: customer.id } }

  def entry_for(entity:, customer:, data:)
    create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: data)
  end

  describe ".scope" do
    it "returns only entries of the bound entity and customer" do
      mine = entry_for(entity: entity, customer: customer, data: { "email" => "a@x.io" })
      entry_for(entity: other_entity, customer: customer, data: { "email" => "b@x.io" })
      foreign = create(:entity_entry, customer: other_customer, entity: entity)

      expect(described_class.scope(ctx).pluck(:id)).to eq([mine.id])
      expect(described_class.scope(ctx).where(id: foreign.id)).to be_empty
    end

    it "returns an empty relation when no entity is bound" do
      expect(described_class.scope(ctx.merge(bound_entity: nil))).to be_empty
    end
  end

  describe ".assign" do
    it "writes entity attributes and ignores internal columns and unknown keys" do
      entry = described_class.scope(ctx).new(customer_id: customer.id)
      described_class.assign(entry, { "email" => "c@x.io", "customer_id" => 999, "id" => 7,
                                      "entity_id" => 42, "data" => "{}", "bogus" => 1 })

      expect(entry.email).to eq("c@x.io")
      expect(entry.customer_id).to eq(customer.id)
      expect(entry.id).to be_nil
      expect(entry.entity_id).to eq(entity.id)
    end
  end

  describe ".where_attributes" do
    it "matches entity attributes stored in the JSON data column" do
      hit = entry_for(entity: entity, customer: customer, data: { "email" => "a@x.io" })
      entry_for(entity: entity, customer: customer, data: { "email" => "z@x.io" })

      relation = described_class.where_attributes(described_class.scope(ctx), { "email" => "a@x.io" }, ctx)
      expect(relation.pluck(:id)).to eq([hit.id])
    end

    it "matches id as a column" do
      hit = entry_for(entity: entity, customer: customer, data: {})
      relation = described_class.where_attributes(described_class.scope(ctx), { "id" => hit.id }, ctx)
      expect(relation.pluck(:id)).to eq([hit.id])
    end
  end
end
```

(If the attribute hash key for the type differs from `data_type`, copy the shape used in `spec/models/entity_entry_spec.rb`.)

- [ ] **Step 2: Run it and confirm it fails** — `TEST_ENV_NUMBER=21 bundle exec rspec spec/services/flowchart_runtime/entries_spec.rb` → `NameError: uninitialized constant FlowchartRuntime::Entries`.

- [ ] **Step 3: Implement `FlowchartRuntime::Entries`**

```ruby
# app/services/flowchart_runtime/entries.rb
# frozen_string_literal: true

module FlowchartRuntime
  # Tenant- and entity-scoped access to entity entries for generated activities.
  # Entity attributes live in the JSON `data` column, so attribute predicates go
  # through WhereClauseBuilder's json_extract routing and writes go through the
  # accessors EntityEntry.build_for defines.
  module Entries
    INTERNAL_COLUMNS = %w[id customer_id entity_id entity_version_number data created_at updated_at].freeze

    module_function

    def scope(ctx)
      entity = ctx[:bound_entity]
      return EntityEntry.none unless entity

      EntityEntry.build_for(entity).where(customer_id: ctx[:customer_id], entity_id: entity.id)
    end

    def assign(entry, attributes)
      writable = writable_slugs(entry.class)
      attributes.to_h.each do |key, value|
        slug = key.to_s
        next if INTERNAL_COLUMNS.include?(slug) || !writable.include?(slug)

        entry.public_send("#{slug}=", value)
      end
      entry
    end

    def where_attributes(relation, conditions, ctx)
      rules = conditions.to_h.map do |key, value|
        field = key.to_s == "id" ? "id" : "#{WhereClauseBuilder::DATA_PREFIX}#{key}"
        { "field" => field, "op" => "==", "value" => value }
      end
      WhereClauseBuilder.apply(relation, { "operator" => "AND", "rules" => rules }, ctx)
    end

    def writable_slugs(model_class)
      entity = model_class.respond_to?(:bound_entity) ? model_class.bound_entity : nil
      return [] unless entity

      Array(entity.property_schema_json).filter_map do |attribute|
        slug = attribute["name_slug"].to_s
        slug if slug.present? && model_class.method_defined?("#{slug}=")
      end
    end
  end
end
```

Read `WhereClauseBuilder#build_rule` first: if a literal value is resolved as a ctx path, pass values the way `query_models` does so literals stay literals.

- [ ] **Step 4: Run the Entries spec until green.**

- [ ] **Step 5: Write the failing behaviour spec for emitted code** (`tenant_isolation_behaviour_spec.rb`). For `find_model`, `upsert_model`, `update_model` (contract-less, strategy `save` and `update`), `check_existence`, `count_records`: generate the body with the generator (`klass.new({"action"=>name,"config"=>cfg}, {}).generate_body`), wrap it in `def run(ctx) … end` inside an anonymous class, and execute it with `ctx = Trailblazer::Context({ params: {...}.with_indifferent_access, bound_entity: entity, customer_id: customer.id })`. Assert:
  - `find_model` with `idExpression: "params.id"` and `params.id` of another customer's entry returns false and leaves `ctx[:model]` nil; with an own entry id sets `ctx[:model]`.
  - `upsert_model` matching `id` of another customer's entry creates a NEW own entry; the foreign row's `customer_id` is unchanged.
  - `upsert_model` matching `email` updates the own entry whose `data.email` matches.
  - `update_model` contract-less with params `{ "email" => "n@x.io", "customer_id" => other.id, "entity_id" => 0, "id" => 0 }` updates `email` only.
  - `check_existence` / `count_records` ignore other customers' and other entities' rows.

- [ ] **Step 6: Change the generators.** In each listed generator replace `EntityEntry.build_for(ctx[:bound_entity])` (and any `.where(customer_id: ctx[:customer_id])`) with `FlowchartRuntime::Entries.scope(ctx)`; attribute predicates use `FlowchartRuntime::Entries.where_attributes(<scope>, { … }, ctx)`; contract-less writes use `FlowchartRuntime::Entries.assign(record, ctx[:params])`. Specifics:
  - `upsert_model`: remove `_record.customer_id = ctx[:customer_id]` for found records (new records get it from `scope.new`); `on_duplicate: :update` (Rails 8.1).
  - `update_model`: options `save`, `update`; delete `update_all`/`update_columns` branches and `lockVersion` (no column exists); contract path unchanged.
  - `bulk_import`: remove the `validate:` keyword from `insert_all` / `insert_all!` / `upsert_all`.
  - `find_model`: add `idExpression` (default `"params.id"`, validated with `safe_expression?`/ctx-path rules already used by other fields); default strategy emits `ctx[:<resultVar>] = FlowchartRuntime::Entries.scope(ctx).find_by(id: <expr>)` followed by `ctx[:<resultVar>].present? || (ctx[:_last_error] = I18n.t("code_generator_model_operations.find_model.not_found")) && false`; `find_by` / `where_first` / `where_many` on attributes use `where_attributes`.
  - `save_model`: remove `bang` from `config_schema` and emission; always `ctx[:<contractRef>].save`.
  - `query_models`: delete the `scope` queryType, `scopeName`, `scopeArgs` and the `public_send` path.
  Put every new message for these generators (validation and runtime, e.g. `code_generator_model_operations.find_model.not_found` — en `No matching record was found`, zh-CN `未找到匹配的记录`) in the new files `config/locales/code_generator_model_operations.{en,zh-CN}.yml` (nested YAML, identical key sets and `%{}` variables). Do not use flat dotted `flowchart_actions.*.errors.*` keys: they do not resolve.

- [ ] **Step 7: Update the old string-pinning specs** to assert the new scoped emission, then run all model-operation specs and the new specs: `TEST_ENV_NUMBER=21 bundle exec rspec spec/services/flowchart_runtime/entries_spec.rb spec/services/code_generators/element_types/process/model_operations` → 0 failures.

### Task 2: Expression safety, guard validation, invocation hardening, seeded defaults (A3, A4, A5, B4)

**Files:**
- Modify: `app/services/code_generators/base_generator.rb`, `app/services/activity_generator.rb` (step-code generation only), `app/services/code_generators/shared/expression_safety.rb`
- Modify every non-model process generator that passes a config value into emitted code when it `start_with?("ctx[")` (find them: `rg -n 'start_with\?\("ctx\["\)' app/services/code_generators/element_types/process --glob '!model_operations/**'`), plus `data_operations/string_manipulate_generator.rb`, `communication/api_call_generator.rb`, `data_operations/assign_value_generator.rb`, `security/authorize_generator.rb`, `communication/send_template_email_generator.rb`, `service_invocation/invoke_service_generator.rb`
- Modify: `app/services/flowchart_runtime/invocable.rb`
- Modify: `config/locales/code_generator_rejection_errors.{en,zh-CN}.yml`, `config/locales/code_generator_validation.{en,zh-CN}.yml`
- Test: `spec/services/code_generators/expression_safety_fuzz_spec.rb` (create), `spec/services/activity_generator_guard_spec.rb` (create), specs of each touched generator, `spec/services/flowchart_runtime/invocable_spec.rb`

**Interfaces:**
- Produces: `ActivityGenerator::Error` code `:invalid_guard_condition` (`element_id`, `action` set); message key `code_generator_validation.invalid_guard_condition`.
- Produces: `CodeGenerators::Shared::ExpressionSafety#safe_single_expression?(source)` → Boolean (safe_expression? AND Prism parses exactly one statement).
- Consumes from Task 6 (editor side): `assign_value` no longer offers `env_var` / `credential`.

- [ ] **Step 1: Write the failing fuzz spec.** For each (action, field) pair that currently passes a `ctx[...]` value through unchanged, plus `string_manipulate.pattern` and `api_call.cookies`, build a config from the generator's `sample_input` with that field set to each payload in `["ctx[:a]; Kernel.exit!(1)", "ctx[:a]\nKernel.exit!(1)", "ctx[:a] == ("]` and expect `generator.validate_config(config)` to be non-empty. Also assert the original valid `ctx[:...]` sample still validates and `Prism.parse(generator.generate_body).success?`.
- [ ] **Step 2: Run it; confirm failures** (`TEST_ENV_NUMBER=22 bundle exec rspec spec/services/code_generators/expression_safety_fuzz_spec.rb`).
- [ ] **Step 3: Add `safe_single_expression?`** to `shared/expression_safety.rb`:

```ruby
def safe_single_expression?(source)
  text = source.to_s.strip
  return false if text.empty? || !safe_expression?(text)

  result = Prism.parse(text)
  result.success? && result.value.statements.body.size == 1
end
```

  Route every passthrough through it: when a `ctx[`-prefixed value fails `safe_single_expression?`, `validate_config` adds `I18n.t("code_generator_rejection_errors.unsafe_expression", field: <field label key>)` (add the key in both locales) and `generate_body` must not emit it. `string_manipulate` emits regex patterns as `Regexp.new(#{pattern.inspect})`; `api_call` emits cookie names/values with `.inspect` (or `safe_read` for ctx paths that pass validation).
- [ ] **Step 4: Guard validation.** Write `spec/services/activity_generator_guard_spec.rb`: a flowchart whose process step has `guardCondition: "true\nKernel.puts(1)"` makes `ActivityGenerator.new(flowchart).generate` raise `ActivityGenerator::Error` with `code == :invalid_guard_condition`, `element_id` and `action`; `guardCondition: "ctx[:role] == \"admin\""` generates. Implement in `ActivityGenerator#generate_step_code` before `apply_wrappers` (use `CodeGenerators::BaseGenerator` helper or include `Shared::ExpressionSafety`). Message key `code_generator_validation.invalid_guard_condition` (en: `Guard condition must be a single safe expression`; zh-CN: `守卫条件必须是单个安全表达式`). Also call `apply_wrappers` publicly (make it public on `BaseGenerator` instead of `send`).
- [ ] **Step 5: Remove dangerous types.** `assign_value`: delete `env_var` and `credential` from valid value types, their fields and emission; validation rejects them. `FlowchartRuntime::Invocable`: reject a resolved class that is `< ActiveRecord::Base` and the methods `delete_all destroy_all update_all delete destroy update_column update_columns insert_all upsert_all find_by_sql connection`; `invoke_service` `validate_config` reports the same when the class constant resolves. Spec both.
- [ ] **Step 6: Seeded defaults (B4).** `authorize`: default user expression emits `FlowchartRuntime::Authentication.session(context: ctx[:authentication], customer_id: ctx[:customer_id])`; spec: a ctx built with `FlowchartRuntime::Authentication.send(:new, admin_user)` (private `new`; use `allocate`-free approach: `FlowchartRuntime::Authentication.from_request` with a stubbed request, or `described_class.send(:new, user)`) authorizes the admin role. `send_template_email`: emit `customer: Customer.find_by(id: ctx[:customer_id])`; spec asserts emitted code contains it and no `ctx[:customer]`.
- [ ] **Step 7: Run** `TEST_ENV_NUMBER=22 bundle exec rspec spec/services/code_generators spec/services/activity_generator_guard_spec.rb spec/services/flowchart_runtime/invocable_spec.rb --exclude-pattern "spec/services/code_generators/element_types/process/model_operations/**/*_spec.rb"` → 0 failures (model operations belong to Task 1).

### Task 3: Runtime context (B1, B2, B3, B6)

**Files:**
- Modify: `app/services/activity_tracer.rb`, `app/services/code_generators/shared/condition_builder.rb`, `app/services/code_generators/shared/operand_converter.rb` (only if needed), `app/services/flowchart_runtime/condition_input.rb`, `config/flowchart_validation.yml`, `app/contracts/entity_entry_contract.rb`
- Test: `spec/services/activity_tracer_spec.rb`, `spec/services/code_generators/shared/condition_builder_spec.rb`, `spec/services/flowchart_runtime/condition_input_spec.rb`, `spec/contracts/entity_entry_contract_spec.rb`, `spec/services/flowchart_input_output_validator_spec.rb`

**Interfaces:**
- Produces: `ctx[:params]` is a `HashWithIndifferentAccess` inside every traced run.
- Produces: `FlowchartRuntime::ConditionInput.compare(left, operator, right)` → Boolean for `> >= < <=` (numeric when both sides are numeric or numeric strings; false otherwise). Emitted by `Shared::ConditionBuilder` for those operators.

- [ ] **Step 1: Failing tracer spec.** In `activity_tracer_spec.rb` add: a flowchart whose decision reads `params.amount > 100` (build with the existing spec helpers in that file) traced with `params: { "amount" => "150" }` (string keys, string value as public forms send) takes the `> 100` branch and succeeds; with `"amount" => "50"` takes the other branch.
- [ ] **Step 2: Implement B1** in `ActivityTracer#call` before `execute_with_trace`:

```ruby
input = input.merge(params: input[:params].to_h.with_indifferent_access) if input[:params].respond_to?(:to_h)
```

- [ ] **Step 3: Implement B2.** Add `ConditionInput.compare` (spec it: `compare("150", ">", 100) == true`, `compare("abc", ">", 1) == false`, `compare(nil, "<", 1) == false`, `compare(2.5, "<=", "2.5") == true`). Make `Shared::ConditionBuilder` emit `FlowchartRuntime::ConditionInput.compare(<left>, ">", <right>)` for `> >= < <=`; update `condition_builder_spec.rb` expectations.
- [ ] **Step 4: Implement B3.** Add to `config/flowchart_validation.yml` implicit keys: `params bound_entity customer_id authentication current_user_id current_user_role audience device_type` (keep existing entries). Spec: `FlowchartInputOutputValidator` on a flowchart whose build_contract step consumes `audience` reports no missing-input problem.
- [ ] **Step 5: Implement B6.** In `EntityEntryContract#invoke_validator_proc` pass `config["value"].to_i` for `:length_minimum, :length_maximum` (keep `.to_f` for numeric comparisons). Spec: an entity whose attribute has `{"type"=>"length_maximum","config"=>{"value"=>"50"}}` builds a contract and rejects a 51-character value.
- [ ] **Step 6: Run** `TEST_ENV_NUMBER=23 bundle exec rspec spec/services/activity_tracer_spec.rb spec/services/code_generators/shared spec/services/flowchart_runtime/condition_input_spec.rb spec/contracts/entity_entry_contract_spec.rb spec/services/flowchart_input_output_validator_spec.rb spec/services/code_generators/element_types/decision spec/services/code_generators/element_types/loop` → 0 failures.

### Task 4: Safe generated names and class-name collision rule (B5)

**Files:**
- Modify: `app/services/activity_generator/name_deriver.rb`, `app/services/activity_generator/structure_validator.rb`
- Modify: `config/locales/maint_core.{en,zh-CN}.yml` (`maint_core.flowcharts.structure_errors.*` only)
- Test: `spec/services/activity_generator/name_deriver_spec.rb`, `spec/services/activity_generator/structure_validator_spec.rb`

**Interfaces:**
- Produces: `NameDeriver#derive_method_name(element, used_names)` never returns a name a `Trailblazer::Activity::Railway` instance responds to; non-ASCII labels → `"#{element["type"]}_#{n}"` (n counts per type from 1); `derive_activity_class_name` splits on `/[^A-Za-z0-9]+/`, falls back to `"Flowchart#{id}Activity"` or `"UnsavedFlowchartActivity"`.
- Produces: structure error key `maint_core.flowcharts.structure_errors.class_name_collision` (`%{name}`). (The multi-action process rule D1 moved to Task 5.)

- [ ] **Step 1: Failing NameDeriver specs:** labels `Initialize Method Send Sleep Raise Class Hash Freeze Puts Instance_variable_get` → `initialize_step`, `method_step`, …; label `创建学生` on a process → `process_1`, second → `process_2`, on an end → `end_1`; class name for `"entity-entry flow"` → `EntityEntryFlowActivity`; for `"学生"` with id 7 → `Flowchart7Activity`; unsaved → `UnsavedFlowchartActivity` (deterministic across calls).
- [ ] **Step 2: Implement:**

```ruby
RESERVED_METHOD_NAMES = (
  RUBY_RESERVED_WORDS +
  Trailblazer::Activity::Railway.new.public_methods.map(&:to_s) +
  Trailblazer::Activity::Railway.new.private_methods.map(&:to_s)
).to_set.freeze
```

  (If `Railway.new` is not instantiable, collect from `Object.new` plus `Trailblazer::Activity::Railway.instance_methods/private_instance_methods`.) Apply `"#{name}_step"` when reserved. Non-ASCII → type counter stored in `used_names` under a `:__type_counters` key or a dedicated hash ivar.
- [ ] **Step 3: Failing StructureValidator spec:** parent named "create entity entry" with a subflow element targeting a flowchart named "Create Entity Entry" → `class_name_collision`.
- [ ] **Step 4: Implement the rule;** add the key (en: `Flowchart class name %{name} collides with a sub-flow. Rename this flowchart or the sub-flow.` / zh-CN: `流程类名 %{name} 与子流程冲突，请重命名本流程或子流程。`).
- [ ] **Step 5: Run** `TEST_ENV_NUMBER=24 bundle exec rspec spec/services/activity_generator spec/services/activity_generator_spec.rb spec/services/flowchart_server_validator_spec.rb` → 0 failures (update expectations that pinned old random/merged names).

### Task 5 (Wave 2): Templates, one-action rule, process splitter, assistant, fixtures and data task (C1 model side, C2, D1, D2, D3)

**Files:**
- Modify: `app/models/flowchart/template_builder.rb`
- Create: `app/services/flowchart_definitions/process_splitter.rb`; Modify: `app/services/flowchart_definitions/normalizer.rb`, `structure_schema.json`, `structure_schema.prompt.txt`
- Create: `lib/tasks/flowcharts.rake` (or extend if present: `rg -n "namespace :flowcharts" lib/tasks`)
- Modify: `config/locales/flowchart_elements.{en,zh-CN}.yml` (template label keys)
- Test: `spec/models/flowchart_spec.rb` (templates), `spec/services/flowchart_definitions/process_splitter_spec.rb` (create), `spec/services/flowchart_definitions/normalizer_spec.rb`, `spec/services/flowchart_definitions/structure_schema_spec.rb`, `spec/tasks/flowcharts_split_spec.rb` (create)

**Interfaces:**
- Consumes (Task 1): `find_model.idExpression`; `save_model` without `bang`.
- Owns in wave 2 additionally: `app/services/activity_generator/structure_validator.rb` (D1 rule), `config/locales/maint_core.{en,zh-CN}.yml` key `maint_core.flowcharts.structure_errors.process_multiple_actions` ONLY (coordinate: Task 10 also edits maint_core in wave 2 — add your key in one StrReplace near the other `structure_errors` keys and re-read the file immediately before editing), and every existing spec fixture that builds a process with more than one step (convert to chains of single-step processes).
- Produces: `FlowchartDefinitions::ProcessSplitter.call(configuration_hash)` → new configuration hash (pure function, no persistence); `Flowchart.new_with_defaults(attrs)` applies `attrs[:template]` even when `configuration` is posted.

- [ ] **Step 1: Failing template specs.** For each template key build `Flowchart.new_with_defaults(name: "T", entity: entity, customer: customer, template: key)`, save, and assert element types/order and connections: blank `start,end`; crud_create `start,process(new_model),process(build_contract),process(validate),process(save_model),end`; crud_update with `find_model`; crud_delete `start,process(find_model),process(destroy_model),end`; every process has exactly one step; `flowchart.activity` present. Trace crud_create with `ActivityTracer.new(flowchart).call(params: { "<slug>" => "v" }, customer_id: customer.id, bound_entity: entity)` → success and an entry exists; crud_update with `params: { "id" => entry.id, "<slug>" => "w" }` → updated; crud_delete → deleted.
- [ ] **Step 2: Implement templates.** Step configs: new_model `{"resultVar"=>"model"}`; build_contract `{"contractClass"=>"EntityEntryContract","resultVar"=>"contract","modelVariable"=>"model"}`; validate `{"contractRef"=>"contract"}`; save_model `{"contractRef"=>"contract"}`; find_model `{"findStrategy"=>"find","idExpression"=>"params.id","resultVar"=>"model"}`; destroy_model `{"strategy"=>"destroy","modelVariable"=>"model"}`. Vertical layout x=400, y from 80 step 100, width 100, height 45, connections bottom→top. Labels via `I18n.t("flowchart_elements.template_labels.<key>")` for `start end new_model build_contract validate save_model find_model destroy_model` (en: `Start End New Model Build Contract Validate Save Model Find Model Destroy Model`; zh-CN: `开始 结束 新建记录 构建契约 校验 保存记录 查找记录 删除记录`). `new_with_defaults`: when `template` is present use the template configuration regardless of a posted `configuration`.
- [ ] **Step 3: Failing splitter spec.** Input: Start→p1(steps a,b,c)→End with p1 at y=200 and End at y=300. Output: p1 keeps id with step a and its incoming edge; new ids `p1_2` (b) and `p1_3` (c) at y=300/400; edges p1→p1_2→p1_3→End (End shifted to y=500; every element with y>200 shifts by 200); labels: first keeps the original label, others `Palette.human_label(action)`; single-step and non-process elements unchanged; idempotent on already-split input.
- [ ] **Step 4: Implement `ProcessSplitter`** (pure Ruby on string-keyed hashes, new ids unique against existing ids by suffix counter). Call it at the end of `Normalizer` before returning the configuration. `structure_schema.json`: add `"maxItems": 1` to `$defs/element/properties/steps` and say so in its description; rewrite the multi-step examples in `structure_schema.prompt.txt` as chains of single-step processes (keep JSON valid; `structure_schema_spec.rb` validates examples).
- [ ] **Step 5: Data task.** `flowcharts:split_multi_action_processes`: iterate `Flowchart.unscoped.where.not(status: "deleted")` (and shared rows); for each whose elements contain a process with >1 step, print `id name before→after element counts`; with `APPLY=1`, assign `configuration_json = ProcessSplitter.call(config)` and `save!` (Versionable creates a restorable version; `generate_activity` runs). Customer overrides (`flowchart_customer_heads`): split each override head's payload too, saving through the override path used by `FlowchartsController#update` for tenant overrides (set `override_customer_id`). Spec with a fixture flowchart: dry run changes nothing; APPLY splits and bumps the version count by one.
- [ ] **Step 5b: One-action rule (D1).** Failing spec in `spec/services/activity_generator/structure_validator_spec.rb`: a process with 2 steps → error using `maint_core.flowcharts.structure_errors.process_multiple_actions` (en: `Process "%{label}" can hold only one action. Split it into one process per action.` / zh-CN: `处理“%{label}”只能包含一个动作，请拆分为每个动作一个处理。`). Implement in `StructureValidator`. Then find every spec/fixture that builds a multi-step process (`rg -n --type ruby -U '"steps"\s*=>\s*\[\s*\{[^]]*\},\s*\{' spec app/models/flowchart` and the symbol-key / JSON variants) and convert each to a chain of single-step processes (use `ProcessSplitter` output as the reference shape), keeping each spec's intent.
- [ ] **Step 6: Run** `TEST_ENV_NUMBER=25 bundle exec rspec spec/models/flowchart_spec.rb spec/services/flowchart_definitions spec/tasks/flowcharts_split_spec.rb spec/services/activity_generator spec/services/activity_generator_spec.rb spec/services/activity_tracer_spec.rb spec/requests/admin/maintenance/flowcharts_spec.rb` plus every spec file whose fixtures you converted → 0 failures.

### Task 6: Action configs, picker defaults, empty condition rows (A5 editor side, C15, C16, A2 editor side)

**Files:**
- Modify: `app/javascript/flowchart/constants/action_configs/validation_actions.js` (`defaultValue:` → `default:`), `model_actions.js` (find_model `idExpression` field; save_model drop `bang`; query_models drop `scope` option and `scopeName`/`scopeArgs`; update_model strategy options `save`,`update`; drop `lockVersion`/`lockVersionVariable`), `data_actions.js` (assign_value drop `env_var`, `credential` options and `envVarName`, `credentialPath` fields)
- Modify: `app/javascript/controllers/property_editor/step_manager/action_picker.js` (never bump `model` or `contract`)
- Modify: `app/javascript/controllers/property_editor/branch_manager/condition_builder.js` (no `signal` default operand; drop the "TRB Activity Success" magic option)
- Modify: `config/locales/flowchart_actions.{en,zh-CN}.yml` (labels/placeholders for `idExpression`; remove keys of deleted fields/options)
- Regenerate: `lib/code_generators/config_schemas.rb` via `bundle exec rake config_schemas:mirror`
- Test: `spec/javascript/flowchart/constants/**` (action config tests), `spec/javascript/controllers/property_editor/step_manager/**`, `spec/javascript/controllers/property_editor/branch_manager/**`

**Interfaces:**
- Consumes (Task 1): `find_model.idExpression` default `"params.id"`, label key `find_model.f.idExpression.l` style used by `action_i18n.js` (follow the existing key shape in `flowchart_actions.en.yml`).

- [ ] **Step 1: Failing Vitest specs:** committing Build Contract from the picker yields config `{contractClass:"EntityEntryContract", resultVar:"contract", modelVariable:"model"}`; Validate yields `{contractRef:"contract"}`; when an upstream element already outputs `model`, a new New Model step keeps `resultVar:"model"` (no `model_2`); a new condition row renders an empty left operand select value and no option labelled "TRB Activity Success"; assign_value valueType options exclude `env_var`/`credential`; query_models queryType options exclude `scope`; find_model schema contains `idExpression` default `params.id`.
- [ ] **Step 2: Implement the JS changes; Step 3: update locales; Step 4: regenerate the mirror** (`bundle exec rake config_schemas:mirror && bundle exec rake config_schemas:check`).
- [ ] **Step 5: Run** Vitest on the touched spec folders with coverage for the touched app files (100% lines/branches) and `TEST_ENV_NUMBER=26 bundle exec rspec spec/services/code_generators/contract_parity_spec.rb spec/scripts/audit_generator_ui_spec.rb` (parity may need Task 1/2 generator changes; report remaining failures that belong to other tasks instead of editing their files).

### Task 7: Canvas persistence, restore, URLs, navigation guard, undo key, subflow open (C4, C5, C6, C7 client, C11, C12, C13, C14)

**Files:** see ownership table (Wave 1, Task 7). Tests in `spec/javascript/` mirroring each file.

**Interfaces:**
- Consumes (Task 10, wave 2): `data-flowchart-canvas-urls-value` JSON `{"update","versions","validation","traces","document","list","implicitKeys","stepIoParams","elementIoParams"}` where `stepIoParams` contains the literal segment `__ACTION__` and `elementIoParams` contains `__TYPE__` to be replaced (encodeURIComponent) client-side. Label values (English defaults in the controller): `unsavedChangesConfirm` ("You have unsaved changes. Leave this page?"), `expandSubflowTitle` ("Expand sub-flow"), `collapseSubflowTitle` ("Collapse sub-flow").
- Produces: `controller.urlsValue` (Object); a module-level helper `flowchartUrl(controller, name, replacements = {})` in `flowchart_canvas_controller.js` or a small `app/javascript/flowchart/urls.js` (create it; Task 7 owns it) used by every fetch listed in the ownership table.
- Produces: `UndoRedoManager` storage key `flowchart_undo_${idValue}` or `flowchart_undo_${idValue}_v${basedOnVersionIdValue}` in version-edit mode; stored stacks discarded when the stored top differs from the loaded `{elements, connections}`.

- [ ] **Step 1: Failing Vitest specs** (one per behaviour): `getConfiguration()` twice with no edits → deep-equal, metadata keeps the loaded `created_at`; restore success with `{configuration}` → `canvas.loadConfiguration` called, unsaved false, undo baseline reset; restore failure → toast shows `message`; save PATCHes `urlsValue.update`; test run POSTs `urlsValue.traces` with `{input, configuration}` and never PATCHes; `turbo:before-visit` with unsaved changes → `confirm(unsavedChangesConfirmValue)` and `preventDefault()` when declined, no prompt when clean; toolbar dot stays visible when an edit happened during save; double-clicking a subflow with a target opens the property sidebar; the subflow node renders an expand toggle (`[data-subflow-toggle]`) whose click toggles expansion; undo manager discards mismatching stored stacks and uses the version key.
- [ ] **Step 2: Implement.** `serialization.js#getConfiguration` stops writing `created_at` (keep `this._loadedMetadata`). `version_history_mixin.js` reads `data.configuration` from Task 10's response and `errorData.message`. Replace every hard-coded `/${customerId}/admin/maintenance/flowcharts…` in owned files with the URL helper. `test_runner_manager.js` drops the pre-save and sends `configuration: canvas.getConfiguration()` (use the controller's `_buildSaveConfiguration()` so expanded subflows are folded). Toolbar `saved` event carries the real unsaved state. `element_renderer.js` draws the subflow toggle (title from labels) and the controller maps its click to `subflowManager.toggleSubflowExpansion(element)`; `onElementDoubleClick` always opens the sidebar.
- [ ] **Step 3: Run** the mirrored Vitest specs with coverage (100% lines/branches for each touched app file).

### Task 8 (Wave 2): Canvas editing correctness (A6, A7, C8, C9, C10)

**Files:** see ownership table (Wave 2, Task 8). Tests mirror each file under `spec/javascript/`.

**Interfaces:**
- Label values added to `flowchart_canvas_controller.js` (English defaults) and passed into canvas `labels`: `connectionIntoStartRejected` ("A Start element cannot have incoming connections"), `connectionOutOfEndRejected` ("An End element cannot have outgoing connections"). Task 10 adds the `data-*-value` attributes and locale keys.

- [ ] **Step 1: Failing Vitest specs:** paste twice → copies have distinct `properties` objects and the first copy's steps/branches unchanged after the second paste; deleting the "true" branch edge and connecting a new element yields match values `false` (existing) + `true` (new), never two `false`; inserting on a decision edge keeps `fromPort/label/matchValue/properties` on the upstream edge and `properties.branches` points at the inserted element; positioned drop (`addElement` with x/y) creates no connection; double-click append never connects from an End or a Decision or an element with an outgoing edge; `createConnection` into Start / out of End returns null and calls `onToast` with the label; A→B and B→A both allowed; a 3 px mousedown/mouseup on an element neither moves nor reconnects it; 9 px drag with release over the property sidebar (outside SVG) ends the drag; keydown Backspace with `event.target` a `<button>` inside the sidebar does not delete; Space keydown on a sidebar button is not prevented; Ctrl+C with focus outside the canvas does not copy elements; Elements tab renders `<img src=x onerror=…>` label as text.
- [ ] **Step 2: Implement** (paste: `structuredClone(el)` per element before remapping; branch auto value: first of `["true","false"]` then `value_${n}` not in the decision's existing match values; insert-between: carry `fromPort`, `fromPosition`, `label`, `matchValue`, `properties` and call `_syncDecisionBranches`; auto-connect rules; connection rejections; 8 px threshold; `document`-level `mousemove`/`mouseup` registered on mousedown and removed on mouseup; keyboard guard `const inCanvas = e.target === document.body || this.container.contains(e.target)`; `escapeHtml` in bottom panel).
- [ ] **Step 3: Run** mirrored Vitest specs with coverage (100%).

### Task 9: Property panel open/cancel without side effects (C3)

**Files:** `app/javascript/controllers/property_editor_controller.js`, `app/javascript/controllers/property_editor/canvas_sync.js`; tests `spec/javascript/controllers/property_editor_controller.test.js`, `spec/javascript/controllers/property_editor/canvas_sync.test.js`.

- [ ] **Step 1: Failing specs:** open + Cancel → no `updateElementProperties`, no `onchange`, no undo entry; open, edit label, Cancel → element label and properties equal the snapshot and canvas updated once to restore; open, edit, Save → changes kept; reopening after an undo shows the undone state (no `unsavedChangesCache`).
- [ ] **Step 2: Implement:** snapshot `structuredClone({label, properties})` on open; `cancel`/`close` restore the snapshot when the current normalized state differs, else skip the final sync; delete `unsavedChangesCache` and its writers/readers; Save keeps current behaviour.
- [ ] **Step 3: Run** both specs with coverage (100%).

### Task 10 (Wave 2): Controllers, views and UI locales (C1 view, C5 server, C6 view, C7 server, labels for Tasks 7–8)

**Files:** `app/controllers/admin/maintenance/base_versions_controller.rb`, `app/controllers/admin/maintenance/flowchart_traces_controller.rb`, `app/views/admin/maintenance/flowcharts/new.html.erb`, `app/views/admin/maintenance/flowcharts/_editor.html.erb`, `config/locales/maint_core.{en,zh-CN}.yml`; specs `spec/requests/admin/maintenance/flowcharts/*` (versions, traces), `spec/requests/admin/maintenance/flowcharts_spec.rb`, `spec/views` or request specs asserting rendered attributes.

- [ ] **Step 1: Failing request specs:** POST restore returns JSON with `configuration` equal to the restored version payload; POST traces with `configuration` (JSON string of an unsaved graph) traces that graph (e.g. a graph whose only process fails yields `success: false`) and does not change `FlowchartVersion.count` or the stored `configuration`; GET edit on the platform prefix renders `data-flowchart-canvas-urls-value` whose `update` starts with `/81721200/admin/maintenance/platform/flowcharts/`; on the tenant prefix with `/81721200/admin/maintenance/flowcharts/`; GET new renders no `flowchart[configuration]` input; POST create with `template: "crud_create"` yields the crud_create graph.
- [ ] **Step 2: Implement.** Restore: render `configuration: parent.reload.resolved_current_version.content.payload` (match the accessor used by `reload_definition_from_head!`). Traces: when `params[:configuration]` is present, build `preview = @flowchart.dup` (or `Flowchart.new(@flowchart.attributes.slice(...))`), assign `configuration_json = JSON.parse(params[:configuration])`, generate its activity in memory (`preview.generate_activity`), and trace `preview`; never save. Views: remove the hidden configuration field in `new.html.erb`; in `_editor.html.erb` add `data-flowchart-canvas-urls-value="<%= { update: admin_maintenance_flowchart_path(current_customer_id, @flowchart), versions: admin_maintenance_flowchart_versions_path(current_customer_id, @flowchart), validation: admin_maintenance_flowchart_validation_path(current_customer_id, @flowchart), traces: admin_maintenance_flowchart_traces_path(current_customer_id, @flowchart), document: admin_maintenance_flowchart_document_path(current_customer_id, @flowchart), list: admin_maintenance_flowcharts_path(current_customer_id, format: :json), implicitKeys: admin_maintenance_validation_implicit_keys_path(current_customer_id, format: :json), stepIoParams: step_io_params_admin_maintenance_flowcharts_path(current_customer_id, generator_action: "__ACTION__"), elementIoParams: element_io_params_admin_maintenance_flowcharts_path(current_customer_id, element_type: "__TYPE__") }.to_json %>"` plus label values `unsaved-changes-confirm`, `expand-subflow-title`, `collapse-subflow-title`, `connection-into-start-rejected`, `connection-out-of-end-rejected` with keys under `maint_core.flowcharts.editor.*` (en text exactly as the JS defaults in Tasks 7–8; zh-CN: `有未保存的更改，确定离开此页面吗？`, `展开子流程`, `收起子流程`, `开始元素不能有传入连接`, `结束元素不能有传出连接`).
- [ ] **Step 3: Run** `TEST_ENV_NUMBER=30 bundle exec rspec spec/requests/admin/maintenance/flowcharts spec/requests/admin/maintenance/flowcharts_spec.rb spec/requests/admin/maintenance/flowchart_restorations_spec.rb` → 0 failures; owner-only authorization unchanged (existing denial specs still pass).

### Task 11 (Wave 3): Playwright builder journey

**Files:** `spec/e2e/flowchart_builder_journey.app.spec.js`, `spec/e2e/helpers/builder_fixtures.{js,rb}` (pattern: `spec/e2e/helpers/drag_fixtures.*`; UUID-named records, exact cleanup, baseline comparison).

- [ ] **Step 1: Write the journey** (gated on `APP_BASE_URL`): create via the New form with each template and assert the graph; blank flow: drag Process from palette below Start and double-click End in palette; pick New Model / Build Contract / Validate / Save Model via the step picker and assert default configs; save once → exactly one new version; save again unchanged → no new version; open + Cancel on Start and a process → no unsaved dot; restore the previous version → canvas shows it; copy/paste a process twice → independent copies; Backspace with the property panel's Cancel button focused keeps the element; Validate → no errors for template flows; Run test → `success` and version count unchanged.
- [ ] **Step 2: Run** against the isolated server: `APP_BASE_URL=http://127.0.0.1:3001 E2E_DATABASE_PATH=$PWD/storage/e2e_flowchart_builder.sqlite3 DATABASE_URL=sqlite3:$PWD/storage/e2e_flowchart_builder.sqlite3 PLAYWRIGHT_BROWSERS_PATH=~/.cache/ms-playwright npx playwright test --config config/javascript/playwright.config.js spec/e2e/flowchart_builder_journey.app.spec.js` → all pass.

### Task 12 (Wave 3): Reference docs (en + zh-CN in lockstep)

Update `doc/reference/{en,zh-CN}/flowchart-builder.md` (templates, default graph, one action per Process box and the split task, restore, one version per change, platform-aware endpoints, test runs without saving, navigation guard, subflow toggle), `code-generators.md` (`FlowchartRuntime::Entries`, expression/guard validation, removed options: assign_value env_var/credential, query_models scope, save_model bang, update_model update_all), `flowchart-runtime.md` (indifferent-access params, numeric comparison coercion, implicit keys, session-based authorize default). Same sections and examples in both locales; zh-CN idiomatic.

### Task 13 (Wave 3): Verification, data migration, release

- [ ] `bundle exec rake config_schemas:check`
- [ ] Full suite: `bin/rails parallel:prepare && bin/rails parallel:spec` → 0 failures
- [ ] `npm run coverage` → 100% lines/branches for `app/javascript/**`
- [ ] Playwright journey (Task 11 command) → pass
- [ ] Dev data: `bin/rails flowcharts:split_multi_action_processes` (dry run, report) then `APPLY=1 bin/rails flowcharts:split_multi_action_processes`; regenerate check: every live flowchart's `ActivityGenerator.new(f).generate` succeeds or reports a structure error listed in the summary
- [ ] Regenerate stored activity code for every live flowchart (emission changed in Tasks 1–4): `bin/rails flowcharts:regenerate_activities` (dry run first if the task supports it) and report any flowchart that no longer generates
- [ ] Restart dev server: `rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000`; smoke `/81721200/admin/maintenance/flowcharts/14/edit`
