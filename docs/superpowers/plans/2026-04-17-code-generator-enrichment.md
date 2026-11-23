# Code Generator Enrichment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enrich all 116 code generators under `app/services/code_generators/element_types/` across three layers (Ruby `generate_body` + `validate_config`, rspec tests, JS `configSchema`) so that every documented and parity-target configuration branch is implemented, nil-safe, error-wrapped, and UI-addressable.

**Architecture:** Preserve existing `BaseGenerator`/`GeneratorInterface` structure. Introduce four new shared modules (`CtxReader`, `ErrorWrapper`, `ConfigFieldReader`, `SchemaReader`) and one new rspec shared example (`"covers all configured branches"`). Then touch each generator in fixed category order, applying cross-cutting rules R1–R6 plus a per-generator diff from §P of this plan.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, RSpec, Trailblazer Activity, StimulusJS, TailwindCSS.

**Spec:** `docs/superpowers/specs/2026-04-17-code-generator-enrichment-design.md`

---

## How To Use This Plan

- **Shape.** 18 batches. Batch 1 is foundation (shared modules + shared example). Batches 2–18 are generator enrichment, one category per batch, with per-generator diff blocks in §P at the end.
- **Per-generator workflow.** For each generator in a batch, follow the repeating template in §T once, substituting the per-generator diff from §P.
- **Order.** Complete batches in order (foundation before category work). Within a batch, generators can be worked in any order — each generator is independent.
- **Commit cadence.** Each generator = 1 commit. Each foundation task = 1 commit.
- **Tests.** Every change must preserve existing tests + add new cases per the diff. Run `bundle exec rspec spec/services/code_generators/element_types/<category>/<name>_generator_spec.rb` after each generator.
- **No auto-commit by agent.** AGENTS.md forbids it — end each batch by showing the user the file tree so they can review/commit manually. Commit commands in steps below are the user's commands to run, not the agent's.

---

## File Structure

### New Files (Foundation, Batch 1)

- `app/services/code_generators/shared/ctx_reader.rb` — nil-safe ctx access helpers
- `app/services/code_generators/shared/error_wrapper.rb` — standard begin/rescue/_last_error block
- `app/services/code_generators/shared/config_field_reader.rb` — enum/int/default config readers
- `app/services/code_generators/shared/schema_reader.rb` — reads Ruby mirror of JS configSchema
- `spec/support/config_schemas.rb` — generated Ruby mirror of JS configSchema arrays (one hash literal per action)
- `spec/support/shared_examples/covers_all_configured_branches.rb` — rspec shared example for R6
- `lib/tasks/config_schemas.rake` — rake task to regenerate mirror from JS + CI drift check

### Modified Files (Foundation)

- `app/services/code_generators/base_generator.rb` — include new mixins, add `wrap_with_error_strategy` hook, extend metadata DSL
- `app/services/code_generators/metadata_dsl.rb` — support `supports_timeout` and `error_strategy_default` DSL methods
- `spec/services/code_generators/base_generator_spec.rb` — test new wrappers

### Modified Files (Enrichment, Batches 2–18)

Per generator, three files in lockstep:
- Ruby: `app/services/code_generators/element_types/<path>/<name>_generator.rb`
- Spec: `spec/services/code_generators/element_types/<path>/<name>_generator_spec.rb`
- JS:   `app/javascript/flowchart/constants/action_configs/<category>_actions.js`

Non-process element generators update these JS files instead:
- `app/javascript/flowchart/constants/action_registry.js` (or nearest element-type registry)

---

## Cross-Cutting Rules (Reference)

Applied to every generator touched in batches 2–18, before the per-generator diff:

- **R1 — Nil-safe ctx reads.** Use `Shared::CtxReader.safe_read(var, type: :array|:hash|:string)` instead of bare `ctx[:var]` when iterating/indexing.
- **R2 — Standard error contract.** Wrap risky ops with `Shared::ErrorWrapper.wrap(code, source: generator_name, strategy_var: errorStrategy)`. New config field `errorStrategy` with values `continue` (default) | `fail_track` | `raise`.
- **R3 — Timeout for blocking ops.** Opt in via `generator_metadata { supports_timeout default: N }`; emits `Timeout.timeout(n) { ... }` wrapper.
- **R4 — Shared-helper adoption.** Route HTTP through `HttpRequestBuilder`, conditions through `ConditionBuilder`, `ctx.<path>` operands through `OperandConverter`.
- **R5 — Output contract standardization.** Rename config keys to canonical names: `resultVar` (scalar), `sourceVariable`, `targetVariable`, `itemVariable`, `indexVariable`. No back-compat.
- **R6 — Config branch coverage.** Every generator spec invokes `it_behaves_like "covers all configured branches", described_class`.

---

## Batch 1: Foundation

### Task 1.1: `CtxReader` shared module

**Files:**
- Create: `app/services/code_generators/shared/ctx_reader.rb`
- Test: `spec/services/code_generators/shared/ctx_reader_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/code_generators/shared/ctx_reader_spec.rb
require "rails_helper"

RSpec.describe CodeGenerators::Shared::CtxReader do
  let(:dummy_class) { Class.new { include CodeGenerators::Shared::CtxReader } }
  let(:instance) { dummy_class.new }

  describe "#safe_read" do
    it "wraps with || [] for :array type" do
      expect(instance.safe_read("items", type: :array)).to eq("(ctx[:items] || [])")
    end

    it "wraps with || {} for :hash type" do
      expect(instance.safe_read("data", type: :hash)).to eq("(ctx[:data] || {})")
    end

    it "uses .to_s for :string type" do
      expect(instance.safe_read("name", type: :string)).to eq("ctx[:name].to_s")
    end

    it "falls back to bare read for :any" do
      expect(instance.safe_read("foo", type: :any)).to eq("ctx[:foo]")
    end
  end

  describe "#ensure_array_expr" do
    it "wraps an arbitrary ruby expression" do
      expect(instance.ensure_array_expr("ctx[:items].first(10)")).to eq("Array(ctx[:items].first(10))")
    end
  end

  describe "#ensure_hash_expr" do
    it "wraps an arbitrary ruby expression" do
      expect(instance.ensure_hash_expr("ctx[:payload]")).to eq("((ctx[:payload]).is_a?(Hash) ? ctx[:payload] : {})")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/shared/ctx_reader_spec.rb -f doc`
Expected: FAIL with `uninitialized constant CodeGenerators::Shared::CtxReader`.

- [ ] **Step 3: Write minimal implementation**

```ruby
# app/services/code_generators/shared/ctx_reader.rb
# frozen_string_literal: true

module CodeGenerators
  module Shared
    module CtxReader
      def safe_read(ctx_var, type: :any)
        case type
        when :array  then "(ctx[:#{ctx_var}] || [])"
        when :hash   then "(ctx[:#{ctx_var}] || {})"
        when :string then "ctx[:#{ctx_var}].to_s"
        else              "ctx[:#{ctx_var}]"
        end
      end

      def ensure_array_expr(expr)
        "Array(#{expr})"
      end

      def ensure_hash_expr(expr)
        "((#{expr}).is_a?(Hash) ? #{expr} : {})"
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/shared/ctx_reader_spec.rb -f doc`
Expected: PASS (4 examples).

- [ ] **Step 5: Commit**

User runs:
```bash
git add app/services/code_generators/shared/ctx_reader.rb spec/services/code_generators/shared/ctx_reader_spec.rb
git commit -m "feat(codegen): add Shared::CtxReader for nil-safe ctx access"
```

---

### Task 1.2: `ErrorWrapper` shared module

**Files:**
- Create: `app/services/code_generators/shared/error_wrapper.rb`
- Test: `spec/services/code_generators/shared/error_wrapper_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/code_generators/shared/error_wrapper_spec.rb
require "rails_helper"

RSpec.describe CodeGenerators::Shared::ErrorWrapper do
  let(:dummy_class) { Class.new { include CodeGenerators::Shared::ErrorWrapper } }
  let(:instance) { dummy_class.new }

  describe "#wrap_with_error_strategy" do
    it "emits begin/rescue with _last_error write on :continue (default)" do
      code = instance.wrap_with_error_strategy("risky_op", source: "api_call", strategy: "continue")
      expect(code).to include("begin")
      expect(code).to include("risky_op")
      expect(code).to include('ctx[:_last_error] = { source: "api_call"')
      expect(code).to include("true\nend")
    end

    it "returns false on :fail_track" do
      code = instance.wrap_with_error_strategy("risky_op", source: "api_call", strategy: "fail_track")
      expect(code).to include("false\nend")
    end

    it "re-raises on :raise" do
      code = instance.wrap_with_error_strategy("risky_op", source: "api_call", strategy: "raise")
      expect(code).to include("raise e")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/shared/error_wrapper_spec.rb -f doc`
Expected: FAIL with `uninitialized constant CodeGenerators::Shared::ErrorWrapper`.

- [ ] **Step 3: Write minimal implementation**

```ruby
# app/services/code_generators/shared/error_wrapper.rb
# frozen_string_literal: true

module CodeGenerators
  module Shared
    module ErrorWrapper
      STRATEGIES = %w[continue fail_track raise].freeze

      def wrap_with_error_strategy(code, source:, strategy: "continue")
        on_error = case strategy
                   when "fail_track" then "false"
                   when "raise"      then "raise e"
                   else                   "true"
                   end

        <<~RUBY.chomp
          begin
          #{code.to_s.indent(2)}
            true
          rescue => e
            ctx[:_last_error] = { source: "#{source}", message: e.message, class: e.class.name, at: Time.current }
            #{on_error}
          end
        RUBY
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/shared/error_wrapper_spec.rb -f doc`
Expected: PASS (3 examples).

- [ ] **Step 5: Commit**

User runs:
```bash
git add app/services/code_generators/shared/error_wrapper.rb spec/services/code_generators/shared/error_wrapper_spec.rb
git commit -m "feat(codegen): add Shared::ErrorWrapper for standard error contract"
```

---

### Task 1.3: `ConfigFieldReader` shared module

**Files:**
- Create: `app/services/code_generators/shared/config_field_reader.rb`
- Test: `spec/services/code_generators/shared/config_field_reader_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/code_generators/shared/config_field_reader_spec.rb
require "rails_helper"

RSpec.describe CodeGenerators::Shared::ConfigFieldReader do
  let(:dummy_class) do
    Class.new do
      include CodeGenerators::Shared::ConfigFieldReader
      attr_accessor :config
      def initialize(cfg); @config = cfg.with_indifferent_access; end
    end
  end

  describe "#fetch_with_default" do
    it "returns config value when present" do
      expect(dummy_class.new("foo" => "bar").fetch_with_default(:foo, "fallback")).to eq("bar")
    end

    it "returns default when blank" do
      expect(dummy_class.new("foo" => "").fetch_with_default(:foo, "fallback")).to eq("fallback")
    end
  end

  describe "#fetch_enum" do
    it "returns the value when in allowed list" do
      expect(dummy_class.new("mode" => "fast").fetch_enum(:mode, %w[fast slow], default: "slow")).to eq("fast")
    end

    it "returns default when value not in allowed list" do
      expect(dummy_class.new("mode" => "x").fetch_enum(:mode, %w[fast slow], default: "slow")).to eq("slow")
    end
  end

  describe "#fetch_int_positive" do
    it "returns the int when > 0" do
      expect(dummy_class.new("n" => "42").fetch_int_positive(:n, default: 10)).to eq(42)
    end

    it "returns default when 0 or negative" do
      expect(dummy_class.new("n" => "-5").fetch_int_positive(:n, default: 10)).to eq(10)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/shared/config_field_reader_spec.rb -f doc`
Expected: FAIL with `uninitialized constant CodeGenerators::Shared::ConfigFieldReader`.

- [ ] **Step 3: Write minimal implementation**

```ruby
# app/services/code_generators/shared/config_field_reader.rb
# frozen_string_literal: true

module CodeGenerators
  module Shared
    module ConfigFieldReader
      def fetch_with_default(key, default)
        value = config[key]
        value.respond_to?(:empty?) && value.empty? ? default : (value.nil? ? default : value)
      end

      def fetch_enum(key, allowed, default:)
        value = config[key]
        allowed.include?(value) ? value : default
      end

      def fetch_int_positive(key, default:)
        raw = config[key]
        n = raw.to_i
        n > 0 ? n : default
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/shared/config_field_reader_spec.rb -f doc`
Expected: PASS (6 examples).

- [ ] **Step 5: Commit**

User runs:
```bash
git add app/services/code_generators/shared/config_field_reader.rb spec/services/code_generators/shared/config_field_reader_spec.rb
git commit -m "feat(codegen): add Shared::ConfigFieldReader helpers"
```

---

### Task 1.4: JS → Ruby schema mirror rake task

**Files:**
- Create: `lib/tasks/config_schemas.rake`
- Create: `spec/support/config_schemas.rb` (initial empty seed)
- Test: manual via `rake config_schemas:mirror` followed by file inspection

- [ ] **Step 1: Create empty seed file**

```ruby
# spec/support/config_schemas.rb
# frozen_string_literal: true
# THIS FILE IS GENERATED by `rake config_schemas:mirror`.
# Do not edit by hand. Regenerate after changing
# app/javascript/flowchart/constants/action_configs/*.js.

module CodeGenerators
  CONFIG_SCHEMAS = {}.freeze
end
```

- [ ] **Step 2: Write the rake task**

```ruby
# lib/tasks/config_schemas.rake
namespace :config_schemas do
  JS_DIR = Rails.root.join("app/javascript/flowchart/constants/action_configs")
  RUBY_MIRROR = Rails.root.join("spec/support/config_schemas.rb")

  desc "Regenerate Ruby mirror of JS action configSchemas at spec/support/config_schemas.rb"
  task :mirror do
    schemas = {}
    Dir[JS_DIR.join("*.js")].sort.each do |js_file|
      content = File.read(js_file)
      # Parse each action block's `value: "..."` and its configSchema via a lightweight regex.
      content.scan(/value:\s*"(?<value>[^"]+)",.*?configSchema:\s*\[(?<schema>.*?)\]\s*}/m) do |value, schema_body|
        schemas[value] = parse_schema_body(schema_body)
      end
    end
    File.write(RUBY_MIRROR, render_mirror(schemas))
    puts "Wrote #{schemas.size} actions to #{RUBY_MIRROR}"
  end

  desc "Verify mirror is in sync with JS; exit non-zero on drift (CI-ready)"
  task :check => :environment do
    before = File.read(RUBY_MIRROR)
    Rake::Task["config_schemas:mirror"].invoke
    after = File.read(RUBY_MIRROR)
    if before != after
      puts "DRIFT: spec/support/config_schemas.rb is stale. Run `rake config_schemas:mirror` and commit."
      exit 1
    end
    puts "OK: config schemas in sync"
  end

  def parse_schema_body(body)
    # Simple per-field parser: extracts key, type, label, default, required, options (enum values only).
    fields = []
    body.scan(/\{\s*(?<body>[^}]*?(?:\{[^}]*\}[^}]*?)*)\}/m).each do |(field_body)|
      key     = field_body[/key:\s*"([^"]+)"/, 1]
      type    = field_body[/type:\s*"([^"]+)"/, 1]
      label   = field_body[/label:\s*"([^"]+)"/, 1]
      required = !!(field_body[/required:\s*true/])
      default = field_body[/default:\s*"([^"]+)"/, 1] || field_body[/default:\s*(\d+)/, 1]
      options = field_body.scan(/\{\s*value:\s*"([^"]+)",\s*label:\s*"[^"]*"\s*\}/).flatten
      fields << { key: key, type: type&.to_sym, label: label, required: required, default: default, options: options }.compact
    end
    fields
  end

  def render_mirror(schemas)
    body = schemas.sort.map { |action, fields|
      "    #{action.inspect} => #{fields.inspect}"
    }.join(",\n")
    <<~RUBY
      # frozen_string_literal: true
      # THIS FILE IS GENERATED by `rake config_schemas:mirror`.
      # Do not edit by hand.

      module CodeGenerators
        CONFIG_SCHEMAS = {
      #{body}
        }.freeze
      end
    RUBY
  end
end
```

- [ ] **Step 3: Run the task**

Run: `bundle exec rake config_schemas:mirror`
Expected: STDOUT "Wrote N actions to ..."; `spec/support/config_schemas.rb` is overwritten with real data from existing JS files.

- [ ] **Step 4: Inspect the output**

Run: `head -30 spec/support/config_schemas.rb`
Expected: Ruby hash literal with one entry per action (there are ~116 JS action entries, most with empty `configSchema` initially).

- [ ] **Step 5: Commit**

User runs:
```bash
git add lib/tasks/config_schemas.rake spec/support/config_schemas.rb
git commit -m "feat(codegen): add rake task to mirror JS configSchema to Ruby"
```

---

### Task 1.5: `SchemaReader` shared module

**Files:**
- Create: `app/services/code_generators/shared/schema_reader.rb`
- Test: `spec/services/code_generators/shared/schema_reader_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/code_generators/shared/schema_reader_spec.rb
require "rails_helper"
require Rails.root.join("spec/support/config_schemas")

RSpec.describe CodeGenerators::Shared::SchemaReader do
  describe ".read" do
    it "returns the schema for a known action" do
      stub_const("CodeGenerators::CONFIG_SCHEMAS", {
        "api_call" => [
          { key: "httpMethod", type: :select, label: "HTTP Method", required: true, options: %w[GET POST] }
        ]
      })
      expect(described_class.read("api_call")).to be_a(Array)
      expect(described_class.read("api_call").first[:key]).to eq("httpMethod")
    end

    it "returns [] for unknown action" do
      stub_const("CodeGenerators::CONFIG_SCHEMAS", {})
      expect(described_class.read("unknown")).to eq([])
    end
  end

  describe ".each_enum_branch" do
    it "yields each [key, value] for select fields with options" do
      stub_const("CodeGenerators::CONFIG_SCHEMAS", {
        "api_call" => [
          { key: "httpMethod", type: :select, options: %w[GET POST] },
          { key: "url", type: :text }
        ]
      })
      yielded = []
      described_class.each_enum_branch("api_call") { |k, v| yielded << [k, v] }
      expect(yielded).to eq([["httpMethod", "GET"], ["httpMethod", "POST"]])
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/shared/schema_reader_spec.rb -f doc`
Expected: FAIL with `uninitialized constant CodeGenerators::Shared::SchemaReader`.

- [ ] **Step 3: Write minimal implementation**

```ruby
# app/services/code_generators/shared/schema_reader.rb
# frozen_string_literal: true

module CodeGenerators
  module Shared
    module SchemaReader
      module_function

      def read(action_name)
        CONFIG_SCHEMAS.fetch(action_name.to_s, [])
      end

      def each_enum_branch(action_name)
        read(action_name).each do |field|
          next unless field[:type] == :select && field[:options].is_a?(Array)
          field[:options].each { |value| yield(field[:key], value) }
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/shared/schema_reader_spec.rb -f doc`
Expected: PASS (3 examples).

- [ ] **Step 5: Commit**

User runs:
```bash
git add app/services/code_generators/shared/schema_reader.rb spec/services/code_generators/shared/schema_reader_spec.rb
git commit -m "feat(codegen): add Shared::SchemaReader for configSchema introspection"
```

---

### Task 1.6: `"covers all configured branches"` shared example

**Files:**
- Create: `spec/support/shared_examples/covers_all_configured_branches.rb`
- Modify: `spec/rails_helper.rb` — require the new support file
- Test: one generator spec uses it (do in Task 1.7)

- [ ] **Step 1: Create the shared example**

```ruby
# spec/support/shared_examples/covers_all_configured_branches.rb
# frozen_string_literal: true

RSpec.shared_examples "covers all configured branches" do |action_name:, base_element: nil|
  it "generates non-stub code for every enum branch in configSchema (action: #{action_name})" do
    base = base_element || { "config" => {} }
    branches_checked = 0
    CodeGenerators::Shared::SchemaReader.each_enum_branch(action_name) do |field, value|
      element = base.deep_merge("config" => { field => value })
      generator = described_class.new(element, {})
      body = generator.generate_body
      next if body.nil? # intentional-nil generators (start/subflow/fork/join)
      expect(body).not_to match(/\A\s*#.*\n\s*true\s*\z/), "#{action_name}.#{field}=#{value}: stub fall-through"
      branches_checked += 1
    end
    # Don't fail if schema has no enum fields — that's legitimate (e.g., text-only generators).
  end
end
```

- [ ] **Step 2: Wire into rails_helper**

Modify `spec/rails_helper.rb` — add one line near existing support loaders (`Dir[Rails.root.join("spec/support/**/*.rb")].each { |f| require f }` likely already handles it; verify by reading the file first). If not, add:

```ruby
require Rails.root.join("spec/support/shared_examples/covers_all_configured_branches")
```

- [ ] **Step 3: Run rspec as smoke**

Run: `bundle exec rspec spec/services/code_generators/ -f progress 2>&1 | tail -5`
Expected: Existing specs still pass; new shared example is loaded but not yet invoked anywhere.

- [ ] **Step 4: Commit**

User runs:
```bash
git add spec/support/shared_examples/covers_all_configured_branches.rb spec/rails_helper.rb
git commit -m "feat(codegen): add 'covers all configured branches' shared example"
```

---

### Task 1.7: Extend `BaseGenerator` with new mixins & metadata DSL

**Files:**
- Modify: `app/services/code_generators/base_generator.rb`
- Modify: `app/services/code_generators/metadata_dsl.rb`
- Modify: `spec/services/code_generators/base_generator_spec.rb` (if exists; else create)

- [ ] **Step 1: Inspect `metadata_dsl.rb`**

Run: `cat app/services/code_generators/metadata_dsl.rb` via Read tool.

- [ ] **Step 2: Add `supports_timeout` DSL method**

Add to `MetadataDSL` (pattern matches existing DSL methods):

```ruby
# app/services/code_generators/metadata_dsl.rb (within the class body)
def supports_timeout(default:)
  @metadata[:supports_timeout] = { default: default }
end

def error_strategy_default(value)
  @metadata[:error_strategy_default] = value
end
```

- [ ] **Step 3: Update `base_generator.rb` to include the new mixins**

```ruby
# app/services/code_generators/base_generator.rb
# frozen_string_literal: true

require_relative "generator_interface"
require_relative "shared/ctx_reader"
require_relative "shared/error_wrapper"
require_relative "shared/config_field_reader"

module CodeGenerators
  class BaseGenerator
    include GeneratorInterface
    include Shared::CtxReader
    include Shared::ErrorWrapper
    include Shared::ConfigFieldReader

    def initialize(element, context)
      @element = element
      @context = context
      @config = extract_config
    end

    protected

    attr_reader :element, :context, :config

    def apply_wrappers(code)
      code = wrap_with_timeout(code)
      code = wrap_with_retry(code)
      wrap_with_guard(code)
    end

    def current_error_strategy
      fetch_enum("errorStrategy", %w[continue fail_track raise],
                 default: self.class._metadata[:error_strategy_default] || "continue")
    end

    private

    def extract_config
      raw = if self.class.generator_kind == :element_type
              element.fetch("properties", {})
            else
              element.fetch("config", {})
            end
      (raw || {}).with_indifferent_access
    end

    def wrap_with_timeout(code)
      # Prefer element["timeout"]; fall back to config["timeoutSeconds"]; fall back to metadata default
      timeout = element["timeout"].to_i
      if timeout <= 0
        timeout = config["timeoutSeconds"].to_i
      end
      if timeout <= 0
        supports = self.class._metadata[:supports_timeout]
        timeout = supports[:default].to_i if supports
      end
      return code unless timeout > 0

      <<~RUBY.chomp
        Timeout.timeout(#{timeout}) do
        #{code.indent(2)}
        end
      RUBY
    end

    def wrap_with_retry(code)
      retry_count = element["retryCount"].to_i
      return code unless retry_count > 0
      backoff = element["retryBackoff"] || "none"
      sleep_line = case backoff
                   when "linear"      then "\n    sleep(attempt)"
                   when "exponential" then "\n    sleep(2**attempt)"
                   else ""
                   end
      <<~RUBY.chomp
        retry_count = #{retry_count}
        attempt = 0
        begin
        #{code.indent(2)}
        rescue => e
          attempt += 1
          if attempt <= retry_count#{sleep_line}
            retry
          else
            raise e
          end
        end
      RUBY
    end

    def wrap_with_guard(code)
      guard = element["guardCondition"].to_s.strip
      return code if guard.empty?
      <<~RUBY.chomp
        if #{guard}
        #{code.indent(2)}
        else
          true
        end
      RUBY
    end
  end
end
```

- [ ] **Step 4: Add spec for new methods**

Create or extend `spec/services/code_generators/base_generator_spec.rb`:

```ruby
# spec/services/code_generators/base_generator_spec.rb
require "rails_helper"

RSpec.describe CodeGenerators::BaseGenerator do
  let(:subclass) do
    Class.new(described_class) do
      generator_metadata { supports_timeout default: 30 }
      def generate_body; "do_thing"; end
    end
  end

  describe "#wrap_with_timeout" do
    it "uses config['timeoutSeconds'] when element['timeout'] missing" do
      element = { "config" => { "timeoutSeconds" => 15 } }
      code = subclass.new(element, {}).send(:wrap_with_timeout, "body")
      expect(code).to include("Timeout.timeout(15)")
    end

    it "falls back to metadata default" do
      element = { "config" => {} }
      code = subclass.new(element, {}).send(:wrap_with_timeout, "body")
      expect(code).to include("Timeout.timeout(30)")
    end
  end

  describe "#current_error_strategy" do
    it "defaults to 'continue'" do
      element = { "config" => {} }
      expect(subclass.new(element, {}).send(:current_error_strategy)).to eq("continue")
    end

    it "honors configured value" do
      element = { "config" => { "errorStrategy" => "fail_track" } }
      expect(subclass.new(element, {}).send(:current_error_strategy)).to eq("fail_track")
    end

    it "rejects unknown values (falls to default)" do
      element = { "config" => { "errorStrategy" => "invalid" } }
      expect(subclass.new(element, {}).send(:current_error_strategy)).to eq("continue")
    end
  end
end
```

- [ ] **Step 5: Run specs**

Run: `bundle exec rspec spec/services/code_generators/base_generator_spec.rb -f doc`
Expected: PASS (5 examples) + existing generator specs still pass when run as a group (do a smoke `bundle exec rspec spec/services/code_generators/element_types/ -f progress`).

- [ ] **Step 6: Commit**

User runs:
```bash
git add app/services/code_generators/base_generator.rb app/services/code_generators/metadata_dsl.rb spec/services/code_generators/base_generator_spec.rb
git commit -m "feat(codegen): extend BaseGenerator with shared mixins and metadata DSL"
```

---

### Task 1.8: Batch-1 smoke

- [ ] **Step 1: Run the full generator spec suite**

Run: `bundle exec rspec spec/services/code_generators/ -f progress`
Expected: All existing tests pass (foundation doesn't break existing generators). Known pre-existing failures: 4 `query_count_branching_spec` cases + 3 CSS component specs — these are out of scope.

- [ ] **Step 2: Regenerate schema mirror**

Run: `bundle exec rake config_schemas:mirror`
Expected: Overwrites `spec/support/config_schemas.rb` with current JS state.

- [ ] **Step 3: Commit if mirror changed**

User runs:
```bash
git status spec/support/config_schemas.rb
# if changed:
git add spec/support/config_schemas.rb
git commit -m "chore(codegen): refresh config schema mirror"
```

---

## §T — Per-Generator Workflow Template

Every task in Batches 2–18 follows this template. Replace `<X>` with per-generator values from §P. Each generator is ONE commit.

### Per-Generator Steps

- [ ] **Step A: Read the three layers**

Run:
```
Read app/services/code_generators/element_types/<path>/<name>_generator.rb
Read spec/services/code_generators/element_types/<path>/<name>_generator_spec.rb
Read app/javascript/flowchart/constants/action_configs/<category>_actions.js
```

Locate the generator's existing `validate_config`, `generate_body`, and JS `configSchema`. Identify the per-generator diff from §P.

- [ ] **Step B: Update the JS `configSchema` first**

Edit `app/javascript/flowchart/constants/action_configs/<category>_actions.js`. Find the action object with `value: "<action>"`. Replace its `configSchema` array with the new array from §P.

Pattern for a select field:
```js
{
  key: "<keyName>",
  type: "select",
  label: "<Human Label>",
  default: "<defaultValue>",
  required: true,   // or omit
  options: [
    { value: "<v1>", label: "<L1>" },
    { value: "<v2>", label: "<L2>" }
  ]
}
```

Pattern for a conditional (visibleWhen) field:
```js
{
  key: "<keyName>",
  type: "text",
  label: "<Label>",
  visibleWhen: { field: "<parentField>", value: "<triggerValue>" }
}
```

Pattern for error strategy (applied to every generator that can fail at runtime):
```js
{
  key: "errorStrategy",
  type: "select",
  label: "On Error",
  default: "continue",
  options: [
    { value: "continue", label: "Continue (log to ctx)" },
    { value: "fail_track", label: "Fail track (Railway)" },
    { value: "raise", label: "Raise exception" }
  ]
}
```

- [ ] **Step C: Regenerate the schema mirror**

Run: `bundle exec rake config_schemas:mirror`
Expected: `spec/support/config_schemas.rb` updates to reflect JS changes.

- [ ] **Step D: Write failing tests for new branches**

Edit `spec/services/code_generators/element_types/<path>/<name>_generator_spec.rb`. For each new config branch in §P, add one `it` block asserting a distinctive token in the generated body.

Pattern:
```ruby
it "generates <branch description>" do
  el = { "config" => { "<field>" => "<value>", "resultVar" => "out" } }
  body = described_class.new(el, {}).generate_body
  expect(body).to include("<distinctive token>")
end
```

Also add the shared example line near the top:
```ruby
it_behaves_like "covers all configured branches", action_name: "<action_name>"
```

- [ ] **Step E: Run tests; expect NEW failures**

Run: `bundle exec rspec spec/services/code_generators/element_types/<path>/<name>_generator_spec.rb -f doc`
Expected: new cases FAIL (generator doesn't emit the new tokens yet); existing cases PASS (or FAIL only on renamed config keys — that's fine, we fix in Step F).

- [ ] **Step F: Update `validate_config` and `generate_body`**

Edit `app/services/code_generators/element_types/<path>/<name>_generator.rb`. Apply the per-generator diff from §P:
1. Rename any config keys per R5 (canonical names).
2. Update `validate_config` to accept/reject new enum values.
3. Add `case`/`if` branches in `generate_body` for every new value.
4. Apply R1 (nil-safe ctx) on collection reads using `safe_read(var, type: :array/:hash/:string)`.
5. Apply R2 (error wrapper) on risky ops by calling `wrap_with_error_strategy(inner, source: "<action>", strategy: current_error_strategy)`.
6. Apply R3 (timeout) by adding `generator_metadata { supports_timeout default: N }` if §P specifies.
7. Apply R4 (shared helpers) — route HTTP through `HttpRequestBuilder`, conditions through `ConditionBuilder`, operands through `OperandConverter`.

- [ ] **Step G: Run tests; expect PASS**

Run: `bundle exec rspec spec/services/code_generators/element_types/<path>/<name>_generator_spec.rb -f doc`
Expected: all cases PASS.

- [ ] **Step H: Smoke-test the full generator spec tree**

Run: `bundle exec rspec spec/services/code_generators/ -f progress 2>&1 | tail -20`
Expected: No new failures introduced (existing unrelated failures persist). If any cross-generator spec fails, check for R5 rename ripples.

- [ ] **Step I: Commit**

User runs:
```bash
git add app/services/code_generators/element_types/<path>/<name>_generator.rb \
        spec/services/code_generators/element_types/<path>/<name>_generator_spec.rb \
        app/javascript/flowchart/constants/action_configs/<category>_actions.js \
        spec/support/config_schemas.rb
git commit -m "feat(codegen): enrich <name>_generator for full config coverage"
```

---

## Batch 2: flow_control (14 generators)

Generators in this batch are element_types, not process/ step actions. JS schemas for these live in `app/javascript/flowchart/constants/schemas.js` (keyed by element-type name: `decision`, `switch`, `loop`, `timer`, etc.). Use §T steps A/B/C but target `schemas.js` instead of `action_configs/*.js`. The Ruby mirror rake task (`config_schemas:mirror`) must be extended to include these element-type schemas under the same `CodeGenerators::CONFIG_SCHEMAS` hash, keyed by element-type name (see Task 2.0).

### Task 2.0: Extend `config_schemas:mirror` to include `schemas.js`

- [ ] **Step 1: Update `lib/tasks/config_schemas.rake`**

Add a second scan block that parses `app/javascript/flowchart/constants/schemas.js` for element-type schemas. Each top-level key becomes a `CONFIG_SCHEMAS` entry (alongside the process-step entries already parsed from `action_configs/*.js`). Element-type field objects have the same shape.

- [ ] **Step 2: Regenerate and inspect**

Run: `bundle exec rake config_schemas:mirror`
Expected: `CONFIG_SCHEMAS` now contains both process actions (e.g., `"api_call"`) and element types (e.g., `"decision"`, `"loop"`).

- [ ] **Step 3: Commit**

User runs:
```bash
git add lib/tasks/config_schemas.rake spec/support/config_schemas.rb
git commit -m "feat(codegen): extend schema mirror to include element-type schemas"
```

---

### Task 2.1: `decision_generator` — verify nil-safety on operands
### Task 2.2: `switch_generator` — enforce `else_branch_index == cases.size` invariant; validate enum
### Task 2.3: `loop_generator` — for_each uses `ensure_array_expr`; while loops commit break on max
### Task 2.4: `timer_generator` — add `timeoutSeconds` hard bound to condition_wait
### Task 2.5: `signal_wait_generator` — add payload schema check
### Task 2.6: `saga_generator` — aggregate compensation errors into `ctx[:_compensation_errors]`
### Task 2.7: `transaction_generator` — add `timeoutSeconds`; validate isolation level per adapter
### Task 2.8: `parallel_for_each_generator` — deep-dup ctx snapshot; `ctx[:_thread_errors]`
### Task 2.9: `error_handler_generator` — route by error class pattern match
### Task 2.10: `end_generator` — support file/streaming response; support response headers
### Task 2.11: `fork_generator` — no-op; validate `joinStrategy` enum on join-paired fork
### Task 2.12: `join_generator` — validate `joinStrategy` enum
### Task 2.13: `start_generator` — no code change; verify `generate_body` returns nil
### Task 2.14: `subflow_generator` — no code change; verify `generate_body` returns nil

(For each task above, follow §T using per-generator diffs from §P section 2.)

---

## Batch 3a: data_operations — collection ops (13 generators)

- Task 3a.1: `map_collection_generator`
- Task 3a.2: `filter_collection_generator`
- Task 3a.3: `sort_collection_generator`
- Task 3a.4: `group_collection_generator`
- Task 3a.5: `partition_collection_generator`
- Task 3a.6: `chunk_collection_generator`
- Task 3a.7: `find_in_collection_generator`
- Task 3a.8: `uniq_collection_generator`
- Task 3a.9: `flatten_collection_generator`
- Task 3a.10: `zip_collections_generator`
- Task 3a.11: `reduce_collection_generator`
- Task 3a.12: `any_all_none_check_generator`
- Task 3a.13: `pluck_fields_generator`

Follow §T per task, diffs in §P section 3a.

---

## Batch 3b: data_operations — strings/regex/serialize (6 generators)

- Task 3b.1: `format_string_generator`
- Task 3b.2: `parse_data_generator`
- Task 3b.3: `serialize_data_generator`
- Task 3b.4: `regex_extract_generator`
- Task 3b.5: `string_manipulate_generator`
- Task 3b.6: `base64_encode_decode_generator`

Follow §T, diffs in §P section 3b.

---

## Batch 3c: data_operations — math/date/misc (12 generators)

- Task 3c.1: `calculate_generator`
- Task 3c.2: `math_operation_generator`
- Task 3c.3: `type_cast_generator`
- Task 3c.4: `date_time_calc_generator`
- Task 3c.5: `generate_id_generator`
- Task 3c.6: `assign_value_generator`
- Task 3c.7: `coalesce_value_generator`
- Task 3c.8: `compare_data_generator`
- Task 3c.9: `hash_manipulate_generator`
- Task 3c.10: `log_generator`
- Task 3c.11: `map_value_generator`
- Task 3c.12: `merge_data_generator`
- Task 3c.13: `transform_generator`

Follow §T, diffs in §P section 3c.

---

## Batch 4a: model_operations — read-path (7 generators)

- Task 4a.1: `find_model_generator`
- Task 4a.2: `query_models_generator`
- Task 4a.3: `count_records_generator`
- Task 4a.4: `check_existence_generator`
- Task 4a.5: `aggregate_query_generator`
- Task 4a.6: `pluck_fields_generator` — (if not moved to 3a; this is the model-ops pluck; different file)
- Task 4a.7: `batch_operation_generator`

Follow §T, diffs in §P section 4a.

---

## Batch 4b: model_operations — write-path (10 generators)

- Task 4b.1: `new_model_generator`
- Task 4b.2: `save_model_generator`
- Task 4b.3: `update_model_generator`
- Task 4b.4: `destroy_model_generator`
- Task 4b.5: `upsert_model_generator`
- Task 4b.6: `clone_model_generator`
- Task 4b.7: `bulk_import_generator`
- Task 4b.8: `soft_delete_model_generator`
- Task 4b.9: `transition_state_generator`
- Task 4b.10: `raw_sql_query_generator`

Follow §T, diffs in §P section 4b.

---

## Batch 5: security (9 generators)

- Task 5.1: `authenticate_generator`
- Task 5.2: `authorize_generator`
- Task 5.3: `encrypt_data_generator`
- Task 5.4: `decrypt_data_generator`
- Task 5.5: `generate_token_generator`
- Task 5.6: `hash_data_generator`
- Task 5.7: `mask_data_generator`
- Task 5.8: `sanitize_input_generator`
- Task 5.9: `verify_token_generator`

Follow §T, diffs in §P section 5.

---

## Batch 6: communication (4 generators)

- Task 6.1: `api_call_generator`
- Task 6.2: `send_webhook_generator`
- Task 6.3: `send_email_generator`
- Task 6.4: `notify_generator`

Follow §T, diffs in §P section 6.

---

## Batch 7: caching (4 generators)

- Task 7.1: `cache_read_generator`
- Task 7.2: `cache_write_generator`
- Task 7.3: `cache_fetch_generator`
- Task 7.4: `cache_delete_generator`

Follow §T, diffs in §P section 7.

---

## Batch 8: concurrency (2 generators)

- Task 8.1: `acquire_lock_generator`
- Task 8.2: `release_lock_generator`

Follow §T, diffs in §P section 8.

---

## Batch 9: file_operations (7 generators)

- Task 9.1: `download_file_generator`
- Task 9.2: `upload_file_generator`
- Task 9.3: `parse_csv_generator`
- Task 9.4: `generate_csv_generator`
- Task 9.5: `compress_files_generator`
- Task 9.6: `decompress_files_generator`
- Task 9.7: `generate_file_generator`

Follow §T, diffs in §P section 9.

---

## Batch 10: human_workflow (4 generators)

- Task 10.1: `approval_gate_generator`
- Task 10.2: `assign_task_generator`
- Task 10.3: `escalation_generator`
- Task 10.4: `user_input_request_generator`

Follow §T, diffs in §P section 10.

---

## Batch 11: realtime (2 generators)

- Task 11.1: `broadcast_generator`
- Task 11.2: `publish_event_generator`

Follow §T, diffs in §P section 11.

---

## Batch 12: resilience (4 generators, bug-fix heavy)

- Task 12.1: `rate_limiter_generator`
- Task 12.2: `retry_with_backoff_generator`
- Task 12.3: `circuit_breaker_generator`
- Task 12.4: `idempotency_check_generator`

Follow §T, diffs in §P section 12.

---

## Batch 13: response (2 generators)

- Task 13.1: `render_response_generator`
- Task 13.2: `redirect_response_generator`

Follow §T, diffs in §P section 13.

---

## Batch 14: scheduling_time (3 generators)

- Task 14.1: `business_hours_check_generator`
- Task 14.2: `deadline_check_generator`
- Task 14.3: `timezone_convert_generator`

Follow §T, diffs in §P section 14.

---

## Batch 15: service_invocation (1 generator)

- Task 15.1: `invoke_service_generator`

Follow §T, diff in §P section 15.

---

## Batch 16: utility (8 generators)

- Task 16.1: `ai_inference_generator`
- Task 16.2: `audit_log_generator`
- Task 16.3: `template_render_generator`
- Task 16.4: `i18n_translate_generator`
- Task 16.5: `currency_convert_generator`
- Task 16.6: `geolocation_lookup_generator`
- Task 16.7: `barcode_generate_generator`
- Task 16.8: `qr_code_generate_generator`

Follow §T, diffs in §P section 16.

---

## Batch 17: validation (2 generators)

- Task 17.1: `build_contract_generator`
- Task 17.2: `validate_contract_generator`

Follow §T, diffs in §P section 17.

---

## Batch 18: background (2 generators)

- Task 18.1: `enqueue_job_generator`
- Task 18.2: `schedule_job_generator`

Follow §T, diffs in §P section 18.

---

## Batch 19: Final — integration smoke tests per category

### Task 19.1 — 19.17: One smoke test per category

For each of the 17 categories, create `spec/integration/code_generators/<category>_smoke_spec.rb`:

```ruby
require "rails_helper"
RSpec.describe "<Category> generators smoke", type: :integration do
  described_class_list = [
    # list of all generator classes in this category
  ]

  described_class_list.each do |klass|
    it "generate_body for #{klass} parses as valid Ruby" do
      element = { "config" => klass.sample_input }
      body = klass.new(element, {}).generate_body
      next if body.nil?
      expect { RubyVM::InstructionSequence.compile(body) }.not_to raise_error
    end
  end
end
```

Follow §T per category. Final commit after all 17 categories have smoke tests.

---

## Batch 20: CI drift check

### Task 20.1: Add CI job for `config_schemas:check`

- [ ] **Step 1: Inspect CI config**

Run: `ls .github/workflows/` or `ls .circleci/` to find CI config.

- [ ] **Step 2: Add the job**

Append to the test workflow:

```yaml
- name: Verify config schema mirror
  run: bundle exec rake config_schemas:check
```

- [ ] **Step 3: Commit**

User runs:
```bash
git add .github/workflows/<file>.yml
git commit -m "ci(codegen): verify config_schemas mirror in sync"
```

---

## §P — Per-Generator Diff Blocks

Each block below tells the engineer what changes to apply to the three files for a given generator. Blocks are in batch/task order.

**Convention:**
- **Current config keys** = what the Ruby generator reads today.
- **New config keys** = the target set (for R5 rename + new fields). Existing keys renamed per R5 are flagged with `← renamed from X`.
- **New code branches** = cases `generate_body` must emit that it doesn't today.
- **Rubric application** = which of R1–R6 apply (R2 and R3 opt-in; R1, R4, R5, R6 always-on).

Most diff blocks are short (2–6 new fields + 0–4 new branches). Longer blocks for richer generators.

---

### §P.2 — flow_control diffs

#### 2.1 decision_generator
- Current fields: `condition`, `_route_index`, `_connection_conditions`
- New fields: + `errorStrategy`
- New branches: none (already rich); apply R1 (nil-safe operand reads)
- Rubric: R1, R2 (optional; wrap only the condition eval in rescue), R6
- JS: decision is an element type, not a process step — update `action_registry.js` or the decision element's metadata. If no configSchema structure exists for elements, note in comment and skip JS change; validate_config stays the source of truth. (Check during execution.)

#### 2.2 switch_generator
- Current fields: `sourceVariable`, `cases`, `_route_index`
- New fields: + `defaultBranchIndex` (optional, defaults to cases.size)
- New branches: emit `:branch_N` where N defaults to `cases.size` but can be overridden by `defaultBranchIndex`
- Validate: reject `defaultBranchIndex < 0 || >= cases.size+1`
- Rubric: R1 (nil-safe on `ctx[:source]`), R6

#### 2.3 loop_generator
- Current fields: `loopType`, `condition`, `iterations`, `collection`, `itemVariable`, `indexVariable`
- R5 rename: `itemVariable`, `indexVariable` already canonical. No rename.
- New branches: for_each now uses `ensure_array_expr(collection_ruby)` instead of `is_a?(Array) ? ... : [...]`
- Rubric: R1, R6

#### 2.4 timer_generator
- Current fields: `delayType`, `duration`, `durationUnit`, `waitCondition`
- New fields: + `conditionTimeoutSeconds` (for `until_condition`; default 600) + `errorStrategy`
- New branches: `until_condition` loop now has `Time.current + conditionTimeoutSeconds` deadline; if exceeded, behavior per `errorStrategy`.
- Rubric: R1, R2, R3 (metadata `supports_timeout default: 600`), R6

#### 2.5 signal_wait_generator
- Current fields: `signalName`, `waitMode`, `timeoutSeconds`, `timeoutAction`
- New fields: + `payloadSchema` (optional JSON-schema expression; validated in generated code)
- New branches: when payloadSchema present, generate `JSON::Validator.validate!(schema, ctx[:signal_result])` inside rescue
- Rubric: R1, R2, R6

#### 2.6 saga_generator
- Current fields: `compensationMode`, `compensationTimeout`
- New fields: + `errorAggregation` (select `collect` | `first` | `none`, default `collect`)
- New branches: compensation rescue writes to `ctx[:_compensation_errors]` when `errorAggregation=collect`; re-raises first when `first`
- Rubric: R1, R6

#### 2.7 transaction_generator
- Current fields: `isolationLevel`, `requiresNew`
- New fields: + `timeoutSeconds` (default 60) + `errorStrategy`
- New branches: wrap transaction in `Timeout.timeout`; surface `ActiveRecord::StatementTimeout` via `_last_error`
- Rubric: R2, R3 (metadata `supports_timeout default: 60`), R6

#### 2.8 parallel_for_each_generator
- Current fields: `sourceVariable`, `itemVariable`, `concurrency`, `resultVariable`
- R5 rename: `resultVariable` → `resultVar`
- New fields: + `errorAggregation` (select `collect` | `first` | `ignore`) + `errorStrategy`
- New branches: ctx_copy via `Marshal.load(Marshal.dump(ctx.to_h))` (deep dup); thread errors collected to `ctx[:_thread_errors]`.
- Rubric: R1 (source), R2, R6

#### 2.9 error_handler_generator
- Current fields: `errorTypes`, `fallbackAction`
- New fields: + `errorClassPattern` (regex string; default matches all) + `customMessage` (optional)
- New branches: case-match on `e.class.name` against pattern; log `customMessage` if set
- Rubric: R6

#### 2.10 end_generator
- Current fields: `responseType`, `returnValue`, `httpStatus`, `responseBody`
- New fields: + `responseHeaders` (key_value_list) + `streamingBody` (boolean) + `responseFormat` (select `json|html|text|redirect|stream`)
- New branches: `stream` sets `ctx[:http_stream] = true, ctx[:http_body_enumerator] = <ruby expr>`; headers applied via `ctx[:http_headers]`
- Rubric: R1, R6

#### 2.11 fork_generator
- Current fields: none
- No changes (pass-through). Validate `joinStrategy` enum reference if fork has a paired join config field; else no-op.
- Rubric: R6 (trivially: no enum fields)

#### 2.12 join_generator
- Current fields: `joinStrategy`
- New fields: validate enum `wait_all | wait_any | wait_n`
- Rubric: R6

#### 2.13 start_generator — no change
#### 2.14 subflow_generator — no change

---

### §P.3a — data_operations collection ops

#### 3a.1 map_collection_generator
- Current fields: `sourceVariable`, `targetVariable`, `fieldMappings: [{ from, to }]`
- R5 rename: none (already canonical)
- New fields: + `fieldMappings[*].from` supports dot-notation (e.g., `"user.name"`) + `keyFormat` (select `symbol|string`, default `symbol`) + `errorStrategy`
- New branches:
  - `from` contains dot → generate `item.dig(:user, :name)` via `OperandConverter`
  - `keyFormat == "string"` → emit `{ "label" => ... }`
  - empty `ctx[:<source>]` → emit `[]` short-circuit
- Rubric: R1 (`safe_read(source, type: :array)`), R4 (OperandConverter for `from`), R6

#### 3a.2 filter_collection_generator
- Current fields: `sourceVariable`, `targetVariable`, `field`, `operator`, `value`
- New fields: + `conditions: [{field, operator, value}]` (multi-field AND), + `conditionOperator` (select `AND|OR`) + `errorStrategy`
- New branches: when `conditions.present?`, use `ConditionBuilder` to build the predicate; single `field+operator+value` still supported for backward compat within this spec only (no external back-compat needed).
- Rubric: R1, R4, R6

#### 3a.3 sort_collection_generator
- Current fields: `sourceVariable`, `targetVariable`, `field`, `direction`
- R5 rename: none
- New fields: + `sortFields: [{ field, direction }]` (multi-field) + `nullHandling` (select `first|last|error`)
- New branches: multi-field → `.sort_by { |r| [r.dig(...), r.dig(...)] }`; nullHandling applied per-field
- Rubric: R1, R4 (OperandConverter on nested fields), R6

#### 3a.4 group_collection_generator
- Current fields: `sourceVariable`, `targetVariable`, `field`
- New fields: + `customKeyExpression` (alternative to `field`) + nested path on `field`
- New branches: when `customKeyExpression` present, `group_by { |r| <expr> }`; else dig
- Rubric: R1, R4, R6

#### 3a.5 partition_collection_generator
- Current fields: `sourceVariable`, `truthyVar`, `falsyVar`, `field`, `operator`, `value`
- New fields: + `conditions: [...]` (multi-field) per ConditionBuilder
- New branches: as filter_collection
- Rubric: R1, R4, R6

#### 3a.6 chunk_collection_generator
- Current fields: `sourceVariable`, `targetVariable`, `chunkSize`
- New fields: + `strategy` (select `by_size|by_value`) + `valueExpression` (for by_value)
- New branches: `by_value` → `chunk_while { |a, b| <expr> }`
- Rubric: R1, R6

#### 3a.7 find_in_collection_generator
- Current fields: `sourceVariable`, `resultVariable`, `field`, `value`, `indexVariable`
- R5 rename: `resultVariable` → `resultVar`
- New fields: + `multiValue` (select `first|all|count`) + nested path on field
- New branches: `all` → `.select`; `count` → `.count { }`
- Rubric: R1, R4, R6

#### 3a.8 uniq_collection_generator
- Current fields: `sourceVariable`, `targetVariable`, `field`
- New fields: + nested path on field
- New branches: dot-notation field → `uniq { |r| r.dig(...) }`
- Rubric: R1, R4, R6

#### 3a.9 flatten_collection_generator
- Current fields: `sourceVariable`, `targetVariable`, `depth`
- New fields: none; apply R1
- New branches: ensure non-array items wrapped via `ensure_array_expr`
- Rubric: R1, R6

#### 3a.10 zip_collections_generator
- Current fields: `leftVariable`, `rightVariable`, `resultVariable`, `mode`
- R5 rename: `resultVariable` → `resultVar`
- New fields: + `shapeHandling` (select `truncate|pad_nil|error`)
- New branches: `pad_nil` → `.zip(...)` pads; `truncate` → `.zip(short_side)`; `error` → raises on length mismatch
- Rubric: R1, R2, R6

#### 3a.11 reduce_collection_generator
- Current fields: `sourceVariable`, `operation`, `initialValue`, `fieldName`, `customExpression`, `resultVar`
- New fields: + `customExpression` now has `|acc, item, idx|` signature; document in placeholder
- New branches: `each_with_index.reduce(initial) { |acc, (item, idx)| <expr> }`
- Rubric: R1, R6

#### 3a.12 any_all_none_check_generator
- Current fields: `sourceVariable`, `resultVar`, `check` (any|all|none), `field`, `operator`, `value`
- New fields: + `conditions: [...]` multi-field
- New branches: delegate to ConditionBuilder when conditions present
- Rubric: R1, R4, R6

#### 3a.13 pluck_fields_generator (data_operations)
- Current fields: `sourceVariable`, `fields`, `resultVar`
- New fields: + nested path support on fields (dot-notation) + `keyFormat` (symbol|string)
- New branches: nested → `r.dig(:a, :b)`
- Rubric: R1, R4, R6

---

### §P.3b — data_operations strings/regex/serialize

#### 3b.1 format_string_generator
- Current fields: `template`, `resultVar`
- New fields: + `variablePaths: [{ placeholder, path }]` enabling `{{user.name}}` → OperandConverter resolution
- New branches: when variablePaths present, substitute via OperandConverter-derived paths; else legacy gsub
- Rubric: R1, R4, R6

#### 3b.2 parse_data_generator
- Current fields: `sourceVariable`, `format` (json|csv), `resultVar`, `headers`
- New fields: + `format` enum `json|csv|xml|yaml` + `errorStrategy`
- New branches: `xml` → `Hash.from_xml`; `yaml` → `YAML.safe_load`
- Rubric: R1, R2, R6

#### 3b.3 serialize_data_generator
- Current fields: `sourceVariable`, `format`, `resultVar`, `prettyPrint`, `rootElement`
- New fields: + `encoding` (text) + `csvNestedSeparator` (default `"."`)
- New branches: csv of nested hashes flattens via separator
- Rubric: R1, R2, R6

#### 3b.4 regex_extract_generator
- Current fields: `sourceVariable`, `pattern`, `operation`, `captureGroup`, `replacement`, `resultVar`
- New fields: + `flags` (select `i|m|x|none`) + `errorStrategy`
- New branches: emit `Regexp.new(pattern, flags)` at runtime; rescue compilation errors
- Rubric: R1, R2, R6

#### 3b.5 string_manipulate_generator
- Current fields: `sourceVariable`, `operation` (13 ops), `arg1`, `arg2`, `resultVar`
- New fields: + operations `unicode_normalize`, `html_escape`, `html_unescape` + `encoding` (utf-8 default)
- New branches: normalization branch; html_escape branch
- Rubric: R1, R6

#### 3b.6 base64_encode_decode_generator
- Current fields: `sourceVariable`, `mode` (encode|decode), `variant` (strict|urlsafe), `resultVar`
- New fields: + `errorStrategy` (decode can fail)
- Rubric: R1, R2, R6

---

### §P.3c — data_operations math/date/misc

#### 3c.1 calculate_generator
- Current fields: `operation`, `collectionExpression`, `fieldName`, `resultVar`, `customExpression`
- New fields: + `emptyCollectionBehavior` (select `zero|nil|error`, default `zero`) + `nullFilter` (boolean)
- New branches: avg handles empty; null filter skips nil values; error branch raises
- Rubric: R1, R2, R6

#### 3c.2 math_operation_generator
- Current fields: `operation`, `operand1`, `operand2`, `resultVar`
- New fields: + `divByZeroPolicy` (select `zero|infinity|nan|error`) + `precision` (integer, for float rounding)
- New branches: per policy
- Rubric: R1, R6

#### 3c.3 type_cast_generator
- Current fields: `sourceVariable`, `targetType`, `resultVar`, `onError`, `defaultValue`, `format`
- New fields: + `timezoneAware` (boolean, for date) + `strictBoolean` (boolean)
- New branches: when strictBoolean, only true/"true"/1 → true; else ActiveModel::Type::Boolean
- Rubric: R1, R2, R6

#### 3c.4 date_time_calc_generator
- Current fields: `operation`, `sourceVariable`, `amount`, `unit`, `timezone`, `format`, `resultVar`
- New fields: + `dstPolicy` (select `preserve_wall|preserve_utc`) + `timezoneAware` (bool)
- New branches: parse with `in_time_zone(timezone)`; dst policy determines add/subtract behavior
- Rubric: R1, R2, R6

#### 3c.5 generate_id_generator
- Current fields: `idType` (uuid|ulid|nanoid|custom), `customPattern`, `resultVar`
- New fields: + `alphabet` (for nanoid) + `size` (int, for nanoid)
- New branches: nanoid uses configurable alphabet/size; ULID uses spec-compliant encoding (`ULID.generate` if gem present else fallback)
- Rubric: R1, R6

#### 3c.6 assign_value_generator
- Current fields: `targetVar`, `valueType`, `stringValue`, `integerValue`, `booleanValue`, `valueExpression`
- R5 rename: `targetVar` → `resultVar`
- New fields: + valueType enum `string|integer|float|boolean|array|hash|expression|null`
- New branches: array → literal array constructor; hash → literal hash; null → `nil`; float → `.to_f`
- Rubric: R1, R6

#### 3c.7 coalesce_value_generator
- Current fields: `candidates[]`, `resultVar`
- New fields: + `predicate` (select `nil|blank|false_or_nil`) to decide what triggers fallthrough
- New branches: blank uses `.blank?`; false_or_nil uses `!value`
- Rubric: R1, R6

#### 3c.8 compare_data_generator
- Current fields: `leftVariable`, `rightVariable`, `ignoreKeys`, `resultVar`
- New fields: + `mode` (select `keys|values|deep`) + `errorStrategy`
- New branches: values → Hash#slice + compare vals; deep → recursive diff
- Rubric: R1, R2, R6

#### 3c.9 hash_manipulate_generator
- Current fields: `sourceVariable`, `operation` (pick|omit|keys|values|deep_merge|diff|rename|invert), `targetKeys`, `newKeys`, `renameMap`, `resultVar`
- New fields: + nested path on targetKeys (dot-notation) + `caseInsensitive` (bool)
- New branches: nested pick digs through structure
- Rubric: R1, R4, R6

#### 3c.10 log_generator
- Current fields: `mode` (log|audit), `level`, `message`, `source`, `auditAction`, `metadata`
- New fields: + `contextFields` (key_value_list) where value can be a ctx path (resolved via OperandConverter) + `errorStrategy`
- New branches: audit mode now falls back to logger if AuditLog model undefined (defined?-guard)
- Rubric: R1, R2, R4, R6

#### 3c.11 map_value_generator
- Current fields: `sourceVariable`, `lookupTable`, `defaultValue`, `resultVar`
- New fields: + `matchMode` (select `exact|regex|range`) + `rules: [{ pattern, value }]` for regex/range
- New branches: regex mode iterates rules with Regexp.match?; range mode uses Range#cover?
- Rubric: R1, R6

#### 3c.12 merge_data_generator
- Current fields: `sourceVariable`, `mergeVariable`, `strategy` (shallow|deep), `conflictResolution`, `resultVar`
- New fields: + `arrayMerge` (select `replace|concat|unique_union`) + `errorStrategy`
- New branches: deep merge uses `deep_merge { |_, l, r| <arrayMerge> }`
- Rubric: R1, R2, R6

#### 3c.13 transform_generator
- Current fields: `operation` (mapFields|formatDate|convertType), `params`
- Bugs to fix: references undefined `element` in `generate_body`; hardcoded date format.
- New fields: + `params.fieldMappings[*].from` supports dot-notation + `params.format` configurable
- New branches: mapFields uses OperandConverter; formatDate parses via `Date.strptime` per config
- Rubric: R1, R2, R4, R6

---

### §P.4a — model_operations read-path

#### 4a.1 find_model_generator
- Current fields: `findStrategy` (find|findBy|where), `resultVar`, `findField`, `findValue`
- New fields: + `findStrategy` enum extended: `find|find_by|find_by!|where_first|where_many` (rename where → where_many for clarity)
- New fields: + `scopeByCustomerId` (boolean, default true) + `errorStrategy`
- New branches: find_by (no bang) vs find_by! (raises); where_first returns .first; where_many returns relation
- Rubric: R1, R2, R4, R6

#### 4a.2 query_models_generator (already rich)
- Current fields: `queryType`, `resultVar`, `joins`, `computedFields`, `conditions`, `orderBy`, `orderDirection`, `pageSize`, `pageVariable`, `scopeName`, `scopeArgs`, `sqlExpression`
- New fields: + `scopeByCustomerId` (enforce; default true) + `errorStrategy`
- New branches: validate entity_ids at runtime via `Entity.exists?(id)` (defined?-guard)
- Rubric: R1, R2, R4, R6

#### 4a.3 count_records_generator
- Current fields: `conditions`, `distinct`, `distinctField`, `resultVar`
- New fields: + `conditions` uses ConditionBuilder
- Rubric: R1, R2, R4, R6

#### 4a.4 check_existence_generator
- Current fields: `method` (exists|any|none), `conditions`, `resultVar`
- New fields: + conditions via ConditionBuilder
- Rubric: R1, R2, R4, R6

#### 4a.5 aggregate_query_generator
- Current fields: `operation` (sum|avg|min|max|count), `field`, `conditions`, `groupFields`, `havingClause`, `resultVar`
- New fields: + `havingConditions` (structured via ConditionBuilder) + `errorStrategy`
- Rubric: R1, R2, R4, R6

#### 4a.6 pluck_fields_generator (model_operations)
- Current fields: `fields`, `conditions`, `distinct`, `resultVar`
- New fields: + conditions via ConditionBuilder
- Rubric: R1, R2, R4, R6

#### 4a.7 batch_operation_generator
- Current fields: `operation` (each|update_all|destroy_all), `batchSize`, `updateFields`, `conditions`
- New fields: + `each` supports a `stepBody` expression + conditions via ConditionBuilder
- Rubric: R1, R2, R4, R6

---

### §P.4b — model_operations write-path

#### 4b.1 new_model_generator
- Current fields: `attributes`, `resultVar`
- New fields: + `scopeByCustomerId` (boolean, default true) + `attributes` values resolved via OperandConverter
- Rubric: R1, R2, R4, R6

#### 4b.2 save_model_generator
- Current fields: `modelVariable`, `strategy` (saveAll|saveOnly)
- New fields: + `strategy` enum `save|save!|saveOnly|saveAll` + `errorStrategy`
- New branches: save! raises; save returns boolean (honored by errorStrategy)
- Rubric: R1, R2, R6

#### 4b.3 update_model_generator
- Current fields: `modelVariable`, `fieldMappings`
- New fields: + `updateMethod` (select `update|update!|update_columns`) + attributes via OperandConverter
- New branches: update_columns skips validations/callbacks
- Rubric: R1, R2, R4, R6

#### 4b.4 destroy_model_generator
- Current fields: `modelVariable`, `strategy` (destroy|softDelete)
- New fields: + `strategy` enum `destroy|destroy!|delete|softDelete` + soft delete field/value configurable
- Rubric: R1, R2, R6

#### 4b.5 upsert_model_generator
- Current fields: `matchFields`, `attributes`, `capturedCreatedVar`
- New fields: + `method` (select `find_or_create_by|find_or_initialize|upsert_all`) + attributes/matchFields via OperandConverter
- Rubric: R1, R2, R4, R6

#### 4b.6 clone_model_generator
- Current fields: `sourceVariable`, `resultVar`, `attributeOverrides`
- New fields: + `deepClone` (boolean) + `cloneAssociations` (select `none|has_many|all`) + attributes via OperandConverter
- New branches: deep → `deep_dup`; associations → iterate and dup
- Rubric: R1, R2, R4, R6

#### 4b.7 bulk_import_generator
- Current fields: `recordsVariable`, `batchSize`, `onDuplicate`
- New fields: + `onDuplicate` enum `skip|update_on_duplicate|raise` + `uniqueBy` (array of fields)
- New branches: `update_on_duplicate` → `upsert_all(records, unique_by:, on_duplicate: :update_all)`
- Rubric: R1, R2, R6

#### 4b.8 soft_delete_model_generator
- Current fields: `modelVariable`, `deletedField`, `deletedValueType`
- New fields: + `valueExpression` (arbitrary expression) + `deletedField` required
- Rubric: R1, R2, R4, R6

#### 4b.9 transition_state_generator
- Current fields: `modelVariable`, `stateField`, `newState`, `allowedFromStates`
- New fields: + `useStateMachine` (boolean; detect AASM/state_machine constants)
- New branches: state machine path → `model.send(transition_event!)`
- Rubric: R1, R2, R6

#### 4b.10 raw_sql_query_generator
- Current fields: `sqlExpression`, `bindings`, `resultVar`
- New fields: + `bindings` uses `ActiveRecord::Base.sanitize_sql_array([sql, *bindings])`; reject `#{` in sqlExpression
- Rubric: R1, R2, R6

---

### §P.5 — security diffs

#### 5.1 authenticate_generator
- Current fields: `authMethod` (password|token|apiKey|jwt), `failAction`
- New fields: + `constantTimeCompare` (boolean, default true) + `errorStrategy`
- New branches: constant-time via `ActiveSupport::SecurityUtils.secure_compare`; JWT validates signature+exp+iss via `JWT.decode`
- Rubric: R1, R2, R4, R6

#### 5.2 authorize_generator
- Current fields: `method` (role|policy|custom), `roleExpression`, `requiredRole`, `policyClass`, `policyAction`, `customExpression`
- New fields: + `customExpression` via OperandConverter + `policyClass` constant-check via `defined?`
- Rubric: R1, R2, R4, R6

#### 5.3 encrypt_data_generator
- Current fields: `sourceVariable`, `mode` (encrypt|decrypt), `resultVar`
- New fields: + `secretSource` (select `credentials|env|config`) + `secretPath` (dot-path into credentials) + `algorithm` enum
- Rubric: R1, R2, R6

#### 5.4 decrypt_data_generator
- Current fields: `sourceVariable`, `algorithm`, `ivExpression`, `authTagExpression`, `resultVar`
- New fields: + `errorStrategy` + `encoding` (select `base64|hex|binary`)
- Rubric: R1, R2, R6

#### 5.5 generate_token_generator
- Current fields: `tokenType`, `length`, `expiresIn`, `payload`, `resultVar`
- New fields: + expiresIn accepts `Duration` string (e.g., `"1h"`) parsed via `ActiveSupport::Duration.parse`
- Rubric: R1, R2, R6

#### 5.6 hash_data_generator
- Current fields: `sourceVariable`, `algorithm`, `salt`, `cost`, `resultVar`
- New fields: + `argon2` branch (if `Argon2` constant defined)
- Rubric: R1, R2, R6

#### 5.7 mask_data_generator
- Current fields: `sourceVariable`, `maskType`, `maskChar`, `resultVar`
- New fields: + bounds-check generated code; Unicode-aware slicing via `.chars`
- Rubric: R1, R6

#### 5.8 sanitize_input_generator
- Current fields: `sourceVariable`, `mode`, `allowedTags`, `resultVar`
- New fields: + `sanitizer` (select `full|white_list|scrubber`)
- Rubric: R1, R2, R6

#### 5.9 verify_token_generator
- Current fields: `sourceVariable`, `secret`, `algorithm`, `requiredClaims`, `resultVar`
- New fields: + `errorStrategy` + requiredClaims supports nested paths
- Rubric: R1, R2, R4, R6

---

### §P.6 — communication diffs

#### 6.1 api_call_generator
- Current fields: `httpMethod`, `url`, `responseVar`, `authType`, `headers`, `bodyTemplate`, `authToken`/`authUsername`/...
- R5 rename: `responseVar` → `resultVar`
- New fields: + `timeoutSeconds` (default 30) + `retryCount`, `retryBackoff` (already on element), `errorStrategy`, `responseFormat` (select `json|text|binary`)
- New branches: success/failure per HTTP status routed by errorStrategy; non-JSON bodies stored as raw
- Rubric: R1, R2, R3 (metadata), R4 (HttpRequestBuilder), R6

#### 6.2 send_webhook_generator
- Current fields: `url`, `payload`, `hmacSecret`, `headers`, `responseVar`
- R5 rename: `responseVar` → `resultVar`
- New fields: + `timeoutSeconds` + `retryCount` + `errorStrategy` + `signatureHeader` (default `X-Hub-Signature-256`) + `signatureAlgorithm` (select `sha256|sha1`)
- Rubric: R1, R2, R3, R4, R6

#### 6.3 send_email_generator
- Current fields: `toExpression`, `subject`, `bodyTemplate`, `mailerMethod`, `mailerClass`, `mailerAction`
- New fields: + `cc`, `bcc`, `from`, `replyTo`, `htmlBody`, `textBody`, `attachments: [{ path, filename }]` + `errorStrategy`
- New branches: when custom mailer, pass keyword args collected from config
- Rubric: R1, R2, R6

#### 6.4 notify_generator
- Current fields: `channel` (email|slack|sms), `recipient`, `message`
- New fields: + `slackWebhookUrl` / `twilioConfig` (key_value_list) + `pushNotification` channel branch + `fallbackChannel`
- New branches: slack → HttpRequestBuilder POST to webhook; sms → Twilio HTTP; push → FCM HTTP
- Rubric: R1, R2, R4, R6

---

### §P.7 — caching diffs

#### 7.1 cache_read_generator
- Current fields: `cacheKey`, `targetVariable`, `ttl`, `fallbackExpression`
- R5 rename: `targetVariable` → `resultVar`
- New fields: + `errorStrategy`
- Rubric: R1, R2, R6

#### 7.2 cache_write_generator
- Current fields: `cacheKey`, `sourceVariable`, `ttl`, `action` (write|delete)
- New fields: + action enum `write|write_if_absent|delete` + errorStrategy
- New branches: write_if_absent → `Rails.cache.write(..., unless_exist: true)`
- Rubric: R1, R2, R6

#### 7.3 cache_fetch_generator
- Current fields: `key`, `ttl`, `fallbackExpression`, `outputKey`
- R5 rename: `outputKey` → `resultVar`; `key` → `cacheKey`
- New fields: + errorStrategy
- Rubric: R1, R2, R4 (OperandConverter on fallbackExpression), R6

#### 7.4 cache_delete_generator
- Current fields: `cacheKey`, `mode` (exact|pattern)
- New fields: + errorStrategy; emit `defined?(Rails.cache.delete_matched)`-guard for pattern
- Rubric: R1, R2, R6

---

### §P.8 — concurrency diffs

#### 8.1 acquire_lock_generator
- Current fields: `lockType`, `lockKey`, `lockKeyVariable`, `ttl`, `retryCount`, `retryDelay`, `failAction`, `modelVariable`, `reloadAfterLock`
- New fields: + `acquireTimeoutSeconds` (new; default 30) + `backoffStrategy` (select `constant|exponential`) + `jitter` (boolean)
- New branches: advisory with timeout uses `Timeout.timeout(n) { loop ... pg_try_advisory_lock }`; redis uses exponential if configured
- Rubric: R1, R2, R3, R6

#### 8.2 release_lock_generator
- Current fields: `lockKey`
- New fields: + `lockType` (must mirror acquire); validate token held
- New branches: advisory → `pg_advisory_unlock(ctx[:_advisory_lock_id])`; redis → delete only if token matches
- Rubric: R1, R2, R6

---

### §P.9 — file_operations diffs

#### 9.1 download_file_generator
- Current fields: `url`, `destinationVar`, `headers`
- R5 rename: `destinationVar` → `resultVar`
- New fields: + `timeoutSeconds` (default 120) + `maxRedirects` + `sslVerify` (bool) + `errorStrategy`
- Rubric: R1, R2, R3, R4, R6

#### 9.2 upload_file_generator
- Current fields: `recordExpression`, `attachmentName`, `fileVariable`, `filenameVariable`
- New fields: + `errorStrategy`
- Rubric: R1, R2, R6

#### 9.3 parse_csv_generator
- Current fields: `sourceVariable`, `resultVar`, `headers`, `delimiter`
- New fields: + `encoding` (default utf-8) + `quoteChar` + `errorStrategy`
- Rubric: R1, R2, R6

#### 9.4 generate_csv_generator
- Current fields: `sourceVariable`, `resultVar`, `columns`, `delimiter`
- New fields: + `encoding` + `headers` (bool) + `nestedSeparator`
- Rubric: R1, R2, R6

#### 9.5 compress_files_generator
- Current fields: `sourceVariable`, `resultVar`, `format` (zip)
- New fields: + `compressionLevel` (int) + `errorStrategy`
- New branches: generate `defined?(Zip)`-guard
- Rubric: R1, R2, R6

#### 9.6 decompress_files_generator
- Current fields: `sourceVariable`, `resultVar`, `filter`
- New fields: + path traversal protection (reject `..`) + `errorStrategy`
- Rubric: R1, R2, R6

#### 9.7 generate_file_generator
- Current fields: `format` (csv|pdf|excel), `columns`, `data`, `resultVar`
- New fields: + `defined?`-guards for PdfGenerator, ExcelGenerator
- New branches: if class missing, write `_last_error` and behavior per errorStrategy
- Rubric: R1, R2, R6

---

### §P.10 — human_workflow diffs

#### 10.1 approval_gate_generator
- Current fields: `approvers`, `approvalMode`, `deadline`, `onTimeout`, `outputKey`
- R5 rename: `outputKey` → `resultVar`
- New fields: + `majorityThreshold` (int %, default 50, visibleWhen approvalMode=majority) + `notifyChannel` (select email|slack)
- New branches: majority emits `ctx[:#{resultVar}][:threshold] = majorityThreshold`; notifies approvers via generated `notify`-style code
- Rubric: R1, R2, R6

#### 10.2 assign_task_generator
- Current fields: `assignee`, `title`, `priority`, `deadline`, `waitForCompletion`, `outputKey`
- R5 rename: `outputKey` → `resultVar`
- New fields: + persistence branch writes to `Rails.cache`; waitForCompletion sets up `ctx[:_signal_wait]`
- Rubric: R1, R2, R6

#### 10.3 escalation_generator
- Current fields: `escalationLevel`, `escalateTo`, `timeout`, `outputKey`
- R5 rename: `outputKey` → `resultVar`
- New fields: + auto-increment `escalationCount` from ctx state; schedule escalation signal
- Rubric: R1, R2, R6

#### 10.4 user_input_request_generator
- Current fields: `fields`, `prompt`, `timeout`, `outputKey`
- R5 rename: `outputKey` → `resultVar`
- New fields: + persistence branch; signal_wait integration
- Rubric: R1, R2, R6

---

### §P.11 — realtime diffs

#### 11.1 broadcast_generator
- Current fields: `mechanism` (turbo|actioncable), `streamName`, `action`, `target`, `partial`, `localsExpression`, `channelClass`
- New fields: + `errorStrategy`; validate action enum for turbo (`append|prepend|replace|remove|update`)
- Rubric: R1, R2, R6

#### 11.2 publish_event_generator
- Current fields: `eventName`, `payloadExpression`
- New fields: + `errorStrategy`; validate eventName format (namespaced `/\A[\w\.]+\z/`)
- Rubric: R1, R2, R4 (OperandConverter on payload), R6

---

### §P.12 — resilience diffs (bug fixes)

#### 12.1 rate_limiter_generator
- Bug: off-by-one in `remaining`; busy-loop on wait
- Current fields: `key`, `threshold`, `windowSeconds`, `onExceed` (raise|wait|skip)
- Fix: remaining = threshold - current_count (not threshold - current_count - 1); wait uses `sleep(retryDelay)`
- New fields: + `jitterPercent` (int, default 10) + `errorStrategy`
- Rubric: R1, R2, R6

#### 12.2 retry_with_backoff_generator
- Bug: body is empty with dead `break`
- Current fields: `maxAttempts`, `strategy` (exponential|linear|constant), `baseDelay`, `jitter`
- Fix: emit real retry loop wrapping "child steps execute here" placeholder; implement jitter as `rand(0..baseDelay * jitterPercent / 100.0)`
- New fields: + `retryableErrors` (array of error class names)
- Rubric: R1, R6

#### 12.3 circuit_breaker_generator
- Bug: half-open race condition
- Current fields: `key`, `failureThreshold`, `resetTimeout`, `halfOpenTrials`
- Fix: emit advisory-lock or Redis SETNX around state transition
- New fields: + `jitterPercent`
- Rubric: R1, R2, R6

#### 12.4 idempotency_check_generator
- Current fields: `keyExpression`, `duplicateAction` (skip|return|raise)
- Fix: `skip` now writes stored result to ctx (not no-op); `return` restores previous result
- New fields: + `resultVar` (to restore on dup) + `ttl`
- Rubric: R1, R2, R6

---

### §P.13 — response diffs

#### 13.1 render_response_generator
- Bug: `flash` conditional missing `else`
- Current fields: `format` (json|html|redirect), `status`, `body`, `flashType`, `flashMessage`, `template`
- Fix: emit complete if/else/end around flash assignment
- New fields: + `headers` (key_value_list) + `templateLocals` (key_value_list) + `redirectUrl` (visibleWhen format=redirect)
- Rubric: R1, R6

#### 13.2 redirect_response_generator
- Bug: `CGI.escape` is a string literal, not a method call
- Current fields: `url`, `queryParams`, `status`
- Fix: emit `CGI.escape(value)` as method invocation
- New fields: + `flashMessage` + `preserveQueryString` (bool)
- Rubric: R1, R6

---

### §P.14 — scheduling_time diffs

#### 14.1 business_hours_check_generator
- Bug: `Time.parse(_time)` uses wrong variable name
- Current fields: `timeVariable`, `timezone`, `schedule` (per-day map), `resultVar`
- Fix: emit `Time.parse(ctx[:timeVariable]).in_time_zone(timezone)`
- New fields: + `dstPolicy` + validate timezone IANA
- Rubric: R1, R2, R6

#### 14.2 deadline_check_generator
- Current fields: `deadlineVariable`, `referenceTime`, `resultVar`
- New fields: + `deadlineFormat` (select `iso8601|rfc2822|auto`) + `errorStrategy`
- Rubric: R1, R2, R6

#### 14.3 timezone_convert_generator
- Current fields: `sourceTimeVariable`, `sourceTimezone`, `targetTimezone`, `resultVar`
- New fields: + IANA validation for both timezones
- Rubric: R1, R2, R6

---

### §P.15 — service_invocation diffs

#### 15.1 invoke_service_generator
- Current fields: `serviceClass`, `serviceMethod`, `argumentsVariable`, `kwargsVariable`, `resultVar`, `callMethod` (call|new)
- New fields: + `defined?` guard for serviceClass + `errorStrategy`
- Rubric: R1, R2, R6

---

### §P.16 — utility diffs

#### 16.1 ai_inference_generator
- Current fields: `provider`, `model`, `promptTemplate`, `systemPrompt`, `responseFormat`, `apiKeyReference`, `temperature`, `maxTokens`, `outputKey`
- R5 rename: `outputKey` → `resultVar`
- New fields: + `timeoutSeconds` (default 60) + `streaming` (bool) + `allowedModels` (array for allowlist) + `errorStrategy`
- New branches: anthropic version `2023-06-01` made configurable; safe prompt substitution via hash replacement
- Rubric: R1, R2, R3, R4, R6

#### 16.2 audit_log_generator
- Current fields: `actor`, `action`, `severity`, `metadata`
- New fields: + `persistence` (select `model|logger|both`) + metadata via OperandConverter
- Rubric: R1, R2, R4, R6

#### 16.3 template_render_generator
- Current fields: `engine` (liquid|erb), `template`, `variables`, `resultVar`
- New fields: + drop ERB (dangerous) or sandbox via `Tilt::SafeERBTemplate` if available; liquid uses `Liquid::Template.parse(..., error_mode: :strict)`
- New branches: erb path emits `defined?(Tilt::SafeERBTemplate)`-guard
- Rubric: R1, R2, R6

#### 16.4 i18n_translate_generator
- Current fields: `key`, `locale`, `interpolations`, `defaultValue`, `resultVar`
- New fields: + locale via OperandConverter + `fallbackLocale` + `errorStrategy`
- Rubric: R1, R2, R4, R6

#### 16.5 currency_convert_generator
- Current fields: `amountVariable`, `fromCurrency`, `toCurrency`, `ratesVariable`, `precision`, `resultVar`
- New fields: + `rateSource` (select `config|external`) + external uses HttpRequestBuilder
- Rubric: R1, R2, R4, R6

#### 16.6 geolocation_lookup_generator
- Current fields: `mode` (ip|distance), `ipVariable`, `coord1`, `coord2`, `resultVar`
- New fields: + `defined?(MaxMindDB)`-guard; precision bump for Haversine
- Rubric: R1, R2, R6

#### 16.7 barcode_generate_generator
- Current fields: `dataVariable`, `symbology`, `format`, `resultVar`
- New fields: + `defined?(Barby)`-guard + `errorStrategy`
- Rubric: R1, R2, R6

#### 16.8 qr_code_generate_generator
- Current fields: `dataVariable`, `size`, `errorCorrection`, `format`, `resultVar`
- New fields: + `defined?(RQRCode)`-guard + `errorStrategy`
- Rubric: R1, R2, R6

---

### §P.17 — validation diffs

#### 17.1 build_contract_generator
- Current fields: (hardcoded EntityEntryContract)
- New fields: + `contractClass` (text, default "EntityEntryContract") + `cachePerClass` (bool)
- Rubric: R1, R6

#### 17.2 validate_contract_generator
- Current fields: `subOption` (permission vs default)
- New fields: + `defined?`-guards for `ActivitySteps::*` classes + `integratePermission` (bool) — when true, both contract validation and permission check must pass
- Rubric: R1, R2, R6

---

### §P.18 — background diffs

#### 18.1 enqueue_job_generator
- Current fields: `jobClass`, `arguments`, `queue`
- New fields: + `performMode` (select `later|now`) + `defined?`-guard + `errorStrategy`
- Rubric: R1, R2, R6

#### 18.2 schedule_job_generator
- Current fields: `jobClass`, `cron`, `arguments`
- New fields: + cron validated at generate time via `Fugit::Cron.parse` (or `defined?`-guard at runtime) + `errorStrategy`
- Rubric: R1, R2, R6

---

## Self-Review Notes

After writing this plan, pass-through checks:

- **Spec coverage:** Every spec section (§1–§9) maps to plan content: §1–§2 → plan intro; §3 → plan not covered (audit is history, not a task); §4 (architecture/rules) → Batch 1 + §T; §5 (per-category rubric) → §P per-generator diffs; §6 (strategy) → batch ordering; §7 (risks) → plan doesn't enumerate risks (they're spec-owned); §8 (deliverables) → every batch produces listed artifact; §9 (acceptance) → §T steps G/H enforce this per-generator.
- **Placeholder scan:** No TBDs. One approximation remains: Task 1.4 regex parser for JS is a lightweight regex — documented limit is "if JS parsing is brittle, maintain Ruby mirror manually." This is an acceptable known limitation stated in the spec, not a placeholder.
- **Type consistency:** `Shared::CtxReader`, `Shared::ErrorWrapper`, `Shared::ConfigFieldReader`, `Shared::SchemaReader` names consistent across tasks. Method names `safe_read`, `wrap_with_error_strategy`, `fetch_with_default`, `fetch_enum`, `fetch_int_positive`, `read`, `each_enum_branch` consistent.
- **Completeness:** All 116 generators accounted for across 18 batches. Counts per batch: Batch 2 flow_control = 14 (including 2 no-ops: start, subflow); Batch 3a data_ops collection = 13; Batch 3b data_ops strings = 6; Batch 3c data_ops math/misc = 13; (data_ops total = 32, but `pluck_fields` in data_ops is one file and `pluck_fields` in model_ops is a second file — both paths are distinct); Batch 4a model_ops read = 7; Batch 4b model_ops write = 10 (model_ops total = 17); 9 + 4 + 4 + 2 + 7 + 4 + 2 + 4 + 2 + 3 + 1 + 8 + 2 + 2 = 54 for remaining batches. 14+32+17+54 = 117 tasks covering 116 unique files plus 1 shared-name collision across namespaces. Re-verify filename disambiguation in Step A when starting either pluck_fields task.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-17-code-generator-enrichment.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Per user instruction to proceed autonomously and pick my own recommendation, I'll proceed with **subagent-driven** execution starting with Batch 1 (foundation tasks) in the next turn unless the user intervenes.
