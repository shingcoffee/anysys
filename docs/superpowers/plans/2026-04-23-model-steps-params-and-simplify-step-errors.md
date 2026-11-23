# Model-step data source + process-element error simplification — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drop `attributes` / `associations` / `fieldMappings` UI from the three model-assigning step actions and derive data from `ctx[:contract]` (Reform sync) or a column-sliced `ctx[:params]`; delete per-step `errorStrategy` across every process-element step generator.

**Architecture:** Add one shared helper (`ModelAssignmentBuilder`) that emits the contract-vs-params branch for the three model-assigning generators. Sweep all process-element step generators to remove the `errorStrategy` config read, the `ErrorWrapper` include, and the `wrap_with_error_strategy` branch — step bodies become plain code and Trailblazer's Railway routes failures. Delete `shared/error_wrapper.rb`. Sweep `app/javascript/flowchart/constants/action_configs/*.js` to drop `errorStrategy` and the three model-action assignment fields.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, Trailblazer::Activity, Reform, dry-validation, RSpec, StimulusJS.

**Design reference:** `docs/superpowers/specs/2026-04-23-model-steps-params-and-simplify-step-errors-design.md`

**Commit policy:** Per AGENTS.md, NEVER auto-commit. Each task ends with a staging + message step; the user will run `git commit` themselves after review.

---

## File structure

### New files

| File | Responsibility |
|---|---|
| `app/services/code_generators/shared/model_assignment_builder.rb` | Emits the contract-vs-params assignment fragment as a Ruby string, consumed by `new_model`, `update_model`, `upsert_model`. |
| `spec/services/code_generators/shared/model_assignment_builder_spec.rb` | Unit tests for the new helper — table-driven across branches and modes. |

### Modified files — model generators

| File | Change |
|---|---|
| `app/services/code_generators/element_types/process/model_operations/new_model_generator.rb` | Rewrite to use `ModelAssignmentBuilder`. Drop `attribute_pairs`, `association_pairs`, `normalize_pairs`, `ErrorWrapper` include, `error_strategy` branch. Keep `OperandConverter` include (used nowhere after refactor — also drop). |
| `app/services/code_generators/element_types/process/model_operations/update_model_generator.rb` | Drop `fieldMappings` → use `ModelAssignmentBuilder`. Drop `safe_ident?` and `IdentifierSanitizer` include. Drop `ErrorWrapper` include + `error_strategy` branch. Keep strategies, `lockVersion`, `returnChanges`, `runCallbacks`. |
| `app/services/code_generators/element_types/process/model_operations/upsert_model_generator.rb` | Drop `attributes` config → use `ModelAssignmentBuilder` for payload building. Drop `ErrorWrapper` include + `error_strategy` branch. Keep `matchFields`, `uniqueBy`, `onConflict`, `returning`, `timestamps`, `createdKey`. |

### Modified files — process step generators (38 files — ErrorWrapper removal only)

Complete list (by directory):

- **background/**: `enqueue_job_generator.rb`, `schedule_job_generator.rb` (schedule doesn't include ErrorWrapper but check `errorStrategy` read)
- **caching/**: `cache_delete_generator.rb`, `cache_fetch_generator.rb`, `cache_read_generator.rb`, `cache_write_generator.rb`
- **communication/**: `api_call_generator.rb`, `notify_generator.rb`, `send_email_generator.rb`, `send_webhook_generator.rb`
- **concurrency/**: `acquire_lock_generator.rb`
- **data_operations/**: `base64_encode_decode_generator.rb`, `compare_data_generator.rb`, `log_generator.rb`, `merge_data_generator.rb`, `parse_data_generator.rb`, `regex_extract_generator.rb`
- **file_operations/**: `compress_files_generator.rb`, `decompress_files_generator.rb`, `download_file_generator.rb`, `generate_file_generator.rb`, `parse_csv_generator.rb`, `upload_file_generator.rb`
- **model_operations/**: `aggregate_query_generator.rb`, `batch_operation_generator.rb`, `bulk_import_generator.rb`, `check_existence_generator.rb`, `clone_model_generator.rb`, `count_records_generator.rb`, `destroy_model_generator.rb`, `find_model_generator.rb`, `pluck_fields_generator.rb`, `query_models_generator.rb`, `raw_sql_query_generator.rb`, `save_model_generator.rb`, `soft_delete_model_generator.rb`, `transition_state_generator.rb` (excluding `new_model`, `update_model`, `upsert_model` which are rewritten separately)
- **security/**: `authenticate_generator.rb`, `decrypt_data_generator.rb`, `verify_token_generator.rb`
- **validation/**: `build_contract_generator.rb`, `validate_contract_generator.rb`

### Deleted files

| File | Reason |
|---|---|
| `app/services/code_generators/shared/error_wrapper.rb` | Feature removed entirely. |
| `spec/services/code_generators/shared/error_wrapper_spec.rb` | Module gone. |

### Modified files — base + JS

| File | Change |
|---|---|
| `app/services/code_generators/base_generator.rb` | Remove `require_relative "shared/error_wrapper"`, `include Shared::ErrorWrapper`, `current_error_strategy` helper. |
| `app/javascript/flowchart/constants/action_configs/model_actions.js` | Remove `attributes` + `associations` from `new_model`. Remove `fieldMappings` from `update_model`. Remove `attributes` from `upsert_model`. |
| `app/javascript/flowchart/constants/action_configs/caching_actions.js` | Remove every `errorStrategy` field entry (3 occurrences). |
| `app/javascript/flowchart/constants/action_configs/file_actions.js` | Remove every `errorStrategy` entry (2). |
| `app/javascript/flowchart/constants/action_configs/resilience_actions.js` | Remove every `errorStrategy` entry (2). |
| `app/javascript/flowchart/constants/action_configs/scheduling_actions.js` | Remove every `errorStrategy` entry (2). |
| `app/javascript/flowchart/constants/action_configs/security_actions.js` | Remove every `errorStrategy` entry (1). |
| `app/javascript/flowchart/constants/action_configs/service_actions.js` | Remove every `errorStrategy` entry (1). |
| `app/javascript/flowchart/constants/action_configs/utility_actions.js` | Remove every `errorStrategy` entry (4). |
| `app/javascript/flowchart/constants/action_configs/validation_actions.js` | Remove every `errorStrategy` entry (1). |

### Modified files — specs

All specs under `spec/services/code_generators/element_types/process/**/*_generator_spec.rb` that reference `errorStrategy`, `wrap_with_error_strategy`, or `_last_error` — roughly 60 files. Plus the three model-generator specs which get new contract/params contexts and lose fixtures referencing `attributes`/`associations`/`fieldMappings`. Plus `spec/services/code_generators/base_generator_spec.rb` (1 file).

---

## Task 0: Baseline

**Files:**
- (read-only baseline)

- [ ] **Step 0.1: Capture baseline spec counts**

Run:
```bash
cd /opt/milestone/anysys
bundle exec rspec spec/services/code_generators/ --format progress 2>&1 | tail -5
```

Record the numbers in your scratch notes (should be ~4331 examples, 0 failures per project memory).

- [ ] **Step 0.2: Capture baseline grep counts**

Run:
```bash
cd /opt/milestone/anysys
echo "generators with ErrorWrapper include:"; grep -rln "Shared::ErrorWrapper" app/services/code_generators/element_types/process/ | wc -l
echo "generators with errorStrategy read:"; grep -rln "errorStrategy" app/services/code_generators/element_types/process/ | wc -l
echo "JS action_configs with errorStrategy:"; grep -rln "errorStrategy" app/javascript/flowchart/constants/action_configs/ | wc -l
echo "specs with errorStrategy/_last_error/wrap_with_error_strategy:"; grep -rln "errorStrategy\|_last_error\|wrap_with_error_strategy" spec/services/code_generators/ | wc -l
```

Expected values at plan start: 38, 41, 8, ~70. These are the remove-targets.

---

## Task 1: Add `ModelAssignmentBuilder` shared helper (TDD)

**Files:**
- Create: `app/services/code_generators/shared/model_assignment_builder.rb`
- Create: `spec/services/code_generators/shared/model_assignment_builder_spec.rb`

The helper emits a Ruby-source fragment that, at runtime in the generated activity, populates a target model variable from `ctx[:contract]` when present or from a column-sliced `ctx[:params]` otherwise. Three modes reflect how the three generators consume it:

- `:assign` — assigns to an existing model variable (for `new_model` after `.new`). Emits `if ctx[:contract] ... contract.sync ... else ... ctx[:model].assign_attributes(...) end`.
- `:update` — identical structural shape, but writes to a caller-supplied model variable name (`update_model` uses the user's `modelVariable`).
- `:payload` — emits an expression (assigned into `_payload =`) whose value is a hash suitable for `upsert` / `upsert_all`. Returns `ctx[:contract].model.attributes.symbolize_keys.slice(*cols)` or the analogous params slice.

- [ ] **Step 1.1: Write failing test — `:assign` mode**

Create `spec/services/code_generators/shared/model_assignment_builder_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::Shared::ModelAssignmentBuilder do
  let(:dummy) { Class.new { include CodeGenerators::Shared::ModelAssignmentBuilder }.new }

  describe "#build_model_assignment" do
    context "mode: :assign" do
      it "emits contract-vs-params branch writing to the given model variable" do
        code = dummy.build_model_assignment(mode: :assign, model_var: "model", class_expr: "_model_class")

        expect(code).to include("if ctx[:contract]")
        expect(code).to include("ctx[:contract].sync")
        expect(code).to include("else")
        expect(code).to include("_allowed = ctx[:params].to_h.with_indifferent_access.slice(*_model_class.attribute_names)")
        expect(code).to include("ctx[:model].assign_attributes(_allowed)")
        expect(code).to include("end")
      end

      it "uses the passed model_var in the params branch" do
        code = dummy.build_model_assignment(mode: :assign, model_var: "record", class_expr: "_model_class")

        expect(code).to include("ctx[:record].assign_attributes(_allowed)")
      end
    end

    context "mode: :update" do
      it "emits contract-vs-params branch using the caller's model variable" do
        code = dummy.build_model_assignment(mode: :update, model_var: "model", class_expr: "ctx[:model].class")

        expect(code).to include("if ctx[:contract]")
        expect(code).to include("ctx[:contract].sync")
        expect(code).to include("_allowed = ctx[:params].to_h.with_indifferent_access.slice(*ctx[:model].class.attribute_names)")
        expect(code).to include("ctx[:model].assign_attributes(_allowed)")
      end
    end

    context "mode: :payload" do
      it "returns an expression usable as a hash rvalue" do
        code = dummy.build_model_assignment(mode: :payload, model_var: "model", class_expr: "_model_class")

        expect(code).to include("if ctx[:contract]")
        expect(code).to include("ctx[:contract].sync")
        expect(code).to include("ctx[:contract].model.attributes.symbolize_keys.slice(*_model_class.attribute_names.map(&:to_sym))")
        expect(code).to include("else")
        expect(code).to include("ctx[:params].to_h.symbolize_keys.slice(*_model_class.attribute_names.map(&:to_sym))")
      end
    end

    context "unknown mode" do
      it "raises ArgumentError" do
        expect {
          dummy.build_model_assignment(mode: :bogus, model_var: "x", class_expr: "y")
        }.to raise_error(ArgumentError, /mode/)
      end
    end
  end
end
```

- [ ] **Step 1.2: Run test to verify it fails**

Run:
```bash
bundle exec rspec spec/services/code_generators/shared/model_assignment_builder_spec.rb --format documentation
```

Expected: FAIL with `uninitialized constant CodeGenerators::Shared::ModelAssignmentBuilder`.

- [ ] **Step 1.3: Implement minimal module**

Create `app/services/code_generators/shared/model_assignment_builder.rb`:

```ruby
# frozen_string_literal: true

module CodeGenerators
  module Shared
    module ModelAssignmentBuilder
      MODES = %i[assign update payload].freeze

      # Emits a Ruby source fragment that at runtime populates a target model
      # from ctx[:contract] (via Reform sync) or from a column-sliced ctx[:params].
      #
      # @param mode [Symbol] :assign | :update | :payload
      # @param model_var [String] name used in ctx[:<model_var>]
      # @param class_expr [String] Ruby expression evaluating to the AR class
      #        (e.g. "_model_class" or "ctx[:model].class")
      # @return [String] Ruby source fragment (no trailing newline)
      def build_model_assignment(mode:, model_var:, class_expr:)
        raise ArgumentError, "mode must be one of #{MODES.inspect}, got #{mode.inspect}" unless MODES.include?(mode)

        case mode
        when :payload then build_payload_fragment(model_var: model_var, class_expr: class_expr)
        else              build_assign_fragment(model_var: model_var, class_expr: class_expr)
        end
      end

      private

      def build_assign_fragment(model_var:, class_expr:)
        <<~RUBY.chomp
          if ctx[:contract]
            ctx[:contract].sync
          else
            _allowed = ctx[:params].to_h.with_indifferent_access.slice(*#{class_expr}.attribute_names)
            ctx[:#{model_var}].assign_attributes(_allowed)
          end
        RUBY
      end

      # Note: :assign and :update modes produce identical fragments here
      # — both are assignment branches that differ only in which model var
      # the caller wants written. The two-mode alias exists to document
      # caller intent (new_model creates the model; update_model assumes
      # it already exists in ctx).

      def build_payload_fragment(model_var:, class_expr:)
        <<~RUBY.chomp
          if ctx[:contract]
            ctx[:contract].sync
            ctx[:contract].model.attributes.symbolize_keys.slice(*#{class_expr}.attribute_names.map(&:to_sym))
          else
            ctx[:params].to_h.symbolize_keys.slice(*#{class_expr}.attribute_names.map(&:to_sym))
          end
        RUBY
      end
    end
  end
end
```

- [ ] **Step 1.4: Run test to verify it passes**

Run:
```bash
bundle exec rspec spec/services/code_generators/shared/model_assignment_builder_spec.rb --format documentation
```

Expected: PASS (all 5 examples green).

- [ ] **Step 1.5: Stage for user commit**

Run:
```bash
git add app/services/code_generators/shared/model_assignment_builder.rb spec/services/code_generators/shared/model_assignment_builder_spec.rb
git status
```

Suggested commit message (user will run commit themselves):
`feat(codegen): add ModelAssignmentBuilder shared helper`

---

## Task 2: Rewrite `NewModelGenerator`

**Files:**
- Modify: `app/services/code_generators/element_types/process/model_operations/new_model_generator.rb`
- Modify: `spec/services/code_generators/element_types/process/model_operations/new_model_generator_spec.rb`

- [ ] **Step 2.1: Read existing spec to understand current cases**

Run:
```bash
bundle exec rspec spec/services/code_generators/element_types/process/model_operations/new_model_generator_spec.rb --dry-run --format documentation
```

Note the example names; you will delete every example asserting `attributes`, `associations`, or `errorStrategy` behavior, and add the new contract/params/tenant tests below.

- [ ] **Step 2.2: Replace the spec file contents**

Overwrite `spec/services/code_generators/element_types/process/model_operations/new_model_generator_spec.rb` with:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::NewModelGenerator do
  def generate(config = {}, element_overrides = {})
    element = {
      "id"   => "step_new_model",
      "type" => "process",
      "properties" => { "config" => config }
    }.deep_merge(element_overrides)
    # The generator is registered under generator_kind :action; `config` lives
    # at element["config"] for action generators (see BaseGenerator#extract_config).
    element["config"] = config
    described_class.new(element, {}).generate_body
  end

  describe "#generate_body" do
    it "builds an empty model instance using EntityEntry.build_for" do
      code = generate

      expect(code).to include('_model_class = EntityEntry.build_for(ctx[:bound_entity])')
      expect(code).to include('ctx[:model] = _model_class.new')
    end

    it "uses the configured resultVar for the ctx key" do
      code = generate("resultVar" => "record")

      expect(code).to include('ctx[:record] = _model_class.new')
      expect(code).to include('ctx[:record].customer_id = ctx[:customer_id]')
    end

    it "defaults resultVar to 'model' when omitted" do
      code = generate

      expect(code).to include('ctx[:model] = _model_class.new')
    end

    context "when ctx[:contract] is present" do
      it "calls ctx[:contract].sync to populate the model" do
        code = generate

        expect(code).to include('if ctx[:contract]')
        expect(code).to include('ctx[:contract].sync')
      end
    end

    context "when ctx[:contract] is not present" do
      it "slices ctx[:params] by the model's attribute_names and assigns" do
        code = generate

        expect(code).to include('_allowed = ctx[:params].to_h.with_indifferent_access.slice(*_model_class.attribute_names)')
        expect(code).to include('ctx[:model].assign_attributes(_allowed)')
      end
    end

    it "pins customer_id to ctx[:customer_id] after the assignment branch" do
      code = generate

      # The pin must appear AFTER the if/else block so it overrides any
      # stray customer_id that leaked through params or the contract.
      idx_block_end = code.index("\nend\n") || code.index("\nend")
      idx_pin      = code.index("ctx[:model].customer_id = ctx[:customer_id]")

      expect(idx_pin).not_to be_nil
      expect(idx_block_end).not_to be_nil
      expect(idx_pin).to be > idx_block_end
    end

    it "returns true as its final expression" do
      expect(generate.strip.split("\n").last).to eq("true")
    end

    it "does not emit any begin/rescue wrapper" do
      code = generate

      expect(code).not_to include("begin")
      expect(code).not_to include("rescue")
      expect(code).not_to include("ctx[:_last_error]")
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
    it "depends on build_contract" do
      expect(described_class.new({ "config" => {} }, {}).dependencies).to eq([:build_contract])
    end
  end
end
```

- [ ] **Step 2.3: Run the spec to verify it fails**

Run:
```bash
bundle exec rspec spec/services/code_generators/element_types/process/model_operations/new_model_generator_spec.rb --format documentation
```

Expected: multiple failures — current generator still emits `begin/rescue`, still reads `attributes`/`associations`, does not emit `if ctx[:contract]`.

- [ ] **Step 2.4: Rewrite the generator**

Overwrite `app/services/code_generators/element_types/process/model_operations/new_model_generator.rb` with:

```ruby
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class NewModelGenerator < BaseGenerator
          include CodeGenerators::Shared::ModelAssignmentBuilder

          generator_metadata do
            description "Creates a new entity model instance"
            category :model_operations
            version "3.0.0"
          end

          def self.sample_input
            { "resultVar" => "model" }
          end

          def generate_body
            result_var = config["resultVar"] || "model"

            <<~RUBY.chomp
              _model_class = EntityEntry.build_for(ctx[:bound_entity])
              ctx[:#{result_var}] = _model_class.new
              #{build_model_assignment(mode: :assign, model_var: result_var, class_expr: '_model_class')}
              ctx[:#{result_var}].customer_id = ctx[:customer_id]
              true
            RUBY
          end

          def dependencies
            [:build_contract]
          end

          def validate_config(_cfg)
            []
          end
        end
      end
    end
  end
end
```

The helper threads `model_var` through correctly, so no post-processing is needed.

- [ ] **Step 2.5: Run the spec to verify it passes**

Run:
```bash
bundle exec rspec spec/services/code_generators/element_types/process/model_operations/new_model_generator_spec.rb --format documentation
```

Expected: PASS.

- [ ] **Step 2.6: Stage for user commit**

Run:
```bash
git add app/services/code_generators/element_types/process/model_operations/new_model_generator.rb spec/services/code_generators/element_types/process/model_operations/new_model_generator_spec.rb
git status
```

Suggested commit message: `refactor(codegen): rewrite new_model generator to use contract/params source`

---

## Task 3: Rewrite `UpdateModelGenerator`

**Files:**
- Modify: `app/services/code_generators/element_types/process/model_operations/update_model_generator.rb`
- Modify: `spec/services/code_generators/element_types/process/model_operations/update_model_generator_spec.rb`

- [ ] **Step 3.1: Replace the spec file contents**

Overwrite `spec/services/code_generators/element_types/process/model_operations/update_model_generator_spec.rb` with:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::UpdateModelGenerator do
  def generate(config = {})
    element = { "type" => "process", "config" => config }
    described_class.new(element, {}).generate_body
  end

  describe "#generate_body — strategy: update (default)" do
    it "emits contract sync + save when contract is present" do
      code = generate

      expect(code).to include("if ctx[:contract]")
      expect(code).to include("ctx[:contract].sync")
      expect(code).to include("ctx[:model].save")
    end

    it "emits params-sliced update when no contract" do
      code = generate

      expect(code).to include("_allowed = ctx[:params].to_h.with_indifferent_access.slice(*ctx[:model].class.attribute_names)")
      expect(code).to include("ctx[:model].update(_allowed)")
    end

    it "uses the configured modelVariable for ctx key" do
      code = generate("modelVariable" => "record")

      expect(code).to include("ctx[:record].class.attribute_names")
      expect(code).to include("ctx[:record].update(_allowed)")
    end

    it "does not emit any begin/rescue wrapper" do
      code = generate
      expect(code).not_to include("begin")
      expect(code).not_to include("rescue")
      expect(code).not_to include("ctx[:_last_error]")
    end
  end

  describe "#generate_body — strategy: save" do
    it "emits contract sync + save when contract is present" do
      code = generate("updateStrategy" => "save")

      expect(code).to include("ctx[:contract].sync")
      expect(code).to include("ctx[:model].save")
    end

    it "emits assign_attributes + save in the params branch" do
      code = generate("updateStrategy" => "save")

      expect(code).to include("ctx[:model].assign_attributes(_allowed)")
      expect(code).to include("ctx[:model].save")
    end
  end

  describe "#generate_body — strategy: update_columns" do
    it "emits update_columns with the allowed hash" do
      code = generate("updateStrategy" => "update_columns")

      expect(code).to include("ctx[:model].update_columns(_allowed)")
    end
  end

  describe "#generate_body — strategy: update_all" do
    it "emits update_all with the allowed hash" do
      code = generate("updateStrategy" => "update_all")

      expect(code).to include("ctx[:model].update_all(_allowed)")
    end
  end

  describe "#generate_body — returnChanges" do
    it "appends saved_changes capture when enabled" do
      code = generate("returnChanges" => "true")

      expect(code).to include("ctx[:saved_changes] = ctx[:model].saved_changes")
    end
  end

  describe "#generate_body — lockVersion" do
    # The default `update` strategy builds `_allowed` as a Hash, so lock_version
    # is injected via hash assignment. The `save` strategy uses Reform sync +
    # `assign_attributes(lock_version: ...)` (keyword form). Both are valid Ruby;
    # the generator picks whichever matches the surrounding strategy body.
    it "includes lock_version in hash assignment for update strategy" do
      code = generate("lockVersion" => "true")

      expect(code).to include("_allowed[:lock_version] = ctx[:lock_version]")
    end

    it "uses the configured lockVersionVariable" do
      code = generate("lockVersion" => "true", "lockVersionVariable" => "my_lock")

      expect(code).to include("_allowed[:lock_version] = ctx[:my_lock]")
    end

    it "includes lock_version in assign_attributes for save strategy" do
      code = generate("updateStrategy" => "save", "lockVersion" => "true")

      expect(code).to include("lock_version: ctx[:lock_version]")
    end
  end

  describe "#validate_config" do
    it "returns [] for valid config" do
      expect(described_class.new({ "config" => {} }, {}).validate_config({})).to eq([])
    end

    it "rejects invalid updateStrategy" do
      errs = described_class.new({ "config" => {} }, {}).validate_config("updateStrategy" => "nope")

      expect(errs).to include(/Invalid updateStrategy/)
    end
  end
end
```

- [ ] **Step 3.2: Run the spec to verify it fails**

Run:
```bash
bundle exec rspec spec/services/code_generators/element_types/process/model_operations/update_model_generator_spec.rb --format documentation
```

Expected: failures — current generator still references `fieldMappings` and wraps in `begin/rescue`.

- [ ] **Step 3.3: Rewrite the generator**

Overwrite `app/services/code_generators/element_types/process/model_operations/update_model_generator.rb` with:

```ruby
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class UpdateModelGenerator < BaseGenerator
          include CodeGenerators::Shared::ModelAssignmentBuilder

          UPDATE_STRATEGIES = %w[save update update_columns update_all].freeze
          BOOL_STRINGS = %w[true false].freeze

          generator_metadata do
            description "Updates an existing model from contract or params"
            category :model_operations
            version "3.0.0"
          end

          def self.sample_input
            { "modelVariable" => "model", "updateStrategy" => "update" }
          end

          def generate_body
            model_var = config["modelVariable"] || "model"
            strategy = resolve_strategy
            return_changes = fetch_enum("returnChanges", BOOL_STRINGS, default: "false") == "true"
            lock_version_enabled = fetch_enum("lockVersion", BOOL_STRINGS, default: "false") == "true"
            lock_version_var = config["lockVersionVariable"].to_s.strip
            lock_version_var = "lock_version" if lock_version_var.empty?

            case strategy
            when "save"           then build_save_body(model_var, return_changes, lock_version_enabled, lock_version_var)
            when "update_columns" then build_columns_body(model_var, return_changes)
            when "update_all"     then build_update_all_body(model_var)
            else                       build_update_body(model_var, return_changes, lock_version_enabled, lock_version_var)
            end
          end

          def validate_config(cfg)
            errors = []
            strategy = cfg["updateStrategy"]
            if strategy.present? && !UPDATE_STRATEGIES.include?(strategy)
              errors << "Invalid updateStrategy: #{strategy}. Must be one of: #{UPDATE_STRATEGIES.join(', ')}"
            end
            %w[runCallbacks returnChanges lockVersion].each do |key|
              val = cfg[key]
              if val.present? && !BOOL_STRINGS.include?(val.to_s)
                errors << "Invalid #{key}: #{val}. Must be one of: #{BOOL_STRINGS.join(', ')}"
              end
            end
            errors
          end

          def dependencies
            [:build_contract]
          end

          private

          def resolve_strategy
            explicit = config["updateStrategy"]
            return explicit if UPDATE_STRATEGIES.include?(explicit)

            "update"
          end

          # Emits: if contract -> sync + save ; else -> assign_attributes + save
          def build_save_body(model_var, return_changes, lock_enabled, lock_var)
            class_expr = "ctx[:#{model_var}].class"
            assignment = build_model_assignment(mode: :update, model_var: model_var, class_expr: class_expr)
            assignment = inject_lock_version(assignment, model_var, lock_var) if lock_enabled
            body = "#{assignment}\nctx[:#{model_var}].save"
            body += "\nctx[:saved_changes] = ctx[:#{model_var}].saved_changes" if return_changes
            body
          end

          # Emits: if contract -> sync + save ; else -> ctx[:model].update(_allowed)
          def build_update_body(model_var, return_changes, lock_enabled, lock_var)
            class_expr = "ctx[:#{model_var}].class"
            <<~RUBY.chomp
              if ctx[:contract]
                ctx[:contract].sync
                ctx[:#{model_var}].save
              else
                _allowed = ctx[:params].to_h.with_indifferent_access.slice(*#{class_expr}.attribute_names)
              #{lock_enabled ? "  _allowed[:lock_version] = ctx[:#{lock_var}]" : ""}
                ctx[:#{model_var}].update(_allowed)
              end#{return_changes ? "\nctx[:saved_changes] = ctx[:#{model_var}].saved_changes" : ''}
            RUBY
          end

          def build_columns_body(model_var, return_changes)
            class_expr = "ctx[:#{model_var}].class"
            <<~RUBY.chomp
              if ctx[:contract]
                ctx[:contract].sync
                _allowed = ctx[:contract].model.attributes.symbolize_keys.slice(*#{class_expr}.attribute_names.map(&:to_sym))
              else
                _allowed = ctx[:params].to_h.with_indifferent_access.slice(*#{class_expr}.attribute_names)
              end
              ctx[:#{model_var}].update_columns(_allowed)#{return_changes ? "\nctx[:saved_changes] = ctx[:#{model_var}].saved_changes" : ''}
            RUBY
          end

          def build_update_all_body(model_var)
            class_expr = "ctx[:#{model_var}].class"
            <<~RUBY.chomp
              if ctx[:contract]
                ctx[:contract].sync
                _allowed = ctx[:contract].model.attributes.symbolize_keys.slice(*#{class_expr}.attribute_names.map(&:to_sym))
              else
                _allowed = ctx[:params].to_h.with_indifferent_access.slice(*#{class_expr}.attribute_names)
              end
              ctx[:#{model_var}].update_all(_allowed)
            RUBY
          end

          def inject_lock_version(assignment_code, model_var, lock_var)
            # Insert `_allowed[:lock_version] = ctx[:lock_var]` after _allowed is defined,
            # and add `assign_attributes(lock_version: ctx[:lock_var])` on the contract side.
            assignment_code
              .sub(/(_allowed = .+)/, "\\1\n  _allowed[:lock_version] = ctx[:#{lock_var}]")
              .sub("ctx[:contract].sync", "ctx[:contract].sync\n  ctx[:#{model_var}].assign_attributes(lock_version: ctx[:#{lock_var}])")
          end
        end
      end
    end
  end
end
```

- [ ] **Step 3.4: Run the spec to verify it passes**

Run:
```bash
bundle exec rspec spec/services/code_generators/element_types/process/model_operations/update_model_generator_spec.rb --format documentation
```

Expected: PASS. If `lock_version` injection is producing malformed code, inspect the generated output of the lockVersion test and adjust `inject_lock_version` until the spec is green.

- [ ] **Step 3.5: Stage for user commit**

Run:
```bash
git add app/services/code_generators/element_types/process/model_operations/update_model_generator.rb spec/services/code_generators/element_types/process/model_operations/update_model_generator_spec.rb
git status
```

Suggested commit message: `refactor(codegen): rewrite update_model generator to use contract/params source`

---

## Task 4: Rewrite `UpsertModelGenerator`

**Files:**
- Modify: `app/services/code_generators/element_types/process/model_operations/upsert_model_generator.rb`
- Modify: `spec/services/code_generators/element_types/process/model_operations/upsert_model_generator_spec.rb`

- [ ] **Step 4.1: Replace the spec file contents**

Overwrite `spec/services/code_generators/element_types/process/model_operations/upsert_model_generator_spec.rb` with:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::UpsertModelGenerator do
  def generate(config = {})
    element = { "type" => "process", "config" => config }
    described_class.new(element, {}).generate_body
  end

  describe "#generate_body — method: find_or_initialize (default)" do
    it "builds find_or_initialize_by with a matchFields-derived hash" do
      code = generate("matchFields" => ["email"])

      expect(code).to include("_model_class.find_or_initialize_by(email: ctx[:email])")
    end

    it "assigns from contract when present" do
      code = generate("matchFields" => ["email"])

      expect(code).to include("if ctx[:contract]")
      expect(code).to include("ctx[:contract].sync")
    end

    it "assigns from params slice when no contract" do
      code = generate("matchFields" => ["email"])

      expect(code).to include("ctx[:params].to_h")
      expect(code).to include("attribute_names")
    end

    it "saves the record after assignment" do
      code = generate("matchFields" => ["email"])

      expect(code).to include("_record.save!")
    end

    it "does not emit any begin/rescue wrapper" do
      code = generate("matchFields" => ["email"])
      expect(code).not_to include("begin")
      expect(code).not_to include("rescue")
      expect(code).not_to include("ctx[:_last_error]")
    end
  end

  describe "#generate_body — method: find_or_create_by" do
    it "builds find_or_create_by with assignment in the block" do
      code = generate("method" => "find_or_create_by", "matchFields" => ["email"])

      expect(code).to include("_model_class.find_or_create_by(email: ctx[:email])")
    end
  end

  describe "#generate_body — method: upsert" do
    it "builds upsert with contract-or-params payload" do
      code = generate("method" => "upsert", "matchFields" => ["email"], "onConflict" => "update")

      expect(code).to include("_payload = if ctx[:contract]")
      expect(code).to include("ctx[:contract].model.attributes.symbolize_keys.slice")
      expect(code).to include("ctx[:params].to_h.symbolize_keys.slice")
      expect(code).to include("_payload[:email] = ctx[:email]")
      expect(code).to include("_model_class.upsert(_payload,")
    end

    it "sets on_duplicate: :update_all for onConflict=update" do
      code = generate("method" => "upsert", "matchFields" => ["email"], "onConflict" => "update")

      expect(code).to include("on_duplicate: :update_all")
    end

    it "sets on_duplicate: :skip for onConflict=skip" do
      code = generate("method" => "upsert", "matchFields" => ["email"], "onConflict" => "skip")

      expect(code).to include("on_duplicate: :skip")
    end

    it "raises on onConflict=raise" do
      code = generate("method" => "upsert", "matchFields" => ["email"], "onConflict" => "raise")

      expect(code).to include("RecordNotUnique")
    end
  end

  describe "#generate_body — method: upsert_all" do
    it "builds upsert_all with a single-row array payload" do
      code = generate("method" => "upsert_all", "matchFields" => ["email"])

      expect(code).to include("_model_class.upsert_all([_payload]")
      expect(code).to include("unique_by: [:email]")
    end
  end

  describe "#validate_config" do
    it "requires matchFields or uniqueBy" do
      errs = described_class.new({ "config" => {} }, {}).validate_config({})

      expect(errs).to include(/matchFields/)
    end
  end
end
```

- [ ] **Step 4.2: Run the spec to verify it fails**

Run:
```bash
bundle exec rspec spec/services/code_generators/element_types/process/model_operations/upsert_model_generator_spec.rb --format documentation
```

Expected: failures.

- [ ] **Step 4.3: Rewrite the generator**

Overwrite `app/services/code_generators/element_types/process/model_operations/upsert_model_generator.rb` with:

```ruby
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class UpsertModelGenerator < BaseGenerator
          include CodeGenerators::Shared::ModelAssignmentBuilder

          METHODS = %w[find_or_create_by find_or_initialize upsert_all upsert].freeze
          ON_CONFLICT = %w[update skip raise].freeze
          BOOL_STRINGS = %w[true false].freeze

          generator_metadata do
            description "Atomic find-or-create / update-or-insert from contract or params"
            category :model_operations
            version "3.0.0"
          end

          def self.sample_input
            { "matchFields" => ["email"], "outputKey" => "model", "method" => "find_or_initialize" }
          end

          def generate_body
            match_fields = Array(config["matchFields"]).compact.reject { |f| f.to_s.empty? }
            match_fields = ["id"] if match_fields.empty?
            target = config["outputKey"] || "model"
            created_key = config["createdKey"] || config["capturedCreatedVar"]
            method = fetch_enum("method", METHODS, default: default_method)

            case method
            when "find_or_create_by"  then build_find_or_create_by(match_fields, target, created_key)
            when "upsert_all"         then build_upsert_all(match_fields, target)
            when "upsert"             then build_upsert(match_fields, target, created_key)
            else                           build_find_or_initialize(match_fields, target, created_key)
            end
          end

          def validate_config(cfg)
            errors = []
            errors << "matchFields is required" if cfg["matchFields"].blank? && cfg["uniqueBy"].blank?
            method = cfg["method"]
            if method.present? && !METHODS.include?(method)
              errors << "Invalid method: #{method}. Must be one of: #{METHODS.join(', ')}"
            end
            if cfg["onConflict"].present? && !ON_CONFLICT.include?(cfg["onConflict"])
              errors << "Invalid onConflict: #{cfg['onConflict']}. Must be one of: #{ON_CONFLICT.join(', ')}"
            end
            if cfg["timestamps"].present? && !BOOL_STRINGS.include?(cfg["timestamps"].to_s)
              errors << "Invalid timestamps: #{cfg['timestamps']}. Must be one of: #{BOOL_STRINGS.join(', ')}"
            end
            errors
          end

          def dependencies
            [:build_contract]
          end

          private

          def default_method
            if config["onConflict"].present? || config["uniqueBy"].present? ||
               config["returning"].present? || config["timestamps"].present?
              "upsert"
            else
              "find_or_initialize"
            end
          end

          def match_hash(match_fields)
            match_fields.map { |f| "#{f}: ctx[:#{f}]" }.join(", ")
          end

          def build_find_or_initialize(match_fields, target, created_key)
            lines = []
            lines << "_model_class = EntityEntry.build_for(ctx[:bound_entity])"
            lines << "_record = _model_class.find_or_initialize_by(#{match_hash(match_fields)})"
            lines << "ctx[:#{created_key}] = _record.new_record?" if created_key.present?
            lines << "if ctx[:contract]"
            lines << "  ctx[:contract].sync"
            lines << "else"
            lines << "  _allowed = ctx[:params].to_h.with_indifferent_access.slice(*_model_class.attribute_names)"
            lines << "  _record.assign_attributes(_allowed)"
            lines << "end"
            lines << "_record.customer_id = ctx[:customer_id]"
            lines << "_record.save!"
            lines << "ctx[:#{target}] = _record"
            lines.join("\n")
          end

          def build_find_or_create_by(match_fields, target, created_key)
            lines = []
            lines << "_model_class = EntityEntry.build_for(ctx[:bound_entity])"
            lines << "_record = _model_class.find_or_create_by(#{match_hash(match_fields)}) do |_r|"
            lines << "  if ctx[:contract]"
            lines << "    ctx[:contract].sync"
            lines << "  else"
            lines << "    _allowed = ctx[:params].to_h.with_indifferent_access.slice(*_model_class.attribute_names)"
            lines << "    _r.assign_attributes(_allowed)"
            lines << "  end"
            lines << "  _r.customer_id = ctx[:customer_id]"
            lines << "end"
            lines << "ctx[:#{created_key}] = _record.saved_change_to_id?" if created_key.present?
            lines << "ctx[:#{target}] = _record"
            lines.join("\n")
          end

          def build_upsert(match_fields, target, created_key)
            unique_by_keys = resolve_unique_by(match_fields)
            on_conflict = fetch_enum("onConflict", ON_CONFLICT, default: "update")
            timestamps = fetch_enum("timestamps", BOOL_STRINGS, default: "true") == "true"
            returning_keys = resolve_returning

            payload_lines = [
              "_model_class = EntityEntry.build_for(ctx[:bound_entity])",
              "_payload = #{build_model_assignment(mode: :payload, model_var: target, class_expr: '_model_class')}"
            ]
            match_fields.each { |f| payload_lines << "_payload[:#{f}] = ctx[:#{f}]" }
            payload_lines << "_payload[:customer_id] = ctx[:customer_id]"

            if on_conflict == "raise"
              payload_lines << "if _model_class.exists?(#{match_hash(match_fields)})"
              payload_lines << "  raise ActiveRecord::RecordNotUnique, \"Record already exists for #{match_fields.join(', ')}\""
              payload_lines << "end"
              options = upsert_options(unique_by_keys, :update_all, timestamps, returning_keys)
              payload_lines << "_result = _model_class.upsert(_payload, #{options})"
              payload_lines << "ctx[:#{created_key}] = true" if created_key.present?
            else
              options = upsert_options(unique_by_keys, on_duplicate_sym(on_conflict), timestamps, returning_keys)
              payload_lines << "_result = _model_class.upsert(_payload, #{options})"
              payload_lines << "ctx[:#{created_key}] = _result.rows.any?" if created_key.present?
            end

            payload_lines << "ctx[:#{target}] = _result"
            payload_lines.join("\n")
          end

          def build_upsert_all(match_fields, target)
            lines = []
            lines << "_model_class = EntityEntry.build_for(ctx[:bound_entity])"
            lines << "_payload = #{build_model_assignment(mode: :payload, model_var: target, class_expr: '_model_class')}"
            match_fields.each { |f| lines << "_payload[:#{f}] = ctx[:#{f}]" }
            lines << "_payload[:customer_id] = ctx[:customer_id]"
            lines << "_result = _model_class.upsert_all([_payload], unique_by: #{match_fields.map(&:to_sym).inspect})"
            lines << "ctx[:#{target}] = _result"
            lines.join("\n")
          end

          def upsert_options(unique_by_keys, on_duplicate, timestamps, returning_keys)
            parts = []
            parts << "unique_by: #{unique_by_keys.inspect}"
            parts << "on_duplicate: :#{on_duplicate}"
            parts << "returning: #{returning_keys.inspect}" if returning_keys.any?
            parts << "record_timestamps: #{timestamps}"
            parts.join(", ")
          end

          def resolve_unique_by(match_fields)
            keys = extract_key_value_list(config["uniqueBy"])
            keys = match_fields if keys.empty?
            Array(keys).compact.reject { |k| k.to_s.empty? }.map(&:to_sym)
          end

          def resolve_returning
            extract_key_value_list(config["returning"]).compact.reject { |k| k.to_s.empty? }.map(&:to_sym)
          end

          def extract_key_value_list(raw)
            case raw
            when Hash  then raw.keys
            when Array then raw.map { |e| e.is_a?(Hash) ? (e["key"] || e[:key]) : e }
            else []
            end
          end

          def on_duplicate_sym(on_conflict)
            on_conflict == "skip" ? "skip" : "update_all"
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4.4: Run the spec to verify it passes**

Run:
```bash
bundle exec rspec spec/services/code_generators/element_types/process/model_operations/upsert_model_generator_spec.rb --format documentation
```

Expected: PASS.

- [ ] **Step 4.5: Stage for user commit**

Run:
```bash
git add app/services/code_generators/element_types/process/model_operations/upsert_model_generator.rb spec/services/code_generators/element_types/process/model_operations/upsert_model_generator_spec.rb
git status
```

Suggested commit message: `refactor(codegen): rewrite upsert_model generator to use contract/params source`

---

## Task 5: Sweep process-element step generators — remove error-wrapping

These 38 generators all follow the same pattern. The sweep removes three things from each:
1. `include CodeGenerators::Shared::ErrorWrapper`
2. `error_strategy = config["errorStrategy"]` (or equivalent)
3. The `if error_strategy.present? ... wrap_with_error_strategy(..., source: "...", strategy: error_strategy) else "#{inner}\ntrue" end` branch → replaced with `inner` or `"#{inner}\ntrue"` depending on whether the inner body ends in a meaningful truthy expression.

**Files (38 generators):** Listed in the "File structure" section above under "Modified files — process step generators".

Because each file is structurally similar, this task runs in small batches with a verification run after each batch. For each file, follow steps 5.A.1-5.A.4.

- [ ] **Step 5.A.1: For one file, read current state**

Open the file. Locate:
- The `include CodeGenerators::Shared::ErrorWrapper` line near the top of the class.
- The `error_strategy = config["errorStrategy"]` line (usually early in `generate_body`).
- The final `if error_strategy.present? / else / end` branch at the end of `generate_body`.

- [ ] **Step 5.A.2: Edit the file**

Apply these edits:

**a.** Delete the `include CodeGenerators::Shared::ErrorWrapper` line.

**b.** Delete the `error_strategy = config["errorStrategy"]` line.

**c.** Replace the closing branch:

From:
```ruby
if error_strategy.present?
  wrap_with_error_strategy(inner, source: "some_source", strategy: error_strategy)
else
  "#{inner}\ntrue"
end
```

To (pick the right variant — inspect what `inner` ends with):
- If `inner`'s last expression is already a truthy method call that should be the step result (e.g. `.save`, `.valid?`), return `inner` directly.
- Otherwise, return `"#{inner}\ntrue"`.

**Safe default:** `"#{inner}\ntrue"` preserves Railway success semantics in all cases — only skip the trailing `true` when you are certain the inner expression already returns a truthy value.

- [ ] **Step 5.A.3: Run that generator's spec**

Run:
```bash
bundle exec rspec spec/services/code_generators/element_types/process/<dir>/<file>_spec.rb --format progress
```

Expected: some failures — the spec still asserts begin/rescue and `errorStrategy` behavior. **Leave the spec failing for now**; we fix all specs in a single batched sweep in Task 6.

- [ ] **Step 5.A.4: Move to the next file**

Batch list (sweep in this order; stage each batch separately so diffs stay reviewable):

**Batch 5.1 — background (2):** `background/enqueue_job_generator.rb`, `background/schedule_job_generator.rb`
**Batch 5.2 — caching (4):** `caching/cache_delete_generator.rb`, `caching/cache_fetch_generator.rb`, `caching/cache_read_generator.rb`, `caching/cache_write_generator.rb`
**Batch 5.3 — communication (4):** `communication/api_call_generator.rb`, `communication/notify_generator.rb`, `communication/send_email_generator.rb`, `communication/send_webhook_generator.rb`
**Batch 5.4 — concurrency + data_operations (7):** `concurrency/acquire_lock_generator.rb`, `data_operations/base64_encode_decode_generator.rb`, `data_operations/compare_data_generator.rb`, `data_operations/log_generator.rb`, `data_operations/merge_data_generator.rb`, `data_operations/parse_data_generator.rb`, `data_operations/regex_extract_generator.rb`
**Batch 5.5 — file_operations (6):** `file_operations/compress_files_generator.rb`, `file_operations/decompress_files_generator.rb`, `file_operations/download_file_generator.rb`, `file_operations/generate_file_generator.rb`, `file_operations/parse_csv_generator.rb`, `file_operations/upload_file_generator.rb`
**Batch 5.6 — model_operations (remaining 14):** `model_operations/aggregate_query_generator.rb`, `model_operations/batch_operation_generator.rb`, `model_operations/bulk_import_generator.rb`, `model_operations/check_existence_generator.rb`, `model_operations/clone_model_generator.rb`, `model_operations/count_records_generator.rb`, `model_operations/destroy_model_generator.rb`, `model_operations/find_model_generator.rb`, `model_operations/pluck_fields_generator.rb`, `model_operations/query_models_generator.rb`, `model_operations/raw_sql_query_generator.rb`, `model_operations/save_model_generator.rb`, `model_operations/soft_delete_model_generator.rb`, `model_operations/transition_state_generator.rb`
**Batch 5.7 — security + validation (5):** `security/authenticate_generator.rb`, `security/decrypt_data_generator.rb`, `security/verify_token_generator.rb`, `validation/build_contract_generator.rb`, `validation/validate_contract_generator.rb`

- [ ] **Step 5.B: After each batch, verify no includes remain in that batch**

Run after each batch:
```bash
grep -l "Shared::ErrorWrapper\|errorStrategy" app/services/code_generators/element_types/process/<dir>/*.rb
```

Expected: empty output. If non-empty, revisit the listed files.

- [ ] **Step 5.C: Stage each batch for user commit**

After each batch, run:
```bash
git add app/services/code_generators/element_types/process/<dir>/
git status
```

Suggested commit message per batch: `refactor(codegen): remove per-step errorStrategy from <dir> generators`

- [ ] **Step 5.D: Final verification — no generator still references errorStrategy or ErrorWrapper**

After all batches, run:
```bash
grep -rln "Shared::ErrorWrapper" app/services/code_generators/element_types/process/
grep -rln "errorStrategy\|wrap_with_error_strategy" app/services/code_generators/element_types/process/
```

Expected: both empty.

---

## Task 6: Sweep specs — remove errorStrategy test paths

**Files:** Roughly 60 spec files under `spec/services/code_generators/element_types/process/**/*_generator_spec.rb` (plus `spec/services/code_generators/base_generator_spec.rb`). The three model-generator specs are already rewritten in Tasks 2-4; skip those here.

Each spec file needs three classes of changes:
1. Delete every `context` / `describe` / `it` block that sets `errorStrategy` in config or asserts begin/rescue / `_last_error` / `wrap_with_error_strategy` output.
2. Delete `let(:error_strategy_config) { ... }` helpers if they exist.
3. Leave the rest of the spec unchanged.

- [ ] **Step 6.1: List all spec files needing changes**

Run:
```bash
grep -rl "errorStrategy\|_last_error\|wrap_with_error_strategy" spec/services/code_generators/
```

Save this list. Exclude the three model-generator specs already rewritten:
- `spec/services/code_generators/element_types/process/model_operations/new_model_generator_spec.rb`
- `spec/services/code_generators/element_types/process/model_operations/update_model_generator_spec.rb`
- `spec/services/code_generators/element_types/process/model_operations/upsert_model_generator_spec.rb`

- [ ] **Step 6.2: For each spec, remove error-strategy blocks**

For each file in the list, open it and delete:
- Any `context "when errorStrategy is set"` / `context "with errorStrategy"` blocks in full.
- Any `it` examples that set `"errorStrategy" => "..."` in their config hash.
- Any assertions like `expect(code).to include("begin")`, `expect(code).to include("rescue")`, `expect(code).to include("ctx[:_last_error]")`, `expect(code).to include("wrap_with_error_strategy")`.
- Any shared `let(:error_strategy_config)` or similar helpers if they become unused.

Keep everything else — DO NOT rewrite these specs.

- [ ] **Step 6.3: Run specs incrementally by directory**

After each directory is swept, run:
```bash
bundle exec rspec spec/services/code_generators/element_types/process/<dir>/ --format progress
```

Expected: 0 failures. If a failure remains, the generator's output no longer matches some non-error assertion — inspect the generator's output and either fix the spec or revert that spec assertion to match the new plain body.

- [ ] **Step 6.4: Update `base_generator_spec.rb`**

Open `spec/services/code_generators/base_generator_spec.rb`. Remove any example that tests `current_error_strategy` or the `ErrorWrapper` include. Leave everything else.

- [ ] **Step 6.5: Verify no spec still references removed symbols**

Run:
```bash
grep -rln "errorStrategy\|_last_error\|wrap_with_error_strategy" spec/services/code_generators/ | grep -v "model_assignment_builder_spec"
```

Expected: only possibly `spec/services/code_generators/shared/error_wrapper_spec.rb` (deleted in Task 7).

- [ ] **Step 6.6: Run the full code_generators spec suite**

Run:
```bash
bundle exec rspec spec/services/code_generators/ --format progress 2>&1 | tail -15
```

Expected: 0 failures. Lower total example count than baseline (error-strategy examples removed outweigh added contract/params examples).

- [ ] **Step 6.7: Stage for user commit**

Run:
```bash
git add spec/services/code_generators/
git status
```

Suggested commit message: `test(codegen): remove errorStrategy test paths from step generator specs`

---

## Task 7: Delete `ErrorWrapper` module and update `BaseGenerator`

**Files:**
- Delete: `app/services/code_generators/shared/error_wrapper.rb`
- Delete: `spec/services/code_generators/shared/error_wrapper_spec.rb`
- Modify: `app/services/code_generators/base_generator.rb`

- [ ] **Step 7.1: Remove the module include + helper from BaseGenerator**

Open `app/services/code_generators/base_generator.rb`. Delete the following lines:

1. Line 5: `require_relative "shared/error_wrapper"`
2. Line 12: `include Shared::ErrorWrapper`
3. Lines 31-34: the `def current_error_strategy / end` method block.

After the edit, `base_generator.rb` should still have:

```ruby
require_relative "generator_interface"
require_relative "shared/ctx_reader"
require_relative "shared/config_field_reader"

module CodeGenerators
  class BaseGenerator
    include GeneratorInterface
    include Shared::CtxReader
    include Shared::ConfigFieldReader
    # ... rest unchanged
```

- [ ] **Step 7.2: Delete the module file and its spec**

Run:
```bash
rm app/services/code_generators/shared/error_wrapper.rb
rm spec/services/code_generators/shared/error_wrapper_spec.rb
```

- [ ] **Step 7.3: Run the full generator spec suite**

Run:
```bash
bundle exec rspec spec/services/code_generators/ --format progress 2>&1 | tail -15
```

Expected: 0 failures. If any spec still references `Shared::ErrorWrapper`, that reference was missed in Task 6 — grep for it and remove:
```bash
grep -rn "Shared::ErrorWrapper\|ErrorWrapper" spec/ app/ 2>&1 | head
```

- [ ] **Step 7.4: Stage for user commit**

Run:
```bash
git add -u
git status
```

Suggested commit message: `refactor(codegen): delete ErrorWrapper shared module`

---

## Task 8: Sweep action config JS — remove `errorStrategy` and model assignment fields

**Files:**
- Modify: `app/javascript/flowchart/constants/action_configs/model_actions.js`
- Modify: `app/javascript/flowchart/constants/action_configs/caching_actions.js` (3 `errorStrategy`)
- Modify: `app/javascript/flowchart/constants/action_configs/file_actions.js` (2)
- Modify: `app/javascript/flowchart/constants/action_configs/resilience_actions.js` (2)
- Modify: `app/javascript/flowchart/constants/action_configs/scheduling_actions.js` (2)
- Modify: `app/javascript/flowchart/constants/action_configs/security_actions.js` (1)
- Modify: `app/javascript/flowchart/constants/action_configs/service_actions.js` (1)
- Modify: `app/javascript/flowchart/constants/action_configs/utility_actions.js` (4)
- Modify: `app/javascript/flowchart/constants/action_configs/validation_actions.js` (1)

- [ ] **Step 8.1: Remove the three assignment fields from `model_actions.js`**

In `app/javascript/flowchart/constants/action_configs/model_actions.js`:

**a.** `new_model` (lines 14-25): remove the two field entries with `key: "attributes"` and `key: "associations"`. Result: `new_model.configSchema` contains only `resultVar`.

**b.** `update_model` (around line 292): remove the entry with `key: "fieldMappings"`. Keep `modelVariable`, `updateStrategy`, `runCallbacks`, `returnChanges`, `lockVersion`, `lockVersionVariable`.

**c.** `upsert_model` (around line 637): remove the entry with `key: "attributes"`. Keep `matchFields`, `uniqueBy`, `method`, `onConflict`, `timestamps`, `returning`, `outputKey`, `createdKey`.

- [ ] **Step 8.2: For each of the 8 other JS files, remove every `errorStrategy` field entry**

For each file, locate every object literal with `key: "errorStrategy"` — these are typically 6-12 lines like:

```js
{
  key: "errorStrategy",
  type: "select",
  label: "Error Strategy",
  options: [
    { value: "continue", label: "Continue on error" },
    { value: "fail_track", label: "Fail track" },
    { value: "raise",    label: "Raise" }
  ]
},
```

Delete each such entry in full, including the trailing comma if it's the last entry before the `]`.

- [ ] **Step 8.3: Verify no `errorStrategy` remains in action configs**

Run:
```bash
grep -rn "errorStrategy" app/javascript/flowchart/constants/action_configs/
```

Expected: empty.

- [ ] **Step 8.4: Verify no other JS references remain**

Run:
```bash
grep -rn "errorStrategy" app/javascript/
```

Expected: empty (or limited to a backward-compat hook that can also be removed). If any usage remains in `property_editor/` controllers or schema validators, remove it.

- [ ] **Step 8.5: Rebuild the CSS/JS bundle**

Run:
```bash
bin/rails tailwindcss:build 2>&1 | tail -5
# or the project's equivalent: bin/rails assets:precompile or yarn build
```

Expected: success with no errors. If the JS pipeline has a syntax error from a misplaced comma, inspect the offending file.

- [ ] **Step 8.6: Stage for user commit**

Run:
```bash
git add app/javascript/flowchart/constants/action_configs/ app/assets/builds/
git status
```

Suggested commit message: `chore(ui): remove errorStrategy and model attribute fields from action configs`

---

## Task 9: Integration verification

**Files:**
- Read-only verification.

- [ ] **Step 9.1: Run the full `spec/services/code_generators/` suite**

Run:
```bash
bundle exec rspec spec/services/code_generators/ --format progress 2>&1 | tail -10
```

Expected: 0 failures. Example count should be lower than baseline 4331 by roughly 50-200 examples (error-strategy contexts removed outweigh added contract/params contexts).

- [ ] **Step 9.2: Run the full app test suite**

Run:
```bash
bundle exec rspec --format progress 2>&1 | tail -20
```

Expected: 0 failures across the entire project. If non-codegen specs fail, investigate — they should not be affected by this change.

- [ ] **Step 9.3: Run the generator↔UI audit script**

Per project memory, `scripts/audit_generator_ui.rb` is the audit toolchain for generator↔UI alignment. Run:

```bash
bundle exec rails runner scripts/audit_generator_ui.rb 2>&1 | tail -30
```

Expected: the audit should still pass. The dropped fields (`attributes`, `associations`, `fieldMappings`, `errorStrategy`) are now absent from both sides, so no new mismatches.

- [ ] **Step 9.4: Refresh the config schemas mirror**

Per project memory, `rake config_schemas:mirror` regenerates `spec/support/config_schemas.rb` from the JS action configs. Run:

```bash
bundle exec rake config_schemas:mirror
```

Then re-run the codegen specs:
```bash
bundle exec rspec spec/services/code_generators/ --format progress 2>&1 | tail -10
```

Expected: still 0 failures.

- [ ] **Step 9.5: Stage the mirror refresh for user commit**

Run:
```bash
git add spec/support/config_schemas.rb
git status
```

Suggested commit message: `chore(codegen): refresh config schemas mirror after action config cleanup`

---

## Task 10: Manual UI verification

**Files:**
- Read-only verification in a running dev server.

- [ ] **Step 10.1: Boot the dev server**

Run:
```bash
bin/dev
# or: bin/rails s
```

Wait for the server to be ready.

- [ ] **Step 10.2: Open a flowchart in the edit page**

In a browser, navigate to the flowchart edit page for an existing flowchart. Drag or select a `process` element and add a `new_model` step.

- [ ] **Step 10.3: Verify the `new_model` property editor**

Expected fields shown:
- `resultVar` (text, default "model")

Expected fields NOT shown:
- `attributes`
- `associations`
- `errorStrategy`

- [ ] **Step 10.4: Verify `update_model` and `upsert_model` similarly**

Repeat step 10.3 for `update_model` (should show `modelVariable`, `updateStrategy`, `runCallbacks`, `returnChanges`, `lockVersion`, `lockVersionVariable`, and nothing else assignment-related; no `fieldMappings`, no `errorStrategy`).

Repeat for `upsert_model` (should show `matchFields`, `uniqueBy`, `method`, `onConflict`, `timestamps`, `returning`, `outputKey`, `createdKey`; no `attributes`, no `errorStrategy`).

- [ ] **Step 10.5: Spot-check a non-model step**

Add a `save_model` step (or any other process step, e.g. `api_call`, `cache_fetch`). Verify:
- `errorStrategy` is NOT shown.
- All other fields are still present.

- [ ] **Step 10.6: Generate code for a flowchart containing `build_contract` → `validate_contract` → `new_model` → `save_model`**

Use whichever mechanism the project provides to preview generated code (e.g. a "Generate Code" button on the flowchart edit page, or `rails runner` against `CodeGenerators::ActivityGenerator`). Inspect the generated activity.

Expected in the generated code:
- The `new_model` step body contains `ctx[:contract].sync`.
- The `new_model` step body contains `ctx[:model].customer_id = ctx[:customer_id]`.
- No step body contains `begin` / `rescue` / `ctx[:_last_error]` from `ErrorWrapper` (element-level retry/timeout wrappers are still allowed).

- [ ] **Step 10.7: Final cleanup — ensure no stray files remain**

Run:
```bash
grep -rn "ErrorWrapper\|wrap_with_error_strategy\|errorStrategy\|_last_error" app/ spec/ 2>&1 | head
```

Expected: empty (or only in commit/plan documentation).

- [ ] **Step 10.8: Stage anything left for user commit**

Run:
```bash
git status
```

If there are stray build artifacts or asset changes, stage them with `git add` and suggest the user commit.

---

## Post-plan baseline

After all tasks: re-run the baseline grep from Task 0:

```bash
echo "generators with ErrorWrapper include:"; grep -rln "Shared::ErrorWrapper" app/services/code_generators/element_types/process/ | wc -l       # expect 0
echo "generators with errorStrategy read:"; grep -rln "errorStrategy" app/services/code_generators/element_types/process/ | wc -l                # expect 0
echo "JS action_configs with errorStrategy:"; grep -rln "errorStrategy" app/javascript/flowchart/constants/action_configs/ | wc -l               # expect 0
echo "specs with errorStrategy/_last_error/wrap_with_error_strategy:"; grep -rln "errorStrategy\|_last_error\|wrap_with_error_strategy" spec/services/code_generators/ | wc -l  # expect 0
```

All four should report `0`.
