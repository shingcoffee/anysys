# Code Generator Canonical Alignment — Phase 1: Audit Script + Checklist

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a machine-runnable audit script (`scripts/audit_generators.rb`) that flags every generator-level violation of the canonical Trailblazer Railway shape described in the spec, plus a prose checklist doc for the human-judgment rules, plus a baseline report capturing current violations. No generator-file or UI-file content changes in this phase.

**Architecture:** One new script (`scripts/audit_generators.rb`) that walks `app/services/code_generators/element_types/**/*.rb`, parses each generator's source with Ripper for static rules, invokes `generate_body` with sample input for dynamic rules, and emits a YAML gap report. One new rake task (`audit:generators`) that wraps the script and exits non-zero on gaps (CI-ready). One new checklist doc (`docs/code-generators/AUTHORING_CHECKLIST.md`) that contributors read before adding a new generator. One spec file exercising the audit script's rule detection against hand-crafted fixture generators (not the live codebase — fixtures so the spec isn't flaky as the real codebase changes).

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, RSpec, Ripper (stdlib), YAML (stdlib). Follows conventions of the existing `scripts/audit_generator_ui.rb` (Ripper-based AST walking) and `lib/tasks/config_schemas.rake` (rake task + exit-status drift check).

**Spec reference:** `docs/superpowers/specs/2026-04-27-code-generator-canonical-alignment-design.md` — sections 4 (checklist rubric), 5 (audit script), and the phase table in section 9 (Phase 1 row).

**Scope note:** This plan implements Phase 1 **only**. Phases 2–9 each get their own plan, written after the prior phase lands.

---

## File Structure

**New files:**

1. `scripts/audit_generators.rb` — the audit script. Parallel to `scripts/audit_generator_ui.rb`; reuses the same Ripper-based AST approach but checks generator-side rules, not UI-side ones.
2. `lib/tasks/audit_generators.rake` — rake task wrapper. Two tasks: `audit:generators` (runs script, exits non-zero on violations) and `audit:generators:baseline` (regenerates the YAML baseline, does not exit non-zero).
3. `docs/code-generators/AUTHORING_CHECKLIST.md` — prose checklist. Links to the spec for rationale. Contributors read this before writing a new generator.
4. `docs/superpowers/specs/2026-04-27-generator-audit-data.yml` — baseline report (generated, committed). First run of the script produces this file.
5. `spec/scripts/audit_generators_spec.rb` — RSpec covering the audit script's rule detection. Uses **fixture generator files** under `spec/fixtures/audit_generators/` rather than live generators so specs stay stable as the real codebase evolves.
6. `spec/fixtures/audit_generators/` (directory) — small fixture generator files that exercise each rule: one fixture that passes all rules (`clean_generator.rb`), one fixture per rule violation type (`legacy_alias_generator.rb`, `inline_orchestration_generator.rb`, etc.).

**Modified files:**

- None in Phase 1. The audit script reads the codebase; it doesn't change any generator or UI file.

**Per-rule responsibility map** (which rule lives in which method of `scripts/audit_generators.rb`):

| Spec rule | Check method | Mechanism |
|---|---|---|
| 2. bracket-notation ctx access | `check_ctx_access(body)` | string regex on emitted body |
| 4. no inline multi-step orchestration | `check_orchestration(body)` | count `ActivitySteps::` invocations in body; allow thin wrapper |
| 5. no legacy alias reads | `check_legacy_aliases(source_ast)` | Ripper walk for `config["X"] \|\| config["Y"]` and `cfg["X"] \|\| cfg["Y"]` patterns |
| 7. enum validation uses fetch_enum | `check_enum_handling(source_ast)` | Ripper walk for `%w[...].include?(...)` inside methods whose name starts with `generate_` or `build_` |
| 8. dependencies reflects ctx reads | `check_dependencies(body, deps)` | extract ctx reads from body; map to expected-dependency generator names; compare to declared `dependencies` |
| 12. no legacy enum values in UI | `check_enum_options_mirror(klass, ui_schema)` | read generator's `fetch_enum` allowed lists (Ripper); compare to UI options |
| 13. visibleWhen references live | `check_visible_when(ui_schema)` | UI schema self-consistency check |

Rules 1, 3, 6, 9, 10, 11 from the spec are:
- Rule 1 (signature) — enforced by `GeneratorInterface#generate_step_method` wrapper; script does a once-only assertion that the wrapper is used (no per-generator check needed).
- Rule 3 (single responsibility) — **(H)** human judgment, not in script. Covered in prose checklist.
- Rule 6 (build-time knobs) — **(H)** human judgment (script cannot tell whether `cacheContract` is "build-time" vs legitimate runtime); covered in prose checklist.
- Rule 9 (multi-tenancy `customer_id`) — **(H)** human judgment; covered in prose checklist.
- Rule 10 (UI field ↔ generator key) — already covered by existing `scripts/audit_generator_ui.rb`; Phase 1 does NOT duplicate that coverage.
- Rule 11 (orphan UI fields) — covered by extending `scripts/audit_generator_ui.rb` with one new gap type `orphan_ui_field`; this IS part of Phase 1 because the existing script only reports missing UI fields, not orphan ones.

---

## Preflight

- [ ] **Step 0: Verify clean working tree and baseline spec suite**

Run:
```bash
cd /opt/milestone/anysys
git status --short
bundle exec rspec spec/services/code_generators/ 2>&1 | tail -3
```

Expected:
- `git status --short` shows no untouched working-directory changes. (There will be the uncommitted design spec from the prior step — that's expected. Confirm nothing else.)
- rspec output ends with something like `3802 examples, 0 failures`. Exact number may drift slightly; the critical condition is `0 failures`.

If rspec has any failures at baseline, **STOP** and fix them before proceeding. The audit script cannot land if the existing specs are red.

---

## Task 1: Create the authoring checklist doc

**Files:**
- Create: `docs/code-generators/AUTHORING_CHECKLIST.md`

- [ ] **Step 1: Create the docs directory and write the checklist**

Run:
```bash
mkdir -p /opt/milestone/anysys/docs/code_generators
```

Write `/opt/milestone/anysys/docs/code-generators/AUTHORING_CHECKLIST.md` with this exact content:

````markdown
# Generator Authoring Checklist

This checklist is the rubric every generator under `app/services/code_generators/element_types/` is held to. It exists because the code-generator layer had drifted from its canonical shape (the Trailblazer Railway example in the project spec), and we needed a written standard so the next drift stays caught.

**Mechanical rules (1, 2, 4, 5, 7, 8, 10, 11, 12, 13 in the spec) are checked by `scripts/audit_generators.rb` and `scripts/audit_generator_ui.rb`.** Run them before shipping a new generator:

```bash
bundle exec rake audit:generators
bundle exec ruby scripts/audit_generator_ui.rb
```

Both must exit 0.

**Judgment rules (3, 6, 9)** are listed below. Self-review against them before opening a PR.

---

## Judgment rule 3 — Single responsibility per step body

The canonical example has four steps — `model`, `contract`, `validate`, `save` — and each one does exactly one thing:

- `model` creates an empty model.
- `contract` wraps the model in a Reform contract.
- `validate` validates the contract with params.
- `save` persists.

If your generator's body does more than one of the conceptual operations below, it's probably two steps fused together:

- Create / find a record
- Wrap a record in a contract
- Assign attributes to a record
- Validate
- Save
- Touch / reload
- Destroy
- Cascade-delete associations
- Enqueue a job
- Send a notification
- Log

If you're unsure, ask: "Would the canonical example fuse these two things?" If the example would keep them separate, so should your generator.

## Judgment rule 6 — Build-time vs runtime knobs

The step body is runtime code. Every `config["..."]` read in the body becomes a runtime decision that ships with the generated file. Check each config key you read and ask: **would this knob be a sensible call signature on the canonical example?**

If the answer is no, the knob is build-time metadata and does not belong in the step body. Examples from the pre-refactor code:

- `cachePerClass`, `cacheContract`, `validateOnBuild` — these described how to construct the contract, not how it runs. They belonged in a factory or were pure overengineering. The canonical example has none of them.
- `strictMode`, `includeWarnings` — these described validator internals. In the canonical example, `validate` is one line. A "strict" validator is a different contract class, not a strict-mode flag on the step.
- `integratePermission`, `permissionType`, `policyAction` — permission checking is a separate step (`authorize`), not a flag on `validate`.

Build-time metadata that's worth keeping usually lives on the class itself (via `generator_metadata` DSL), not in the emitted body.

## Judgment rule 9 — Multi-tenancy: customer_id scoping

Every model read and write in a step body must respect multi-tenancy:

- **Reads:** Queries through `EntityEntry.build_for(ctx[:bound_entity])` must apply `.where(customer_id: ctx[:customer_id])`. Direct `Model.find(id)` calls are forbidden unless the model is known to be non-tenant (rare).
- **Writes on create:** `ctx[:model].customer_id = ctx[:customer_id]` (or set via contract sync).
- **Writes on update:** inherited from the existing record; don't change it.

If your generator operates on raw strings / non-model data (e.g. a string formatter or a cache read), rule 9 doesn't apply.

---

## When a new rule is needed

If a reviewer repeats the same judgment call across multiple generators, promote the pattern to a mechanical rule in `scripts/audit_generators.rb`. Add the check, regenerate the baseline, commit the new baseline alongside the code change. The prose checklist and the script should never disagree.
````

- [ ] **Step 2: Verify file is present**

Run:
```bash
ls -la /opt/milestone/anysys/docs/code-generators/AUTHORING_CHECKLIST.md
```

Expected: file exists, non-empty.

- [ ] **Step 3: Commit**

Run:
```bash
cd /opt/milestone/anysys
git add docs/code-generators/AUTHORING_CHECKLIST.md
git status --short
```

DO NOT run `git commit`. User commits manually. Confirm the status output shows only the new checklist file staged.

---

## Task 2: Create the fixture generators for testing the audit script

**Files:**
- Create: `spec/fixtures/audit_generators/clean_generator_fixture.rb`
- Create: `spec/fixtures/audit_generators/legacy_alias_generator_fixture.rb`
- Create: `spec/fixtures/audit_generators/inline_orchestration_generator_fixture.rb`
- Create: `spec/fixtures/audit_generators/dotted_ctx_generator_fixture.rb`
- Create: `spec/fixtures/audit_generators/hand_rolled_enum_generator_fixture.rb`
- Create: `spec/fixtures/audit_generators/missing_dependency_generator_fixture.rb`
- Create: `spec/fixtures/audit_generators/thin_wrapper_generator_fixture.rb`

Fixtures are full, loadable Ruby files that subclass `BaseGenerator` — each exercises one rule. The audit script specs load and run checks against these fixtures, not against the live codebase.

- [ ] **Step 1: Create fixtures directory and the "clean" reference fixture**

Run:
```bash
mkdir -p /opt/milestone/anysys/spec/fixtures/audit_generators
```

Write `/opt/milestone/anysys/spec/fixtures/audit_generators/clean_generator_fixture.rb`:

```ruby
# frozen_string_literal: true
# Fixture: a clean generator that passes ALL mechanical audit rules.
# Used by spec/scripts/audit_generators_spec.rb as the positive baseline.

module AuditFixtures
  class CleanGenerator < CodeGenerators::BaseGenerator
    generator_metadata do
      description "Clean fixture generator"
      category :fixtures
      version "1.0.0"
    end

    def generate_body
      target = fetch_with_default("resultVar", "model")
      <<~RUBY.chomp
        ctx[:#{target}] = EntityEntry.build_for(ctx[:bound_entity]).new(customer_id: ctx[:customer_id])
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
```

- [ ] **Step 2: Create the legacy-alias violation fixture**

Write `/opt/milestone/anysys/spec/fixtures/audit_generators/legacy_alias_generator_fixture.rb`:

```ruby
# frozen_string_literal: true
# Fixture: violates rule 5 — reads config["primaryKey"] || config["legacyKey"].

module AuditFixtures
  class LegacyAliasGenerator < CodeGenerators::BaseGenerator
    generator_metadata do
      description "Legacy alias fixture"
      category :fixtures
      version "1.0.0"
    end

    def generate_body
      strategy = config["strategy"] || config["saveStrategy"]
      "ctx[:result] = #{strategy.inspect}\ntrue"
    end

    def validate_config(_cfg)
      []
    end
  end
end
```

- [ ] **Step 3: Create the inline-orchestration violation fixture**

Write `/opt/milestone/anysys/spec/fixtures/audit_generators/inline_orchestration_generator_fixture.rb`:

```ruby
# frozen_string_literal: true
# Fixture: violates rule 4 — emits TWO ActivitySteps:: calls in one body.

module AuditFixtures
  class InlineOrchestrationGenerator < CodeGenerators::BaseGenerator
    generator_metadata do
      description "Inline orchestration fixture"
      category :fixtures
      version "1.0.0"
    end

    def generate_body
      <<~RUBY.chomp
        ActivitySteps::DetectAndRouteParams.call(ctx)
        ActivitySteps::PopulatePrimary.call(ctx, model: ctx[:model])
        true
      RUBY
    end

    def validate_config(_cfg)
      []
    end
  end
end
```

- [ ] **Step 4: Create the dotted-ctx violation fixture**

Write `/opt/milestone/anysys/spec/fixtures/audit_generators/dotted_ctx_generator_fixture.rb`:

```ruby
# frozen_string_literal: true
# Fixture: violates rule 2 — emits ctx.foo dotted access instead of ctx[:foo].

module AuditFixtures
  class DottedCtxGenerator < CodeGenerators::BaseGenerator
    generator_metadata do
      description "Dotted ctx fixture"
      category :fixtures
      version "1.0.0"
    end

    def generate_body
      <<~RUBY.chomp
        ctx.model.save
        true
      RUBY
    end

    def validate_config(_cfg)
      []
    end
  end
end
```

- [ ] **Step 5: Create the hand-rolled-enum violation fixture**

Write `/opt/milestone/anysys/spec/fixtures/audit_generators/hand_rolled_enum_generator_fixture.rb`:

```ruby
# frozen_string_literal: true
# Fixture: violates rule 7 — uses %w[...].include?(...) inside generate_body
# instead of fetch_enum.

module AuditFixtures
  class HandRolledEnumGenerator < CodeGenerators::BaseGenerator
    generator_metadata do
      description "Hand-rolled enum fixture"
      category :fixtures
      version "1.0.0"
    end

    def generate_body
      raw = config["strategy"]
      strategy = %w[save save!].include?(raw) ? raw : "save"
      "ctx[:model].#{strategy}\ntrue"
    end

    def validate_config(_cfg)
      []
    end
  end
end
```

- [ ] **Step 6: Create the missing-dependency violation fixture**

Write `/opt/milestone/anysys/spec/fixtures/audit_generators/missing_dependency_generator_fixture.rb`:

```ruby
# frozen_string_literal: true
# Fixture: violates rule 8 — body reads ctx[:contract] but dependencies is empty.

module AuditFixtures
  class MissingDependencyGenerator < CodeGenerators::BaseGenerator
    generator_metadata do
      description "Missing dependency fixture"
      category :fixtures
      version "1.0.0"
    end

    def generate_body
      <<~RUBY.chomp
        ctx[:contract].save
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
```

- [ ] **Step 7: Create the thin-wrapper allowed-case fixture**

Write `/opt/milestone/anysys/spec/fixtures/audit_generators/thin_wrapper_generator_fixture.rb`:

```ruby
# frozen_string_literal: true
# Fixture: passes rule 4 — single ActivitySteps:: call IS the body. Thin wrapper
# is the canonical "one step = one service invocation" shape and is allowed.

module AuditFixtures
  class ThinWrapperGenerator < CodeGenerators::BaseGenerator
    generator_metadata do
      description "Thin wrapper fixture"
      category :fixtures
      version "1.0.0"
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
  end
end
```

- [ ] **Step 8: Verify all fixtures load**

Run:
```bash
cd /opt/milestone/anysys
bundle exec ruby -e '
  require_relative "config/environment"
  Dir[Rails.root.join("spec/fixtures/audit_generators/*.rb")].each { |f| load f }
  klasses = AuditFixtures.constants.map { |c| AuditFixtures.const_get(c) }
  puts "Loaded: #{klasses.map(&:name).join(", ")}"
'
```

Expected output includes all seven fixture class names: `AuditFixtures::CleanGenerator, AuditFixtures::LegacyAliasGenerator, AuditFixtures::InlineOrchestrationGenerator, AuditFixtures::DottedCtxGenerator, AuditFixtures::HandRolledEnumGenerator, AuditFixtures::MissingDependencyGenerator, AuditFixtures::ThinWrapperGenerator`.

- [ ] **Step 9: Stage (do not commit)**

Run:
```bash
cd /opt/milestone/anysys
git add spec/fixtures/audit_generators/
git status --short
```

Expected: seven new files staged under `spec/fixtures/audit_generators/`.

---

## Task 3: Write failing specs for the audit script

**Files:**
- Create: `spec/scripts/audit_generators_spec.rb`

The audit script module (created in Task 4) is `GeneratorAudit` with class methods per rule. Specs test the classmethods in isolation against fixture data.

- [ ] **Step 1: Create the spec directory and write the full spec file**

Run:
```bash
mkdir -p /opt/milestone/anysys/spec/scripts
```

Write `/opt/milestone/anysys/spec/scripts/audit_generators_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"
load Rails.root.join("scripts/audit_generators.rb")
Dir[Rails.root.join("spec/fixtures/audit_generators/*.rb")].each { |f| load f }

RSpec.describe GeneratorAudit do
  def run_for(klass)
    described_class.check_generator(klass)
  end

  describe ".check_generator returns gaps as an Array of Hashes" do
    it "returns an Array" do
      expect(run_for(AuditFixtures::CleanGenerator)).to be_an(Array)
    end

    it "each gap has :rule, :message, :file keys" do
      result = run_for(AuditFixtures::LegacyAliasGenerator)
      expect(result).not_to be_empty
      gap = result.first
      expect(gap).to include(:rule, :message, :file)
    end
  end

  describe "rule 2: bracket-notation ctx access" do
    it "passes for a generator using ctx[:key] reads only" do
      gaps = run_for(AuditFixtures::CleanGenerator).select { |g| g[:rule] == :ctx_access }
      expect(gaps).to be_empty
    end

    it "flags a generator that emits ctx.foo dotted access" do
      gaps = run_for(AuditFixtures::DottedCtxGenerator).select { |g| g[:rule] == :ctx_access }
      expect(gaps).not_to be_empty
      expect(gaps.first[:message]).to include("ctx.")
    end
  end

  describe "rule 4: no inline multi-step orchestration" do
    it "passes for a clean generator" do
      gaps = run_for(AuditFixtures::CleanGenerator).select { |g| g[:rule] == :inline_orchestration }
      expect(gaps).to be_empty
    end

    it "passes for a thin-wrapper generator (single ActivitySteps:: call is the body)" do
      gaps = run_for(AuditFixtures::ThinWrapperGenerator).select { |g| g[:rule] == :inline_orchestration }
      expect(gaps).to be_empty
    end

    it "flags a generator with TWO ActivitySteps:: calls in one body" do
      gaps = run_for(AuditFixtures::InlineOrchestrationGenerator).select { |g| g[:rule] == :inline_orchestration }
      expect(gaps).not_to be_empty
      expect(gaps.first[:message]).to match(/multiple .* orchestration/i)
    end
  end

  describe "rule 5: no legacy alias reads" do
    it "passes for a clean generator" do
      gaps = run_for(AuditFixtures::CleanGenerator).select { |g| g[:rule] == :legacy_alias }
      expect(gaps).to be_empty
    end

    it "flags config[\"X\"] || config[\"Y\"] patterns" do
      gaps = run_for(AuditFixtures::LegacyAliasGenerator).select { |g| g[:rule] == :legacy_alias }
      expect(gaps).not_to be_empty
      expect(gaps.first[:message]).to include("strategy")
      expect(gaps.first[:message]).to include("saveStrategy")
    end
  end

  describe "rule 7: enum validation uses fetch_enum" do
    it "passes for a clean generator" do
      gaps = run_for(AuditFixtures::CleanGenerator).select { |g| g[:rule] == :enum_handling }
      expect(gaps).to be_empty
    end

    it "flags %w[...].include?(...) inside generate_body" do
      gaps = run_for(AuditFixtures::HandRolledEnumGenerator).select { |g| g[:rule] == :enum_handling }
      expect(gaps).not_to be_empty
    end
  end

  describe "rule 8: dependencies reflects ctx reads" do
    it "passes for a generator with correct dependencies" do
      gaps = run_for(AuditFixtures::CleanGenerator).select { |g| g[:rule] == :dependencies }
      expect(gaps).to be_empty
    end

    it "flags a body that reads ctx[:contract] without declaring :build_contract" do
      gaps = run_for(AuditFixtures::MissingDependencyGenerator).select { |g| g[:rule] == :dependencies }
      expect(gaps).not_to be_empty
      expect(gaps.first[:message]).to include("contract")
    end
  end

  describe ".run_audit scans the live codebase" do
    it "returns a hash keyed by generator class name" do
      report = described_class.run_audit
      expect(report).to be_a(Hash)
      expect(report.keys).to all(be_a(String))
    end

    it "produces an empty or populated :gaps array for each entry" do
      report = described_class.run_audit
      report.each_value do |entry|
        expect(entry).to have_key(:gaps)
        expect(entry[:gaps]).to be_an(Array)
      end
    end
  end
end
```

- [ ] **Step 2: Run the spec and confirm it fails with the expected reason**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rspec spec/scripts/audit_generators_spec.rb 2>&1 | tail -20
```

Expected: the spec file fails because `scripts/audit_generators.rb` does not yet exist. Error message like:
```
LoadError: cannot load such file -- .../scripts/audit_generators.rb
```
or
```
NameError: uninitialized constant GeneratorAudit
```

Either is acceptable. The point is that we have a failing test we need the next task to make pass.

- [ ] **Step 3: Stage (do not commit)**

Run:
```bash
cd /opt/milestone/anysys
git add spec/scripts/audit_generators_spec.rb
git status --short
```

---

## Task 4: Implement the audit script

**Files:**
- Create: `scripts/audit_generators.rb`

The script has two shapes of entry point:
1. `GeneratorAudit.check_generator(klass)` — returns `Array<Hash>` of gaps for one generator class. Used by specs and by the full-scan entry point.
2. `GeneratorAudit.run_audit` — walks `app/services/code_generators/element_types/**/*.rb`, calls `check_generator` on each loaded class, returns a Hash keyed by class name. Used by the CLI entry point.
3. CLI entry: when the file is run as `ruby scripts/audit_generators.rb`, it calls `run_audit`, writes YAML to `docs/superpowers/specs/2026-04-27-generator-audit-data.yml`, prints a summary, and exits non-zero on any gap.

- [ ] **Step 1: Write the full script**

Write `/opt/milestone/anysys/scripts/audit_generators.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Audits every in-scope code generator against the canonical Trailblazer Railway
# shape. Emits a machine-readable YAML gap report at
#   docs/superpowers/specs/2026-04-27-generator-audit-data.yml
#
# Rules checked (see docs/superpowers/specs/2026-04-27-code-generator-canonical-alignment-design.md):
#   2. bracket-notation ctx access
#   4. no inline multi-step orchestration
#   5. no legacy alias reads
#   7. enum validation uses fetch_enum
#   8. dependencies reflects ctx reads
#
# Usage (from repo root):
#   bundle exec ruby scripts/audit_generators.rb           # exits non-zero on gaps
#   bundle exec rake audit:generators                       # same, via rake
#   bundle exec rake audit:generators:baseline              # regenerates baseline YAML

require_relative "../config/environment" unless defined?(Rails)
require "ripper"
require "yaml"
require "pathname"
require "set"

module GeneratorAudit
  BASELINE_PATH = Rails.root.join("docs/superpowers/specs/2026-04-27-generator-audit-data.yml")
  GENERATORS_ROOT = Rails.root.join("app/services/code_generators/element_types")

  # Map of ctx keys that are canonically written by specific generators.
  # Used by rule 8 to verify that a body reading ctx[:X] declares the
  # writer-generator in its dependencies.
  CTX_PRODUCERS = {
    "contract"       => :build_contract,
    "model"          => :new_model,
    "routed_params"  => :detect_and_route_params,
    "valid"          => :validate_contract
  }.freeze

  # Ctx keys that every step is allowed to read without declaring a dependency
  # (ambient context set by the runtime harness).
  AMBIENT_CTX_KEYS = %w[
    bound_entity customer_id current_user current_user_id params request response
    session flash headers id page per_page limit offset sort filter q
  ].to_set.freeze

  class << self
    def run_audit
      report = {}
      generator_files.each do |file|
        klass = load_generator(file)
        next unless klass

        gaps = check_generator(klass)
        report[klass.name] = {
          file: relative_path(file),
          gaps: gaps
        }
      end
      report
    end

    def check_generator(klass)
      source = File.read(source_path_for(klass))
      ast = Ripper.sexp(source)
      body = generate_body_safely(klass)

      gaps = []
      gaps.concat(check_ctx_access(body, klass))
      gaps.concat(check_orchestration(body, klass))
      gaps.concat(check_legacy_aliases(ast, klass))
      gaps.concat(check_enum_handling(source, klass))
      gaps.concat(check_dependencies(body, klass))
      gaps
    end

    def write_baseline(report)
      serialized = report.each_with_object({}) do |(name, entry), out|
        out[name] = {
          "file" => entry[:file],
          "gaps" => entry[:gaps].map { |g| g.transform_keys(&:to_s) }
        }
      end
      File.write(BASELINE_PATH, serialized.to_yaml)
    end

    private

    # --- rule implementations ---------------------------------------------

    def check_ctx_access(body, klass)
      return [] if body.nil?

      # Forbid ctx.foo dotted reads that aren't ctx.dig(...) or ctx[...]
      # Allowed: ctx[:foo], ctx.dig(:foo, :bar)
      # Forbidden: ctx.foo, ctx.foo.bar
      matches = body.scan(/\bctx\.(?!dig\b|\[)[a-zA-Z_][a-zA-Z_0-9]*/)
      return [] if matches.empty?

      [{
        rule: :ctx_access,
        message: "Body reads ctx via dotted access instead of ctx[:key]: #{matches.uniq.join(', ')}",
        file: relative_source(klass)
      }]
    end

    def check_orchestration(body, klass)
      return [] if body.nil?

      # Count ActivitySteps:: invocations; allow thin wrapper (single call, body
      # contains nothing else of substance).
      activity_calls = body.scan(/ActivitySteps::[A-Z][A-Za-z0-9_]*\.call/).size
      return [] if activity_calls.zero?

      if activity_calls >= 2
        return [{
          rule: :inline_orchestration,
          message: "Body contains multiple (#{activity_calls}) ActivitySteps:: orchestration calls — each orchestration call is a separate step.",
          file: relative_source(klass)
        }]
      end

      # activity_calls == 1. Allow only if the body is a thin wrapper: one
      # ActivitySteps:: call plus at most a single trailing `true` line.
      meaningful_lines = body.lines.map(&:strip).reject { |l| l.empty? || l == "true" }
      if meaningful_lines.size > 1
        return [{
          rule: :inline_orchestration,
          message: "Body mixes an ActivitySteps:: call with additional logic (#{meaningful_lines.size} meaningful lines). Either make the body a thin wrapper (just the ActivitySteps:: call) or split the extra logic into its own step.",
          file: relative_source(klass)
        }]
      end

      []
    end

    def check_legacy_aliases(ast, klass)
      # Pattern: (binary ... (:|| (aref ... "X") (aref ... "Y")))
      # Walk the AST; for every Ripper :binary node with op :"||", check if both
      # operands are `config["literal"]` or `cfg["literal"]` reads.
      violations = []
      walk(ast) do |node|
        next unless node.is_a?(Array) && node[0] == :binary && node[2] == :"||"
        left = extract_config_key(node[1])
        right = extract_config_key(node[3])
        next unless left && right

        violations << "config[#{left.inspect}] || config[#{right.inspect}]"
      end
      return [] if violations.empty?

      [{
        rule: :legacy_alias,
        message: "Legacy-alias fallback pattern detected: #{violations.uniq.join('; ')}. Pick the canonical key, drop the alias, rename the UI field.",
        file: relative_source(klass)
      }]
    end

    def check_enum_handling(source, klass)
      # Look for %w[...].include?(...) patterns inside methods whose name starts
      # with generate_ or build_. Allow inside validate_config.
      offenders = []
      current_method = nil
      source.each_line.with_index(1) do |line, lineno|
        if line =~ /^\s*def\s+(\w+)/
          current_method = Regexp.last_match(1)
        elsif line =~ /^\s*end\s*$/
          # naive: doesn't track nesting, but good enough given generator shapes
          current_method = nil if current_method && !line.include?("end of")
        end

        next unless current_method

        next if current_method == "validate_config"
        next unless current_method.start_with?("generate_", "build_")

        if line =~ /%w\[[^\]]+\]\.include\?/
          offenders << "#{relative_source(klass)}:#{lineno} in ##{current_method}"
        end
      end
      return [] if offenders.empty?

      [{
        rule: :enum_handling,
        message: "Hand-rolled enum check (%w[...].include?) inside generate_* / build_* method — use fetch_enum. Offenders: #{offenders.join('; ')}",
        file: relative_source(klass)
      }]
    end

    def check_dependencies(body, klass)
      return [] if body.nil?

      declared = Array(safely_call(klass, :dependencies) || []).map(&:to_sym).to_set
      ctx_reads = body.scan(/ctx\[:([a-zA-Z_][a-zA-Z_0-9]*)\]/).flatten.uniq
      missing = []
      ctx_reads.each do |key|
        next if AMBIENT_CTX_KEYS.include?(key)
        producer = CTX_PRODUCERS[key]
        next unless producer
        next if declared.include?(producer)

        missing << "reads ctx[:#{key}] (produced by :#{producer}) but :#{producer} not in dependencies"
      end
      return [] if missing.empty?

      [{
        rule: :dependencies,
        message: missing.join('; '),
        file: relative_source(klass)
      }]
    end

    # --- helpers ---------------------------------------------------------

    def generator_files
      Dir[GENERATORS_ROOT.join("**/*.rb")].sort
    end

    def load_generator(file)
      require file
      name = file_to_class_name(file)
      name.constantize
    rescue NameError, LoadError => e
      warn "Failed to load generator #{file}: #{e.message}"
      nil
    end

    def file_to_class_name(file)
      rel = Pathname.new(file).relative_path_from(Rails.root.join("app/services"))
      rel.to_s.delete_suffix(".rb").camelize
    end

    def source_path_for(klass)
      method_source_location = klass.instance_method(:generate_body).source_location
      # For fixtures loaded from spec/fixtures/, source_location returns the
      # fixture path, which is what we want. For real generators, same thing.
      method_source_location && method_source_location[0]
    end

    def generate_body_safely(klass)
      element = build_sample_element(klass)
      klass.new(element, {}).generate_body
    rescue StandardError => e
      warn "Could not call generate_body on #{klass.name}: #{e.class}: #{e.message}"
      nil
    end

    def build_sample_element(klass)
      sample = klass.respond_to?(:sample_input) ? klass.sample_input : {}
      element_kind = klass.respond_to?(:generator_kind) ? klass.generator_kind : :step_action
      if element_kind == :element_type
        { "id" => "audit", "type" => klass.generator_name, "properties" => sample }
      else
        { "id" => "audit", "type" => "process", "config" => sample }
      end
    end

    def safely_call(klass, method)
      element = build_sample_element(klass)
      klass.new(element, {}).send(method)
    rescue StandardError
      nil
    end

    def extract_config_key(node)
      # Ripper AST for `config["X"]` or `cfg["X"]`:
      # [:aref, [:vcall, [:@ident, "config", [L, C]]], [:args_add_block, [[:string_literal, [:string_content, [:@tstring_content, "X", ...]]]], false]]
      return nil unless node.is_a?(Array)
      return nil unless node[0] == :aref

      receiver = node[1]
      return nil unless receiver.is_a?(Array)
      return nil unless receiver[0] == :vcall || receiver[0] == :var_ref

      ident = dig_array(receiver, [1, 1])
      return nil unless %w[config cfg].include?(ident)

      args = node[2]
      return nil unless args.is_a?(Array) && args[0] == :args_add_block

      string_literal = args[1].is_a?(Array) ? args[1][0] : nil
      return nil unless string_literal.is_a?(Array) && string_literal[0] == :string_literal

      string_content = string_literal[1]
      return nil unless string_content.is_a?(Array) && string_content[0] == :string_content

      tstring = string_content[1]
      return nil unless tstring.is_a?(Array) && tstring[0] == :@tstring_content

      tstring[1]
    end

    def walk(node, &block)
      return unless node.is_a?(Array)
      yield node
      node.each { |child| walk(child, &block) if child.is_a?(Array) }
    end

    def dig_array(node, path)
      path.inject(node) { |acc, idx| acc.is_a?(Array) ? acc[idx] : nil }
    end

    def relative_path(file)
      Pathname.new(file).relative_path_from(Rails.root).to_s
    end

    def relative_source(klass)
      path = source_path_for(klass)
      path ? relative_path(path) : klass.name
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  report = GeneratorAudit.run_audit
  GeneratorAudit.write_baseline(report)
  actionable = report.sum { |_, entry| entry[:gaps].size }
  puts "Wrote audit report with #{report.size} generators and #{actionable} total gaps to #{GeneratorAudit::BASELINE_PATH}"
  exit(actionable.zero? ? 0 : 1)
end
```

- [ ] **Step 2: Run the spec to verify it now passes**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rspec spec/scripts/audit_generators_spec.rb 2>&1 | tail -30
```

Expected: all examples in the spec file pass. If any fail, read the failure, fix the audit script (not the spec), re-run until green.

Common failure modes and fixes:
- `ctx_access` rule triggering on the clean generator because the fixture body happens to include `ctx.dig` — the regex `\bctx\.(?!dig\b|\[)[a-zA-Z_]` should handle that. If it fires, the regex needs adjustment.
- `legacy_alias` rule not detecting the fixture — step into `extract_config_key` with a Ripper `.sexp` dump to verify the AST shape matches.
- `dependencies` rule flagging `ctx[:customer_id]` — it's in `AMBIENT_CTX_KEYS`, so it should pass. If it fires, check the set.

- [ ] **Step 3: Run the full generator-spec suite to confirm no regression**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rspec spec/services/code_generators/ 2>&1 | tail -3
```

Expected: same count as preflight, 0 failures. The audit script doesn't modify any runtime code, so the generator specs must be unchanged.

- [ ] **Step 4: Stage (do not commit)**

Run:
```bash
cd /opt/milestone/anysys
git add scripts/audit_generators.rb
git status --short
```

---

## Task 5: Create the rake task

**Files:**
- Create: `lib/tasks/audit_generators.rake`

- [ ] **Step 1: Write the rake task**

Write `/opt/milestone/anysys/lib/tasks/audit_generators.rake`:

```ruby
# lib/tasks/audit_generators.rake
# Wraps scripts/audit_generators.rb so it can be invoked via `rake` in CI.

namespace :audit do
  desc "Audit every code generator against the canonical Railway checklist; exit non-zero on gaps (CI-ready)"
  task generators: :environment do
    load Rails.root.join("scripts/audit_generators.rb").to_s
    report = GeneratorAudit.run_audit
    GeneratorAudit.write_baseline(report)
    actionable = report.sum { |_, entry| entry[:gaps].size }
    puts "Audit: #{report.size} generators, #{actionable} total gaps. Baseline: #{GeneratorAudit::BASELINE_PATH}"

    if actionable.positive?
      report.each do |name, entry|
        next if entry[:gaps].empty?
        puts "  #{name} (#{entry[:file]}):"
        entry[:gaps].each { |g| puts "    - [#{g[:rule]}] #{g[:message]}" }
      end
      exit 1
    end
  end

  namespace :generators do
    desc "Regenerate audit baseline YAML without failing on gaps (use when intentionally accepting the current state)"
    task baseline: :environment do
      load Rails.root.join("scripts/audit_generators.rb").to_s
      report = GeneratorAudit.run_audit
      GeneratorAudit.write_baseline(report)
      actionable = report.sum { |_, entry| entry[:gaps].size }
      puts "Baseline regenerated: #{report.size} generators, #{actionable} total gaps captured in #{GeneratorAudit::BASELINE_PATH}"
    end
  end
end
```

- [ ] **Step 2: Verify the rake tasks are discoverable**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rake -T audit 2>&1
```

Expected output (order may differ):
```
rake audit:generators            # Audit every code generator against the canonical Railway checklist; exit non-zero on gaps (CI-ready)
rake audit:generators:baseline   # Regenerate audit baseline YAML without failing on gaps ...
```

- [ ] **Step 3: Stage (do not commit)**

Run:
```bash
cd /opt/milestone/anysys
git add lib/tasks/audit_generators.rake
git status --short
```

---

## Task 6: Produce the baseline YAML

**Files:**
- Create: `docs/superpowers/specs/2026-04-27-generator-audit-data.yml`

- [ ] **Step 1: Run the baseline task**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rake audit:generators:baseline 2>&1 | tail -20
```

Expected:
- Task runs to completion without raising.
- Output includes `Baseline regenerated: N generators, M total gaps captured in ...2026-04-27-generator-audit-data.yml`.
- `N` is approximately 130 (number of generator files).
- `M` is expected to be in the range ~30–80 based on the drift count in the spec. An exact number cannot be predicted; write it down — it becomes the reduction target for subsequent phases.

- [ ] **Step 2: Inspect the baseline YAML**

Run:
```bash
cd /opt/milestone/anysys
head -40 docs/superpowers/specs/2026-04-27-generator-audit-data.yml
```

Confirm the file starts with a YAML hash keyed by Ruby class names (e.g. `CodeGenerators::ElementTypes::Process::ModelOperations::SaveModelGenerator:`), each entry has a `file:` and `gaps:` list, and gaps include `rule:`, `message:`, `file:` keys.

- [ ] **Step 3: Confirm expected known violations appear**

Run:
```bash
cd /opt/milestone/anysys
grep -A 1 "SaveModelGenerator" docs/superpowers/specs/2026-04-27-generator-audit-data.yml | head -10
grep -c "legacy_alias" docs/superpowers/specs/2026-04-27-generator-audit-data.yml
grep -c "inline_orchestration" docs/superpowers/specs/2026-04-27-generator-audit-data.yml
```

Expected:
- `SaveModelGenerator` section contains at least one gap (legacy_alias for `strategy || saveStrategy`; inline_orchestration for `ActivitySteps::SaveAll.call`).
- `legacy_alias` count >= 15 (spec enumerates at least 17 instances under rule 5).
- `inline_orchestration` count >= 2 (save_model + validate_contract).

If any of these assertions fail, the audit script missed violations the spec explicitly calls out — debug the relevant rule implementation before continuing.

- [ ] **Step 4: Stage (do not commit)**

Run:
```bash
cd /opt/milestone/anysys
git add docs/superpowers/specs/2026-04-27-generator-audit-data.yml
git status --short
```

---

## Task 7: Confirm `rake audit:generators` correctly fails on gaps

- [ ] **Step 1: Run the audit task (not baseline) and confirm non-zero exit**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rake audit:generators 2>&1 | tail -30
echo "Exit status: $?"
```

Expected:
- Output lists each generator with one or more gaps, formatted as `  <ClassName> (<file>):` followed by `    - [<rule>] <message>` lines.
- Final line: `Exit status: 1`.

This is the state the next phase (Phase 2) will start from. The task exits non-zero precisely because the codebase has pre-refactor drift — that's the point of the baseline.

- [ ] **Step 2: Do NOT alter the exit behavior**

Confirm by re-reading `lib/tasks/audit_generators.rake` that `audit:generators` still has `exit 1` on positive gaps. If a later instinct suggests "make this task pass until we've refactored," resist it — the whole purpose of the CI-ready task is to gate merges on gap reduction.

---

## Task 8: Final verification and handoff

- [ ] **Step 1: Full generator spec suite must still pass**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rspec spec/services/code_generators/ spec/scripts/ 2>&1 | tail -5
```

Expected: `0 failures`. The audit spec file adds ~20–25 examples; total should be previous count + ~20 examples, still `0 failures`.

- [ ] **Step 2: UI audit script still works (untouched by this phase)**

Run:
```bash
cd /opt/milestone/anysys
bundle exec ruby scripts/audit_generator_ui.rb 2>&1 | tail -5
```

Expected: runs to completion (the actionable-gap count is whatever it was before this phase; we haven't changed UI or generators).

- [ ] **Step 3: Review staged files**

Run:
```bash
cd /opt/milestone/anysys
git status --short
git diff --cached --stat
```

Expected staged (new) files:
```
docs/code-generators/AUTHORING_CHECKLIST.md
docs/superpowers/specs/2026-04-27-generator-audit-data.yml
lib/tasks/audit_generators.rake
scripts/audit_generators.rb
spec/fixtures/audit_generators/clean_generator_fixture.rb
spec/fixtures/audit_generators/dotted_ctx_generator_fixture.rb
spec/fixtures/audit_generators/hand_rolled_enum_generator_fixture.rb
spec/fixtures/audit_generators/inline_orchestration_generator_fixture.rb
spec/fixtures/audit_generators/legacy_alias_generator_fixture.rb
spec/fixtures/audit_generators/missing_dependency_generator_fixture.rb
spec/fixtures/audit_generators/thin_wrapper_generator_fixture.rb
spec/scripts/audit_generators_spec.rb
```

(Plus, from earlier work, the spec file `docs/superpowers/specs/2026-04-27-code-generator-canonical-alignment-design.md` and this plan file.)

- [ ] **Step 4: Handoff — do NOT commit**

Per project convention (AGENTS.md + feedback memory `feedback_no_auto_commit`), do not run `git commit`. Report to the user:

- Phase 1 complete.
- Exact baseline gap count (from Task 6 Step 1 output).
- Exact failing-generator names from `rake audit:generators` output.
- Suggested commit message for the user's manual commit:

  ```
  add generator audit script and canonical alignment checklist

  - scripts/audit_generators.rb: machine-checks rules 2, 4, 5, 7, 8 from
    the canonical alignment spec against every generator under
    app/services/code_generators/element_types/
  - lib/tasks/audit_generators.rake: CI-ready rake wrapper
  - docs/code-generators/AUTHORING_CHECKLIST.md: prose checklist for the
    judgment rules (3, 6, 9) that the script cannot check
  - docs/superpowers/specs/2026-04-27-generator-audit-data.yml: baseline
    violation report (N generators, M gaps) used as the reduction target
    for Phases 2–9
  - spec/scripts/audit_generators_spec.rb + spec/fixtures/audit_generators/:
    fixture-based tests for the audit script's rule detection
  ```

- Phase 2 (canonical 4 rewrite) can begin; its plan references this baseline.

---

## Self-Review Checklist

- Spec coverage: section 5 of the design spec (audit script rules) maps to Tasks 3–4; section 4.3 rules 10/11 for UI audit are explicitly deferred to the next phase per the scope note; checklist doc covers section 4.1 rules 3, 6, 9. **Gap:** spec rules 12 (legacy enum values in UI) and 13 (visibleWhen references) were listed as machine-checkable in the spec but are not implemented by the Phase 1 script — they involve cross-checking the UI schema, which the existing `audit_generator_ui.rb` covers in a different way. **Resolution:** rules 12 and 13 are covered by extending `audit_generator_ui.rb` in Phase 2 (when we're actually changing UI fields). Phase 1's job is the generator-side audit; the UI-side extension is in-scope for whichever phase first needs it. This plan is explicit about that split — see "per-rule responsibility map" in File Structure.
- Placeholder scan: no TBD / TODO / "add appropriate X" strings. Every code block is complete.
- Type consistency: `GeneratorAudit.check_generator(klass)` returns `Array<Hash>` with keys `:rule, :message, :file` — consistent across Task 3 (spec assertions), Task 4 (implementation), and Task 5 (rake printout).
- Assumption verified in preflight: rspec baseline is green.

No fixes needed.
