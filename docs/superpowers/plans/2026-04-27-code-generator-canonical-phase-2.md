# Code Generator Canonical Alignment — Phase 2: Canonical 4 Rewrite

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite the four canonical-flow generators (`new_model`, `build_contract`, `validate_contract`, `save_model`) so each produces a step body that matches the Trailblazer Railway example in the spec. Simultaneously update their UI config schemas and paired specs to reflect the slimmed-down surface. The audit baseline's row count for these four generators drops to zero.

**Architecture:** Per-generator rewrite. Each generator ends up with a body of ≤ 6 lines, at most 2–3 config knobs, and no dead switch branches. Inline orchestration (`ActivitySteps::X.call(...)`) is extracted into dedicated thin-wrapper generators where actual callers exist; otherwise the orchestration logic is dropped entirely. `ModelAssignmentBuilder` usage shrinks accordingly.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, Trailblazer Activity, Reform. RSpec for generator specs. UI schemas in `app/javascript/flowchart/constants/action_configs/*.js`. Post-edit, `rake config_schemas:mirror` regenerates `spec/support/config_schemas.rb`.

**Spec reference:** `docs/superpowers/specs/2026-04-27-code-generator-canonical-alignment-design.md` sections 6.1–6.4 (what each of the four becomes), 7 (UI-side cleanup), 11 (open questions deferred to this phase).

**Baseline from Phase 1:** `docs/superpowers/specs/2026-04-27-generator-audit-data.yml` (34 gaps across 116 generators). The four canonical generators currently contribute:
- `NewModelGenerator`: 1 gap (`dependencies` — reads `ctx[:model]` without declaring the producer, which is itself — that's a fixable self-reference oddity in the rule-8 check).
- `BuildContractGenerator`: 0 gaps from the audit, but the spec mandates a semantic rewrite (drop cache/coercion/mapping knobs).
- `ValidateContractGenerator`: 2 gaps (`inline_orchestration`, `dependencies`).
- `SaveModelGenerator`: 1 gap (`legacy_alias`).

After Phase 2 these four generators contribute **0** gaps.

---

## Open-question resolutions (spec §11)

Before writing code, resolve the spec's deferred questions by grepping for actual usage. **Do these lookups at the start of the phase and record the results in Task 0.**

1. **`ActivitySteps::SaveAll` callers outside the generator.** Grep in `app/`, `spec/`, `lib/`, but exclude `app/services/code_generators/` (the generator itself), `app/services/activity_steps/save_all.rb` (the class definition), and the fixture files (`spec/fixtures/audit_generators/`). Only real callers — hand-written or generated — count.

2. **`ActivitySteps::DetectAndRouteParams` / `PopulatePrimary` / `PopulateAssociations` callers outside the generator.** Same grep exclusions.

3. **`EntityContractFactory` and `entity_contract_factory.rb` usage.** Does `build_contract_generator` actually need `EntityEntryContract.build_for(entity)` to work, or does the codebase have a factory pattern that makes `Contract.new(model, params)` sufficient as per the canonical example? Check `app/services/entity_contract_factory.rb` and any callers.

4. **`ModelAssignmentBuilder` usage after Phase 2.** Does `upsert_model_generator.rb` still call `build_model_assignment(mode: :payload, ...)` after Phase 2? (Phase 3 handles `upsert_model`, so the answer is: yes, the mixin stays for Phase 2; Phase 3 revisits.)

Task 0 records the grep output. Subsequent tasks depend on these findings:

- If `SaveAll` has real callers → create a `save_all_model` thin-wrapper generator.
- If `SaveAll` has no real callers → drop it from the generated output entirely, do NOT create a replacement generator.
- Same decision rule for `DetectAndRouteParams` / `PopulatePrimary` / `PopulateAssociations`: real callers → narrow generators; no callers → drop.

---

## File Structure

**Modified files (Phase 2):**

- `app/services/code_generators/element_types/process/model_operations/new_model_generator.rb` — bodily rewrite to canonical shape.
- `app/services/code_generators/element_types/process/model_operations/save_model_generator.rb` — bodily rewrite.
- `app/services/code_generators/element_types/process/validation/build_contract_generator.rb` — bodily rewrite.
- `app/services/code_generators/element_types/process/validation/validate_contract_generator.rb` — bodily rewrite.
- `app/javascript/flowchart/constants/action_configs/model_actions.js` — trim `new_model` and `save_model` UI schemas.
- `app/javascript/flowchart/constants/action_configs/validation_actions.js` — trim `build_contract` and `validate_contract` UI schemas.
- `spec/services/code_generators/element_types/process/model_operations/new_model_generator_spec.rb` — rewrite assertions.
- `spec/services/code_generators/element_types/process/model_operations/save_model_generator_spec.rb` — rewrite assertions.
- `spec/services/code_generators/element_types/process/validation/build_contract_generator_spec.rb` — rewrite assertions.
- `spec/services/code_generators/element_types/process/validation/validate_contract_generator_spec.rb` — rewrite assertions.
- `spec/services/activity_generator_spec.rb` — update integration assertions that pattern-match on `ActivitySteps::SaveAll`, `PopulatePrimary`, `PopulateAssociations`, `DetectAndRouteParams`. The specific line references from Phase 1 grep: lines 562, 563, 566, 569, 573, 650, 651, 654, 655, 672, 685, 693, 695, 744, 769, 770, 773, 1384, 1406, 1421, 1435.
- `spec/support/config_schemas.rb` — regenerated by `rake config_schemas:mirror` after JS edits (do not hand-edit).
- `docs/superpowers/specs/2026-04-27-generator-audit-data.yml` — regenerated by `rake audit:generators:baseline` at the end of the phase.

**Potentially-created files (depend on Task 0 findings):**

- `app/services/code_generators/element_types/process/model_operations/save_all_model_generator.rb` — IF SaveAll has real callers.
- `app/services/code_generators/element_types/process/validation/route_params_generator.rb` — IF DetectAndRouteParams has real callers.
- `app/services/code_generators/element_types/process/validation/populate_primary_generator.rb` — IF PopulatePrimary has real callers.
- `app/services/code_generators/element_types/process/validation/populate_associations_generator.rb` — IF PopulateAssociations has real callers.
- Plus matching specs and UI entries for each created narrow generator.

**Deleted files:** None in Phase 2 (runtime services like `ActivitySteps::SaveAll` stay; they're out of scope per spec §2.2).

---

## Preflight

- [ ] **Step 0a: Verify Phase 1 artifacts are present**

Run:
```bash
cd /opt/milestone/anysys
ls scripts/audit_generators.rb lib/tasks/audit_generators.rake docs/superpowers/specs/2026-04-27-generator-audit-data.yml
bundle exec rake audit:generators:baseline 2>&1 | tail -3
```

Expected: all three files present; baseline run prints `Baseline regenerated: 116 generators, 34 total gaps`.

If any Phase 1 artifact is missing or the baseline run fails, **STOP** and fix Phase 1 issues before proceeding.

- [ ] **Step 0b: Verify full spec suite is green**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rspec spec/services/code_generators/ spec/scripts/ spec/services/activity_generator_spec.rb 2>&1 | tail -3
```

Expected: `0 failures`. Note the baseline example count — it's the reduction target (example count can change by ±10% per the spec's acceptance criteria, but **0 failures** must hold throughout).

---

## Task 0: Resolve open questions

**Files:** None (research only)

- [ ] **Step 1: Find real callers of `ActivitySteps::SaveAll`**

Run:
```bash
cd /opt/milestone/anysys
grep -rn "ActivitySteps::SaveAll" app/ lib/ spec/ 2>/dev/null \
  | grep -v "app/services/code_generators/" \
  | grep -v "app/services/activity_steps/" \
  | grep -v "spec/fixtures/audit_generators/"
```

Record the lines printed. Every hit is either (a) a real call site (subagent-spawned code, test fixture, Trailblazer compose block) or (b) a spec that asserts generated output contains the string. Distinguish the two:

- **Spec assertions** (files under `spec/services/activity_generator_spec.rb`) — these test that the generator emits the call. They'll be rewritten in Task 5; they don't prove SaveAll has runtime callers.
- **Real calls** (anywhere else) — these prove SaveAll has runtime callers. If any exist, `save_all_model_generator` must be created.

- [ ] **Step 2: Find real callers of `ActivitySteps::DetectAndRouteParams`**

Run:
```bash
cd /opt/milestone/anysys
grep -rn "ActivitySteps::DetectAndRouteParams" app/ lib/ spec/ 2>/dev/null \
  | grep -v "app/services/code_generators/" \
  | grep -v "app/services/activity_steps/" \
  | grep -v "spec/fixtures/audit_generators/"
```

Same analysis as Step 1.

- [ ] **Step 3: Find real callers of `ActivitySteps::PopulatePrimary`**

Run:
```bash
cd /opt/milestone/anysys
grep -rn "ActivitySteps::PopulatePrimary" app/ lib/ spec/ 2>/dev/null \
  | grep -v "app/services/code_generators/" \
  | grep -v "app/services/activity_steps/" \
  | grep -v "spec/fixtures/audit_generators/"
```

- [ ] **Step 4: Find real callers of `ActivitySteps::PopulateAssociations`**

Run:
```bash
cd /opt/milestone/anysys
grep -rn "ActivitySteps::PopulateAssociations" app/ lib/ spec/ 2>/dev/null \
  | grep -v "app/services/code_generators/" \
  | grep -v "app/services/activity_steps/" \
  | grep -v "spec/fixtures/audit_generators/"
```

- [ ] **Step 5: Check `EntityEntryContract.build_for` usage**

Run:
```bash
cd /opt/milestone/anysys
grep -rn "EntityEntryContract\.build_for\|EntityContractFactory" app/ spec/ 2>/dev/null | head -15
ls app/services/entity_contract_factory.rb 2>&1
```

The canonical example uses `User::Contract::Create.new(ctx[:model])` — no factory. Our codebase probably has `EntityEntryContract.build_for(entity).new(model, params)` because contracts are entity-driven (not hardcoded per-class). This phase **keeps** the `build_for(entity)` pattern because the entity is the multi-tenancy boundary. Record the current usage for reference.

- [ ] **Step 6: Record findings in a scratch note**

Write a short markdown note at `/tmp/phase-2-task-0-findings.md` summarizing:
- SaveAll: N real callers, M spec assertions → decision: {create save_all_model | drop}
- DetectAndRouteParams: N real callers → decision: {create route_params | drop}
- PopulatePrimary: N real callers → decision: {create populate_primary | drop}
- PopulateAssociations: N real callers → decision: {create populate_associations | drop}
- Contract build pattern: keep `EntityEntryContract.build_for(entity).new(model, params)`.

This note is NOT committed; it's a handoff to Tasks 3 and 6. If a subsequent subagent is dispatched to execute those tasks, pass the findings inline in the task prompt.

**Do not commit anything in Task 0.** It's read-only.

---

## Task 1: Rewrite `new_model_generator.rb` + its spec

**Files:**
- Modify: `app/services/code_generators/element_types/process/model_operations/new_model_generator.rb`
- Modify: `spec/services/code_generators/element_types/process/model_operations/new_model_generator_spec.rb`

**Canonical target (from spec §6.1):**

```ruby
module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class NewModelGenerator < BaseGenerator
          generator_metadata do
            description "Creates a new entity model instance"
            category :model_operations
            version "4.0.0"
          end

          def self.sample_input
            { "resultVar" => "model" }
          end

          def generate_body
            result_var = fetch_with_default("resultVar", "model")
            <<~RUBY.chomp
              ctx[:#{result_var}] = EntityEntry.build_for(ctx[:bound_entity]).new(customer_id: ctx[:customer_id])
              true
            RUBY
          end

          def validate_config(_cfg)
            []
          end

          def dependencies
            []
          end
        end
      end
    end
  end
end
```

**Changes vs current:**
- Remove `include CodeGenerators::Shared::ModelAssignmentBuilder`.
- Remove `build_model_assignment(...)` call — attribute assignment is no longer `new_model`'s job.
- Remove the two-line `ctx[:#{result_var}].customer_id = ...` pin (replaced by keyword-arg construction).
- Remove `_model_class` local variable (drop the intermediate).
- Fix `dependencies` from `[:build_contract]` to `[]`.
- Bump `version "3.0.0"` → `"4.0.0"`.

- [ ] **Step 1: Write the failing spec first (TDD)**

Rewrite `spec/services/code_generators/element_types/process/model_operations/new_model_generator_spec.rb` with this exact content:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::NewModelGenerator do
  def generate(config = {})
    element = { "id" => "step_new_model", "type" => "process", "config" => config }
    described_class.new(element, {}).generate_body
  end

  describe "#generate_body" do
    it "constructs a new model instance with customer_id from ctx" do
      code = generate
      expect(code).to include("ctx[:model] = EntityEntry.build_for(ctx[:bound_entity]).new(customer_id: ctx[:customer_id])")
    end

    it "uses the configured resultVar for the ctx key" do
      code = generate("resultVar" => "record")
      expect(code).to include("ctx[:record] = EntityEntry.build_for(ctx[:bound_entity]).new(customer_id: ctx[:customer_id])")
    end

    it "defaults resultVar to 'model' when omitted" do
      code = generate
      expect(code).to include("ctx[:model] = EntityEntry.build_for")
    end

    it "returns true as its final expression" do
      expect(generate.strip.split("\n").last).to eq("true")
    end

    it "does not assign attributes — that is the contract+validate+save chain's job" do
      code = generate
      expect(code).not_to include("assign_attributes")
      expect(code).not_to include("ctx[:contract]")
      expect(code).not_to include("ctx[:params]")
      expect(code).not_to include("_allowed")
    end

    it "does not emit a separate customer_id pin line (it's in the constructor)" do
      code = generate
      expect(code.scan(/customer_id/).size).to eq(1)
    end

    it "does not reference the dropped attributes or associations config keys" do
      code = generate("attributes" => { "evil" => "payload" }, "associations" => { "bad" => "assoc" })
      expect(code).not_to include("evil")
      expect(code).not_to include("bad")
      expect(code).not_to include("assoc")
    end
  end

  describe "#validate_config" do
    it "returns an empty array" do
      expect(described_class.new({ "config" => {} }, {}).validate_config({})).to eq([])
    end
  end

  describe ".sample_input" do
    it "returns a minimal hash containing at least the result var" do
      expect(described_class.sample_input).to include("resultVar")
    end
  end

  describe "#dependencies" do
    it "has no dependencies — new_model is the first canonical step" do
      expect(described_class.new({ "config" => {} }, {}).dependencies).to eq([])
    end
  end
end
```

- [ ] **Step 2: Run the spec and confirm it fails**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rspec spec/services/code_generators/element_types/process/model_operations/new_model_generator_spec.rb 2>&1 | tail -20
```

Expected: failures. The current generator still emits `_model_class = ...` intermediate, the legacy `assign_attributes` block, and `dependencies: [:build_contract]`. Each of those violates one of the new assertions.

- [ ] **Step 3: Rewrite `new_model_generator.rb`**

Replace the content of `app/services/code_generators/element_types/process/model_operations/new_model_generator.rb` with the canonical version shown at the top of Task 1.

- [ ] **Step 4: Run the spec and confirm it passes**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rspec spec/services/code_generators/element_types/process/model_operations/new_model_generator_spec.rb 2>&1 | tail -5
```

Expected: all examples pass.

- [ ] **Step 5: Run the audit script against just this generator**

Run:
```bash
cd /opt/milestone/anysys
bundle exec ruby -e '
  require_relative "scripts/audit_generators"
  require_relative "app/services/code_generators/element_types/process/model_operations/new_model_generator"
  klass = CodeGenerators::ElementTypes::Process::ModelOperations::NewModelGenerator
  pp GeneratorAudit.check_generator(klass)
' 2>&1 | tail -5
```

Expected: `[]` (empty array — zero gaps).

- [ ] **Step 6: Run the full generator spec suite — no regressions**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rspec spec/services/code_generators/ 2>&1 | tail -3
```

Expected: 0 failures. The example count may change (this spec rewrote 10 old examples into 9 new ones).

If failures appear in other files (e.g., `activity_generator_spec.rb` asserts a generated activity contains a pattern from the old `new_model`), note them — they'll be fixed in Task 5.

- [ ] **Step 7: Stage (do not commit)**

Run:
```bash
cd /opt/milestone/anysys
git add app/services/code_generators/element_types/process/model_operations/new_model_generator.rb
git add spec/services/code_generators/element_types/process/model_operations/new_model_generator_spec.rb
git status --short
```

---

## Task 2: Rewrite `build_contract_generator.rb` + its spec

**Files:**
- Modify: `app/services/code_generators/element_types/process/validation/build_contract_generator.rb`
- Modify: `spec/services/code_generators/element_types/process/validation/build_contract_generator_spec.rb`

**Canonical target (from spec §6.2):**

```ruby
module CodeGenerators
  module ElementTypes
    module Process
      module Validation
        class BuildContractGenerator < BaseGenerator
          CLASS_NAME_FORMAT = /\A[A-Z][A-Za-z0-9_]*(::[A-Z][A-Za-z0-9_]*)*\z/

          generator_metadata do
            description "Builds a Reform validation contract for the primary entity"
            category :validation
            version "2.0.0"
          end

          def self.sample_input
            { "contractClass" => "EntityEntryContract", "resultVar" => "contract", "modelVariable" => "model" }
          end

          def generate_body
            contract_class = fetch_with_default("contractClass", "EntityEntryContract")
            target         = fetch_with_default("resultVar", "contract")
            model_var      = fetch_with_default("modelVariable", "model")
            <<~RUBY.chomp
              ctx[:#{target}] = #{contract_class}.build_for(ctx[:bound_entity]).new(ctx[:#{model_var}])
              true
            RUBY
          end

          def validate_config(cfg)
            errors = []
            klass = cfg["contractClass"]
            if klass.present? && !klass.to_s.match?(CLASS_NAME_FORMAT)
              errors << "contractClass must be a valid Ruby class name"
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

**Changes vs current:**
- Drop `BOOL_VALUES`, `cachePerClass`, `cacheContract`, `validateOnBuild`, `typeCoercion`, `attributeMappings`, `defaultValues`.
- Drop every helper method (`build_inner_code`, `build_attrs_code`, `build_simple_build_code`, `build_cache_per_class_code`, `build_cache_contract_code`, `default_value_expr`, `normalize_kv_pairs`).
- Drop the `_contract_attrs` preparation logic.
- `generate_body` is now three config reads and a single heredoc line.
- `validate_config` shrinks to just the class-name format check.
- Bump `version "1.1.0"` → `"2.0.0"`.

- [ ] **Step 1: Write the failing spec first**

Rewrite `spec/services/code_generators/element_types/process/validation/build_contract_generator_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Validation::BuildContractGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate_body" do
    it "emits a single-line contract instantiation by default" do
      code = described_class.new(element, context).generate_body
      expect(code).to include("ctx[:contract] = EntityEntryContract.build_for(ctx[:bound_entity]).new(ctx[:model])")
    end

    it "honours configured contractClass" do
      el = { "config" => { "contractClass" => "OrderContract" } }
      code = described_class.new(el, {}).generate_body
      expect(code).to include("OrderContract.build_for(ctx[:bound_entity]).new(ctx[:model])")
    end

    it "honours configured resultVar" do
      el = { "config" => { "resultVar" => "my_contract" } }
      code = described_class.new(el, {}).generate_body
      expect(code).to include("ctx[:my_contract] = EntityEntryContract.build_for")
    end

    it "honours configured modelVariable" do
      el = { "config" => { "modelVariable" => "record" } }
      code = described_class.new(el, {}).generate_body
      expect(code).to include(".new(ctx[:record])")
    end

    it "emits no caching, coercion, mapping, or attribute-prep logic" do
      el = { "config" => { "cachePerClass" => true, "cacheContract" => "true", "validateOnBuild" => "true",
                          "typeCoercion" => "true", "attributeMappings" => { "a" => "b" },
                          "defaultValues" => { "status" => "active" } } }
      code = described_class.new(el, {}).generate_body
      expect(code).not_to include("Rails.cache")
      expect(code).not_to include("_contract_attrs")
      expect(code).not_to include("_attribute_mappings")
      expect(code).not_to include("_default_values")
      expect(code).not_to include("ActiveModel::Type")
      expect(code).not_to include(".validate(_contract_attrs)")
    end

    it "returns true as its final expression" do
      code = described_class.new(element, context).generate_body
      expect(code.strip.split("\n").last).to eq("true")
    end
  end

  describe "#validate_config" do
    it "rejects malformed contractClass names" do
      errors = described_class.new(element, {}).validate_config({ "contractClass" => "not a class" })
      expect(errors).to include(/contractClass must be a valid Ruby class name/)
    end

    it "accepts namespaced class names" do
      errors = described_class.new(element, {}).validate_config({ "contractClass" => "Shop::OrderContract" })
      expect(errors).to be_empty
    end

    it "accepts blank contractClass (default applies)" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to be_empty
    end
  end

  describe "#dependencies" do
    it "depends on :new_model (contract wraps a model)" do
      expect(described_class.new(element, {}).dependencies).to eq([:new_model])
    end
  end
end
```

- [ ] **Step 2: Run the spec and confirm it fails**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rspec spec/services/code_generators/element_types/process/validation/build_contract_generator_spec.rb 2>&1 | tail -20
```

Expected: several failures. The current generator emits `Rails.cache.fetch`, `_contract_attrs`, etc., all of which the new spec forbids.

- [ ] **Step 3: Rewrite `build_contract_generator.rb`**

Replace the content of `app/services/code_generators/element_types/process/validation/build_contract_generator.rb` with the canonical version at the top of Task 2.

- [ ] **Step 4: Run the spec and confirm it passes**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rspec spec/services/code_generators/element_types/process/validation/build_contract_generator_spec.rb 2>&1 | tail -5
```

Expected: all pass.

- [ ] **Step 5: Audit this generator alone**

Run:
```bash
cd /opt/milestone/anysys
bundle exec ruby -e '
  require_relative "scripts/audit_generators"
  require_relative "app/services/code_generators/element_types/process/validation/build_contract_generator"
  klass = CodeGenerators::ElementTypes::Process::Validation::BuildContractGenerator
  pp GeneratorAudit.check_generator(klass)
' 2>&1 | tail -5
```

Expected: `[]`.

- [ ] **Step 6: Full generator spec suite still green**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rspec spec/services/code_generators/ 2>&1 | tail -3
```

Expected: 0 failures (other than pending integration-level changes in Task 5).

- [ ] **Step 7: Stage**

Run:
```bash
cd /opt/milestone/anysys
git add app/services/code_generators/element_types/process/validation/build_contract_generator.rb
git add spec/services/code_generators/element_types/process/validation/build_contract_generator_spec.rb
git status --short
```

---

## Task 3: Rewrite `validate_contract_generator.rb` + its spec (and conditionally create `route_params`, `populate_primary`, `populate_associations`)

**Files:**
- Modify: `app/services/code_generators/element_types/process/validation/validate_contract_generator.rb`
- Modify: `spec/services/code_generators/element_types/process/validation/validate_contract_generator_spec.rb`
- Conditionally create: `app/services/code_generators/element_types/process/validation/route_params_generator.rb` + spec
- Conditionally create: `app/services/code_generators/element_types/process/validation/populate_primary_generator.rb` + spec
- Conditionally create: `app/services/code_generators/element_types/process/validation/populate_associations_generator.rb` + spec

**Canonical target for `validate_contract_generator.rb` (from spec §6.3):**

```ruby
module CodeGenerators
  module ElementTypes
    module Process
      module Validation
        class ValidateContractGenerator < BaseGenerator
          generator_metadata do
            description "Validates the Reform contract against ctx[:params]"
            category :validation
            version "2.0.0"
          end

          def self.registered_names
            ["validate_contract", "validate"]
          end

          def self.sample_input
            { "contractRef" => "contract" }
          end

          def generate_body
            contract_ref = fetch_with_default("contractRef", "contract")
            "ctx[:#{contract_ref}].validate(ctx[:params])"
          end

          def validate_config(_cfg)
            []
          end

          def dependencies
            [:build_contract]
          end
        end
      end
    end
  end
end
```

**Changes vs current:**
- Drop `PERMISSION_TYPES`, `PERMISSION_CHECKS`, `BOOL_ENUM`, `strictMode`, `includeWarnings`, `integratePermission`, `permissionType`, `permissionCheck`, `policyAction`, `userExpression`, `recordExpression`, `policyClass`, `roleExpression`, `requiredRole`, `errorVar`, `subOption`.
- Drop every private helper (`generate_contract_validation`, `strict_mode_check`, `permission_check_line`, `warnings_merge_line`, `permission_inline_check`, `generate_permission_check`).
- Drop all `ActivitySteps::*` references from the body.
- `generate_body` is a single line.
- Keep the `registered_names` alias (`validate` is an alternate UI key for this generator — confirmed in `scripts/audit_generator_ui.rb` ACTION_KEY_ALIASES).
- Bump `version "1.0.0"` → `"2.0.0"`.

**Narrow-generator creation rule:** For each of `DetectAndRouteParams`, `PopulatePrimary`, `PopulateAssociations`:

- If Task 0 found real callers (outside the generator itself and outside spec-assertion files), create a new narrow generator. Each generator's `generate_body` is exactly `ActivitySteps::X.call(ctx, <args>)\ntrue`.
- If Task 0 found only spec-assertion callers (i.e., the only references are `expect(code).to include(...)` in `activity_generator_spec.rb`), DO NOT create a narrow generator. The orchestration is dead and goes away.

- [ ] **Step 1: Record Task 0 decisions**

Open `/tmp/phase-2-task-0-findings.md` (created in Task 0) and note which of the four narrow generators you're creating in this task. If you're creating any, they need matching UI entries — see Task 6.

- [ ] **Step 2: Write the failing spec for `validate_contract`**

Rewrite `spec/services/code_generators/element_types/process/validation/validate_contract_generator_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Validation::ValidateContractGenerator do
  def generate(config = {})
    element = { "id" => "step_validate", "type" => "process", "config" => config }
    described_class.new(element, {}).generate_body
  end

  describe "#generate_body" do
    it "emits the single canonical validate call by default" do
      expect(generate).to eq("ctx[:contract].validate(ctx[:params])")
    end

    it "honours configured contractRef" do
      expect(generate("contractRef" => "order_contract")).to eq("ctx[:order_contract].validate(ctx[:params])")
    end

    it "emits no ActivitySteps:: calls, permission checks, or param-routing logic" do
      code = generate("integratePermission" => true, "strictMode" => "true", "includeWarnings" => "true",
                     "permissionType" => "role_check", "requiredRole" => "admin")
      expect(code).not_to include("ActivitySteps::")
      expect(code).not_to include("Pundit")
      expect(code).not_to include("return false unless")
      expect(code).not_to include("entity_params")
      expect(code).not_to include("_known_keys")
    end
  end

  describe "#validate_config" do
    it "returns an empty array regardless of input" do
      expect(described_class.new({ "config" => {} }, {}).validate_config({ "strictMode" => "true" })).to eq([])
    end
  end

  describe ".registered_names" do
    it "keeps the 'validate' alias" do
      expect(described_class.registered_names).to contain_exactly("validate_contract", "validate")
    end
  end

  describe "#dependencies" do
    it "depends on :build_contract" do
      expect(described_class.new({ "config" => {} }, {}).dependencies).to eq([:build_contract])
    end
  end
end
```

- [ ] **Step 3: Run the spec; confirm failures**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rspec spec/services/code_generators/element_types/process/validation/validate_contract_generator_spec.rb 2>&1 | tail -20
```

Expected: failures (current generator emits `ActivitySteps::DetectAndRouteParams` among other things the new spec forbids).

- [ ] **Step 4: Rewrite `validate_contract_generator.rb`**

Replace the content with the canonical version at the top of Task 3.

- [ ] **Step 5: Spec passes**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rspec spec/services/code_generators/element_types/process/validation/validate_contract_generator_spec.rb 2>&1 | tail -5
```

Expected: all pass.

- [ ] **Step 6: (Conditional) Create `route_params_generator.rb` IF Task 0 found real callers**

If Task 0 found real callers of `ActivitySteps::DetectAndRouteParams`, create `app/services/code_generators/element_types/process/validation/route_params_generator.rb`:

```ruby
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Validation
        class RouteParamsGenerator < BaseGenerator
          generator_metadata do
            description "Routes ctx[:params] through ActivitySteps::DetectAndRouteParams"
            category :validation
            version "1.0.0"
          end

          def self.sample_input
            {}
          end

          def generate_body
            <<~RUBY.chomp
              ActivitySteps::DetectAndRouteParams.call(ctx)
              true
            RUBY
          end

          def validate_config(_cfg)
            []
          end

          def dependencies
            []
          end
        end
      end
    end
  end
end
```

And `spec/services/code_generators/element_types/process/validation/route_params_generator_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Validation::RouteParamsGenerator do
  def generate(config = {})
    element = { "id" => "step_route_params", "type" => "process", "config" => config }
    described_class.new(element, {}).generate_body
  end

  describe "#generate_body" do
    it "is a thin wrapper around ActivitySteps::DetectAndRouteParams" do
      expect(generate).to include("ActivitySteps::DetectAndRouteParams.call(ctx)")
      expect(generate.strip.split("\n").last).to eq("true")
    end

    it "emits only the one orchestration call and `true` (thin wrapper shape)" do
      meaningful = generate.lines.map(&:strip).reject { |l| l.empty? || l == "true" }
      expect(meaningful.size).to eq(1)
    end
  end

  describe "#validate_config" do
    it "returns []" do
      expect(described_class.new({ "config" => {} }, {}).validate_config({})).to eq([])
    end
  end
end
```

If Task 0 found NO real callers, skip this step.

- [ ] **Step 7: (Conditional) Create `populate_primary_generator.rb` IF Task 0 found real callers**

Analogous to Step 6. Generator body:

```ruby
def generate_body
  <<~RUBY.chomp
    ActivitySteps::PopulatePrimary.call(ctx, model: ctx[:model], routed_params: ctx[:routed_params])
    true
  RUBY
end

def dependencies
  [:new_model, :route_params]
end
```

Full file and spec structure: mirror Step 6, adjust class name / ActivitySteps reference / dependencies / description. If Task 0 did NOT find callers, skip.

- [ ] **Step 8: (Conditional) Create `populate_associations_generator.rb` IF Task 0 found real callers**

Generator body:

```ruby
def generate_body
  <<~RUBY.chomp
    ActivitySteps::PopulateAssociations.call(ctx, routed_params: ctx[:routed_params], customer_id: ctx[:customer_id])
    true
  RUBY
end

def dependencies
  [:route_params]
end
```

Mirror Step 6 for the spec. If Task 0 did NOT find callers, skip.

- [ ] **Step 9: Audit all validate-group generators**

Run:
```bash
cd /opt/milestone/anysys
bundle exec ruby -e '
  require_relative "scripts/audit_generators"
  Dir["app/services/code_generators/element_types/process/validation/*_generator.rb"].each { |f| require_relative f }
  [
    CodeGenerators::ElementTypes::Process::Validation::BuildContractGenerator,
    CodeGenerators::ElementTypes::Process::Validation::ValidateContractGenerator
  ].each do |klass|
    gaps = GeneratorAudit.check_generator(klass)
    puts "#{klass.name}: #{gaps.empty? ? "CLEAN" : gaps.inspect}"
  end
' 2>&1 | tail -10
```

Expected: both classes print `CLEAN`. Narrow generators (if created) should also print CLEAN.

- [ ] **Step 10: Full spec suite check**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rspec spec/services/code_generators/ 2>&1 | tail -3
```

Expected: 0 failures in the code_generators tree. Failures in `activity_generator_spec.rb` are expected and handled by Task 5.

- [ ] **Step 11: Stage**

Run:
```bash
cd /opt/milestone/anysys
git add app/services/code_generators/element_types/process/validation/
git add spec/services/code_generators/element_types/process/validation/
git status --short
```

---

## Task 4: Rewrite `save_model_generator.rb` + its spec (and conditionally create `save_all_model`)

**Files:**
- Modify: `app/services/code_generators/element_types/process/model_operations/save_model_generator.rb`
- Modify: `spec/services/code_generators/element_types/process/model_operations/save_model_generator_spec.rb`
- Conditionally create: `app/services/code_generators/element_types/process/model_operations/save_all_model_generator.rb` + spec

**Canonical target for `save_model_generator.rb` (from spec §6.4):**

```ruby
module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class SaveModelGenerator < BaseGenerator
          BOOL_STRINGS = %w[true false].freeze

          generator_metadata do
            description "Persists the Reform contract (contract.save)"
            category :model_operations
            version "3.0.0"
          end

          def self.sample_input
            { "contractRef" => "contract", "bang" => "false" }
          end

          def generate_body
            contract_ref = fetch_with_default("contractRef", "contract")
            method       = fetch_enum("bang", BOOL_STRINGS, default: "false") == "true" ? "save!" : "save"
            "ctx[:#{contract_ref}].#{method}"
          end

          def validate_config(cfg)
            errors = []
            bang = cfg["bang"]
            if bang.present? && !BOOL_STRINGS.include?(bang.to_s)
              errors << "bang must be one of: #{BOOL_STRINGS.join(', ')}"
            end
            errors
          end

          def dependencies
            [:validate_contract]
          end
        end
      end
    end
  end
end
```

**Changes vs current:**
- Drop `STRATEGIES`, `BOOL_FLAGS`, `CONTEXT_SYMBOL_PATTERN`.
- Drop `strategy`, `saveStrategy` (legacy), `saveAll` branch, `touch`, `returnUpdated`, `context`, `modelVariable`, `validate` knobs.
- Drop helpers `build_save_args`, `build_save_call`, `normalized_context_symbol`.
- New knob set: `contractRef` + `bang`.
- Bump `version "2.1.0"` → `"3.0.0"`.

- [ ] **Step 1: Write the failing spec first**

Rewrite `spec/services/code_generators/element_types/process/model_operations/save_model_generator_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::SaveModelGenerator do
  def generate(config = {})
    element = { "id" => "step_save", "type" => "process", "config" => config }
    described_class.new(element, {}).generate_body
  end

  describe "#generate_body" do
    it "emits ctx[:contract].save by default" do
      expect(generate).to eq("ctx[:contract].save")
    end

    it "emits ctx[:contract].save! when bang=true" do
      expect(generate("bang" => "true")).to eq("ctx[:contract].save!")
    end

    it "honours configured contractRef" do
      expect(generate("contractRef" => "order_contract")).to eq("ctx[:order_contract].save")
    end

    it "combines contractRef and bang" do
      expect(generate("contractRef" => "order_contract", "bang" => "true"))
        .to eq("ctx[:order_contract].save!")
    end

    it "emits no ActivitySteps::SaveAll reference" do
      expect(generate("strategy" => "saveAll")).not_to include("ActivitySteps::SaveAll")
    end

    it "emits no touch or reload post-ops" do
      code = generate("touch" => "true", "returnUpdated" => "true")
      expect(code).not_to include(".touch")
      expect(code).not_to include(".reload")
    end

    it "ignores legacy strategy / saveStrategy keys entirely" do
      %w[strategy saveStrategy].each do |legacy|
        code = generate(legacy => "saveAll")
        expect(code).to eq("ctx[:contract].save")
      end
    end
  end

  describe "#validate_config" do
    it "returns [] for valid bang" do
      expect(described_class.new({ "config" => {} }, {}).validate_config({ "bang" => "true" })).to eq([])
    end

    it "flags invalid bang" do
      errors = described_class.new({ "config" => {} }, {}).validate_config({ "bang" => "yes" })
      expect(errors).not_to be_empty
      expect(errors.first).to include("bang must be one of")
    end
  end

  describe "#dependencies" do
    it "depends on :validate_contract" do
      expect(described_class.new({ "config" => {} }, {}).dependencies).to eq([:validate_contract])
    end
  end
end
```

- [ ] **Step 2: Run spec; confirm failures**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rspec spec/services/code_generators/element_types/process/model_operations/save_model_generator_spec.rb 2>&1 | tail -20
```

Expected: failures.

- [ ] **Step 3: Rewrite `save_model_generator.rb`**

Replace content with the canonical version at the top of Task 4.

- [ ] **Step 4: Spec passes**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rspec spec/services/code_generators/element_types/process/model_operations/save_model_generator_spec.rb 2>&1 | tail -5
```

- [ ] **Step 5: (Conditional) Create `save_all_model_generator.rb` IF Task 0 found real callers of `ActivitySteps::SaveAll`**

If Task 0 determined `SaveAll` has real (non-spec, non-generator) callers, create:

`app/services/code_generators/element_types/process/model_operations/save_all_model_generator.rb`:

```ruby
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class SaveAllModelGenerator < BaseGenerator
          generator_metadata do
            description "Persists model + associations via ActivitySteps::SaveAll"
            category :model_operations
            version "1.0.0"
          end

          def self.sample_input
            {}
          end

          def generate_body
            <<~RUBY.chomp
              ActivitySteps::SaveAll.call(ctx)
              true
            RUBY
          end

          def validate_config(_cfg)
            []
          end

          def dependencies
            [:validate_contract]
          end
        end
      end
    end
  end
end
```

And its spec file at `spec/services/code_generators/element_types/process/model_operations/save_all_model_generator_spec.rb` — mirror the structure of the `route_params` spec from Task 3 Step 6, adjusting class name and expected body content.

If Task 0 found no real callers, skip this step.

- [ ] **Step 6: Audit the model_operations canonical generators**

Run:
```bash
cd /opt/milestone/anysys
bundle exec ruby -e '
  require_relative "scripts/audit_generators"
  Dir["app/services/code_generators/element_types/process/model_operations/*_generator.rb"].each { |f| require_relative f }
  [
    CodeGenerators::ElementTypes::Process::ModelOperations::NewModelGenerator,
    CodeGenerators::ElementTypes::Process::ModelOperations::SaveModelGenerator
  ].each do |klass|
    gaps = GeneratorAudit.check_generator(klass)
    puts "#{klass.name}: #{gaps.empty? ? "CLEAN" : gaps.inspect}"
  end
' 2>&1 | tail -5
```

Expected: both print `CLEAN`.

- [ ] **Step 7: Full generator spec suite check**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rspec spec/services/code_generators/ 2>&1 | tail -3
```

Expected: 0 failures.

- [ ] **Step 8: Stage**

Run:
```bash
cd /opt/milestone/anysys
git add app/services/code_generators/element_types/process/model_operations/save_model_generator.rb
git add spec/services/code_generators/element_types/process/model_operations/save_model_generator_spec.rb
# If save_all_model was created:
git add app/services/code_generators/element_types/process/model_operations/save_all_model_generator.rb 2>/dev/null
git add spec/services/code_generators/element_types/process/model_operations/save_all_model_generator_spec.rb 2>/dev/null
git status --short
```

---

## Task 5: Update `spec/services/activity_generator_spec.rb` integration assertions

**Files:**
- Modify: `spec/services/activity_generator_spec.rb`

The file has many assertions that the generated Activity contains strings like `ActivitySteps::SaveAll.call(ctx)`, `ActivitySteps::PopulatePrimary.call(...)`, etc. These assertions test that the COMPOSED Activity code contains specific outputs; they're integration-level, not generator-level. After Phase 2 the composed Activity code will change.

**Strategy:**
- For each failing assertion, find the generated substring it's pattern-matching on. Determine whether that substring survives Phase 2 (e.g., if Task 0 determined `SaveAll` has no real callers, every `ActivitySteps::SaveAll` assertion in this file must be rewritten to assert something the new flow actually produces).
- The new flow is: `model` → `contract` → `validate` → `save`, producing these lines in the generated Activity:
  - `ctx[:model] = EntityEntry.build_for(ctx[:bound_entity]).new(customer_id: ctx[:customer_id])` (from new_model)
  - `ctx[:contract] = EntityEntryContract.build_for(ctx[:bound_entity]).new(ctx[:model])` (from build_contract)
  - `ctx[:contract].validate(ctx[:params])` (from validate_contract)
  - `ctx[:contract].save` or `ctx[:contract].save!` (from save_model)
- The legacy calls (`ActivitySteps::SaveAll.call(ctx)`, etc.) are EITHER replaced by the thin-wrapper generators from Task 3/4 Step 5 (if Task 0 found callers), OR simply dropped from expected output.

- [ ] **Step 1: Run the file and capture all failures**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rspec spec/services/activity_generator_spec.rb 2>&1 > /tmp/activity-generator-failures.txt
tail -60 /tmp/activity-generator-failures.txt
```

Expected: some number of failures. Each failure has a file:line reference showing which assertion broke.

- [ ] **Step 2: For each failing assertion, decide its fate**

For each failing line:

1. Read the surrounding `it "..." do ... end` block to understand what the test is trying to verify.
2. Classify:
   - (a) Asserting `ActivitySteps::SaveAll.call(ctx)` appears in output → if Task 0 created `save_all_model` generator, rewrite the test to use the new generator in the input flowchart fixture; if Task 0 dropped SaveAll, delete the assertion (and possibly the whole `it` block if nothing else of substance remains).
   - (b) Asserting `ActivitySteps::PopulatePrimary.call(...)` / `PopulateAssociations.call(...)` → same rule: surviving → rewrite; dropped → delete.
   - (c) Asserting `ActivitySteps::DetectAndRouteParams.call(ctx)` → same.
   - (d) Asserting something about `new_model`, `build_contract`, `validate_contract`, `save_model` output that uses the OLD body patterns → rewrite to match the new body.

3. Preserve the INTENT of each test:
   - "generates save_model using ActivitySteps::SaveAll" was testing that save_model produces a valid Ruby call. The new intent: "generates save_model as ctx[:contract].save". Rewrite accordingly.
   - "populates associations after validate" was testing step ordering. If populate_associations survives, the assertion changes to `populate_associations` step placement (not `ActivitySteps::PopulateAssociations.call` line). If dropped, the test is removed.

- [ ] **Step 3: Apply edits**

Edit each offending line in `spec/services/activity_generator_spec.rb`. Line references from the Phase 1 grep: 562, 563, 566, 569, 573, 650, 651, 654, 655, 672, 685, 693, 695, 744, 769, 770, 773, 1384, 1406, 1421, 1435. **Line numbers will shift as you edit.** Re-run the failing spec after each edit batch to confirm progress.

- [ ] **Step 4: Spec passes**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rspec spec/services/activity_generator_spec.rb 2>&1 | tail -3
```

Expected: 0 failures.

- [ ] **Step 5: Full spec suite check**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rspec 2>&1 | tail -3
```

Expected: 0 failures across the whole suite. Note: the full suite includes controller / model / ViewComponent specs for the rest of the app. If anything else fails, investigate — it's likely a regression, not a planned change.

- [ ] **Step 6: Stage**

Run:
```bash
cd /opt/milestone/anysys
git add spec/services/activity_generator_spec.rb
git status --short
```

---

## Task 6: Update UI property-editor schemas (model_actions.js + validation_actions.js)

**Files:**
- Modify: `app/javascript/flowchart/constants/action_configs/model_actions.js`
- Modify: `app/javascript/flowchart/constants/action_configs/validation_actions.js`
- Regenerate: `spec/support/config_schemas.rb` (via rake, not hand edit)

### 6.1 `new_model` in `model_actions.js`

**Before (current):**
```js
{
  value: "new_model",
  label: "New Model",
  ...,
  configSchema: [
    { key: "resultVar", type: "text", label: "Result Variable", placeholder: "e.g., model", default: "model" }
  ]
}
```

This is already minimal. Verify it matches. If additional fields have been added since Phase 1, prune them.

### 6.2 `save_model` in `model_actions.js`

**Before:** has `strategy`, `modelVariable`, `validate`, `touch`, `context`, `returnUpdated`, `saveStrategy` (legacy).

**After:**
```js
{
  value: "save_model",
  label: "Save Model",
  icon: "M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3 3m0 0l-3-3m3 3V4",
  color: "green",
  category: "model",
  description: "Save the Reform contract",
  singleUse: true,
  configSchema: [
    {
      key: "contractRef",
      type: "text",
      label: "Contract Variable",
      placeholder: "e.g., contract",
      default: "contract"
    },
    {
      key: "bang",
      type: "select",
      label: "Raise on failure (save!)",
      default: "false",
      options: [
        { value: "false", label: "false" },
        { value: "true", label: "true" }
      ]
    }
  ]
}
```

### 6.3 `build_contract` in `validation_actions.js`

**Inspect the current content** to find the existing `build_contract` entry.

**After:**
```js
{
  value: "build_contract",
  label: "Build Contract",
  icon: <keep existing icon>,
  color: <keep existing color>,
  category: "validation",
  description: "Build the Reform contract wrapping the primary entity model",
  singleUse: true,
  configSchema: [
    {
      key: "contractClass",
      type: "text",
      label: "Contract Class",
      placeholder: "e.g., EntityEntryContract",
      default: "EntityEntryContract"
    },
    {
      key: "resultVar",
      type: "text",
      label: "Result Variable",
      placeholder: "e.g., contract",
      default: "contract"
    },
    {
      key: "modelVariable",
      type: "text",
      label: "Model Variable",
      placeholder: "e.g., model",
      default: "model"
    }
  ]
}
```

Drop every field not in the list above (cachePerClass, cacheContract, validateOnBuild, typeCoercion, attributeMappings, defaultValues).

### 6.4 `validate_contract` / `validate` in `validation_actions.js`

Registered under both keys per `ACTION_KEY_ALIASES` in `audit_generator_ui.rb`. UI entry is the `validate` entry (or `validate_contract`, whichever exists today).

**After:**
```js
{
  value: "validate",        // or "validate_contract" — keep whichever key is currently used
  label: "Validate Contract",
  icon: <keep existing icon>,
  color: <keep existing color>,
  category: "validation",
  description: "Validate the Reform contract against ctx[:params]",
  singleUse: true,
  configSchema: [
    {
      key: "contractRef",
      type: "text",
      label: "Contract Variable",
      placeholder: "e.g., contract",
      default: "contract"
    }
  ]
}
```

Drop every other field. If the current entry has `subOption` driving a "permission" branch, that branch is gone — the permission machinery leaves `validate_contract` and either becomes a separate generator (if usage demands) or is dropped (more likely). In Phase 2 we simply delete the permission UI surface on this entry.

### 6.5 (Conditional) Add UI entries for narrow generators created in Task 3/4

If Task 0/3/4 created `save_all_model_generator`, `route_params_generator`, `populate_primary_generator`, or `populate_associations_generator`, each needs a matching UI entry. Use this shape (substituting the correct key / label / icon / category):

```js
{
  value: "save_all_model",  // or "route_params" / "populate_primary" / "populate_associations"
  label: "Save All (Model + Associations)",  // etc
  icon: "M3 10h18M3 14h18",  // pick an appropriate icon from existing entries
  color: "green",  // etc
  category: "model",  // or "validation" for the route_params group
  description: "Persist the primary entity plus its associations",  // etc
  singleUse: true,
  configSchema: []  // narrow generators have no config knobs
}
```

Place `save_all_model` in `model_actions.js` near `save_model`. Place the three validation ones in `validation_actions.js` near `validate_contract`.

- [ ] **Step 1: Edit `model_actions.js`**

Open `app/javascript/flowchart/constants/action_configs/model_actions.js`. Apply the `new_model` (§6.1), `save_model` (§6.2), and `save_all_model` (§6.5 conditional) changes. Preserve the file's overall structure and any unrelated entries (find_model, destroy_model, etc. — those are Phase 3).

- [ ] **Step 2: Edit `validation_actions.js`**

Open `app/javascript/flowchart/constants/action_configs/validation_actions.js`. Apply the `build_contract` (§6.3), `validate_contract` (§6.4), and the three conditional narrow-generator entries (§6.5) if applicable. Preserve anything else in the file.

- [ ] **Step 3: Regenerate the Ruby mirror**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rake config_schemas:mirror 2>&1 | tail -5
```

Expected: prints `Wrote N entries (actions + element types) to .../spec/support/config_schemas.rb`.

- [ ] **Step 4: Verify drift check**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rake config_schemas:check 2>&1 | tail -3
```

Expected: `OK: config schemas in sync`. If DRIFT is reported, Step 3 didn't actually regenerate the mirror — debug the node extractor.

- [ ] **Step 5: UI audit**

Run:
```bash
cd /opt/milestone/anysys
bundle exec ruby scripts/audit_generator_ui.rb 2>&1 | tail -5
```

Expected: actionable-gap count decreases from the Phase 1 baseline (Phase 1 showed 4 actionable gaps in the UI audit, tracked against the 2026-04-19 report). After Phase 2 UI cleanup, this number should drop, not rise. Record the new count.

- [ ] **Step 6: Full spec suite**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rspec 2>&1 | tail -3
```

Expected: 0 failures.

- [ ] **Step 7: Stage**

Run:
```bash
cd /opt/milestone/anysys
git add app/javascript/flowchart/constants/action_configs/model_actions.js
git add app/javascript/flowchart/constants/action_configs/validation_actions.js
git add spec/support/config_schemas.rb
git status --short
```

---

## Task 7: Regenerate audit baseline and confirm target gaps are zero

**Files:**
- Regenerate: `docs/superpowers/specs/2026-04-27-generator-audit-data.yml`

- [ ] **Step 1: Run the baseline task**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rake audit:generators:baseline 2>&1 | tail -3
```

Expected: `Baseline regenerated: N generators, M total gaps captured in ...`. Both N and M should change from Phase 1:
- N: 116 + (number of narrow generators Task 3/4 created — 0 to 4).
- M: Phase 1 baseline was 34; after Phase 2, expect it to drop by at least 4 (one gap from each of the canonical 4 generators, possibly more if related generators share fixes via dropped `ActivitySteps::` references). Reasonable target: M ≤ 30.

- [ ] **Step 2: Confirm the canonical 4 are CLEAN**

Run:
```bash
cd /opt/milestone/anysys
grep -A 2 "NewModelGenerator:\|BuildContractGenerator:\|ValidateContractGenerator:\|SaveModelGenerator:" docs/superpowers/specs/2026-04-27-generator-audit-data.yml | head -40
```

Each of the four entries should show `gaps: []`. If any shows gaps, go back to the generator and re-inspect against the audit output.

- [ ] **Step 3: Audit task exits non-zero** (we haven't refactored everything yet, so there will still be gaps from Phase 3+)

Run:
```bash
cd /opt/milestone/anysys
bundle exec rake audit:generators
echo "Exit status: $?"
```

Expected: prints remaining gaps, `Exit status: 1`. This is correct — Phase 3+ work remains.

- [ ] **Step 4: Stage the updated baseline YAML**

Run:
```bash
cd /opt/milestone/anysys
git add docs/superpowers/specs/2026-04-27-generator-audit-data.yml
git status --short
```

---

## Task 8: Final verification and handoff

- [ ] **Step 1: Full test suite**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rspec 2>&1 | tail -3
```

Expected: 0 failures. Total example count may drift from the 3833 post-Phase-1 baseline (Phase 2 removed some knob-specific examples, added narrow-generator specs). Acceptable: ±10%.

- [ ] **Step 2: UI audit**

Run:
```bash
cd /opt/milestone/anysys
bundle exec ruby scripts/audit_generator_ui.rb 2>&1 | tail -5
```

Expected: actionable-gap count is ≤ the Phase 1 count.

- [ ] **Step 3: Generator audit**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rake audit:generators 2>&1 | tail -5
```

Exit 1 is expected — Phase 3+ work remains. Total gaps should be strictly less than 34 (Phase 1 baseline).

- [ ] **Step 4: Browser spot-check**

This is a UI-touching refactor. Per AGENTS.md convention for UI changes, start the dev server and verify in the browser:

Run:
```bash
cd /opt/milestone/anysys
# Check if dev server is already running (Rails default port 3000)
curl -sSf http://localhost:3000/ -o /dev/null && echo "server running" || echo "server not running"
```

If the server isn't running, start it:
```bash
bin/dev 2>&1 &
sleep 5
```

Load a flowchart page in the browser that has a `new_model` / `build_contract` / `validate_contract` / `save_model` step. Open the property editor for each of the four. Verify:
- `new_model`: only `resultVar` shown.
- `build_contract`: only `contractClass`, `resultVar`, `modelVariable` shown.
- `validate_contract` / `validate`: only `contractRef` shown.
- `save_model`: only `contractRef` and `bang` shown.
- No `cachePerClass`, `strictMode`, `integratePermission`, `saveStrategy`, `touch`, `returnUpdated`, etc. fields visible.

If the browser shows fields that should have been removed, the UI edits weren't flushed through — re-run `config_schemas:mirror`, restart the dev server.

If the user can't run a dev server (or the Phase 2 changes haven't been deployed to a running instance), explicitly state that in the handoff: "UI spot-check deferred — no dev server accessible."

- [ ] **Step 5: Review staged files**

Run:
```bash
cd /opt/milestone/anysys
git status --short
git diff --cached --stat
```

Expected staged (modified or new) files:

Always:
```
M  app/javascript/flowchart/constants/action_configs/model_actions.js
M  app/javascript/flowchart/constants/action_configs/validation_actions.js
M  app/services/code_generators/element_types/process/model_operations/new_model_generator.rb
M  app/services/code_generators/element_types/process/model_operations/save_model_generator.rb
M  app/services/code_generators/element_types/process/validation/build_contract_generator.rb
M  app/services/code_generators/element_types/process/validation/validate_contract_generator.rb
M  docs/superpowers/specs/2026-04-27-generator-audit-data.yml
M  spec/services/activity_generator_spec.rb
M  spec/services/code_generators/element_types/process/model_operations/new_model_generator_spec.rb
M  spec/services/code_generators/element_types/process/model_operations/save_model_generator_spec.rb
M  spec/services/code_generators/element_types/process/validation/build_contract_generator_spec.rb
M  spec/services/code_generators/element_types/process/validation/validate_contract_generator_spec.rb
M  spec/support/config_schemas.rb
```

Conditionally (per Task 0 findings), also staged:
```
A  app/services/code_generators/element_types/process/model_operations/save_all_model_generator.rb
A  app/services/code_generators/element_types/process/validation/route_params_generator.rb
A  app/services/code_generators/element_types/process/validation/populate_primary_generator.rb
A  app/services/code_generators/element_types/process/validation/populate_associations_generator.rb
(and matching *_spec.rb)
```

- [ ] **Step 6: Handoff — do NOT commit**

Per project convention (AGENTS.md `feedback_no_auto_commit`), do not run `git commit`. Report to the user:

- Phase 2 complete.
- Exact new audit baseline: N generators, M gaps (from Task 7 Step 1 output).
- Narrow generators created (if any): list class names.
- Narrow generators NOT created (orchestration dropped): list class names (e.g. "ActivitySteps::SaveAll had no real callers; save_all_model_generator not created; legacy saveAll path removed from generated code").
- Suggested commit message:

  ```
  Phase 2: canonical 4 generator rewrite

  Align new_model / build_contract / validate_contract / save_model with the
  Trailblazer Railway example:
    - new_model: ctx[:model] = EntityEntry.build_for(ctx[:bound_entity]).new(customer_id: ctx[:customer_id])
    - build_contract: ctx[:contract] = Contract.build_for(...).new(ctx[:model])
    - validate_contract: ctx[:contract].validate(ctx[:params])
    - save_model: ctx[:contract].save (or .save!)

  Drop knobs: cachePerClass/cacheContract/validateOnBuild/typeCoercion/
  attributeMappings/defaultValues (build_contract); strictMode/
  includeWarnings/integratePermission/permissionType (validate_contract);
  strategy/saveStrategy/saveAll/touch/returnUpdated/context/modelVariable/
  validate (save_model); attributes/associations (new_model).

  {If narrow generators created: list them here.}

  UI schemas (model_actions.js, validation_actions.js) pruned to match;
  spec/support/config_schemas.rb regenerated.

  Audit baseline reduced from 34 to M gaps.
  ```

- Phase 3 (remaining model_operations rewrite) can begin; its plan references the updated baseline.

---

## Self-Review Checklist

**1. Spec coverage:**
- Spec §6.1 (new_model) → Task 1 ✓
- Spec §6.2 (build_contract) → Task 2 ✓
- Spec §6.3 (validate_contract) → Task 3, plus conditional narrow generators for the orchestration services ✓
- Spec §6.4 (save_model) → Task 4, plus conditional save_all_model ✓
- Spec §7 (UI cleanup) → Task 6 ✓
- Spec §8 (testing strategy, A1 "specs stay green") → every task has a "spec passes" step before proceeding ✓
- Spec §9 Phase 2 row → Tasks 0–8 map to that row ✓
- Spec §11 open questions → Task 0 ✓

**2. Placeholder scan:** No TBD / TODO / "add appropriate X". Every code block is complete. Line references in Task 5 pull from the Phase 1 grep output.

**3. Type consistency:** Dependencies are consistent:
- `new_model.dependencies = []` (Task 1) — matches `build_contract.dependencies = [:new_model]` (Task 2).
- `build_contract.dependencies = [:new_model]` — matches `validate_contract.dependencies = [:build_contract]` (Task 3).
- `validate_contract.dependencies = [:build_contract]` — matches `save_model.dependencies = [:validate_contract]` (Task 4).
- Narrow generators (if created): `route_params.dependencies = []`, `populate_primary.dependencies = [:new_model, :route_params]`, `populate_associations.dependencies = [:route_params]`, `save_all_model.dependencies = [:validate_contract]` — internally consistent.

**4. Knob name consistency:**
- `contractRef` used by both `validate_contract` and `save_model`; UI matches. ✓
- `modelVariable` used by `build_contract`; UI matches. ✓
- `resultVar` used by `new_model` and `build_contract`; UI matches. ✓
- `bang` used by `save_model`; UI matches. ✓

**5. Scope check:** All tasks are within Phase 2 (canonical 4 rewrite + UI mirror for those 4 + integration spec updates + audit re-baseline). Nothing bleeds into Phase 3 (other model_operations).

**6. Task 0's findings drive Tasks 3/4/6:** Clear conditional branches in Tasks 3, 4, and 6 based on whether Task 0 found real callers. No "it depends" phrasing — the decision is explicit.

No fixes needed.
