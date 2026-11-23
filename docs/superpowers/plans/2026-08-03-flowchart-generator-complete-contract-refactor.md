# Flowchart Generator Complete Contract Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove and enforce complete parity between every flowchart builder configuration and its Ruby generator, replace hand-rolled runtime behavior with mature libraries behind thin services, and verify generated activities execute correctly.

**Architecture:** Treat each builder action/element as a contract row spanning JavaScript schema, Ruby `ConfigSchema`, emitted activity source, runtime facade, locales, and tests. Strengthen the audits first, finish the existing uncommitted runtime refactor, then process structural elements and action categories in bounded slices.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, Trailblazer Activity, dry-rb/Reform conventions, Faraday, jwt, rubyzip, Barby, RQRCode, Liquid, Loofah, bcrypt, RSpec, Vitest

## Global Constraints

- Work directly on `master`; do not create a worktree.
- Preserve the existing uncommitted changes and never revert unrelated user work.
- Do not commit; leave all changes for human review.
- Every user-facing field label, option, placeholder, and error copy must have matching `en` and `zh-CN` translations.
- JavaScript changes require 100% lines and branches with `npm run coverage`.
- Do not expose computed topology fields as editable UI controls.
- Do not add gems for behavior clearly and reliably covered by Rails or the Ruby standard library.
- Required dependencies must fail explicitly; do not emit `defined?(Gem)` fallbacks.
- Generated code must not use unsafe `eval`, `class_eval`, unsafe YAML/Marshal loading, or unchecked `constantize`.
- Every task ends with targeted tests and a review checkpoint, not a commit.

**Design:** `docs/superpowers/specs/2026-08-03-flowchart-generator-complete-contract-refactor-design.md`

---

## File Map

| Path | Responsibility |
|---|---|
| `scripts/audit_generator_ui.rb` | Discover all elements/actions and compare UI with generator contracts |
| `scripts/audit_step_action_config.rb` | Detect dead fields, enum/default/required drift, and reserved-key collisions |
| `scripts/audit_generators.rb` | Detect unsafe or noncanonical emitted source |
| `spec/support/config_schemas.rb` | Generated Ruby mirror of builder schemas |
| `spec/services/code_generators/contract_parity_spec.rb` | Executable whole-registry parity contract |
| `spec/services/code_generators/generated_activity_execution_spec.rb` | Syntax and representative runtime execution |
| `app/services/code_generators/config_schema.rb` | Authoritative accepted configuration contract |
| `app/services/code_generators/shared/` | Shared safe emission helpers |
| `app/services/flowchart_runtime/` | Thin gem/Rails-backed runtime facades |
| `app/javascript/flowchart/constants/schemas.js` | Structural element editor schemas |
| `app/javascript/flowchart/constants/action_configs/` | Process action editor schemas |
| `config/locales/flowchart_actions.{en,zh-CN}.yml` | Process action copy |
| `docs/superpowers/specs/2026-04-19-generator-ui-audit-data.yml` | Reproducible generated contract catalog |
| `lib/tasks/flowchart_regenerate_activities.rake` | Persist regenerated activity source |

---

### Task 1: Make the Contract Audit Authoritative

**Files:**
- Modify: `scripts/audit_generator_ui.rb`
- Modify: `scripts/audit_step_action_config.rb`
- Modify: `scripts/audit_generators.rb`
- Create: `spec/services/code_generators/contract_parity_spec.rb`
- Regenerate: `spec/support/config_schemas.rb`
- Regenerate: `docs/superpowers/specs/2026-04-19-generator-ui-audit-data.yml`

**Interfaces:**
- Consumes: `CodeGenerators::GeneratorRegistry`, generator `.config_fields`, generated `CodeGenerators::CONFIG_SCHEMAS`
- Produces: `GeneratorUiAudit.run_report` returning `{ entries:, defects: }`, with non-zero CLI exit when defects exist

- [ ] **Step 1: Write failing audit specs**

Create `spec/services/code_generators/contract_parity_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("scripts/audit_generator_ui")
require Rails.root.join("scripts/audit_step_action_config")

RSpec.describe "flowchart generator contract parity" do
  it "discovers every registered element and process action exactly once" do
    report = GeneratorUiAudit.run_report
    keys = report.fetch(:entries).map { |entry| [entry.fetch(:kind), entry.fetch(:ui_key)] }

    expect(keys).not_to be_empty
    expect(keys).to eq(keys.uniq)
    expect(report.fetch(:defects)).to all(include(:type, :ui_key))
  end

  it "returns structured step-action configuration defects" do
    expect(StepActionConfigAudit.run_report).to all(
      include(:ui_key, :phase, :defects)
    )
  end
end
```

- [ ] **Step 2: Run the specs and confirm the current scripts are not reusable**

Run:

```bash
bundle exec rspec spec/services/code_generators/contract_parity_spec.rb --format documentation
```

Expected: fail because `run_report` does not exist and current scripts write/print as side effects.

- [ ] **Step 3: Refactor audits into reusable report APIs**

Add public APIs without executing on `require`:

```ruby
module GeneratorUiAudit
  module_function

  def run_report
    ui = load_ui_schemas
    entries = build_report(ui)
    {
      entries: entries,
      defects: entries.flat_map do |entry|
        entry.fetch(:gaps).map { |gap| gap.merge(ui_key: entry.fetch(:ui_key)) }
      end
    }
  end
end

if $PROGRAM_NAME == __FILE__
  report = GeneratorUiAudit.run_report
  File.write(OUTPUT_PATH, report.fetch(:entries).to_yaml)
  abort "Generator/UI defects: #{report.fetch(:defects).size}" if report.fetch(:defects).any?
end
```

Apply the same pattern to `StepActionConfigAudit.run_report`. Make
`scripts/audit_generators.rb` include forbidden emitted-source rules for:

```ruby
FORBIDDEN_EMISSION = {
  net_http: /\bNet::HTTP\b/,
  raw_cipher: /\bOpenSSL::Cipher\b/,
  optional_dependency: /defined\?\((?:Zip|Barby|RQRCode|Liquid|Loofah|MiniMagick)\)/,
  unsafe_eval: /\b(?:eval|class_eval)\s*\(/,
  unsafe_marshal: /\bMarshal\.load\b/,
  unsafe_yaml: /\bYAML\.(?:load|unsafe_load)\b/
}.freeze
```

Allow an audited exception only through a source comment of the form
`# generator-audit: allow <rule> -- <reason>` and include that reason in the
report.

- [ ] **Step 4: Discover all structural generators**

Replace the eight-item `IN_SCOPE_ELEMENT_TYPES` list with discovery under
`app/services/code_generators/element_types/*/*_generator.rb`, excluding only
the `process` directory. The expected structural keys are:

```ruby
%w[
  decision end fork join loop parallel_for_each saga signal_wait start subflow
  switch timer transaction
]
```

Assert that each has a corresponding `ELEMENT_SCHEMAS` entry or an explicit
documented computed-only schema classification.

- [ ] **Step 5: Classify non-user fields**

Introduce constants used by the parity check:

```ruby
COMMON_STEP_FIELDS = %w[
  retryCount retryBackoff timeout guardCondition errorStrategy
].freeze

COMPUTED_FIELDS = {
  "decision" => %w[_connection_match_values _route_index]
}.freeze
```

Computed fields are valid generator inputs but cannot satisfy parity through a
builder control. Extra UI fields are defects unless classified as common
presentation fields (`label`, `description`) or read by the generator.

- [ ] **Step 6: Regenerate mirrors and run the audit specs**

Run:

```bash
bundle exec rake config_schemas:mirror
bundle exec ruby scripts/audit_generator_ui.rb
bundle exec ruby scripts/audit_step_action_config.rb
bundle exec rake audit:generators
bundle exec rspec spec/services/code_generators/contract_parity_spec.rb
```

Expected: scripts may report real product defects, but no false positives from
computed/common fields and no load-time side effects. Do not baseline defects
away; record them for Tasks 3-6.

- [ ] **Step 7: Review checkpoint**

Inspect:

```bash
git --no-pager diff -- scripts/audit_generator_ui.rb scripts/audit_step_action_config.rb scripts/audit_generators.rb spec/services/code_generators/contract_parity_spec.rb docs/superpowers/specs/2026-04-19-generator-ui-audit-data.yml
```

Confirm all defects identify an actionable schema/generator mismatch.

---

### Task 2: Finish the Existing Runtime-Facade Refactor

**Files:**
- Modify: `Gemfile`, `Gemfile.lock`
- Modify: `app/services/outbound_http.rb`
- Modify/Create: `app/services/flowchart_runtime/*.rb`
- Modify: currently changed generators listed by `git diff --name-only -- app/services/code_generators`
- Modify: matching specs under `spec/services/flowchart_runtime/` and `spec/services/code_generators/`

**Interfaces:**
- Consumes: direct gem dependencies in `Gemfile`
- Produces: narrow `FlowchartRuntime::*` class methods raising namespaced `Error`

- [ ] **Step 1: Run the existing focused runtime and changed-generator specs**

Run:

```bash
bundle exec rspec \
  spec/services/outbound_http_spec.rb \
  spec/services/flowchart_runtime \
  spec/services/code_generators/shared/http_request_builder_spec.rb \
  $(git diff --name-only -- 'spec/services/code_generators/**/*_spec.rb')
```

Expected: capture exact failures; do not modify code before obtaining the
baseline.

- [ ] **Step 2: Enforce one facade shape**

Every facade must follow:

```ruby
module FlowchartRuntime
  class Example
    class Error < StandardError; end

    class << self
      def call(...)
        # one mature library or Rails API
      rescue LibrarySpecificError => e
        raise Error, e.message
      end
    end
  end
end
```

Do not rescue `StandardError`. Validate enums and required values before
calling the dependency. Return plain Ruby values suitable for `ctx`.

- [ ] **Step 3: Remove fallback and protocol implementation from generators**

For each changed generator, add expectations:

```ruby
expect(body).to include("FlowchartRuntime::")
expect(body).not_to match(/\bNet::HTTP\b/)
expect(body).not_to match(/\bOpenSSL::Cipher\b/)
expect(body).not_to include("defined?(")
```

HTTP generators may include `OutboundHttp` instead of `FlowchartRuntime`.
Generated bodies rescue the exact facade error and set:

```ruby
ctx[:_last_error] = e.message
false
```

- [ ] **Step 4: Verify dependency necessity**

Run:

```bash
bundle exec ruby -e 'Bundler.load.dependencies.each { |d| puts "#{d.name} #{d.requirement}" }' | sort
```

Keep direct dependencies only when used by an app facade. Retain stdlib for
CSV, JSON, Base64, URI, SecureRandom, and plain Digest. Remove duplicate or
unused new gems and run `bundle install` only if `Gemfile` changes.

- [ ] **Step 5: Run focused specs and audits**

Run:

```bash
bundle exec rspec spec/services/outbound_http_spec.rb spec/services/flowchart_runtime
bundle exec rspec $(git diff --name-only -- 'spec/services/code_generators/**/*_spec.rb')
bundle exec rake audit:generators
bundle exec ruby scripts/audit_step_action_config.rb
```

Expected: all focused specs pass; no forbidden-source defects in touched
generators.

- [ ] **Step 6: Review checkpoint**

Use `git --no-pager diff --check` and inspect the runtime/generator diff. Ensure
no existing user change was reverted and every removed UI field was also
removed from both locale files.

---

### Task 3: Align All Structural Element Generators

**Files:**
- Modify: `app/javascript/flowchart/constants/schemas.js`
- Modify: `app/services/code_generators/element_types/{start,end,decision,loop,join,fork,switch,subflow,timer,signal_wait,saga,transaction,parallel_for_each}/*_generator.rb`
- Modify: matching specs in `spec/services/code_generators/element_types/`
- Modify: relevant flowchart locale files when visible copy changes

**Interfaces:**
- Consumes: Task 1 contract classifications
- Produces: zero structural-element parity defects and syntax-valid generated bodies

- [ ] **Step 1: Add a table-driven structural parity spec**

Extend `contract_parity_spec.rb`:

```ruby
STRUCTURAL_KEYS = %w[
  decision end fork join loop parallel_for_each saga signal_wait start subflow
  switch timer transaction
].freeze

it "has no structural element defects" do
  defects = GeneratorUiAudit.run_report.fetch(:defects).select do |defect|
    STRUCTURAL_KEYS.include?(defect.fetch(:ui_key))
  end
  expect(defects).to be_empty
end
```

- [ ] **Step 2: Run structural specs**

Run:

```bash
bundle exec rspec spec/services/code_generators/contract_parity_spec.rb \
  spec/services/code_generators/element_types/{start,end,decision,loop,join,fork,switch,subflow,timer,signal_wait,saga,transaction,parallel_for_each}
```

Expected: failures identify exact fields/options/body branches.

- [ ] **Step 3: Align each element contract**

For each structural generator:

1. declare all accepted fields in `config_schema`;
2. add conditional validation for visible/required branches;
3. remove dead UI fields or implement their promised behavior;
4. align enum values/defaults byte-for-byte;
5. test every option branch;
6. use computed-field classification for topology data.

Conditional validation follows:

```ruby
config_schema do
  field :mode, :enum, values: MODES, default: "default"
  field :requiredCount, :integer, min: 1

  validate do |cfg, errors|
    if cfg["mode"] == "wait_n" && cfg["requiredCount"].blank?
      errors << "requiredCount is required when mode is wait_n"
    end
  end
end
```

- [ ] **Step 4: Add syntax checks**

For every structural generator spec:

```ruby
expect { RubyVM::InstructionSequence.compile(generator.generate_step_method) }
  .not_to raise_error
```

- [ ] **Step 5: Run structural specs and JavaScript coverage**

Run:

```bash
bundle exec rspec spec/services/code_generators/contract_parity_spec.rb \
  spec/services/code_generators/element_types/{start,end,decision,loop,join,fork,switch,subflow,timer,signal_wait,saga,transaction,parallel_for_each}
npm run coverage
```

Expected: structural defects zero; changed JavaScript files at 100% lines and
branches.

- [ ] **Step 6: Review checkpoint**

Inspect structural schema and generator diffs together. Confirm no generated
code branch accepts an option absent from UI and no UI option falls through to
an unrelated default.

---

### Task 4: Align Model, Validation, Data, and Caching Actions

**Files:**
- Modify: `app/javascript/flowchart/constants/action_configs/{model,validation,data,caching}_actions.js`
- Modify: `app/services/code_generators/element_types/process/{model_operations,validation,data_operations,caching}/*_generator.rb`
- Modify: matching generator specs
- Modify: `config/locales/flowchart_actions.{en,zh-CN}.yml`

**Interfaces:**
- Consumes: Task 1 audit APIs and Task 2 runtime facades
- Produces: zero contract defects for phases `model`, `validation`, `data`, and `caching`

- [ ] **Step 1: Write phase-filtered parity examples**

```ruby
%w[model validation data caching].each do |phase|
  it "has no #{phase} action defects" do
    defects = GeneratorUiAudit.run_report.fetch(:defects).select do |defect|
      defect[:phase] == phase
    end
    expect(defects).to be_empty
  end
end
```

- [ ] **Step 2: Run category specs and capture failures**

Run:

```bash
bundle exec rspec \
  spec/services/code_generators/contract_parity_spec.rb \
  spec/services/code_generators/element_types/process/{model_operations,validation,data_operations,caching}
```

- [ ] **Step 3: Remove unsafe model and collection behavior**

Replace `Marshal.load(Marshal.dump(...))` clone emission with a Rails-aware
facade:

```ruby
module FlowchartRuntime
  class Clone
    class Error < StandardError; end

    def self.call(value)
      return value.deep_dup if value.respond_to?(:deep_dup)

      raise Error, "value cannot be safely cloned"
    end
  end
end
```

Resolve model classes through one helper that requires `ApplicationRecord`
ancestry:

```ruby
def self.model_class(name)
  klass = name.to_s.safe_constantize
  raise Error, "unknown model" unless klass&.<(ApplicationRecord)

  klass
end
```

Never emit raw SQL from a normal text field. If `raw_sql_query` remains, mark
its SQL input as an explicit privileged expression surface, bind all values,
enforce read-only statements, and add security specs.

- [ ] **Step 4: Align every configuration branch**

For every action, compare UI fields against `config_schema` and generated body.
Remove aliases such as duplicated legacy field names rather than supporting
both. Use `ConfigSchema#value_for` for defaults and `fetch_enum` for enum
emission.

- [ ] **Step 5: Run focused specs, audits, and coverage**

Run:

```bash
bundle exec rspec \
  spec/services/code_generators/contract_parity_spec.rb \
  spec/services/code_generators/element_types/process/{model_operations,validation,data_operations,caching} \
  spec/services/flowchart_runtime
bundle exec ruby scripts/audit_step_action_config.rb
bundle exec rake audit:generators
npm run coverage
```

- [ ] **Step 6: Review checkpoint**

Confirm query operations preserve tenant scoping provided by their input
relation and no generator silently calls an unscoped model constant.

---

### Task 5: Align Communication, File, Realtime, Background, and Service Actions

**Files:**
- Modify: `app/javascript/flowchart/constants/action_configs/{communication,file,realtime,background,service}_actions.js`
- Modify: `app/services/code_generators/element_types/process/{communication,file_operations,realtime,background,service_invocation}/*_generator.rb`
- Modify: `app/services/outbound_http.rb`
- Modify/Create: required `app/services/flowchart_runtime/*.rb`
- Modify: matching specs and both locale files

**Interfaces:**
- Consumes: `OutboundHttp.request`, archive/file/template runtime facades
- Produces: bounded, TLS-verifying, explicit-failure I/O actions

- [ ] **Step 1: Add phase parity examples and run focused specs**

Use the Task 4 phase-filtered example for:

```ruby
%w[communication file realtime background service]
```

Run the matching category specs before editing.

- [ ] **Step 2: Standardize outbound calls**

All HTTP emission must use:

```ruby
response = OutboundHttp.request(
  method,
  url,
  headers: headers,
  body: body,
  open_timeout: open_timeout,
  read_timeout: read_timeout,
  follow_redirects: follow_redirects,
  max_redirects: max_redirects
)
```

Do not expose a TLS-disable option. Validate URL schemes, bound redirects and
timeouts, and rescue only `OutboundHttp::TransportError`.

- [ ] **Step 3: Standardize jobs, broadcasts, and service invocation**

Use Active Job, Action Cable/notifications, and an allow-listed service
resolver. Service classes must implement the documented public method and
must not be resolved through unchecked `constantize`.

- [ ] **Step 4: Align file format options with actual dependencies**

Every format shown in UI must have a working facade and spec. Remove formats
whose mature dependency is not adopted. File generation must return explicit
binary/text values and must not write arbitrary filesystem paths from a text
field.

- [ ] **Step 5: Run focused specs, audits, and coverage**

Run:

```bash
bundle exec rspec \
  spec/services/outbound_http_spec.rb \
  spec/services/flowchart_runtime \
  spec/services/code_generators/contract_parity_spec.rb \
  spec/services/code_generators/element_types/process/{communication,file_operations,realtime,background,service_invocation}
bundle exec ruby scripts/audit_step_action_config.rb
bundle exec rake audit:generators
npm run coverage
```

- [ ] **Step 6: Review checkpoint**

Confirm no generated I/O code contains protocol loops, optional dependency
guards, arbitrary filesystem writes, or silent success fallbacks.

---

### Task 6: Align Security, Concurrency, Resilience, Scheduling, Human Workflow, Response, and Utility Actions

**Files:**
- Modify: `app/javascript/flowchart/constants/action_configs/{security,concurrency,resilience,scheduling,human_workflow,response,utility}_actions.js`
- Modify: `app/services/code_generators/element_types/process/{security,concurrency,resilience,scheduling_time,human_workflow,response,utility}/*_generator.rb`
- Modify/Create: required `app/services/flowchart_runtime/*.rb`
- Modify: matching specs and both locale files

**Interfaces:**
- Consumes: Tasks 1-2 audit/runtime foundations
- Produces: zero defects for all remaining process phases

- [ ] **Step 1: Add remaining phase parity examples and run focused specs**

Use the Task 4 phase-filtered example for:

```ruby
%w[security concurrency resilience scheduling human_workflow response utility]
```

- [ ] **Step 2: Remove unsafe authorization and crypto emission**

Authorization must call an app policy/authorization facade; never emit
`eval(policy_expression)`. JWT, encryption, password hashing, and sanitization
must call their runtime facades. Token/cipher algorithms are allow-listed in
the facade and mirrored exactly in UI.

- [ ] **Step 3: Bound concurrency and resilience behavior**

Locks, retries, circuit breakers, rate limits, schedules, and parallel maps
must have validated positive bounds. No configuration may produce unbounded
sleep, retry, thread creation, or lock acquisition.

- [ ] **Step 4: Replace simulated human-workflow success**

Actions such as approval, assignment, escalation, and user input must either
call a real application service/model or fail explicitly as unsupported.
Remove generated placeholder hashes that report success without persisting or
signaling the workflow promised by the UI.

- [ ] **Step 5: Align response and utility output semantics**

Ensure every `resultVar`/output key is declared in metadata, written exactly
once, and has tests for each output format. Barcode, QR, template, currency,
geolocation, AI, and audit behavior use the adopted runtime/app services.

- [ ] **Step 6: Run focused specs, audits, and coverage**

Run:

```bash
bundle exec rspec \
  spec/services/flowchart_runtime \
  spec/services/code_generators/contract_parity_spec.rb \
  spec/services/code_generators/element_types/process/{security,concurrency,resilience,scheduling_time,human_workflow,response,utility}
bundle exec ruby scripts/audit_step_action_config.rb
bundle exec rake audit:generators
npm run coverage
```

- [ ] **Step 7: Review checkpoint**

Confirm all registered process phases now have zero contract defects and no
action is success-shaped without implementing its configured behavior.

---

### Task 7: Compile and Execute Generated Activities

**Files:**
- Create: `spec/services/code_generators/generated_activity_execution_spec.rb`
- Modify: `app/services/code_generators/test_runner.rb`
- Modify: `app/services/activity_generator.rb` if compilation exposes assembly defects
- Modify: generator/runtime files only when an execution test identifies a bug

**Interfaces:**
- Consumes: every registered generator `.sample_input`
- Produces: syntax compilation for every generated step and representative activity execution

- [ ] **Step 1: Write registry-wide syntax coverage**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "generated flowchart activity execution" do
  CodeGenerators::GeneratorRegistry.all.each do |generator_class|
    it "compiles #{generator_class.name} sample source" do
      result = CodeGenerators::TestRunner.run(
        generator_class,
        config: generator_class.sample_input
      )

      expect(result.fetch(:validation_errors)).to be_empty
      expect {
        RubyVM::InstructionSequence.compile(result.fetch(:code))
      }.not_to raise_error
    end
  end
end
```

- [ ] **Step 2: Add representative execution examples**

Execute at least one success and one operational failure path for each runtime
facade category: HTTP, crypto, archive/file, data/model, cache/lock, job,
response, and human workflow. Stub the facade, not its underlying gem, in
generator execution specs.

Example:

```ruby
allow(OutboundHttp).to receive(:request)
  .and_return(OutboundHttp::Response.new(status: 200, headers: {}, body: '{"ok":true}'))

result = generated_step.call(ctx, **)
expect(result).to eq(true)
expect(ctx[:result]).to eq(ok: true)
```

- [ ] **Step 3: Ensure invalid configuration never compiles into activity source**

`ActivityGenerator` must raise or return a structured generation failure when
`validate_config` has errors. It must not persist partial activity source.
Add a model/request spec covering save/regeneration failure.

- [ ] **Step 4: Run the execution suite**

Run:

```bash
bundle exec rspec \
  spec/services/code_generators/generated_activity_execution_spec.rb \
  spec/services/code_generators/test_runner_spec.rb \
  spec/services/activity_generator_spec.rb \
  spec/models/flowchart_spec.rb
```

Expected: every registered sample compiles and representative paths execute.

- [ ] **Step 5: Review checkpoint**

Inspect any generator changed by execution failures and confirm the fix
addresses the contract, not only the sample input.

---

### Task 8: Regeneration, Documentation, and Final Verification

**Files:**
- Modify: `lib/tasks/flowchart_regenerate_activities.rake`
- Modify: `docs/superpowers/specs/2026-04-19-generator-ui-audit-data.yml`
- Modify: directly related flowchart generator documentation

**Interfaces:**
- Consumes: valid `ActivityGenerator`
- Produces: safe dry-run and scoped regeneration with failure summary

- [ ] **Step 1: Add rake-task specs**

Create or extend a task spec to cover:

- `DRY_RUN=1` generates but does not persist;
- `CUSTOMER_ID` scopes regeneration;
- one invalid flowchart is reported and does not stop remaining records;
- task exits non-zero when any regeneration fails;
- output contains counts, not sensitive generated source.

- [ ] **Step 2: Implement safe regeneration**

Use:

```ruby
dry_run = ActiveModel::Type::Boolean.new.cast(ENV["DRY_RUN"])
failures = []

scope.find_each do |flowchart|
  activity = ActivityGenerator.new(flowchart).generate
  flowchart.update_column(:activity, activity) unless dry_run
rescue ActivityGenerator::Error => e
  failures << [flowchart.id, e.message]
end

abort "#{failures.size} flowcharts failed regeneration" if failures.any?
```

Do not rescue `StandardError`; use the generator's explicit error type.

- [ ] **Step 3: Regenerate the contract catalog**

Run:

```bash
bundle exec rake config_schemas:mirror
bundle exec ruby scripts/audit_generator_ui.rb
```

Inspect the YAML and confirm every row has empty unexplained gaps.

- [ ] **Step 4: Run final audits**

Run:

```bash
bundle exec ruby scripts/audit_generator_ui.rb
bundle exec ruby scripts/audit_step_action_config.rb
bundle exec rake audit:generators
```

Expected: zero defects and exit status 0.

- [ ] **Step 5: Run final Ruby verification**

Run:

```bash
bin/rails parallel:prepare && bin/rails parallel:spec
```

If parallel setup is unavailable, run:

```bash
bundle exec rspec
```

Expected: full RSpec suite passes.

- [ ] **Step 6: Run final JavaScript verification**

Run:

```bash
npm run lint
npm run coverage
```

Expected: lint passes; 100% lines and branches under `app/javascript/**`.

- [ ] **Step 7: Run a dry regeneration**

Run:

```bash
DRY_RUN=1 CUSTOMER_ID=81721200 bundle exec rake flowcharts:regenerate_activities
```

Expected: all scoped flowcharts generate successfully without persistence.

- [ ] **Step 8: Final worktree review**

Run:

```bash
git --no-pager diff --check
git --no-pager status --short
git --no-pager diff --stat
```

Confirm the complete work remains uncommitted and no unrelated file was
reverted.
