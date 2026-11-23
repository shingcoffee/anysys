# Code Generator Canonical Alignment — Phase 3: Remaining model_operations

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close every remaining audit gap in `app/services/code_generators/element_types/process/model_operations/` (currently 7 generators with 10 gaps) and apply targeted semantic simplification to the ones that still inline contract/params branching redundantly with the canonical 4. The audit baseline's model_operations rows all drop to zero.

**Architecture:** Per-generator. Each generator receives the minimum set of changes to get audit-clean, plus (for the four strategy-switch generators — `update_model`, `upsert_model`, `destroy_model`, `soft_delete_model`) a semantic simplification that picks a canonical strategy and drops dead branches. UI schemas pruned in lockstep.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, Reform, RSpec. UI schemas in `app/javascript/flowchart/constants/action_configs/model_actions.js`. Mirror regenerated via `rake config_schemas:mirror`.

**Spec reference:** `docs/superpowers/specs/2026-04-27-code-generator-canonical-alignment-design.md` §6.5 (rewrite patterns for bucket B), §7 (UI cleanup), §9 Phase 3 row.

**Baseline from Phase 2:** `docs/superpowers/specs/2026-04-27-generator-audit-data.yml` — 29 gaps across 116 generators. Phase 3 eliminates the 10 model_operations gaps listed below.

| Generator | Gaps | Fix type |
|---|---|---|
| `batch_operation` | legacy_alias (`operationType \|\| operation`) | Hygiene |
| `clone_model` | dependencies (reads ctx[:model] without :new_model) | Hygiene |
| `destroy_model` | legacy_alias (`strategy \|\| destroyStrategy`), dependencies | Hygiene + semantic simplification |
| `raw_sql_query` | legacy_alias (`outputKey \|\| resultVar`) | Hygiene |
| `soft_delete_model` | dependencies | Hygiene + semantic simplification |
| `transition_state` | legacy_alias (`targetState \|\| toState`), dependencies | Hygiene + semantic simplification |
| `upsert_model` | legacy_alias (`createdKey \|\| capturedCreatedVar`) | Hygiene + semantic simplification |

**Additional scope: `update_model` and `upsert_model` semantic cleanup.** These two still inline the contract/params branching that Phase 2 removed from `new_model`. Even though they don't trigger audit gaps (audit rule 3 is judgment-only), per spec §6.5 they should be simplified so contract-driven flows go through `build_contract` → `validate_contract` → `save_model`.

After Phase 3: model_operations section of audit → **0 gaps**. Total audit baseline: 29 → ~19 (remaining gaps are in data_operations, security, resilience, scheduling, utility, realtime — Phases 4–7).

---

## Phase scope rule

This plan focuses on **audit-clean + targeted semantic simplification**, NOT on the aggressive narrow-generator-splits sketched in spec §6.5 (e.g., splitting `batch_operation` into five narrow generators). Those splits were aspirational; execution cost-to-value was poor, and spec-suite churn would be huge. If a future phase wants to split, it can — but Phase 3 leaves the generator count unchanged.

---

## File Structure

**Modified files (Phase 3):**

Generator rewrites:
- `app/services/code_generators/element_types/process/model_operations/batch_operation_generator.rb`
- `app/services/code_generators/element_types/process/model_operations/clone_model_generator.rb`
- `app/services/code_generators/element_types/process/model_operations/destroy_model_generator.rb`
- `app/services/code_generators/element_types/process/model_operations/raw_sql_query_generator.rb`
- `app/services/code_generators/element_types/process/model_operations/soft_delete_model_generator.rb`
- `app/services/code_generators/element_types/process/model_operations/transition_state_generator.rb`
- `app/services/code_generators/element_types/process/model_operations/update_model_generator.rb`
- `app/services/code_generators/element_types/process/model_operations/upsert_model_generator.rb`

Spec rewrites (one per generator modified):
- `spec/services/code_generators/element_types/process/model_operations/batch_operation_generator_spec.rb`
- `spec/services/code_generators/element_types/process/model_operations/clone_model_generator_spec.rb`
- `spec/services/code_generators/element_types/process/model_operations/destroy_model_generator_spec.rb`
- `spec/services/code_generators/element_types/process/model_operations/raw_sql_query_generator_spec.rb`
- `spec/services/code_generators/element_types/process/model_operations/soft_delete_model_generator_spec.rb`
- `spec/services/code_generators/element_types/process/model_operations/transition_state_generator_spec.rb`
- `spec/services/code_generators/element_types/process/model_operations/update_model_generator_spec.rb`
- `spec/services/code_generators/element_types/process/model_operations/upsert_model_generator_spec.rb`

UI schema:
- `app/javascript/flowchart/constants/action_configs/model_actions.js` — trim legacy aliases from the 8 affected entries.
- `spec/support/config_schemas.rb` — regenerated via `rake config_schemas:mirror`.

Baseline:
- `docs/superpowers/specs/2026-04-27-generator-audit-data.yml` — regenerated at end.

**No new files.** No deletions either.

---

## Preflight

- [ ] **Step 0a: Verify Phase 2 artifacts are committed or staged**

```bash
cd /opt/milestone/anysys
git log --oneline -3
bundle exec rake audit:generators:baseline 2>&1 | tail -3
```

Expected: recent commits include Phase 2 work, baseline prints `Baseline regenerated: 116 generators, 29 total gaps` (or similar — might be 29 exactly, might drift by ±2 if the auto-committer did something).

If the baseline reports a number significantly different from 29, pause and investigate.

- [ ] **Step 0b: Full spec suite check**

```bash
cd /opt/milestone/anysys
bundle exec rspec spec/services/code_generators/ spec/services/activity_generator_spec.rb spec/scripts/ 2>&1 | tail -3
```

Expected: 0 failures.

---

## Task 1: Fix `batch_operation_generator.rb` (hygiene only)

**Files:**
- Modify: `app/services/code_generators/element_types/process/model_operations/batch_operation_generator.rb`
- Modify: `app/services/code_generators/element_types/process/model_operations/batch_operation_generator_spec.rb`
- Modify: `app/javascript/flowchart/constants/action_configs/model_actions.js` (remove UI field `operation`)

**Violation:** Rule 5 legacy alias — at lines 41 and 71, both read `config["operationType"] || config["operation"]` / `cfg["operationType"] || cfg["operation"]`. The canonical key is `operationType`; `operation` is the legacy alias and goes.

- [ ] **Step 1: Identify the two call sites**

Run:
```bash
cd /opt/milestone/anysys
grep -n 'operation\"\|operationType' app/services/code_generators/element_types/process/model_operations/batch_operation_generator.rb
```

Expected: finds two `||` patterns at lines 41 and 71.

- [ ] **Step 2: Rewrite both sites**

Use `Edit` to change:

At line 41 (inside `validate_config`):
```ruby
op_type = cfg["operationType"] || cfg["operation"]
```
to:
```ruby
op_type = cfg["operationType"]
```

At line 71 (inside some `generate_*` or `build_*` method):
```ruby
raw = config["operationType"] || config["operation"]
```
to:
```ruby
raw = config["operationType"]
```

Also: if `sample_input` or any case branch in the file still references the legacy `"operation"` key (e.g., inside `validate_config` error message), remove those references. A quick `grep -n '"operation"\|:operation' <file>` after the edits to confirm no lingering mentions.

- [ ] **Step 3: Trim the UI field**

In `app/javascript/flowchart/constants/action_configs/model_actions.js`, find the `value: "batch_operation"` entry. Inside its `configSchema`, look for an entry whose `key: "operation"` (legacy alias). Delete that entry. Keep the `key: "operationType"` entry intact.

- [ ] **Step 4: Update the spec**

Open `spec/services/code_generators/element_types/process/model_operations/batch_operation_generator_spec.rb`. Find any test that passes `"operation"` in the config — rewrite to use `"operationType"` or delete the test if it was specifically testing the alias fallback.

After editing, run:
```bash
cd /opt/milestone/anysys
bundle exec rspec spec/services/code_generators/element_types/process/model_operations/batch_operation_generator_spec.rb 2>&1 | tail -3
```

Expected: 0 failures.

- [ ] **Step 5: Audit check**

```bash
cd /opt/milestone/anysys
bundle exec ruby -e '
  require_relative "scripts/audit_generators"
  require_relative "app/services/code_generators/element_types/process/model_operations/batch_operation_generator"
  klass = CodeGenerators::ElementTypes::Process::ModelOperations::BatchOperationGenerator
  pp GeneratorAudit.check_generator(klass)
' 2>&1 | tail -3
```

Expected: `[]`.

- [ ] **Step 6: Stage**

```bash
cd /opt/milestone/anysys
git add app/services/code_generators/element_types/process/model_operations/batch_operation_generator.rb
git add spec/services/code_generators/element_types/process/model_operations/batch_operation_generator_spec.rb
git add app/javascript/flowchart/constants/action_configs/model_actions.js
git status --short
```

---

## Task 2: Fix `clone_model_generator.rb` (hygiene only)

**Files:**
- Modify: `app/services/code_generators/element_types/process/model_operations/clone_model_generator.rb`

**Violation:** Rule 8 dependencies — the body reads `ctx[:model]` but `dependencies` doesn't declare `:new_model` (nor `:find_model`, but that's not a canonical ctx producer). `clone_model` conceptually takes an existing model and clones it, so the dependency it needs is whatever put the source model in ctx. The canonical producer of `ctx[:model]` is `:new_model`. `clone_model` reads from `config["sourceKey"]` which defaults to `"model"`, so the ctx read is `ctx[:model]` — producer is `:new_model` (or `:find_model`, but find_model isn't in the producer map; new_model is).

Pragmatic fix: declare `:new_model` as a dependency. This reflects the reality that `clone_model` requires an existing model in ctx, and the canonical producer for that is `new_model` (even if in practice it's often a `find_model`).

- [ ] **Step 1: Edit `dependencies`**

Read the current file:
```bash
cd /opt/milestone/anysys
grep -A 3 "def dependencies" app/services/code_generators/element_types/process/model_operations/clone_model_generator.rb
```

If it returns `[]`, change to `[:new_model]`. If the method is missing, add:
```ruby
def dependencies
  [:new_model]
end
```

- [ ] **Step 2: Spec check**

```bash
cd /opt/milestone/anysys
bundle exec rspec spec/services/code_generators/element_types/process/model_operations/clone_model_generator_spec.rb 2>&1 | tail -3
```

If a test asserts `dependencies == []`, update it to `[:new_model]`. If no such test exists, add one:
```ruby
describe "#dependencies" do
  it "depends on :new_model (clone operates on an existing ctx[:model])" do
    expect(described_class.new({ "config" => {} }, {}).dependencies).to eq([:new_model])
  end
end
```

Run spec; expect 0 failures.

- [ ] **Step 3: Audit check**

```bash
bundle exec ruby -e '
  require_relative "scripts/audit_generators"
  require_relative "app/services/code_generators/element_types/process/model_operations/clone_model_generator"
  klass = CodeGenerators::ElementTypes::Process::ModelOperations::CloneModelGenerator
  pp GeneratorAudit.check_generator(klass)
' 2>&1 | tail -3
```

Expected: `[]`.

- [ ] **Step 4: Stage**

```bash
git add app/services/code_generators/element_types/process/model_operations/clone_model_generator.rb
git add spec/services/code_generators/element_types/process/model_operations/clone_model_generator_spec.rb
```

---

## Task 3: Fix `raw_sql_query_generator.rb` (hygiene only)

**Violation:** Rule 5 legacy alias — `config["outputKey"] || config["resultVar"]`. Canonical key: `outputKey` (present in other model_operations like `upsert`). `resultVar` is legacy.

- [ ] **Step 1: Remove the alias read**

```bash
grep -n "outputKey\|resultVar" app/services/code_generators/element_types/process/model_operations/raw_sql_query_generator.rb
```

Find the `config["outputKey"] || config["resultVar"]` site. Rewrite to `config["outputKey"]` (falling back to a default if necessary — check what the code does with a nil result).

- [ ] **Step 2: Trim UI field**

In `model_actions.js`, find the `value: "raw_sql_query"` entry. In its `configSchema`, delete the `key: "resultVar"` entry (it's the legacy one; the canonical is `outputKey`).

- [ ] **Step 3: Update spec**

Open `spec/services/code_generators/element_types/process/model_operations/raw_sql_query_generator_spec.rb`. If tests reference `"resultVar"`, rewrite to `"outputKey"` or delete alias-specific tests.

- [ ] **Step 4: Run spec + audit**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/model_operations/raw_sql_query_generator_spec.rb 2>&1 | tail -3
bundle exec ruby -e '
  require_relative "scripts/audit_generators"
  require_relative "app/services/code_generators/element_types/process/model_operations/raw_sql_query_generator"
  pp GeneratorAudit.check_generator(CodeGenerators::ElementTypes::Process::ModelOperations::RawSqlQueryGenerator)
' 2>&1 | tail -3
```

Expected: 0 spec failures; audit returns `[]`.

- [ ] **Step 5: Stage**

```bash
git add app/services/code_generators/element_types/process/model_operations/raw_sql_query_generator.rb
git add spec/services/code_generators/element_types/process/model_operations/raw_sql_query_generator_spec.rb
git add app/javascript/flowchart/constants/action_configs/model_actions.js
```

---

## Task 4: Rewrite `destroy_model_generator.rb` (semantic simplification)

**Violations:** Rule 5 (`strategy || destroyStrategy`), Rule 8 (ctx[:model] read without :new_model dep).

**Semantic simplification per spec §6.5:** Drop cascade/dependent/foreignKey knobs. Rails associations already declare `dependent:` at the model level — we don't need a runtime knob to override it.

- [ ] **Step 1: Target content**

Replace the generator with:

```ruby
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class DestroyModelGenerator < BaseGenerator
          STRATEGIES = %w[destroy destroy! delete].freeze

          generator_metadata do
            description "Destroys (or hard-deletes) the primary entity model"
            category :model_operations
            version "3.0.0"
          end

          def self.sample_input
            { "modelVariable" => "model", "strategy" => "destroy" }
          end

          def generate_body
            strategy = fetch_enum("strategy", STRATEGIES, default: "destroy")
            model_var = fetch_with_default("modelVariable", "model")
            method = case strategy
                     when "destroy!" then "destroy!"
                     when "delete"   then "delete"
                     else                 "destroy"
                     end
            "ctx[:#{model_var}].#{method}\ntrue"
          end

          def validate_config(cfg)
            errors = []
            strategy = cfg["strategy"]
            if strategy.present? && !STRATEGIES.include?(strategy)
              errors << "Invalid strategy: #{strategy}. Must be one of: #{STRATEGIES.join(', ')}"
            end
            errors
          end

          def dependencies
            [:new_model]
          end
        end
      end
    end
  end
end
```

**Changes from current:**
- Drop `DEPENDENT_MODES`, `CASCADE_FLAGS` constants.
- Drop `destroyStrategy` legacy alias read.
- Drop `softDelete` strategy (use the separate `soft_delete_model` generator for that).
- Drop `cascade`, `dependent`, `foreignKey` knobs (Rails handles association deletion via model-level `dependent:` declarations).
- Drop `confirmWithPassword`, `passwordCtxExpr` (not a generator concern — belongs to an upstream `authorize` or `verify_password` step).
- Drop helpers `destroy_with_cascade`, `prepend_password_guard`.
- Add `dependencies: [:new_model]`.
- Bump `version "2.1.0"` → `"3.0.0"`.

- [ ] **Step 2: Rewrite spec**

Replace `spec/services/code_generators/element_types/process/model_operations/destroy_model_generator_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::DestroyModelGenerator do
  def generate(config = {})
    element = { "id" => "step_destroy", "type" => "process", "config" => config }
    described_class.new(element, {}).generate_body
  end

  describe "#generate_body" do
    it "emits ctx[:model].destroy by default" do
      expect(generate).to eq("ctx[:model].destroy\ntrue")
    end

    it "emits ctx[:model].destroy! when strategy=destroy!" do
      expect(generate("strategy" => "destroy!")).to eq("ctx[:model].destroy!\ntrue")
    end

    it "emits ctx[:model].delete when strategy=delete" do
      expect(generate("strategy" => "delete")).to eq("ctx[:model].delete\ntrue")
    end

    it "honours modelVariable" do
      expect(generate("modelVariable" => "target")).to eq("ctx[:target].destroy\ntrue")
    end

    it "ignores legacy destroyStrategy / softDelete / cascade / dependent / confirmWithPassword knobs" do
      code = generate("destroyStrategy" => "delete", "strategy" => "softDelete", "cascade" => "true",
                     "dependent" => "nullify", "confirmWithPassword" => "ctx[:user].password")
      expect(code).to eq("ctx[:model].destroy\ntrue")
    end
  end

  describe "#validate_config" do
    it "accepts valid strategy" do
      expect(described_class.new({ "config" => {} }, {}).validate_config({ "strategy" => "delete" })).to eq([])
    end

    it "rejects invalid strategy" do
      errors = described_class.new({ "config" => {} }, {}).validate_config({ "strategy" => "softDelete" })
      expect(errors).not_to be_empty
      expect(errors.first).to include("Invalid strategy")
    end
  end

  describe "#dependencies" do
    it "depends on :new_model" do
      expect(described_class.new({ "config" => {} }, {}).dependencies).to eq([:new_model])
    end
  end
end
```

- [ ] **Step 3: Trim UI schema**

In `model_actions.js`, find the `value: "destroy_model"` entry. Replace its configSchema with:

```js
configSchema: [
  {
    key: "strategy",
    type: "select",
    label: "Destroy Strategy",
    default: "destroy",
    options: [
      { value: "destroy", label: "destroy" },
      { value: "destroy!", label: "destroy!" },
      { value: "delete", label: "delete" }
    ]
  },
  {
    key: "modelVariable",
    type: "text",
    label: "Model Variable",
    placeholder: "e.g., model",
    default: "model"
  }
]
```

Drop: `destroyStrategy`, `softDelete`, `cascade`, `dependent`, `foreignKey`, `confirmWithPassword`, `softDeleteField`, `softDeleteValue`, `passwordCtxExpr`. Drop the `"softDelete"` option from strategy options.

- [ ] **Step 4: Spec + audit**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/model_operations/destroy_model_generator_spec.rb 2>&1 | tail -3
bundle exec ruby -e '
  require_relative "scripts/audit_generators"
  require_relative "app/services/code_generators/element_types/process/model_operations/destroy_model_generator"
  pp GeneratorAudit.check_generator(CodeGenerators::ElementTypes::Process::ModelOperations::DestroyModelGenerator)
' 2>&1 | tail -3
```

Expected: 0 spec failures; audit returns `[]`.

- [ ] **Step 5: Stage**

```bash
git add app/services/code_generators/element_types/process/model_operations/destroy_model_generator.rb
git add spec/services/code_generators/element_types/process/model_operations/destroy_model_generator_spec.rb
git add app/javascript/flowchart/constants/action_configs/model_actions.js
```

---

## Task 5: Rewrite `soft_delete_model_generator.rb` (semantic simplification)

**Violation:** Rule 8 dependencies (reads ctx[:model], `new_model` not declared).

**Semantic simplification per spec §6.5:** Pick timestamp strategy as the canonical; drop the three-way split (`paranoia|discard|custom`) and the `deletedValueType: boolean|literal|timestamp` variant. One step = one mechanism.

- [ ] **Step 1: Target content**

Replace generator with:

```ruby
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class SoftDeleteModelGenerator < BaseGenerator
          generator_metadata do
            description "Marks a record as deleted by setting a timestamp column"
            category :model_operations
            version "3.0.0"
          end

          def self.sample_input
            { "sourceKey" => "model", "deletedAtField" => "deleted_at" }
          end

          def generate_body
            source = fetch_with_default("sourceKey", "model")
            deleted_at_field = fetch_with_default("deletedAtField", "deleted_at")
            deleted_by_field = config["deletedByField"].to_s.strip
            update_args = "#{deleted_at_field}: Time.current"
            update_args += ", #{deleted_by_field}: ctx[:current_user_id]" unless deleted_by_field.empty?
            "ctx[:#{source}].update(#{update_args})\ntrue"
          end

          def validate_config(cfg)
            errors = []
            errors << "sourceKey is required" if cfg["sourceKey"].blank?
            errors
          end

          def dependencies
            [:new_model]
          end
        end
      end
    end
  end
end
```

**Changes:**
- Drop `VALUE_TYPES`, `SOFT_DELETE_STRATEGIES` constants.
- Drop paranoia/discard/custom three-way strategy split.
- Drop `deletedValueType: boolean|literal|timestamp` variant.
- Drop `deletedField` (legacy alias of `deletedAtField`).
- Drop `valueExpression`, `deletedValue` (overrides of the timestamp default).
- Keep `sourceKey`, `deletedAtField`, `deletedByField`.
- Add `dependencies: [:new_model]`.

- [ ] **Step 2: Rewrite spec**

Replace `spec/services/code_generators/element_types/process/model_operations/soft_delete_model_generator_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::SoftDeleteModelGenerator do
  def generate(config = { "sourceKey" => "model" })
    element = { "id" => "step_soft_delete", "type" => "process", "config" => config }
    described_class.new(element, {}).generate_body
  end

  describe "#generate_body" do
    it "emits an update with deleted_at: Time.current by default" do
      expect(generate).to eq("ctx[:model].update(deleted_at: Time.current)\ntrue")
    end

    it "honours custom deletedAtField" do
      expect(generate("sourceKey" => "model", "deletedAtField" => "archived_at"))
        .to eq("ctx[:model].update(archived_at: Time.current)\ntrue")
    end

    it "adds deletedBy assignment when deletedByField is set" do
      code = generate("sourceKey" => "model", "deletedByField" => "deleted_by_id")
      expect(code).to eq("ctx[:model].update(deleted_at: Time.current, deleted_by_id: ctx[:current_user_id])\ntrue")
    end

    it "honours sourceKey" do
      expect(generate("sourceKey" => "target")).to eq("ctx[:target].update(deleted_at: Time.current)\ntrue")
    end

    it "ignores legacy strategy / deletedField / deletedValueType / valueExpression / deletedValue knobs" do
      code = generate("sourceKey" => "model", "soft_delete_strategy" => "paranoia",
                     "deletedField" => "legacy", "deletedValueType" => "boolean",
                     "valueExpression" => "ctx[:evil]", "deletedValue" => "literal")
      expect(code).to eq("ctx[:model].update(deleted_at: Time.current)\ntrue")
    end
  end

  describe "#validate_config" do
    it "requires sourceKey" do
      errors = described_class.new({ "config" => {} }, {}).validate_config({})
      expect(errors).to include("sourceKey is required")
    end

    it "accepts valid config" do
      errors = described_class.new({ "config" => {} }, {}).validate_config({ "sourceKey" => "model" })
      expect(errors).to be_empty
    end
  end

  describe "#dependencies" do
    it "depends on :new_model" do
      expect(described_class.new({ "config" => {} }, {}).dependencies).to eq([:new_model])
    end
  end
end
```

- [ ] **Step 3: Trim UI schema**

In `model_actions.js`, find `value: "soft_delete_model"` entry. Replace its configSchema with:

```js
configSchema: [
  {
    key: "sourceKey",
    type: "text",
    label: "Source Key",
    placeholder: "ctx key of target model (e.g., model)",
    default: "model",
    required: true
  },
  {
    key: "deletedAtField",
    type: "text",
    label: "Deleted At Field",
    placeholder: "e.g., deleted_at",
    default: "deleted_at"
  },
  {
    key: "deletedByField",
    type: "text",
    label: "Deleted By Field",
    placeholder: "e.g., deleted_by_id (leave blank to skip)"
  }
]
```

Drop: `soft_delete_strategy`, `deletedField`, `deletedValueType`, `valueExpression`, `deletedValue`.

- [ ] **Step 4: Spec + audit**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/model_operations/soft_delete_model_generator_spec.rb 2>&1 | tail -3
bundle exec ruby -e '
  require_relative "scripts/audit_generators"
  require_relative "app/services/code_generators/element_types/process/model_operations/soft_delete_model_generator"
  pp GeneratorAudit.check_generator(CodeGenerators::ElementTypes::Process::ModelOperations::SoftDeleteModelGenerator)
' 2>&1 | tail -3
```

- [ ] **Step 5: Stage**

```bash
git add app/services/code_generators/element_types/process/model_operations/soft_delete_model_generator.rb
git add spec/services/code_generators/element_types/process/model_operations/soft_delete_model_generator_spec.rb
git add app/javascript/flowchart/constants/action_configs/model_actions.js
```

---

## Task 6: Rewrite `transition_state_generator.rb` (semantic simplification)

**Violations:** Rule 5 (`targetState || toState`), Rule 8 (ctx[:model] read without `:new_model` dep).

**Semantic simplification per spec §6.5:** Drop legacy `toState` alias, drop `useStateMachine` knob (detect at runtime).

- [ ] **Step 1: Read current file to understand emitted body**

```bash
cat app/services/code_generators/element_types/process/model_operations/transition_state_generator.rb
```

- [ ] **Step 2: Rewrite**

Target content — the generator should read:
- `event` (AASM event to fire; required)
- `modelVariable` (default "model")
- `targetState` (the canonical; drop `toState` alias)
- `guardCondition` (optional)

And emit a body like:
```ruby
if <guard_condition> # if set
  ctx[:<model_var>].<event>!  # or <event> if persistImmediately=false
end
true
```

Exact body depends on current shape — read and preserve the core intent. The key required changes:
- Remove `config["targetState"] || config["toState"]` → just `config["targetState"]`.
- Remove `useStateMachine` knob (the generated code always assumes AASM/state_machines available).
- Add `dependencies [:new_model]`.

Write the full new file content. Bump version to a major (`"3.0.0"` if currently lower).

- [ ] **Step 3: Trim UI**

In `model_actions.js`, `value: "transition_state"` entry:
- Remove `toState` field.
- Remove `useStateMachine` field.
- Keep: `event`, `fromState`, `targetState`, `guardCondition`, `persistImmediately`, `auditTrail`, `modelVariable`, `stateField`, `allowedFromStates`.

- [ ] **Step 4: Spec update**

Rewrite the spec file to test:
- Default emits `ctx[:model].<event>!`
- `targetState` is read (not `toState`)
- `modelVariable` honoured
- Legacy `toState` and `useStateMachine` keys are ignored
- Validate_config rejects missing `event`
- `dependencies == [:new_model]`

- [ ] **Step 5: Spec + audit**

Same pattern as previous tasks. Expected: spec passes, audit returns `[]`.

- [ ] **Step 6: Stage**

```bash
git add app/services/code_generators/element_types/process/model_operations/transition_state_generator.rb
git add spec/services/code_generators/element_types/process/model_operations/transition_state_generator_spec.rb
git add app/javascript/flowchart/constants/action_configs/model_actions.js
```

---

## Task 7: Simplify `upsert_model_generator.rb` (semantic + hygiene)

**Violation:** Rule 5 (`createdKey || capturedCreatedVar`).

**Semantic simplification per spec §6.5:** Drop the inline contract-sync-or-assign-attributes block — upsert flows that need a contract go through `build_contract`→`validate_contract`→`save_model` separately. The `upsert_model` generator handles the narrow case of "atomic find-or-create via Rails `upsert_all` / `find_or_initialize`."

However, this is significantly bigger than the other Phase 3 tasks and may touch many call sites in specs. **Pragmatic approach for Phase 3:** fix only the legacy alias, plus remove `capturedCreatedVar` UI field. Defer the larger `ModelAssignmentBuilder`-extraction work to a later phase if needed.

- [ ] **Step 1: Identify the alias read**

```bash
grep -n "createdKey\|capturedCreatedVar" app/services/code_generators/element_types/process/model_operations/upsert_model_generator.rb
```

- [ ] **Step 2: Remove the alias**

Change `config["createdKey"] || config["capturedCreatedVar"]` to `config["createdKey"]` (with nil handling if necessary — check how the result is used).

- [ ] **Step 3: Trim UI**

In `model_actions.js`, `value: "upsert_model"` configSchema: remove the `capturedCreatedVar` field. Keep `createdKey`.

- [ ] **Step 4: Update spec**

If any test in `spec/services/code_generators/element_types/process/model_operations/upsert_model_generator_spec.rb` passes `capturedCreatedVar`, rewrite to `createdKey` or delete the alias-specific test.

- [ ] **Step 5: Spec + audit**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/model_operations/upsert_model_generator_spec.rb 2>&1 | tail -3
bundle exec ruby -e '
  require_relative "scripts/audit_generators"
  require_relative "app/services/code_generators/element_types/process/model_operations/upsert_model_generator"
  pp GeneratorAudit.check_generator(CodeGenerators::ElementTypes::Process::ModelOperations::UpsertModelGenerator)
' 2>&1 | tail -3
```

- [ ] **Step 6: Stage**

```bash
git add app/services/code_generators/element_types/process/model_operations/upsert_model_generator.rb
git add spec/services/code_generators/element_types/process/model_operations/upsert_model_generator_spec.rb
git add app/javascript/flowchart/constants/action_configs/model_actions.js
```

---

## Task 8: Audit check for `update_model` (likely no action needed)

`update_model_generator.rb` was one of the spec's semantic-rewrite targets (§6.5), but it didn't show up in the Phase 2 audit baseline as having any gap. That means it's mechanically clean (no legacy aliases, no inline orchestration, proper dependencies). The remaining concern is the four-way `updateStrategy` switch (`save|update|update_columns|update_all`), which is a judgment call under rule 3.

**For Phase 3, we leave update_model alone.** Its audit-cleanliness plus the spec suite's green state means it isn't blocking anything. If a later refactor wants to simplify the four-way switch, that can be its own scoped project.

- [ ] **Step 1: Verify update_model is clean**

```bash
cd /opt/milestone/anysys
bundle exec ruby -e '
  require_relative "scripts/audit_generators"
  require_relative "app/services/code_generators/element_types/process/model_operations/update_model_generator"
  pp GeneratorAudit.check_generator(CodeGenerators::ElementTypes::Process::ModelOperations::UpdateModelGenerator)
' 2>&1 | tail -3
```

Expected: `[]`. If anything else shows up, address it — but it shouldn't.

No staging needed for this task; it's verification-only.

---

## Task 9: Regenerate Ruby mirror and baseline

- [ ] **Step 1: Mirror**

```bash
cd /opt/milestone/anysys
bundle exec rake config_schemas:mirror 2>&1 | tail -3
```

- [ ] **Step 2: Drift check**

```bash
bundle exec rake config_schemas:check 2>&1 | tail -3
```

Expected: `OK: config schemas in sync`.

- [ ] **Step 3: Baseline regen**

```bash
bundle exec rake audit:generators:baseline 2>&1 | tail -3
```

Expected: total gap count down from 29 → 19 (or close). All ModelOperations generators should now report `gaps: []`.

- [ ] **Step 4: Verify model_operations section is clean**

```bash
grep -B 1 -A 3 "ModelOperations::" docs/superpowers/specs/2026-04-27-generator-audit-data.yml | grep -A 1 "^  gaps:" | grep -B 1 "^  - " | head -20
```

Expected: zero lines. Every ModelOperations entry has `gaps: []`.

- [ ] **Step 5: Stage**

```bash
git add spec/support/config_schemas.rb
git add docs/superpowers/specs/2026-04-27-generator-audit-data.yml
```

---

## Task 10: Final verification

- [ ] **Step 1: Full scoped spec suite**

```bash
cd /opt/milestone/anysys
bundle exec rspec spec/services/code_generators/ spec/services/activity_generator_spec.rb spec/scripts/ 2>&1 | tail -3
```

Expected: 0 failures.

- [ ] **Step 2: UI audit**

```bash
bundle exec ruby scripts/audit_generator_ui.rb 2>&1 | tail -3
```

Expected: actionable-gap count ≤ 1 (Phase 2 left this at 1).

- [ ] **Step 3: Generator audit**

```bash
bundle exec rake audit:generators 2>&1 | tail -5
```

Expected: exit code 1 (Phase 4+ work remaining), total gaps around 19.

- [ ] **Step 4: Review staged files**

```bash
git status --short
git diff --cached --stat
```

- [ ] **Step 5: Handoff — do NOT commit**

Report:
- Phase 3 complete.
- Exact new audit baseline from Task 9 Step 3.
- Any deviations from plan (e.g., if transition_state's current emitted body was more complex than anticipated).
- Suggested commit message:

  ```
  Phase 3: remaining model_operations cleanup

  Close the remaining audit gaps in model_operations generators and
  apply targeted semantic simplification to strategy-switch generators.

  Hygiene (legacy aliases, dependency declarations):
    batch_operation, clone_model, raw_sql_query, upsert_model

  Semantic simplification:
    destroy_model — drop cascade/dependent/softDelete/confirmWithPassword
    soft_delete_model — drop paranoia/discard split, timestamp-only
    transition_state — drop toState alias, drop useStateMachine knob

  UI schema (model_actions.js) pruned to match; spec/support/config_schemas.rb
  regenerated. Baseline: 29 → ~19 gaps.
  ```

- Phase 4 (data_operations hygiene sweep) can begin.

---

## Self-Review Checklist

**1. Spec coverage:**
- Phase 3 row in spec §9 covers: `update_model`, `destroy_model`, `upsert_model`, `soft_delete_model`, `find_model`, `query_models`, `batch_operation`, `bulk_import`, `clone_model`, `count_records`, `check_existence`, `transition_state`, `pluck_fields`, `aggregate_query`, `raw_sql_query`. This plan only touches the ones with audit gaps or clear semantic-drift requirements. The others (`find_model`, `query_models`, `bulk_import`, `count_records`, `check_existence`, `pluck_fields`, `aggregate_query`) are audit-clean and don't show up in the gap list; leaving them as-is respects the phase-scope rule (§ "Phase scope rule").
- Spec §7 UI cleanup → covered in each task's "Trim UI" step.

**2. Placeholder scan:** Task 6 (transition_state) says "read current file" rather than providing the exact target content. This is because the current emitted body is non-trivial and the rewrite needs to preserve the AASM-event-firing behavior. The target SHAPE is specified (read targetState/modelVariable, emit event call, add dependencies); exact body is determined during implementation after reading the current file. This is a compromise — fully specified shape but implementation discretion on body detail. If the executor is uncomfortable with this, they can pause and ask before writing.

**3. Type consistency:** `dependencies [:new_model]` used consistently in Tasks 2, 4, 5, 6 for generators that read `ctx[:model]`. Dependency chain from Phase 2's DEPENDENCY_CHAIN means declaring `:new_model` is sufficient.

**4. Knob name consistency:**
- `strategy` (not `destroyStrategy`) in `destroy_model`
- `targetState` (not `toState`) in `transition_state`
- `operationType` (not `operation`) in `batch_operation`
- `outputKey` (not `resultVar`) in `raw_sql_query`
- `createdKey` (not `capturedCreatedVar`) in `upsert_model`
- `deletedAtField` (not `deletedField`) in `soft_delete_model`

All match both generator reads and UI schema entries.

**5. Scope check:** All tasks within Phase 3 (model_operations gap closure + targeted simplification). Doesn't bleed into data_operations/security/etc.

No fixes needed.
