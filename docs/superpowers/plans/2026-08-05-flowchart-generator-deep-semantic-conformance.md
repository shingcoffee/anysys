# Flowchart Generator Deep Semantic Conformance Pass — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate every gap between the flowchart property editor's configuration surface and the Ruby code generators that consume it, proven by a harness that compiles and executes emitted source rather than by structural inspection.

**Architecture:** A three-phase pass. Phase 0 builds a semantic conformance harness that mechanically proves each property-editor field, enum option, and visibility rule genuinely influences emitted code, and produces a per-category defect inventory. Phase 1 runs seventeen parallel repair tracks, one per action category plus one for element types, each owning its generators and its property-editor config file. Phase 2 integrates shared-file changes through a single integrator and runs full verification.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, RSpec, Trailblazer Activity, Reform, Liquid, Faraday, Stimulus, Vitest, Node 18+ ESM.

**Design:** `docs/superpowers/specs/2026-08-05-flowchart-generator-deep-semantic-conformance-design.md`

## Global Constraints

- **Model:** Claude Opus 5 for this session and every subagent. Never switch models.
- **Git:** work directly on `master`. Never run `git commit`. `git add` is permitted. The human reviewer commits.
- **Disposition default:** enrich the generator so a config option genuinely works. Remove an option only when the Activity architecture cannot support it, and document why in the code.
- **Multi-tenancy:** every emitted cache key, lock key, query, and filesystem path must be scoped by customer.
- **I18n:** no hard-coded user-facing strings anywhere. Ruby uses `t(...)` / `I18n.t(...)`; JavaScript uses Stimulus Values with an English `default:` populated from a server-rendered `data-*` attribute. The English value must be byte-identical to the string it replaces. Every key needs both `en` and `zh-CN`.
- **JavaScript coverage:** 100% lines **and** branches for every touched file under `app/javascript/**`, measured by `npx vitest run --coverage`.
- **Gems over hand-rolled code:** replace hand-rolled protocol, crypto, parsing, or retry logic with a maintained gem behind a thin `FlowchartRuntime::*` facade exposing a single public interface.
- **Test scoping:** tracks run only their own targeted specs. The full suite runs once, in Task 23.
- **Never edit generated files by hand:** `spec/support/config_schemas.rb` is produced by `rake config_schemas:mirror`.

---

## Background: How This Code Fits Together

An engineer picking up a task needs this orientation.

**The user-facing surface.** At `/81721200/admin/maintenance/flowcharts/1/edit` a user drags elements onto a canvas. Selecting an element opens the property editor. A `process` element holds an ordered list of *step actions*; each step action has its own configuration form.

**Where the form comes from.** Each action's form fields are declared in `app/javascript/flowchart/constants/action_configs/<category>_actions.js` as a `configSchema` array. A field looks like:

```javascript
{
  key: "cacheKey",
  type: "text",
  label: "Cache Key",
  required: true,
  placeholder: "e.g., user_42"
}
```

Field `type` is one of `text`, `textarea`, `number`, `select`, `condition`, `key_value_list`, `steps`, `branches`. A `select` carries `options: [{ value, label }, ...]`. A field may carry `visibleWhen: { field: "authType", value: "bearer" }` or `visibleWhen: { field: "httpMethod", values: ["POST", "PUT", "PATCH"] }`, which hides it unless the referenced field matches.

**Where the code generator lives.** `app/services/code_generators/element_types/process/<category>/<action>_generator.rb`. It subclasses `CodeGenerators::BaseGenerator`, declares a `config_schema do ... end` block for server-side validation, implements `generate_body` returning a Ruby source string, and implements `self.sample_input` returning a valid config hash.

**The Ruby mirror of the JS forms.** `rake config_schemas:mirror` runs `lib/tasks/extract_config_schemas.mjs`, which imports the JS config modules under Node and dumps them to `spec/support/config_schemas.rb` as `CodeGenerators::CONFIG_SCHEMAS` — a hash keyed by action name, each value an array of field hashes with symbol keys (`:key`, `:type`, `:label`, `:required`, `:default`, `:options`, `:placeholder`, `:visibleWhen`). This is how Ruby tests read the property editor's schema. `visibleWhen` **is** preserved in the mirror; 51 actions use it.

**How to compile and run a generator in a test.** `CodeGenerators::TestRunner`:

```ruby
CodeGenerators::TestRunner.run(generator_class, config: {...})
# => { body:, code:, inputs:, outputs:, validation_errors: }

CodeGenerators::TestRunner.execute(generator_class, config: {...}, ctx: {})
# => the run() keys plus { outcome:, ctx: }
```

`run` emits source without executing it. `execute` compiles the emitted step method into an anonymous class and invokes it against `ctx`, returning the step's return value as `:outcome` and the mutated `ctx`. Stubs belong in the caller.

**The registry.** `CodeGenerators::GeneratorRegistry.all` returns all 110 registered generator classes. `find_step_action("cache_write")` returns one by action name. Supported element types are exactly `start`, `end`, `decision`, `loop`, `subflow`, `timer`.

**Why the existing audits are not enough.** `scripts/audit_generator_ui.rb`, `scripts/audit_step_action_config.rb`, and `rake audit:generators` all currently exit with zero defects. They compare *declared* fields against *referenced* fields using Ripper source analysis. They cannot tell whether a referenced field actually changes the emitted string. `cache_write_generator.rb` passes all three while emitting cache keys with no tenant scoping.

---

## File Structure

**Created in Phase 0:**

| File | Responsibility |
|---|---|
| `spec/support/generator_conformance.rb` | Harness library: probe-value generation, emission diffing, allow-list |
| `spec/support/generator_conformance/inert_field_allowlist.rb` | Declared exceptions, each with a written justification |
| `spec/services/code_generators/generator_conformance_spec.rb` | Registry-wide field-delta, enum coverage, visibility parity specs |
| `spec/services/code_generators/tenant_scoping_spec.rb` | Asserts emitted keys, queries, and paths are customer-scoped |
| `lib/tasks/generator_conformance.rake` | `rake conformance:inventory` — writes the per-category defect inventory |
| `.superpowers/sdd/conformance-inventory.yml` | Machine-readable defect inventory, the input to every Phase 1 track |

**Created in Phase 1 (integrator-applied):**

| File | Responsibility |
|---|---|
| `app/services/flowchart_runtime/cache_key.rb` | Tenant-scoped cache-key construction, mirroring `Lock.cache_key` |

**Modified in Phase 1 (per track, exclusively owned):**

- `app/services/code_generators/element_types/process/<category>/**`
- `spec/services/code_generators/element_types/process/<category>/**`
- `app/javascript/flowchart/constants/action_configs/<category>_actions.js`
- `spec/javascript/flowchart/constants/action_configs/<category>_actions.test.js`

**Integrator-owned. No track may edit these:**

- `app/services/code_generators/base_generator.rb`
- `app/services/code_generators/shared/**`
- existing `app/services/flowchart_runtime/**`
- `config/locales/flowchart_actions.en.yml`, `config/locales/flowchart_actions.zh-CN.yml`
- `spec/support/config_schemas.rb` (generated)
- audit baseline YAML under `docs/superpowers/specs/`

**Request protocol.** A track needing a shared-file change appends to `.superpowers/sdd/track-<category>-requests.md` using this exact format:

```markdown
## Request: <one-line summary>
**Type:** locale | facade | shared-helper
**File:** config/locales/flowchart_actions.en.yml
**Change:**
```yaml
flowchart_actions:
  cache_write:
    errors:
      invalid_ttl: "TTL must be a positive number of seconds"
```
**zh-CN:** "TTL 必须是正整数秒"
**Why:** cache_write rejects non-positive TTL and needs a localized message.
```

The track writes the `t("...")` call in place immediately, so its code is correct once the integrator adds the key. Tracks may freely **create new** `FlowchartRuntime::*` files, since additive files do not conflict.

---

## Task 1: Conformance harness core — probe values and emission diffing

**Files:**
- Create: `spec/support/generator_conformance/inert_field_allowlist.rb`
- Create: `spec/support/generator_conformance.rb`
- Test: `spec/services/code_generators/generator_conformance_spec.rb`

**Interfaces:**
- Consumes: `CodeGenerators::CONFIG_SCHEMAS` (from `spec/support/config_schemas.rb`), `CodeGenerators::GeneratorRegistry`, `CodeGenerators::TestRunner`.
- Produces:
  - `GeneratorConformance.ui_fields(key) -> Array<Hash>`
  - `GeneratorConformance.emit(generator_class, config) -> String` (emitted body, or `nil` when the generator emits no body)
  - `GeneratorConformance.probe_value(field, baseline_value) -> Object | nil` (`nil` means "not probeable")
  - `GeneratorConformance.field_delta(generator_class, action_key, field) -> Symbol` returning `:changed`, `:inert`, `:rejected`, or `:skipped`
  - `GeneratorConformance::INERT_FIELD_ALLOWLIST -> Hash{String => Hash{String => String}}`

- [ ] **Step 1: Write the allow-list file**

This starts empty. Entries are added only in Task 4, each with a justification.

```ruby
# spec/support/generator_conformance/inert_field_allowlist.rb
# frozen_string_literal: true

module GeneratorConformance
  # Fields whose variation legitimately produces no emitted-source delta.
  #
  # Every entry MUST carry a written justification explaining why the field
  # cannot change emitted code. An entry without a real reason is a laundered
  # defect, not an exception.
  #
  # Shape: { "action_key" => { "fieldKey" => "justification" } }
  INERT_FIELD_ALLOWLIST = {}.freeze
end
```

- [ ] **Step 2: Write the failing test**

```ruby
# spec/services/code_generators/generator_conformance_spec.rb
# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("spec/support/generator_conformance")

RSpec.describe GeneratorConformance do
  describe ".probe_value" do
    it "returns a different select option than the baseline" do
      field = {
        key: "action",
        type: :select,
        options: [{ "value" => "write" }, { "value" => "delete" }]
      }
      expect(described_class.probe_value(field, "write")).to eq("delete")
    end

    it "returns nil for a select with only one option" do
      field = { key: "mode", type: :select, options: [{ "value" => "only" }] }
      expect(described_class.probe_value(field, "only")).to be_nil
    end

    it "returns a numerically different value for a number field" do
      field = { key: "ttl", type: :number }
      expect(described_class.probe_value(field, 3600)).to eq(3607)
    end

    it "returns a distinct string for a text field" do
      field = { key: "cacheKey", type: :text }
      expect(described_class.probe_value(field, "user_data"))
        .to eq("conformance_probe_cacheKey")
    end

    it "returns a populated pair list for a key_value_list field" do
      field = { key: "tags", type: :key_value_list }
      expect(described_class.probe_value(field, nil))
        .to eq([{ "key" => "conformance_probe_tag", "value" => "probe" }])
    end

    it "returns nil for structural field types it cannot probe" do
      expect(described_class.probe_value({ key: "steps", type: :steps }, nil)).to be_nil
      expect(described_class.probe_value({ key: "branches", type: :branches }, nil)).to be_nil
    end
  end

  describe ".field_delta" do
    let(:generator) { CodeGenerators::ElementTypes::Process::Caching::CacheWriteGenerator }

    it "reports :changed for a field that influences emitted source" do
      field = described_class.ui_fields("cache_write").find { |f| f[:key] == "sourceVariable" }
      expect(described_class.field_delta(generator, "cache_write", field)).to eq(:changed)
    end

    it "reports :skipped for a field it cannot probe" do
      expect(described_class.field_delta(generator, "cache_write", { key: "x", type: :steps }))
        .to eq(:skipped)
    end
  end
end
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/generator_conformance_spec.rb`
Expected: FAIL with `LoadError` — cannot load `spec/support/generator_conformance`.

- [ ] **Step 4: Implement the harness**

```ruby
# spec/support/generator_conformance.rb
# frozen_string_literal: true

require Rails.root.join("spec/support/config_schemas")
require Rails.root.join("spec/support/generator_conformance/inert_field_allowlist")

# Semantic conformance harness for flowchart code generators.
#
# The repository's structural audits prove that a property-editor field is
# *referenced* by a generator. They cannot prove the field *changes the emitted
# source*. This harness closes that gap by emitting source twice — once at a
# baseline config, once with a single field perturbed — and comparing.
module GeneratorConformance
  # Field types the harness cannot meaningfully perturb. `steps` and `branches`
  # are nested structural editors owned by the element-type track; `condition`
  # carries a builder-specific shape probed by its own track.
  UNPROBEABLE_TYPES = %i[steps branches condition].freeze

  module_function

  # Property-editor fields for an action or element type, from the JS mirror.
  def ui_fields(key)
    CodeGenerators::CONFIG_SCHEMAS.fetch(key.to_s, [])
  end

  # Emitted body for a config, or nil when the generator emits no body.
  # Emission failures are returned as a marker string so a crash surfaces as a
  # delta rather than aborting the whole sweep.
  def emit(generator_class, config)
    CodeGenerators::TestRunner.run(generator_class, config: config)[:body]
  rescue StandardError => e
    "CONFORMANCE_EMISSION_ERROR: #{e.class}: #{e.message}"
  end

  def validation_errors(generator_class, config)
    CodeGenerators::TestRunner.run(generator_class, config: config)[:validation_errors]
  rescue StandardError
    []
  end

  # A value guaranteed to differ from +baseline+, or nil when the field type
  # cannot be probed.
  def probe_value(field, baseline)
    type = field[:type]&.to_sym
    return nil if UNPROBEABLE_TYPES.include?(type)

    case type
    when :select
      values = Array(field[:options]).map { |o| o["value"] || o[:value] }.compact.map(&:to_s)
      values.find { |v| v != baseline.to_s }
    when :number
      baseline.to_i + 7
    when :key_value_list
      [{ "key" => "conformance_probe_tag", "value" => "probe" }]
    when :text, :textarea
      "conformance_probe_#{field[:key]}"
    end
  end

  # Baseline config for a generator: its own declared sample input.
  def baseline_config(generator_class)
    generator_class.sample_input || {}
  end

  # Classify one field:
  #   :changed  — perturbing the field changed emitted source (correct)
  #   :inert    — emitted source was byte-identical (defect unless allow-listed)
  #   :rejected — the probe was refused by server-side validation (acceptable;
  #               the generator validates rather than silently ignoring)
  #   :skipped  — the field type is not probeable
  def field_delta(generator_class, action_key, field)
    key = field[:key].to_s
    baseline = baseline_config(generator_class)
    probe = probe_value(field, baseline[key])
    return :skipped if probe.nil?

    variant = baseline.merge(key => probe)
    return :rejected if validation_errors(generator_class, variant).any?

    emit(generator_class, baseline) == emit(generator_class, variant) ? :inert : :changed
  end

  def allow_listed?(action_key, field_key)
    INERT_FIELD_ALLOWLIST.fetch(action_key.to_s, {}).key?(field_key.to_s)
  end
end
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/generator_conformance_spec.rb`
Expected: PASS, 8 examples, 0 failures.

If `field_delta` for `sourceVariable` returns `:inert`, that is a genuine `cache_write` defect rather than a harness bug — record it and change the example to a field that does vary, keeping the discovered defect for Task 11.

- [ ] **Step 6: Stage the work**

```bash
git add spec/support/generator_conformance.rb \
        spec/support/generator_conformance/inert_field_allowlist.rb \
        spec/services/code_generators/generator_conformance_spec.rb
```

Do not commit.

---

## Task 2: Registry-wide field-delta, enum coverage, and visibility parity

**Files:**
- Modify: `spec/services/code_generators/generator_conformance_spec.rb`
- Modify: `spec/support/generator_conformance.rb`

**Interfaces:**
- Consumes: everything Task 1 produced.
- Produces:
  - `GeneratorConformance.enum_coverage(generator_class, action_key, field) -> Hash{String => String}` mapping each option value to a digest of its emitted body
  - `GeneratorConformance.visibility_leak?(generator_class, action_key, field) -> Boolean`

- [ ] **Step 1: Write the failing tests**

Append to `spec/services/code_generators/generator_conformance_spec.rb`:

```ruby
  describe ".enum_coverage" do
    let(:generator) { CodeGenerators::ElementTypes::Process::Caching::CacheWriteGenerator }

    it "emits distinct source for each option of a meaningful select" do
      field = described_class.ui_fields("cache_write").find { |f| f[:key] == "action" }
      digests = described_class.enum_coverage(generator, "cache_write", field)

      expect(digests.keys).to contain_exactly("write", "write_if_absent", "delete")
      expect(digests.values.uniq.size).to eq(3)
    end
  end

  describe ".visibility_leak?" do
    it "is false when a hidden field does not influence emitted source" do
      generator = CodeGenerators::ElementTypes::Process::Communication::ApiCallGenerator
      field = described_class.ui_fields("API_call").find { |f| f[:visibleWhen] }

      expect(described_class.visibility_leak?(generator, "API_call", field)).to be(false)
    end
  end

  # --- Registry-wide sweeps -------------------------------------------------

  CodeGenerators::GeneratorRegistry.step_action_generators.each do |action_key, generator_class|
    describe "#{action_key} (#{generator_class.name})" do
      GeneratorConformance.ui_fields(action_key).each do |field|
        field_key = field[:key].to_s

        it "honors the #{field_key} property-editor field" do
          verdict = GeneratorConformance.field_delta(generator_class, action_key, field)

          if GeneratorConformance.allow_listed?(action_key, field_key)
            expect(verdict).to eq(:inert),
              "#{action_key}.#{field_key} is allow-listed as inert but now emits a delta; remove the allow-list entry"
          else
            expect(verdict).not_to eq(:inert),
              "#{action_key}.#{field_key} is offered in the property editor but changing it does not change generated code"
          end
        end

        next unless field[:type]&.to_sym == :select

        it "emits distinct, compilable source for every #{field_key} option" do
          digests = GeneratorConformance.enum_coverage(generator_class, action_key, field)
          next if digests.size < 2

          expect(digests.values.uniq.size).to be > 1,
            "#{action_key}.#{field_key} offers #{digests.size} options that all emit identical source"
        end
      end

      GeneratorConformance.ui_fields(action_key).select { |f| f[:visibleWhen] }.each do |field|
        it "ignores #{field[:key]} when its visibleWhen condition is unmet" do
          expect(GeneratorConformance.visibility_leak?(generator_class, action_key, field)).to be(false),
            "#{action_key}.#{field[:key]} is hidden in the editor but still changes generated code"
        end
      end
    end
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/generator_conformance_spec.rb`
Expected: FAIL with `NoMethodError: undefined method 'enum_coverage'`.

- [ ] **Step 3: Implement the two new harness methods**

Append inside `module GeneratorConformance`, after `field_delta`:

```ruby
  # Digest of emitted source per enum option. Raises if any option emits
  # source that does not compile.
  def enum_coverage(generator_class, action_key, field)
    key = field[:key].to_s
    baseline = baseline_config(generator_class)
    options = Array(field[:options]).map { |o| o["value"] || o[:value] }.compact.map(&:to_s)

    options.each_with_object({}) do |option, acc|
      config = baseline.merge(key => option)
      result = CodeGenerators::TestRunner.run(generator_class, config: config)
      code = result[:code]
      if code
        begin
          RubyVM::InstructionSequence.compile(code)
        rescue SyntaxError => e
          raise "#{action_key}.#{key}=#{option} emits source that does not compile: #{e.message}"
        end
      end
      acc[option] = Digest::SHA256.hexdigest(result[:body].to_s)
    end
  end

  # True when a field whose visibleWhen condition is UNMET still changes the
  # emitted source. The property editor hides such a field, so a user cannot
  # see or control the behavior it drives.
  def visibility_leak?(generator_class, action_key, field)
    condition = field[:visibleWhen]
    return false if condition.nil?

    anchor = (condition["field"] || condition[:field]).to_s
    shown = Array(condition["values"] || condition[:values] ||
                  condition["value"]  || condition[:value]).map(&:to_s)

    anchor_field = ui_fields(action_key).find { |f| f[:key].to_s == anchor }
    return false if anchor_field.nil?

    anchor_options = Array(anchor_field[:options])
                     .map { |o| (o["value"] || o[:value]).to_s }
    hidden_anchor = anchor_options.find { |v| !shown.include?(v) }
    return false if hidden_anchor.nil?

    key = field[:key].to_s
    probe = probe_value(field, nil)
    return false if probe.nil?

    hidden_baseline = baseline_config(generator_class).merge(anchor => hidden_anchor)
    hidden_baseline.delete(key)
    with_hidden_field = hidden_baseline.merge(key => probe)

    emit(generator_class, hidden_baseline) != emit(generator_class, with_hidden_field)
  end
```

Add `require "digest"` at the top of the file, below the existing requires.

- [ ] **Step 4: Run the unit examples to verify they pass**

Run: `bundle exec rspec spec/services/code_generators/generator_conformance_spec.rb -e "enum_coverage" -e "visibility_leak"`
Expected: PASS.

- [ ] **Step 5: Run the full sweep and capture the failures**

Run: `bundle exec rspec spec/services/code_generators/generator_conformance_spec.rb 2>&1 | tail -100`

Expected: **many failures.** This is the deliverable, not a problem. Do not fix generators here — Task 4 turns these failures into the inventory.

- [ ] **Step 6: Stage the work**

```bash
git add spec/support/generator_conformance.rb \
        spec/services/code_generators/generator_conformance_spec.rb
```

---

## Task 3: Tenant-scoping assertions and the execution matrix

**Files:**
- Create: `spec/services/code_generators/tenant_scoping_spec.rb`
- Modify: `spec/services/code_generators/generated_activity_execution_spec.rb`

**Interfaces:**
- Consumes: `GeneratorConformance.emit`, `CodeGenerators::GeneratorRegistry`, `CodeGenerators::TestRunner.execute`.
- Produces: a failing tenant-scoping spec that Task 12 (caching) and any other offending track must make pass.

- [ ] **Step 1: Write the failing tenant-scoping test**

```ruby
# spec/services/code_generators/tenant_scoping_spec.rb
# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("spec/support/generator_conformance")

# In a multi-tenant application every shared-namespace key must be scoped by
# customer. FlowchartRuntime::Lock already requires a tenant namespace; this
# spec holds every other emitted key, query, and path to the same standard.
RSpec.describe "generated activity tenant scoping" do
  # Emitted source touching a shared namespace must reference customer scoping.
  SHARED_NAMESPACE_PATTERNS = {
    "Rails.cache" => /Rails\.cache\.(read|write|delete|fetch|exist\?)/,
    "filesystem"  => /File\.(open|write|read|delete)|FileUtils\./
  }.freeze

  TENANT_MARKERS = /customer_id|tenant_namespace|FlowchartRuntime::CacheKey|FlowchartRuntime::SandboxPath|Current\.customer/

  CodeGenerators::GeneratorRegistry.step_action_generators.each do |action_key, generator_class|
    it "scopes any shared-namespace access by customer in #{action_key}" do
      body = GeneratorConformance.emit(generator_class, generator_class.sample_input).to_s
      next if body.empty?

      offending = SHARED_NAMESPACE_PATTERNS.select { |_name, pattern| body.match?(pattern) }.keys
      next if offending.empty?

      expect(body).to match(TENANT_MARKERS),
        "#{action_key} emits #{offending.join(', ')} access with no customer scoping:\n#{body}"
    end
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/tenant_scoping_spec.rb`
Expected: FAIL for at least `cache_write`, `cache_read`, `cache_fetch`, `cache_delete`, with the emitted body printed.

- [ ] **Step 3: Extend the execution matrix to one success and one failure path per category**

`spec/services/code_generators/generated_activity_execution_spec.rb` currently covers eight representative cases. Add a guard proving no category is unrepresented, so a category cannot silently lack an execution test:

```ruby
  describe "execution coverage" do
    COVERED_CATEGORIES = %w[
      background caching communication concurrency data_operations
      file_operations human_workflow model_operations realtime resilience
      response scheduling_time security service_invocation utility validation
    ].freeze

    it "exercises at least one generator from every action category" do
      exercised = EXECUTED_GENERATORS
        .map { |klass| klass.name.split("::")[-2].underscore }
        .uniq

      expect(COVERED_CATEGORIES - exercised).to be_empty,
        "no execution test for categories: #{(COVERED_CATEGORIES - exercised).join(', ')}"
    end
  end
```

Declare `EXECUTED_GENERATORS` at the top of the file as a mutable set and have each `describe` block register its generator:

```ruby
EXECUTED_GENERATORS = Set.new
```

with `EXECUTED_GENERATORS << generator` inside each existing `describe`'s `before` hook.

- [ ] **Step 4: Run it to verify it fails with the uncovered category list**

Run: `bundle exec rspec spec/services/code_generators/generated_activity_execution_spec.rb -e "execution coverage"`
Expected: FAIL listing the categories with no execution test. Each Phase 1 track adds its own.

- [ ] **Step 5: Stage the work**

```bash
git add spec/services/code_generators/tenant_scoping_spec.rb \
        spec/services/code_generators/generated_activity_execution_spec.rb
```

---

## Task 4: Produce the per-category defect inventory

**Files:**
- Create: `lib/tasks/generator_conformance.rake`
- Create: `.superpowers/sdd/conformance-inventory.yml`

**Interfaces:**
- Consumes: `GeneratorConformance`.
- Produces: `.superpowers/sdd/conformance-inventory.yml`, the work queue every Phase 1 track reads. Shape:

```yaml
caching:
  cache_write:
    inert_fields: [compress, version]
    identical_enum_options: []
    visibility_leaks: []
    tenant_scoping: fail
```

- [ ] **Step 1: Write the inventory rake task**

```ruby
# lib/tasks/generator_conformance.rake
# frozen_string_literal: true

namespace :conformance do
  desc "Write the per-category generator conformance defect inventory"
  task inventory: :environment do
    require Rails.root.join("spec/support/generator_conformance")
    require "yaml"

    output = Hash.new { |h, k| h[k] = {} }

    CodeGenerators::GeneratorRegistry.step_action_generators.each do |action_key, klass|
      category = klass.name.split("::")[-2].underscore
      fields = GeneratorConformance.ui_fields(action_key)

      inert = fields.select do |f|
        GeneratorConformance.field_delta(klass, action_key, f) == :inert &&
          !GeneratorConformance.allow_listed?(action_key, f[:key])
      end.map { |f| f[:key].to_s }

      identical_enums = fields.select { |f| f[:type]&.to_sym == :select }.select do |f|
        digests = GeneratorConformance.enum_coverage(klass, action_key, f)
        digests.size > 1 && digests.values.uniq.size == 1
      rescue StandardError
        true
      end.map { |f| f[:key].to_s }

      leaks = fields.select { |f| f[:visibleWhen] }.select do |f|
        GeneratorConformance.visibility_leak?(klass, action_key, f)
      end.map { |f| f[:key].to_s }

      next if inert.empty? && identical_enums.empty? && leaks.empty?

      output[category][action_key] = {
        "inert_fields" => inert,
        "identical_enum_options" => identical_enums,
        "visibility_leaks" => leaks
      }
    end

    path = Rails.root.join(".superpowers/sdd/conformance-inventory.yml")
    File.write(path, output.to_h.deep_stringify_keys.to_yaml)
    total = output.values.sum { |actions| actions.size }
    puts "Wrote inventory for #{total} actions with defects to #{path}"
  end
end
```

- [ ] **Step 2: Run the inventory**

Run: `bundle exec rake conformance:inventory`
Expected: writes the YAML and prints a non-zero action count.

- [ ] **Step 3: Review the inventory and seed the allow-list**

Read `.superpowers/sdd/conformance-inventory.yml`. For each `inert_fields` entry decide, **defaulting to "this is a real defect"**:

- The generator should honor the field → leave it in the inventory as work for the track.
- The field genuinely cannot change emitted source → add an allow-list entry with a written justification.

A justification must explain the mechanism, not restate the symptom. Acceptable: `"consumed by validate_config only; never reaches generate_body because the runtime facade re-derives it"`. Not acceptable: `"does not affect output"`.

- [ ] **Step 4: Stage the work**

```bash
git add lib/tasks/generator_conformance.rake \
        .superpowers/sdd/conformance-inventory.yml \
        spec/support/generator_conformance/inert_field_allowlist.rb
```

---

## Tasks 5–20: Category repair tracks

Tasks 5 through 20 are **structurally identical**, differing only in category. They run in parallel. The per-category table follows the shared procedure.

### Shared procedure for every category track

Substitute `<category>` and `<Category>` throughout.

**Files:**
- Modify: `app/services/code_generators/element_types/process/<category>/**`
- Modify: `app/javascript/flowchart/constants/action_configs/<category>_actions.js`
- Test: `spec/services/code_generators/element_types/process/<category>/**`
- Test: `spec/javascript/flowchart/constants/action_configs/<category>_actions.test.js`
- Create (as needed): `app/services/flowchart_runtime/<new_facade>.rb`
- Create (as needed): `.superpowers/sdd/track-<category>-requests.md`

**Interfaces:**
- Consumes: `.superpowers/sdd/conformance-inventory.yml` (the `<category>` key), `GeneratorConformance`, `CodeGenerators::TestRunner`, `FlowchartRuntime::*` facades.
- Produces: generators in `<category>` that pass the conformance, tenant-scoping, and execution specs; plus a request file for any shared-file change.

- [ ] **Step 1: Read the inventory for this category**

Run: `bundle exec ruby -ryaml -e 'puts YAML.load_file(".superpowers/sdd/conformance-inventory.yml").fetch("<category>", {}).to_yaml'`

This is the work queue. Every listed action has at least one proven defect.

- [ ] **Step 2: Run this category's conformance failures**

Run:
```bash
bundle exec rspec spec/services/code_generators/generator_conformance_spec.rb \
  -e "<action_key_1>" -e "<action_key_2>" 2>&1 | tail -60
```

Expected: FAIL, with each failure naming the action and field.

- [ ] **Step 3: For each action, read the config and the generator side by side**

```bash
bundle exec ruby -e 'require "./spec/support/config_schemas"; \
  pp CodeGenerators::CONFIG_SCHEMAS["<action_key>"]'
cat app/services/code_generators/element_types/process/<category>/<action>_generator.rb
```

Apply all nine checklist items:

1. **Bidirectional field parity.** Every property-editor field is read; every field read is declared.
2. **Conditional parity.** `visibleWhen` matches the generator's branching. A hidden field must not drive emission.
3. **Enum parity.** The editor's option list matches the generator's allow-list constant, with server-side rejection of out-of-range values via `config_schema`.
4. **Semantic honoring.** Every field changes emitted source, proven by the harness.
5. **Multi-tenancy.** Customer scoping on every cache key, lock key, query, and path.
6. **Injection safety.** No unsanitized interpolation into emitted Ruby. Route identifiers through `CodeGenerators::Shared::IdentifierSanitizer`; emit literals with `.inspect`, never bare interpolation.
7. **Gems over hand-rolled code.** Replace hand-rolled protocol, crypto, parsing, or retry logic with a maintained gem behind a thin `FlowchartRuntime::*` facade.
8. **I18n.** No hard-coded user-facing strings. Write the `t(...)` call and file a locale request.
9. **Tests.** A generator spec, an execution spec, and 100% Vitest lines and branches on touched JavaScript.

- [ ] **Step 4: Write a failing spec for each defect before fixing it**

Follow the repository's TDD convention. Example shape for an inert field:

```ruby
# spec/services/code_generators/element_types/process/<category>/<action>_generator_spec.rb
require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::<Category>::<Action>Generator do
  def body(config)
    CodeGenerators::TestRunner.run(described_class, config: config)[:body]
  end

  it "honors the <field> configuration option" do
    base = described_class.sample_input
    expect(body(base.merge("<field>" => "<value_a>")))
      .not_to eq(body(base.merge("<field>" => "<value_b>")))
  end
end
```

- [ ] **Step 5: Run the new spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/<category>`
Expected: FAIL.

- [ ] **Step 6: Fix the generator**

Default to enrichment: implement the behavior so the option genuinely works. Remove the option from both the generator and `<category>_actions.js` only when the Activity architecture cannot support it, and add a code comment explaining why.

- [ ] **Step 7: Run the category specs to verify they pass**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/<category>`
Expected: PASS.

- [ ] **Step 8: Add an execution test for this category**

Add a `describe` block to `spec/services/code_generators/generated_activity_execution_spec.rb` covering one success path and one operational-failure path, asserting fail-closed behavior on failure. Register the generator in `EXECUTED_GENERATORS`.

Because this file is shared across tracks, append only; never reformat or reorder existing blocks.

- [ ] **Step 9: If the JS config changed, update its Vitest spec and prove 100% coverage**

Run: `npx vitest run --coverage spec/javascript/flowchart/constants/action_configs/<category>_actions.test.js`
Expected: PASS with the touched file at 100% lines and branches.

- [ ] **Step 10: Re-run the conformance and tenant-scoping specs for this category**

```bash
bundle exec rspec spec/services/code_generators/generator_conformance_spec.rb -e "<action_key_1>"
bundle exec rspec spec/services/code_generators/tenant_scoping_spec.rb -e "<action_key_1>"
```
Expected: PASS.

- [ ] **Step 11: File any shared-file requests**

Write `.superpowers/sdd/track-<category>-requests.md` using the request format in the File Structure section. If no shared change is needed, state `No requests.` explicitly so the integrator knows the track finished.

- [ ] **Step 12: Stage the work**

```bash
git add app/services/code_generators/element_types/process/<category> \
        spec/services/code_generators/element_types/process/<category> \
        app/javascript/flowchart/constants/action_configs/<category>_actions.js \
        .superpowers/sdd/track-<category>-requests.md
```

### Category assignments

| Task | Category | Generators | Category module | Known starting defects |
|---|---|---|---|---|
| 5 | `data_operations` | 32 | `DataOperations` | Largest surface; residual merge/find dual aliases and persisted `partitionField`/`shapeHandling` configs |
| 6 | `model_operations` | 17 | `ModelOperations` | Residual entity scope allow-list; verify `QueryBuilder` select/distinct/includes/preload/lock/readonly all reachable from the editor |
| 7 | `security` | 9 | `Security` | Verify token/api_key/password paths reject invalid input server-side |
| 8 | `utility` | 8 | `Utility` | Barcode raster text options (`include_text`, `text_font`) must work or be removed |
| 9 | `file_operations` | 7 | `FileOperations` | Every format and upload/download destination must genuinely work; archive traversal protection intact |
| 10 | `communication` | 5 | `Communication` | Vendor non-2xx handling; no hand-rolled protocol emission |
| 11 | `caching` | 4 | `Caching` | **Confirmed:** unscoped `Rails.cache` keys and a hand-rolled tag index race in `cache_write_generator.rb`. Depends on Task 21 |
| 12 | `human_workflow` | 4 | `HumanWorkflow` | Must persist or signal real behavior; never a success-shaped placeholder |
| 13 | `resilience` | 4 | `Resilience` | Residual dual `onTimeout`/`timeoutBehavior`; every retry value bounded |
| 14 | `scheduling_time` | 3 | `SchedulingTime` | Bound every schedule value |
| 15 | `background` | 2 | `Background` | Jobs use Rails APIs with explicit failure semantics |
| 16 | `concurrency` | 2 | `Concurrency` | Bound every lock and concurrency value |
| 17 | `realtime` | 2 | `Realtime` | Broadcasts use Rails APIs with explicit failure semantics |
| 18 | `response` | 2 | `Response` | Declared outputs written exactly once |
| 19 | `validation` | 2 | `Validation` | Verify contract building rejects invalid rules |
| 20 | `service_invocation` | 1 | `ServiceInvocation` | Allow-listed resolver only; never unchecked constant lookup |

---

## Task 21: Tenant-scoped cache keys (integrator-owned, blocks Task 11)

**Files:**
- Create: `app/services/flowchart_runtime/cache_key.rb`
- Test: `spec/services/flowchart_runtime/cache_key_spec.rb`

**Interfaces:**
- Consumes: nothing.
- Produces: `FlowchartRuntime::CacheKey.scoped(tenant_namespace, key, namespace: nil, version: nil) -> String`, used by every caching generator in Task 11.

This mirrors the existing `FlowchartRuntime::Lock.cache_key`, which already namespaces by tenant. Caching is the outlier.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/flowchart_runtime/cache_key_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::CacheKey do
  describe ".scoped" do
    it "prefixes the key with the flowchart cache namespace and tenant" do
      expect(described_class.scoped("81721200", "user_data"))
        .to eq("flowchart:cache:81721200:user_data")
    end

    it "inserts an optional user namespace between tenant and key" do
      expect(described_class.scoped("81721200", "user_data", namespace: "reports"))
        .to eq("flowchart:cache:81721200:reports:user_data")
    end

    it "appends an optional version suffix" do
      expect(described_class.scoped("81721200", "user_data", version: "v2"))
        .to eq("flowchart:cache:81721200:user_data:v2")
    end

    it "rejects a blank tenant namespace so keys can never be shared" do
      expect { described_class.scoped("", "user_data") }
        .to raise_error(described_class::Error, /tenant/)
    end

    it "rejects a blank key" do
      expect { described_class.scoped("81721200", "  ") }
        .to raise_error(described_class::Error, /key/)
    end
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/services/flowchart_runtime/cache_key_spec.rb`
Expected: FAIL with `NameError: uninitialized constant FlowchartRuntime::CacheKey`.

- [ ] **Step 3: Implement the facade**

```ruby
# app/services/flowchart_runtime/cache_key.rb
# frozen_string_literal: true

module FlowchartRuntime
  # Builds tenant-scoped Rails.cache keys for flowchart caching steps.
  #
  # Mirrors FlowchartRuntime::Lock.cache_key, which already namespaces every
  # lock by tenant. Without this, two customers caching under the same logical
  # key share one cache entry.
  module CacheKey
    class Error < StandardError; end

    CACHE_PREFIX = "flowchart:cache:"

    module_function

    def scoped(tenant_namespace, key, namespace: nil, version: nil)
      tenant = tenant_namespace.to_s.strip
      raise Error, "tenant namespace is required" if tenant.empty?

      base = key.to_s.strip
      raise Error, "cache key is required" if base.empty?

      parts = [tenant]
      user_namespace = namespace.to_s.strip
      parts << user_namespace unless user_namespace.empty?
      parts << base
      suffix = version.to_s.strip
      parts << suffix unless suffix.empty?

      "#{CACHE_PREFIX}#{parts.join(':')}"
    end
  end
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `bundle exec rspec spec/services/flowchart_runtime/cache_key_spec.rb`
Expected: PASS, 5 examples, 0 failures.

- [ ] **Step 5: Stage the work**

```bash
git add app/services/flowchart_runtime/cache_key.rb \
        spec/services/flowchart_runtime/cache_key_spec.rb
```

---

## Task 22: Element-type track

**Files:**
- Modify: `app/services/code_generators/element_types/{start,end,decision,loop,subflow,timer}/**`
- Modify: `app/javascript/flowchart/constants/schemas.js`
- Test: `spec/services/code_generators/element_types/**`

**Interfaces:**
- Consumes: `.superpowers/sdd/conformance-inventory.yml`, `GeneratorConformance`.
- Produces: the six supported element types passing conformance.

Only `start`, `end`, `decision`, `loop`, `subflow`, and `timer` are registered. Directories exist for `fork`, `join`, `saga`, `transaction`, `parallel_for_each`, and `signal_wait`, but `GeneratorRegistry::SUPPORTED_ELEMENT_TYPES` excludes them.

- [ ] **Step 1: Prove the unsupported types are unreachable**

```ruby
# spec/services/code_generators/element_types/registry_scope_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::GeneratorRegistry do
  UNSUPPORTED = %w[fork join saga transaction parallel_for_each signal_wait switch].freeze

  it "registers exactly the six supported element types" do
    expect(described_class.element_type_generators.keys)
      .to match_array(%w[start end decision loop subflow timer])
  end

  UNSUPPORTED.each do |type|
    it "does not resolve the unsupported #{type} element type" do
      expect(described_class.find_element_type(type)).to be_nil
    end

    it "does not offer #{type} in the builder property schema" do
      expect(CodeGenerators::CONFIG_SCHEMAS).not_to have_key(type)
    end
  end
end
```

- [ ] **Step 2: Run it**

Run: `bundle exec rspec spec/services/code_generators/element_types/registry_scope_spec.rb`
Expected: PASS. If a `CONFIG_SCHEMAS` example fails, the builder still offers a type the registry rejects — remove it from `schemas.js`, which is a genuine editor/generator gap.

- [ ] **Step 3: Apply the shared category procedure to the six supported types**

Run Steps 3 through 10 of the shared category procedure, substituting the element-type paths. `decision` and `loop` carry the `branches` and `steps` field types the harness marks `:skipped`; verify those by hand against `spec/services/code_generators/element_types/decision` and assert emitted branch routing matches the editor's branch list.

- [ ] **Step 4: File shared-file requests**

Write `.superpowers/sdd/track-element-types-requests.md`, or `No requests.`

- [ ] **Step 5: Stage the work**

```bash
git add app/services/code_generators/element_types \
        spec/services/code_generators/element_types \
        app/javascript/flowchart/constants/schemas.js \
        .superpowers/sdd/track-element-types-requests.md
```

---

## Task 23: Integration and final verification

**Files:**
- Modify: `config/locales/flowchart_actions.en.yml`, `config/locales/flowchart_actions.zh-CN.yml`
- Modify: `app/services/flowchart_runtime/**`, `app/services/code_generators/shared/**` (per track requests)
- Regenerate: `spec/support/config_schemas.rb`, `docs/superpowers/specs/2026-04-19-generator-ui-audit-data.yml`, `docs/superpowers/specs/2026-04-27-generator-audit-data.yml`
- Modify: `lib/tasks/flowchart_regenerate_activities.rake` if the dry run reveals gaps

**Interfaces:**
- Consumes: every `.superpowers/sdd/track-*-requests.md`.
- Produces: a green repository with all audits at zero defects.

- [ ] **Step 1: Apply every track request**

```bash
ls .superpowers/sdd/track-*-requests.md
```

Apply each in order. For locale requests add both `en` and `zh-CN` keys, keeping the two files structurally identical.

- [ ] **Step 2: Verify locale parity**

```bash
bundle exec rspec spec/config/flowchart_elements_locale_spec.rb
```
Expected: PASS.

- [ ] **Step 3: Regenerate the JS-to-Ruby schema mirror**

```bash
bundle exec rake config_schemas:mirror
bundle exec rake config_schemas:check
```
Expected: `OK: config schemas in sync`.

- [ ] **Step 4: Re-run the full conformance, tenant-scoping, and execution suites**

```bash
bundle exec rspec spec/services/code_generators/generator_conformance_spec.rb \
                  spec/services/code_generators/tenant_scoping_spec.rb \
                  spec/services/code_generators/generated_activity_execution_spec.rb
```
Expected: PASS, with every remaining exception justified in the allow-list.

- [ ] **Step 5: Confirm the inventory is empty**

```bash
bundle exec rake conformance:inventory
```
Expected: `Wrote inventory for 0 actions with defects`.

- [ ] **Step 6: Regenerate audit baselines and confirm zero defects**

```bash
bundle exec ruby scripts/audit_generator_ui.rb
bundle exec ruby scripts/audit_step_action_config.rb
bundle exec rake audit:generators
```
Expected: all three exit 0 with `Total defects: 0`.

- [ ] **Step 7: Run the full Ruby suite**

```bash
bin/rails parallel:prepare && bin/rails parallel:spec
```
Expected: 0 failures. Fall back to `bundle exec rspec` if parallel setup is unavailable.

- [ ] **Step 8: Run lint and the JavaScript suite at 100% coverage**

```bash
npm run lint
npx vitest run --coverage
```
Expected: lint clean; every touched file under `app/javascript/**` at 100% lines and branches.

- [ ] **Step 9: Dry-run activity regeneration**

```bash
DRY_RUN=1 CUSTOMER_ID=81721200 bundle exec rake flowcharts:regenerate_activities
```
Expected: exit 0, no generated source or secrets in the output.

- [ ] **Step 10: Final worktree check**

```bash
git --no-pager diff --check
git --no-pager status --short
git --no-pager diff --stat
```
Expected: no whitespace errors. Leave everything uncommitted for the human reviewer.

---

## Parallelization

```
Task 1 → Task 2 → Task 3 → Task 4  (sequential; Task 4 gates Phase 1)
                              │
                              ├─ Task 21 (cache key facade; blocks Task 11)
                              │
                              ├─ Tasks 5,6,7,8,9,10,12,13,14,15,16,17,18,19,20,22  (parallel)
                              └─ Task 11 (after Task 21)
                                          │
                                          ▼
                                      Task 23 (integrator)
```

Tasks 1–4 are strictly sequential: each builds on the previous, and Task 4's inventory is the input to every track. Task 21 is small and can run concurrently with Task 4. The sixteen category tracks plus the element-type track have disjoint file ownership and run fully in parallel. Task 23 runs alone.

## Notes for Reviewers

The single highest-risk item is the **inert-field allow-list**. It is the one mechanism by which a real defect can be reclassified as acceptable. Every entry must explain the mechanism that prevents the field from reaching `generate_body`. Reject any entry whose justification merely restates that output does not change.

The second risk is **execution-spec append contention**: all seventeen tracks append to `generated_activity_execution_spec.rb`. Tracks append only and never reorder, so conflicts stay textual and local.
