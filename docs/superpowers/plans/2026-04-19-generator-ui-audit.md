# Generator ↔ Property Editor Alignment: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** For every in-scope Ruby code generator, ensure the flowchart edit page's property editor exposes every config key and enum value the generator reads, with correct `visibleWhen` and default rules.

**Architecture:** Single automated audit → machine-readable gap artifact → 25 phased UI refactor tasks driven by the artifact. No generator Ruby code changes. Fixes are JS-only edits to `app/javascript/flowchart/constants/schemas.js` and `app/javascript/flowchart/constants/action_configs/*.js`, plus regeneration of the Ruby mirror `spec/support/config_schemas.rb`.

**Tech Stack:** Ruby on Rails 8.1.2, RSpec, `rake config_schemas:mirror` (node-based extractor at `lib/tasks/extract_config_schemas.mjs`), vanilla JS constants, yarn build.

**Spec:** `docs/superpowers/specs/2026-04-19-generator-ui-audit-design.md`

---

## Phase 0 — Build the audit

### Task 0.1: Create the audit script skeleton

**Files:**
- Create: `scripts/audit_generator_ui.rb`
- Create: `spec/scripts/audit_generator_ui_spec.rb`

- [ ] **Step 1: Write failing spec for script boot**

`spec/scripts/audit_generator_ui_spec.rb`:

```ruby
# frozen_string_literal: true
require "rails_helper"

RSpec.describe "scripts/audit_generator_ui.rb", type: :script do
  let(:script_path) { Rails.root.join("scripts/audit_generator_ui.rb") }
  let(:output_path) { Rails.root.join("docs/superpowers/specs/2026-04-19-generator-ui-audit-data.yml") }

  it "exists and is runnable" do
    expect(File).to exist(script_path)
  end

  it "produces YAML artifact at the expected path when run" do
    output_path.delete if output_path.exist?
    system("bundle", "exec", "ruby", script_path.to_s, exception: true)
    expect(output_path).to exist
    content = YAML.safe_load_file(output_path, permitted_classes: [Symbol])
    expect(content).to be_an(Array)
    expect(content.size).to be >= 100
  end
end
```

- [ ] **Step 2: Run spec, confirm it fails**

```bash
bundle exec rspec spec/scripts/audit_generator_ui_spec.rb
```

Expected: FAIL — script does not exist.

- [ ] **Step 3: Create script skeleton**

`scripts/audit_generator_ui.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Audits every in-scope code generator against the UI property-editor schema.
# Emits a machine-readable YAML gap report at
#   docs/superpowers/specs/2026-04-19-generator-ui-audit-data.yml
#
# Usage (from repo root):
#   bundle exec ruby scripts/audit_generator_ui.rb

require_relative "../config/environment"
require "yaml"

OUTPUT_PATH = Rails.root.join("docs/superpowers/specs/2026-04-19-generator-ui-audit-data.yml")

IN_SCOPE_ELEMENT_TYPES = %w[
  start end process decision loop join subflow error_handler timer
].freeze

ACTION_KEY_ALIASES = {
  # generator filename => UI value: key
  "api_call"         => "API_call",
  "validate_contract" => "validate"
}.freeze

# pluck_fields lives in both data_operations and model_operations; only the
# data_operations generator is paired with the single UI entry "pluck_fields"
# (model_operations version will appear as an unpaired entry flagged in the audit).
PLUCK_FIELDS_PRIMARY_DIR = "data_operations"

module GeneratorUiAudit
  GAP_TYPES = %i[action_key_mismatch missing_enum_option missing_field mismatched_visibility_or_default].freeze

  def self.run
    report = []
    # Implementation filled in by subsequent tasks.
    File.write(OUTPUT_PATH, report.to_yaml)
    puts "Wrote #{report.size} generator audit entries to #{OUTPUT_PATH}"
  end
end

GeneratorUiAudit.run if $PROGRAM_NAME == __FILE__
```

- [ ] **Step 4: Make script executable**

```bash
chmod +x scripts/audit_generator_ui.rb
```

- [ ] **Step 5: Run spec, confirm the "exists" test passes but the "≥100 entries" test still fails**

```bash
bundle exec rspec spec/scripts/audit_generator_ui_spec.rb
```

Expected: 1 pass, 1 fail (artifact exists but has 0 entries).

- [ ] **Step 6: Commit**

```bash
git add scripts/audit_generator_ui.rb spec/scripts/audit_generator_ui_spec.rb
git commit -m "chore(audit): scaffold generator-UI audit script and spec"
```

---

### Task 0.2: Load UI schemas from the Ruby mirror

**Files:**
- Modify: `scripts/audit_generator_ui.rb`

- [ ] **Step 1: Add UI-loading helper + test**

Append to `spec/scripts/audit_generator_ui_spec.rb`:

```ruby
  describe "UI schema loading" do
    before { require Rails.root.join("scripts/audit_generator_ui.rb") }

    it "loads UI configSchemas from the Ruby mirror" do
      ui = GeneratorUiAudit.load_ui_schemas
      expect(ui).to be_a(Hash)
      expect(ui).to include("assign_value", "save_model", "start", "end")
      expect(ui["assign_value"]).to be_an(Array)
      expect(ui["assign_value"].first).to include(:key)
    end
  end
```

- [ ] **Step 2: Run spec, confirm it fails on `load_ui_schemas`**

```bash
bundle exec rspec spec/scripts/audit_generator_ui_spec.rb
```

Expected: NoMethodError on `load_ui_schemas`.

- [ ] **Step 3: Implement `load_ui_schemas`**

In `scripts/audit_generator_ui.rb`, replace the `module GeneratorUiAudit` body with:

```ruby
module GeneratorUiAudit
  GAP_TYPES = %i[action_key_mismatch missing_enum_option missing_field mismatched_visibility_or_default].freeze

  def self.load_ui_schemas
    # Refresh the mirror so audit always sees current JS state.
    Rake::Task["config_schemas:mirror"].reenable if Rake::Task.task_defined?("config_schemas:mirror")
    Rake::Task["config_schemas:mirror"].invoke if Rake::Task.task_defined?("config_schemas:mirror")
    load Rails.root.join("spec/support/config_schemas.rb").to_s
    CodeGenerators::CONFIG_SCHEMAS.transform_values { |fields| fields.map { |f| f.transform_keys(&:to_sym) } }
  end

  def self.run
    ui = load_ui_schemas
    puts "Loaded #{ui.size} UI schemas."
    report = []
    File.write(OUTPUT_PATH, report.to_yaml)
    puts "Wrote #{report.size} generator audit entries to #{OUTPUT_PATH}"
  end
end
```

- [ ] **Step 4: Run spec, confirm UI loading test passes**

```bash
bundle exec rspec spec/scripts/audit_generator_ui_spec.rb -e "UI schema loading"
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/audit_generator_ui.rb spec/scripts/audit_generator_ui_spec.rb
git commit -m "chore(audit): load UI schemas via config_schemas mirror"
```

---

### Task 0.3: Discover in-scope generators

**Files:**
- Modify: `scripts/audit_generator_ui.rb`
- Modify: `spec/scripts/audit_generator_ui_spec.rb`

- [ ] **Step 1: Add discovery spec**

Append to spec:

```ruby
  describe ".discover_generators" do
    before { require Rails.root.join("scripts/audit_generator_ui.rb") }

    it "returns 112 in-scope generators (9 element-level + 103 step-action, minus 0 skipped)" do
      gens = GeneratorUiAudit.discover_generators
      expect(gens.size).to eq(112)

      kinds = gens.group_by { |g| g[:kind] }
      expect(kinds[:element_type].size).to eq(9)
      expect(kinds[:step_action].size).to eq(103)
    end

    it "resolves aliases for api_call and validate_contract" do
      gens = GeneratorUiAudit.discover_generators
      api = gens.find { |g| g[:generator_key] == "api_call" }
      expect(api[:ui_key]).to eq("API_call")

      vc = gens.find { |g| g[:generator_key] == "validate_contract" }
      expect(vc[:ui_key]).to eq("validate")
    end

    it "skips out-of-scope element types" do
      gens = GeneratorUiAudit.discover_generators
      out_of_scope = %w[fork parallel_for_each saga signal_wait switch transaction]
      gens.each do |g|
        expect(out_of_scope).not_to include(g[:generator_key]) if g[:kind] == :element_type
      end
    end
  end
```

- [ ] **Step 2: Run spec, confirm it fails**

```bash
bundle exec rspec spec/scripts/audit_generator_ui_spec.rb -e "discover_generators"
```

Expected: NoMethodError.

- [ ] **Step 3: Implement discovery**

Add inside `module GeneratorUiAudit`:

```ruby
  PROCESS_CATEGORIES = %w[
    background caching communication concurrency data_operations file_operations
    human_workflow model_operations realtime resilience response scheduling_time
    security service_invocation utility validation
  ].freeze

  CATEGORY_TO_PHASE = {
    "background" => "background",  "caching" => "caching",
    "communication" => "communication", "concurrency" => "concurrency",
    "data_operations" => "data", "file_operations" => "file",
    "human_workflow" => "human_workflow", "model_operations" => "model",
    "realtime" => "realtime", "resilience" => "resilience",
    "response" => "response", "scheduling_time" => "scheduling",
    "security" => "security", "service_invocation" => "service",
    "utility" => "utility", "validation" => "validation"
  }.freeze

  def self.discover_generators
    element_types = IN_SCOPE_ELEMENT_TYPES.map do |type|
      path = Rails.root.join("app/services/code_generators/element_types/#{type}/#{type}_generator.rb")
      next unless path.exist?
      {
        generator_key: type,
        ui_key: type,
        kind: :element_type,
        phase: "element_#{type}",
        generator_path: path.to_s,
        ui_ref: "schemas.js::#{type}"
      }
    end.compact

    step_actions = PROCESS_CATEGORIES.flat_map do |cat|
      Dir[Rails.root.join("app/services/code_generators/element_types/process/#{cat}/*_generator.rb")].map do |path|
        gen_key = File.basename(path, "_generator.rb")
        # pluck_fields model_operations generator is excluded from UI-pairing audit
        # (the sole UI entry "pluck_fields" is paired with the data_operations generator).
        next if gen_key == "pluck_fields" && cat != PLUCK_FIELDS_PRIMARY_DIR
        ui_key = ACTION_KEY_ALIASES[gen_key] || gen_key
        {
          generator_key: gen_key,
          ui_key: ui_key,
          kind: :step_action,
          phase: CATEGORY_TO_PHASE.fetch(cat),
          generator_path: path,
          ui_ref: "action_configs/#{CATEGORY_TO_PHASE.fetch(cat)}_actions.js::#{ui_key}"
        }
      end.compact
    end

    element_types + step_actions
  end
```

Note: in-scope count is 112 (9 + 103), because `pluck_fields_generator.rb` appears in two directories but only one is audited (the model_operations copy is excluded).

Wait — the correct count: `find ... process -name "*_generator.rb" | wc -l` returned **103**. Since we exclude the model_operations `pluck_fields` duplicate, step_action count becomes 102. Element types = 9. Total = 111.

Update spec to expect `111`, `element_type: 9`, `step_action: 102`.

```ruby
    it "returns 111 in-scope generators (9 element-level + 102 step-action after de-duping pluck_fields)" do
      gens = GeneratorUiAudit.discover_generators
      expect(gens.size).to eq(111)

      kinds = gens.group_by { |g| g[:kind] }
      expect(kinds[:element_type].size).to eq(9)
      expect(kinds[:step_action].size).to eq(102)
    end
```

- [ ] **Step 4: Run all discover_generators specs**

```bash
bundle exec rspec spec/scripts/audit_generator_ui_spec.rb -e "discover_generators"
```

Expected: PASS (all 3 examples).

- [ ] **Step 5: Commit**

```bash
git add scripts/audit_generator_ui.rb spec/scripts/audit_generator_ui_spec.rb
git commit -m "chore(audit): discover in-scope generators with alias resolution"
```

---

### Task 0.4: Extract generator config contract via Ripper

**Files:**
- Modify: `scripts/audit_generator_ui.rb`
- Modify: `spec/scripts/audit_generator_ui_spec.rb`

- [ ] **Step 1: Add extraction spec using `assign_value` as a known fixture**

Append to spec:

```ruby
  describe ".extract_contract" do
    before { require Rails.root.join("scripts/audit_generator_ui.rb") }

    let(:path) { Rails.root.join("app/services/code_generators/element_types/process/data_operations/assign_value_generator.rb").to_s }

    it "extracts keys read from config" do
      contract = GeneratorUiAudit.extract_contract(path)
      expect(contract[:keys_read]).to include(
        "resultVar", "valueType", "stringValue", "integerValue", "floatValue",
        "booleanValue", "arrayValue", "hashValue", "ctxRefVariable",
        "envVarName", "credentialPath", "randomType", "randomLength", "valueExpression"
      )
    end

    it "extracts enum values from constants" do
      contract = GeneratorUiAudit.extract_contract(path)
      expect(contract[:enums]["valueType"]).to match_array(%w[
        string integer float boolean array hash expression null
        ctx_ref env_var credential random
      ])
      expect(contract[:enums]["randomType"]).to match_array(%w[uuid hex int float])
    end

    it "extracts required keys from validate_config" do
      contract = GeneratorUiAudit.extract_contract(path)
      expect(contract[:required]).to include("resultVar")
    end
  end
```

- [ ] **Step 2: Run spec, confirm failure**

```bash
bundle exec rspec spec/scripts/audit_generator_ui_spec.rb -e "extract_contract"
```

Expected: NoMethodError on `extract_contract`.

- [ ] **Step 3: Implement extraction**

Add inside `module GeneratorUiAudit`:

```ruby
  require "ripper"

  # Extracts the config contract from a generator source file.
  # Returns { keys_read: Set<String>, enums: { key => Array<String> }, required: Set<String> }
  def self.extract_contract(path)
    source = File.read(path)
    sexp = Ripper.sexp(source) or raise "Ripper failed to parse #{path}"

    keys = []
    enums = Hash.new { |h, k| h[k] = [] }
    required = []

    walk(sexp) do |node|
      case node
      in [:aref, receiver, [:args_add_block, [[:string_literal, _]], _]] if ident_name(receiver) == "config"
        keys << string_value(node[2][1][0])
      in [:command, [:@ident, "fetch_enum", _], [:args_add_block, args, _]]
        key = string_value(args[0])
        values = array_string_values(args[1])
        keys << key if key
        enums[key].concat(values) if key && values
      in [:command, [:@ident, "fetch_with_default", _], [:args_add_block, args, _]]
        key = string_value(args[0]); keys << key if key
      in [:command, [:@ident, "fetch_int_positive", _], [:args_add_block, args, _]]
        key = string_value(args[0]); keys << key if key
      in [:massign | :assign, [:var_field, [:@const, const_name, _]], rhs] if const_name =~ /_(TYPES|VALUES|STRATEGIES|MODES|OPERATIONS|ENCODINGS|KEY_VALUES|FORMATS)$/
        # top-level constant like VALUE_TYPES = %w[...]
      else
        # no-op
      end
    end

    # Second pass: parse `%w[...]` / `%i[...]` literals assigned to uppercase constants,
    # cross-referenced with `fetch_enum(key, CONST, ...)` and `case config["key"]; when "…"`.
    const_arrays = extract_constants(source)
    merge_constant_enums(source, const_arrays, enums)

    # Required keys from validate_config — look for `cfg["key"].blank?` etc.
    required.concat(extract_required(source))

    {
      keys_read: keys.uniq,
      enums: enums.transform_values(&:uniq),
      required: required.uniq
    }
  end

  # --- helpers: walk, ident_name, string_value, array_string_values,
  #     extract_constants, merge_constant_enums, extract_required ---
  #
  # These are implemented straightforwardly; see Ripper AST docs.
  # They live below GeneratorUiAudit.run.
```

Then add the helper implementations:

```ruby
  def self.walk(node, &blk)
    return unless node.is_a?(Array)
    yield node
    node.each { |child| walk(child, &blk) }
  end

  def self.ident_name(node)
    node.is_a?(Array) && node[0] == :var_ref && node[1].is_a?(Array) && node[1][0] == :@ident ? node[1][1] : nil
  end

  def self.string_value(node)
    return nil unless node.is_a?(Array) && node[0] == :string_literal
    parts = node[1][1..] || []
    parts.map { |p| p.is_a?(Array) && p[0] == :@tstring_content ? p[1] : "" }.join
  end

  def self.array_string_values(node)
    return [] unless node.is_a?(Array) && node[0] == :array
    (node[1] || []).map { |el| string_value(el) }.compact
  end

  CONST_ARRAY_RE = /^\s+([A-Z_]+)\s*=\s*%w\[([^\]]*)\]\.freeze\s*$/.freeze

  def self.extract_constants(source)
    source.scan(CONST_ARRAY_RE).to_h { |name, body| [name, body.split(/\s+/).reject(&:empty?)] }
  end

  def self.merge_constant_enums(source, consts, enums)
    # fetch_enum("key", CONST_NAME, ...)
    source.scan(/fetch_enum\(\s*"([^"]+)"\s*,\s*([A-Z_]+)/).each do |key, const|
      enums[key].concat(consts[const] || [])
    end
    # case config["key"] / when "..."  patterns
    source.scan(/case\s+(?:config\["([^"]+)"\]|value_type)(.*?)end/m).each do |key, body|
      next if key.nil?
      body.scan(/when\s+"([^"]+)"/).each { |(val)| enums[key] << val }
    end
    # Special: `case value_type` with `value_type = config["valueType"] || "expression"`
    if source.match?(/case\s+value_type/)
      source.scan(/case\s+value_type(.*?)end/m).each do |(body)|
        body.scan(/when\s+"([^"]+)"/).each { |(val)| enums["valueType"] << val }
      end
    end
  end

  def self.extract_required(source)
    # Pattern: `errors << "... is required" if cfg["key"].blank?`
    source.scan(/cfg\["([^"]+)"\]\.(?:blank\?|to_s\.strip\.empty\?)/).flatten.uniq
  end
```

- [ ] **Step 4: Run extract_contract specs**

```bash
bundle exec rspec spec/scripts/audit_generator_ui_spec.rb -e "extract_contract"
```

Expected: 3 pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/audit_generator_ui.rb spec/scripts/audit_generator_ui_spec.rb
git commit -m "chore(audit): extract generator config contract via Ripper+regex"
```

---

### Task 0.5: Compute gaps per generator

**Files:**
- Modify: `scripts/audit_generator_ui.rb`
- Modify: `spec/scripts/audit_generator_ui_spec.rb`

- [ ] **Step 1: Add gap-computation spec**

Append to spec:

```ruby
  describe ".compute_gaps" do
    before { require Rails.root.join("scripts/audit_generator_ui.rb") }

    it "reports missing enum options for assign_value valueType" do
      gens = GeneratorUiAudit.discover_generators
      ui = GeneratorUiAudit.load_ui_schemas
      av = gens.find { |g| g[:generator_key] == "assign_value" }
      contract = GeneratorUiAudit.extract_contract(av[:generator_path])
      gaps = GeneratorUiAudit.compute_gaps(contract, ui["assign_value"])

      enum_gap = gaps.find { |g| g[:type] == :missing_enum_option && g[:field] == "valueType" }
      expect(enum_gap[:missing]).to include("float", "array", "hash", "null")
    end

    it "reports missing fields for assign_value float/array/hash value inputs" do
      gens = GeneratorUiAudit.discover_generators
      ui = GeneratorUiAudit.load_ui_schemas
      av = gens.find { |g| g[:generator_key] == "assign_value" }
      contract = GeneratorUiAudit.extract_contract(av[:generator_path])
      gaps = GeneratorUiAudit.compute_gaps(contract, ui["assign_value"])

      missing_fields = gaps.select { |g| g[:type] == :missing_field }.map { |g| g[:field] }
      expect(missing_fields).to include("floatValue", "arrayValue", "hashValue")
    end
  end
```

- [ ] **Step 2: Run spec, confirm failure**

```bash
bundle exec rspec spec/scripts/audit_generator_ui_spec.rb -e "compute_gaps"
```

Expected: NoMethodError.

- [ ] **Step 3: Implement `compute_gaps`**

Add inside `module GeneratorUiAudit`:

```ruby
  TYPE_FOR_KEY = lambda do |key|
    case key
    when /Expression$/, /Template$/, /^customExpression$/, /responseBody/ then :textarea
    when /Value$/, /Count$/, /Length$/, /Size$/, /Width$/, /Seconds$/, /Depth$/, /Precision$/ then :number
    when /List$/, /Fields$/, /Mappings$/, /Tags$/, /Operations$/, /Options$/ then :key_value_list
    else :text
    end
  end

  def self.compute_gaps(contract, ui_fields)
    ui_fields ||= []
    ui_by_key = ui_fields.to_h { |f| [f[:key].to_s, f] }
    gaps = []

    # missing_enum_option
    contract[:enums].each do |key, values|
      ui_field = ui_by_key[key]
      next unless ui_field && ui_field[:type].to_sym == :select
      ui_values = (ui_field[:options] || []).map { |o| o["value"] || o[:value] }
      missing = values - ui_values
      gaps << { type: :missing_enum_option, field: key, missing: missing } if missing.any?
    end

    # missing_field
    contract[:keys_read].each do |key|
      next if ui_by_key.key?(key)
      # Don't report cross-cutting wrapper fields; they live at step-level advanced section.
      next if %w[retryCount retryBackoff timeout guardCondition errorStrategy].include?(key)
      gaps << {
        type: :missing_field,
        field: key,
        input_type: TYPE_FOR_KEY.call(key),
        suggested_label: key.gsub(/([A-Z])/, ' \1').strip.split.map(&:capitalize).join(" ")
      }
    end

    # mismatched_visibility_or_default: `required` missing on known-required keys
    contract[:required].each do |key|
      ui_field = ui_by_key[key]
      next unless ui_field
      unless ui_field[:required] == true
        gaps << { type: :mismatched_visibility_or_default, field: key, fix: { set: { required: true } } }
      end
    end

    gaps
  end
```

- [ ] **Step 4: Run compute_gaps specs**

```bash
bundle exec rspec spec/scripts/audit_generator_ui_spec.rb -e "compute_gaps"
```

Expected: 2 pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/audit_generator_ui.rb spec/scripts/audit_generator_ui_spec.rb
git commit -m "chore(audit): compute per-generator gap rows"
```

---

### Task 0.6: Wire end-to-end audit run and emit YAML

**Files:**
- Modify: `scripts/audit_generator_ui.rb`
- Modify: `spec/scripts/audit_generator_ui_spec.rb`

- [ ] **Step 1: Update `.run` to orchestrate and enrich existing top-level spec**

Replace `.run` body:

```ruby
  def self.run
    ui = load_ui_schemas
    report = discover_generators.map do |g|
      contract = extract_contract(g[:generator_path])
      ui_fields = ui[g[:ui_key]]
      gaps = compute_gaps(contract, ui_fields)

      entry = {
        generator: generator_class_name(g[:generator_path]),
        generator_key: g[:generator_key],
        ui_key: g[:ui_key],
        kind: g[:kind],
        phase: g[:phase],
        ui_ref: g[:ui_ref],
        gaps: gaps
      }

      if g[:ui_key] != g[:generator_key]
        entry[:gaps] = [{ type: :action_key_mismatch, ui_key: g[:ui_key] }] + entry[:gaps]
      end

      entry
    end

    File.write(OUTPUT_PATH, report.to_yaml)
    puts "Wrote #{report.size} generator audit entries to #{OUTPUT_PATH}"
    puts "Total gaps: #{report.sum { |e| e[:gaps].size }}"
  end

  def self.generator_class_name(path)
    rel = Pathname.new(path).relative_path_from(Rails.root.join("app/services")).to_s
    rel.sub(/\.rb$/, "").split("/").map { |p| p.camelize }.join("::")
  end
```

- [ ] **Step 2: Add end-to-end spec**

Append:

```ruby
  describe "end-to-end run" do
    before { require Rails.root.join("scripts/audit_generator_ui.rb") }

    it "produces a populated audit artifact" do
      Rails.root.join("docs/superpowers/specs/2026-04-19-generator-ui-audit-data.yml").tap do |p|
        p.delete if p.exist?
      end
      system("bundle", "exec", "ruby", "scripts/audit_generator_ui.rb", exception: true)

      data = YAML.safe_load_file(
        Rails.root.join("docs/superpowers/specs/2026-04-19-generator-ui-audit-data.yml"),
        permitted_classes: [Symbol]
      )
      expect(data.size).to eq(111)
      expect(data.flat_map { |e| e[:gaps] }.size).to be > 0
      expect(data.map { |e| e[:phase] }.uniq.sort).to match_array(%w[
        background caching communication concurrency data element_decision element_end
        element_error_handler element_join element_loop element_process element_start
        element_subflow element_timer file human_workflow model realtime resilience
        response scheduling security service utility validation
      ])
    end
  end
```

- [ ] **Step 3: Run spec**

```bash
bundle exec rspec spec/scripts/audit_generator_ui_spec.rb
```

Expected: all pass.

- [ ] **Step 4: Commit audit infrastructure**

```bash
git add scripts/audit_generator_ui.rb spec/scripts/audit_generator_ui_spec.rb
git commit -m "chore(audit): emit YAML gap report for all in-scope generators"
```

- [ ] **Step 5: Run audit and commit artifact**

```bash
bundle exec ruby scripts/audit_generator_ui.rb
git add docs/superpowers/specs/2026-04-19-generator-ui-audit-data.yml
git commit -m "docs(audit): add generator↔UI gap report for 2026-04-19 audit"
```

---

## Phases 1–25 — UI Refactor (Data-Driven)

> **Uniform structure:** Each fix phase is identical in shape; only the target file and affected action/element list differ. The audit YAML is the source of truth — every gap row corresponds to a specific UI edit.

### Phase template

For phase `<PHASE_ID>` targeting UI file `<UI_FILE>`:

**Files:**
- Modify: `<UI_FILE>` (exact path below per phase)
- Regenerate: `spec/support/config_schemas.rb` (via `rake config_schemas:mirror`)

- [ ] **Step 1: Read all gap entries for this phase**

```bash
ruby -ryaml -e '
  d = YAML.safe_load_file("docs/superpowers/specs/2026-04-19-generator-ui-audit-data.yml", permitted_classes: [Symbol])
  d.select { |e| e[:phase] == "<PHASE_ID>" }.each { |e| puts "\n=== #{e[:ui_key]} (#{e[:gaps].size} gaps) ==="; e[:gaps].each { |g| puts "  #{g.inspect}" } }
'
```

- [ ] **Step 2: For each `missing_enum_option` gap**

In `<UI_FILE>`, locate the action entry with `value: "<ui_key>"`, locate the field in its `configSchema` with `key: "<field>"`, append each missing value to the `options:` array using the shape `{ value: "<val>", label: "<val>" }`. Preserve existing formatting and trailing commas.

- [ ] **Step 3: For each `missing_field` gap**

In the same action's `configSchema`, append a new field entry positioned after the most related existing field (usually the field named in the gap's implicit `visible_when`). Template:

```js
{
  key: "<field>",
  type: "<input_type>",           // from gap row
  label: "<suggested_label>",
  placeholder: "<derive from contract>",
  // visibleWhen: { field: "<anchor>", value: "<val>" }  // include only when generator branches on another key
}
```

- [ ] **Step 4: For each `mismatched_visibility_or_default` gap**

Patch the existing field in place using the `fix` directive from the gap row (e.g. `{ set: { required: true } }` → add `required: true` to the field object).

- [ ] **Step 5: Regenerate the Ruby mirror and confirm it parses**

```bash
bundle exec rake config_schemas:mirror
```

Expected: "Wrote N entries…"

- [ ] **Step 6: Run the phase-scoped generator specs**

```bash
bundle exec rspec spec/services/code_generators/element_types/<phase_dir>
```

(Replace `<phase_dir>` per phase — see table below.)

Expected: all green. If any generator spec fails, the UI edit introduced a schema inconsistency — do NOT work around by editing generator code; fix the UI edit.

- [ ] **Step 7: Re-run audit, verify phase has zero gaps**

```bash
bundle exec ruby scripts/audit_generator_ui.rb
ruby -ryaml -e '
  d = YAML.safe_load_file("docs/superpowers/specs/2026-04-19-generator-ui-audit-data.yml", permitted_classes: [Symbol])
  phase = d.select { |e| e[:phase] == "<PHASE_ID>" }
  puts "Phase <PHASE_ID>: #{phase.sum { |e| e[:gaps].reject { |g| g[:type] == :action_key_mismatch }.size }} gaps remaining"
'
```

Expected: `Phase <PHASE_ID>: 0 gaps remaining`. (Action-key-mismatch entries are informational and remain.)

- [ ] **Step 8: Build JS to catch syntax errors**

```bash
yarn build
```

Expected: build succeeds.

- [ ] **Step 9: Commit**

```bash
git add <UI_FILE> spec/support/config_schemas.rb docs/superpowers/specs/2026-04-19-generator-ui-audit-data.yml
git commit -m "feat(property-editor): close generator-UI gaps for <PHASE_ID>"
```

---

### Phase roster

| # | PHASE_ID | UI_FILE | phase_dir (for spec run) |
|---|---|---|---|
| 1 | `element_start` | `app/javascript/flowchart/constants/schemas.js` (block `start`) | `start` |
| 2 | `element_end` | `schemas.js` (block `end`) | `end` |
| 3 | `element_process` | `schemas.js` (block `process`) | (step-action phases cover process body; phase 3 audits only the element-level schema: `steps`, `isolateCtx`, `onStepFailure`, `errorHandling`) |
| 4 | `element_decision` | `schemas.js` (block `decision`) | `decision` |
| 5 | `element_loop` | `schemas.js` (block `loop`) | `loop` |
| 6 | `element_join` | `schemas.js` (block `join`) | `join` |
| 7 | `element_subflow` | `schemas.js` (block `subflow`) | `subflow` (no existing dir — skip RSpec step) |
| 8 | `element_error_handler` | `schemas.js` (block `error_handler`) | `error_handler` |
| 9 | `element_timer` | `schemas.js` (block `timer`) | `timer` |
| 10 | `model` | `action_configs/model_actions.js` | `process/model_operations` |
| 11 | `validation` | `action_configs/validation_actions.js` | `process/validation` |
| 12 | `data` | `action_configs/data_actions.js` | `process/data_operations` |
| 13 | `communication` | `action_configs/communication_actions.js` | `process/communication` |
| 14 | `security` | `action_configs/security_actions.js` | `process/security` |
| 15 | `background` | `action_configs/background_actions.js` | `process/background` |
| 16 | `file` | `action_configs/file_actions.js` | `process/file_operations` |
| 17 | `realtime` | `action_configs/realtime_actions.js` | `process/realtime` |
| 18 | `response` | `action_configs/response_actions.js` | `process/response` |
| 19 | `caching` | `action_configs/caching_actions.js` | `process/caching` |
| 20 | `concurrency` | `action_configs/concurrency_actions.js` | `process/concurrency` |
| 21 | `human_workflow` | `action_configs/human_workflow_actions.js` | `process/human_workflow` |
| 22 | `resilience` | `action_configs/resilience_actions.js` | `process/resilience` |
| 23 | `scheduling` | `action_configs/scheduling_actions.js` | `process/scheduling_time` |
| 24 | `service` | `action_configs/service_actions.js` | `process/service_invocation` |
| 25 | `utility` | `action_configs/utility_actions.js` | `process/utility` |

When phase has **zero gaps** (check the Step 1 readout), record a one-line commit "chore(property-editor): phase `<PHASE_ID>` has no gaps (no-op)" and move on.

---

## Phase 26 — Final verification

### Task 26.1: Full baseline re-check

**Files:** none.

- [ ] **Step 1: Run full code_generators spec suite**

```bash
bundle exec rspec spec/services/code_generators/
```

Expected: 1735 examples (or higher if new examples were added during phases), 0 failures.

- [ ] **Step 2: Confirm no schema drift**

```bash
bundle exec rake config_schemas:check
```

Expected: "OK: config schemas in sync".

- [ ] **Step 3: Re-run audit — expect zero actionable gaps globally**

```bash
bundle exec ruby scripts/audit_generator_ui.rb
ruby -ryaml -e '
  d = YAML.safe_load_file("docs/superpowers/specs/2026-04-19-generator-ui-audit-data.yml", permitted_classes: [Symbol])
  actionable = d.sum { |e| e[:gaps].reject { |g| g[:type] == :action_key_mismatch }.size }
  puts "Actionable gaps remaining: #{actionable}"
'
```

Expected: `Actionable gaps remaining: 0`.

- [ ] **Step 4: Commit the final audit artifact**

```bash
git add docs/superpowers/specs/2026-04-19-generator-ui-audit-data.yml
git commit -m "docs(audit): final audit snapshot — all actionable gaps closed"
```

- [ ] **Step 5: Visual smoke test**

Start dev server (`bin/dev`) and open the flowchart edit page. Open the property editor for one representative element per element-type phase and one step-action per category phase. Confirm:

- New fields render.
- `visibleWhen` toggles correctly between parent-field values.
- No console errors.

Record findings in the PR description rather than the plan.

---

## Notes for the executing engineer

- **Never change Ruby generator code to satisfy an audit gap.** The generator is the source of truth; the audit exists to bring the UI in line with the generator, not the other way around. If a gap looks like a generator bug (e.g., the generator reads a key that seems meaningless), flag it — don't silently fix either side.
- **Extraction false positives** are possible (metaprogramming, dynamic string construction). If a gap row describes a field that clearly doesn't make sense, inspect the generator; the fix may be to add an extractor exception rather than a UI field. Record such exceptions in `scripts/audit_generator_ui.rb` as explicit skip rules with an inline comment.
- **Wrapper fields** (`retryCount`, `retryBackoff`, `timeout`, `guardCondition`, `errorStrategy`) are deliberately excluded from `missing_field` reporting by `compute_gaps`. Do not add them as element-level property-editor fields in this plan — that's a separate initiative.
- **`pluck_fields_generator.rb` appears under both `data_operations/` and `model_operations/`.** Only the `data_operations` version is audited against the sole UI entry `"pluck_fields"`; the model-operations copy is out of scope for this plan's UI work. If, during audit, the model-operations version reveals config keys not present in the data-operations version, emit the report but leave the UI add-action to a follow-up.
- **Autonomous execution:** Per user preference in memory, do not pause for confirmation between phases. Run through all 25 phases continuously, committing after each. Halt only on test failures, build failures, or genuinely ambiguous decisions.
