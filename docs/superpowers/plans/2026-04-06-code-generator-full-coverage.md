# Code Generator Full Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 51 new code generators to bring the platform from 59 to 110 step action generators, covering all significant programming primitives for a general-purpose zero-coding platform.

**Architecture:** All generators follow the existing `BaseGenerator` interface pattern: `generator_metadata` block, `generate` method returning Ruby code strings, `validate_config` returning error arrays. Generators are file-based, auto-discovered by `GeneratorRegistry`. Each generator is a self-contained Ruby class under `app/services/code_generators/element_types/process/<category>/`.

**Tech Stack:** Ruby 3.2, Rails 8.1, Trailblazer Activity, RSpec, FactoryBot

**Spec:** `docs/superpowers/specs/2026-04-06-code-generator-full-coverage-design.md`

---

## File Structure

### Infrastructure Changes
- Modify: `app/services/code_generators/source_assembler.rb` (add 4 new categories to CATEGORIES)

### New Directories (4)
- `app/services/code_generators/element_types/process/human_workflow/`
- `app/services/code_generators/element_types/process/resilience/`
- `app/services/code_generators/element_types/process/scheduling_time/`
- `app/services/code_generators/element_types/process/utility/`

### New Generator Files (51)
**Data Operations (15):**
- `app/services/code_generators/element_types/process/data_operations/reduce_collection_generator.rb`
- `app/services/code_generators/element_types/process/data_operations/flatten_collection_generator.rb`
- `app/services/code_generators/element_types/process/data_operations/zip_collections_generator.rb`
- `app/services/code_generators/element_types/process/data_operations/chunk_collection_generator.rb`
- `app/services/code_generators/element_types/process/data_operations/partition_collection_generator.rb`
- `app/services/code_generators/element_types/process/data_operations/find_in_collection_generator.rb`
- `app/services/code_generators/element_types/process/data_operations/any_all_none_check_generator.rb`
- `app/services/code_generators/element_types/process/data_operations/coalesce_value_generator.rb`
- `app/services/code_generators/element_types/process/data_operations/type_cast_generator.rb`
- `app/services/code_generators/element_types/process/data_operations/string_manipulate_generator.rb`
- `app/services/code_generators/element_types/process/data_operations/math_operation_generator.rb`
- `app/services/code_generators/element_types/process/data_operations/hash_manipulate_generator.rb`
- `app/services/code_generators/element_types/process/data_operations/base64_encode_decode_generator.rb`
- `app/services/code_generators/element_types/process/data_operations/generate_id_generator.rb`
- `app/services/code_generators/element_types/process/data_operations/compare_data_generator.rb`

**Model Operations (5):**
- `app/services/code_generators/element_types/process/model_operations/upsert_model_generator.rb`
- `app/services/code_generators/element_types/process/model_operations/clone_model_generator.rb`
- `app/services/code_generators/element_types/process/model_operations/soft_delete_model_generator.rb`
- `app/services/code_generators/element_types/process/model_operations/bulk_import_generator.rb`
- `app/services/code_generators/element_types/process/model_operations/raw_sql_query_generator.rb`

**Security (4):**
- `app/services/code_generators/element_types/process/security/verify_token_generator.rb`
- `app/services/code_generators/element_types/process/security/decrypt_data_generator.rb`
- `app/services/code_generators/element_types/process/security/sanitize_input_generator.rb`
- `app/services/code_generators/element_types/process/security/mask_data_generator.rb`

**File Operations (4):**
- `app/services/code_generators/element_types/process/file_operations/parse_csv_generator.rb`
- `app/services/code_generators/element_types/process/file_operations/generate_csv_generator.rb`
- `app/services/code_generators/element_types/process/file_operations/compress_files_generator.rb`
- `app/services/code_generators/element_types/process/file_operations/decompress_files_generator.rb`

**Caching (2):**
- `app/services/code_generators/element_types/process/caching/cache_delete_generator.rb`
- `app/services/code_generators/element_types/process/caching/cache_fetch_generator.rb`

**Concurrency (1):**
- `app/services/code_generators/element_types/process/concurrency/release_lock_generator.rb`

**Response (1):**
- `app/services/code_generators/element_types/process/response/redirect_response_generator.rb`

**Human Workflow (4):**
- `app/services/code_generators/element_types/process/human_workflow/approval_gate_generator.rb`
- `app/services/code_generators/element_types/process/human_workflow/assign_task_generator.rb`
- `app/services/code_generators/element_types/process/human_workflow/user_input_request_generator.rb`
- `app/services/code_generators/element_types/process/human_workflow/escalation_generator.rb`

**Resilience (4):**
- `app/services/code_generators/element_types/process/resilience/circuit_breaker_generator.rb`
- `app/services/code_generators/element_types/process/resilience/rate_limiter_generator.rb`
- `app/services/code_generators/element_types/process/resilience/retry_with_backoff_generator.rb`
- `app/services/code_generators/element_types/process/resilience/idempotency_check_generator.rb`

**Scheduling/Time (3):**
- `app/services/code_generators/element_types/process/scheduling_time/deadline_check_generator.rb`
- `app/services/code_generators/element_types/process/scheduling_time/business_hours_check_generator.rb`
- `app/services/code_generators/element_types/process/scheduling_time/timezone_convert_generator.rb`

**Utility (8):**
- `app/services/code_generators/element_types/process/utility/template_render_generator.rb`
- `app/services/code_generators/element_types/process/utility/audit_log_generator.rb`
- `app/services/code_generators/element_types/process/utility/ai_inference_generator.rb`
- `app/services/code_generators/element_types/process/utility/qr_code_generate_generator.rb`
- `app/services/code_generators/element_types/process/utility/barcode_generate_generator.rb`
- `app/services/code_generators/element_types/process/utility/geolocation_lookup_generator.rb`
- `app/services/code_generators/element_types/process/utility/currency_convert_generator.rb`
- `app/services/code_generators/element_types/process/utility/i18n_translate_generator.rb`

### New Test Files (51 — mirror generator paths under spec/)
Each generator at `app/services/.../foo_generator.rb` has a corresponding `spec/services/.../foo_generator_spec.rb`.

---

## Task 0: Infrastructure Setup

**Files:**
- Modify: `app/services/code_generators/source_assembler.rb`
- Create: 4 new directories

- [ ] **Step 1: Add new categories to SourceAssembler::CATEGORIES**

```ruby
# In app/services/code_generators/source_assembler.rb, change the CATEGORIES constant to:
CATEGORIES = %i[
  flow_control model_operations validation data_operations
  communication security background file_operations realtime response
  concurrency service_invocation caching
  human_workflow resilience scheduling_time utility
].freeze
```

- [ ] **Step 2: Create new category directories**

```bash
mkdir -p app/services/code_generators/element_types/process/human_workflow
mkdir -p app/services/code_generators/element_types/process/resilience
mkdir -p app/services/code_generators/element_types/process/scheduling_time
mkdir -p app/services/code_generators/element_types/process/utility
mkdir -p spec/services/code_generators/element_types/process/human_workflow
mkdir -p spec/services/code_generators/element_types/process/resilience
mkdir -p spec/services/code_generators/element_types/process/scheduling_time
mkdir -p spec/services/code_generators/element_types/process/utility
```

- [ ] **Step 3: Verify registry discovers existing generators**

```bash
bundle exec rails runner "CodeGenerators::GeneratorRegistry.reload!; puts CodeGenerators::GeneratorRegistry.step_action_generators.count"
```

Expected: current generator count (should be ~59 or close)

- [ ] **Step 4: Commit**

```bash
git add app/services/code_generators/source_assembler.rb
git commit -m "chore: add human_workflow, resilience, scheduling_time, utility categories to SourceAssembler"
```

---

## Task 1: Data Operations — Collection Reducers (reduce, flatten, zip, chunk)

**Files:**
- Create: `app/services/code_generators/element_types/process/data_operations/reduce_collection_generator.rb`
- Create: `app/services/code_generators/element_types/process/data_operations/flatten_collection_generator.rb`
- Create: `app/services/code_generators/element_types/process/data_operations/zip_collections_generator.rb`
- Create: `app/services/code_generators/element_types/process/data_operations/chunk_collection_generator.rb`
- Test: `spec/services/code_generators/element_types/process/data_operations/reduce_collection_generator_spec.rb`
- Test: `spec/services/code_generators/element_types/process/data_operations/flatten_collection_generator_spec.rb`
- Test: `spec/services/code_generators/element_types/process/data_operations/zip_collections_generator_spec.rb`
- Test: `spec/services/code_generators/element_types/process/data_operations/chunk_collection_generator_spec.rb`

- [ ] **Step 1: Write tests for all 4 generators**

```ruby
# spec/services/code_generators/element_types/process/data_operations/reduce_collection_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::ReduceCollectionGenerator do
  let(:element) { { "config" => { "collectionKey" => "items", "operation" => "sum", "field" => "amount", "outputKey" => "total" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates sum reduction" do
      code = described_class.new(element, context).generate
      expect(code).to include("ctx[:total]")
      expect(code).to include("ctx[:items]")
      expect(code).to include("sum")
      expect(code).to include("true")
    end

    it "generates product reduction" do
      el = { "config" => { "collectionKey" => "nums", "operation" => "product", "field" => "value", "outputKey" => "result" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("inject")
      expect(code).to include("ctx[:result]")
    end

    it "generates concat reduction" do
      el = { "config" => { "collectionKey" => "parts", "operation" => "concat", "field" => "text", "outputKey" => "combined" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("join")
      expect(code).to include("ctx[:combined]")
    end

    it "generates custom expression reduction" do
      el = { "config" => { "collectionKey" => "items", "operation" => "custom", "customExpression" => "acc + item[:val]", "initialValue" => "0", "outputKey" => "total" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("inject")
      expect(code).to include("acc + item[:val]")
    end

    it "uses default values when config is minimal" do
      el = { "config" => {} }
      code = described_class.new(el, {}).generate
      expect(code).to include("ctx[:items]")
      expect(code).to include("ctx[:result]")
    end
  end

  describe "#validate_config" do
    it "requires collectionKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("collectionKey is required")
    end

    it "validates operation is in allowed list" do
      errors = described_class.new(element, {}).validate_config({ "collectionKey" => "x", "operation" => "invalid" })
      expect(errors).to include(/Invalid operation/)
    end

    it "requires customExpression for custom operation" do
      errors = described_class.new(element, {}).validate_config({ "collectionKey" => "x", "operation" => "custom" })
      expect(errors).to include("customExpression is required for custom operation")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/data_operations/flatten_collection_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::FlattenCollectionGenerator do
  let(:element) { { "config" => { "collectionKey" => "nested", "outputKey" => "flat" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates flatten code" do
      code = described_class.new(element, context).generate
      expect(code).to include("ctx[:flat]")
      expect(code).to include("ctx[:nested]")
      expect(code).to include("flatten")
      expect(code).to include("true")
    end

    it "respects depth parameter" do
      el = { "config" => { "collectionKey" => "nested", "depth" => 1, "outputKey" => "flat" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("flatten(1)")
    end

    it "uses unlimited depth by default" do
      code = described_class.new(element, {}).generate
      expect(code).to include(".flatten\n").or include(".flatten\r")
    end
  end

  describe "#validate_config" do
    it "requires collectionKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("collectionKey is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/data_operations/zip_collections_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::ZipCollectionsGenerator do
  let(:element) { { "config" => { "collectionKeys" => ["keys", "values"], "mode" => "tuples", "outputKey" => "pairs" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates zip with tuples mode" do
      code = described_class.new(element, context).generate
      expect(code).to include("ctx[:keys]")
      expect(code).to include("zip")
      expect(code).to include("ctx[:pairs]")
      expect(code).to include("true")
    end

    it "generates zip with merge mode" do
      el = { "config" => { "collectionKeys" => ["a", "b"], "mode" => "merge", "outputKey" => "merged" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("zip")
      expect(code).to include("merge")
      expect(code).to include("ctx[:merged]")
    end

    it "handles more than 2 collections" do
      el = { "config" => { "collectionKeys" => ["a", "b", "c"], "mode" => "tuples", "outputKey" => "result" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("ctx[:b]")
      expect(code).to include("ctx[:c]")
    end
  end

  describe "#validate_config" do
    it "requires collectionKeys" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("collectionKeys is required")
    end

    it "requires at least 2 collection keys" do
      errors = described_class.new(element, {}).validate_config({ "collectionKeys" => ["only_one"] })
      expect(errors).to include("At least 2 collection keys are required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/data_operations/chunk_collection_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::ChunkCollectionGenerator do
  let(:element) { { "config" => { "collectionKey" => "items", "chunkSize" => 10, "outputKey" => "batches" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates each_slice code" do
      code = described_class.new(element, context).generate
      expect(code).to include("each_slice(10)")
      expect(code).to include("ctx[:batches]")
      expect(code).to include("to_a")
      expect(code).to include("true")
    end

    it "uses default chunk size of 100" do
      el = { "config" => { "collectionKey" => "items", "outputKey" => "batches" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("each_slice(100)")
    end
  end

  describe "#validate_config" do
    it "requires collectionKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("collectionKey is required")
    end

    it "validates chunkSize is positive" do
      errors = described_class.new(element, {}).validate_config({ "collectionKey" => "x", "chunkSize" => 0 })
      expect(errors).to include("chunkSize must be a positive integer")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/data_operations/reduce_collection_generator_spec.rb spec/services/code_generators/element_types/process/data_operations/flatten_collection_generator_spec.rb spec/services/code_generators/element_types/process/data_operations/zip_collections_generator_spec.rb spec/services/code_generators/element_types/process/data_operations/chunk_collection_generator_spec.rb 2>&1 | tail -5
```

Expected: FAIL — classes not found

- [ ] **Step 3: Implement all 4 generators**

```ruby
# app/services/code_generators/element_types/process/data_operations/reduce_collection_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class ReduceCollectionGenerator < BaseGenerator
          OPERATIONS = %w[sum product concat min max custom].freeze

          generator_metadata do
            description "Folds/accumulates a collection to a single value"
            category :data_operations
            version "1.0.0"
          end

          input_schema  :collection_key
          output_schema :output_key

          def generate
            collection = config["collectionKey"] || "items"
            operation = config["operation"] || "sum"
            field = config["field"]
            target = config["outputKey"] || "result"

            code = case operation
                   when "sum"
                     if field.present?
                       "ctx[:#{target}] = ctx[:#{collection}].sum { |item| item[:#{field}].to_f }"
                     else
                       "ctx[:#{target}] = ctx[:#{collection}].sum"
                     end
                   when "product"
                     if field.present?
                       "ctx[:#{target}] = ctx[:#{collection}].inject(1) { |acc, item| acc * item[:#{field}].to_f }"
                     else
                       "ctx[:#{target}] = ctx[:#{collection}].inject(1) { |acc, item| acc * item.to_f }"
                     end
                   when "concat"
                     if field.present?
                       "ctx[:#{target}] = ctx[:#{collection}].map { |item| item[:#{field}] }.join"
                     else
                       "ctx[:#{target}] = ctx[:#{collection}].join"
                     end
                   when "min"
                     if field.present?
                       "ctx[:#{target}] = ctx[:#{collection}].min_by { |item| item[:#{field}] }"
                     else
                       "ctx[:#{target}] = ctx[:#{collection}].min"
                     end
                   when "max"
                     if field.present?
                       "ctx[:#{target}] = ctx[:#{collection}].max_by { |item| item[:#{field}] }"
                     else
                       "ctx[:#{target}] = ctx[:#{collection}].max"
                     end
                   when "custom"
                     initial = config["initialValue"] || "0"
                     expr = config["customExpression"] || "acc"
                     "ctx[:#{target}] = ctx[:#{collection}].inject(#{initial}) { |acc, item| #{expr} }"
                   end

            "#{code}\ntrue"
          end

          def validate_config(cfg)
            errors = []
            errors << "collectionKey is required" if cfg["collectionKey"].blank?
            if cfg["operation"].present? && !OPERATIONS.include?(cfg["operation"])
              errors << "Invalid operation: #{cfg['operation']}. Must be one of: #{OPERATIONS.join(', ')}"
            end
            if cfg["operation"] == "custom" && cfg["customExpression"].blank?
              errors << "customExpression is required for custom operation"
            end
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/data_operations/flatten_collection_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class FlattenCollectionGenerator < BaseGenerator
          generator_metadata do
            description "Flattens nested arrays into a single-level array"
            category :data_operations
            version "1.0.0"
          end

          input_schema  :collection_key
          output_schema :output_key

          def generate
            collection = config["collectionKey"] || "items"
            depth = config["depth"]
            target = config["outputKey"] || "result"

            flatten_call = depth.present? && depth.to_i > 0 ? "flatten(#{depth.to_i})" : "flatten"
            "ctx[:#{target}] = ctx[:#{collection}].#{flatten_call}\ntrue"
          end

          def validate_config(cfg)
            errors = []
            errors << "collectionKey is required" if cfg["collectionKey"].blank?
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/data_operations/zip_collections_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class ZipCollectionsGenerator < BaseGenerator
          generator_metadata do
            description "Combines two or more collections element-wise"
            category :data_operations
            version "1.0.0"
          end

          input_schema  :collection_keys
          output_schema :output_key

          def generate
            keys = config["collectionKeys"] || ["items_a", "items_b"]
            mode = config["mode"] || "tuples"
            target = config["outputKey"] || "result"

            first = "ctx[:#{keys[0]}]"
            rest = keys[1..].map { |k| "ctx[:#{k}]" }.join(", ")

            if mode == "merge"
              <<~RUBY.chomp
                _zipped = #{first}.zip(#{rest})
                ctx[:#{target}] = _zipped.map { |group| group.compact.reduce({}) { |merged, item| merged.merge(item.is_a?(Hash) ? item : { value: item }) } }
                true
              RUBY
            else
              "ctx[:#{target}] = #{first}.zip(#{rest})\ntrue"
            end
          end

          def validate_config(cfg)
            errors = []
            errors << "collectionKeys is required" if cfg["collectionKeys"].blank?
            if cfg["collectionKeys"].is_a?(Array) && cfg["collectionKeys"].length < 2
              errors << "At least 2 collection keys are required"
            end
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/data_operations/chunk_collection_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class ChunkCollectionGenerator < BaseGenerator
          generator_metadata do
            description "Splits a collection into sub-arrays of size N"
            category :data_operations
            version "1.0.0"
          end

          input_schema  :collection_key
          output_schema :output_key

          def generate
            collection = config["collectionKey"] || "items"
            size = (config["chunkSize"] || 100).to_i
            target = config["outputKey"] || "result"

            "ctx[:#{target}] = ctx[:#{collection}].each_slice(#{size}).to_a\ntrue"
          end

          def validate_config(cfg)
            errors = []
            errors << "collectionKey is required" if cfg["collectionKey"].blank?
            if cfg["chunkSize"].present? && cfg["chunkSize"].to_i <= 0
              errors << "chunkSize must be a positive integer"
            end
            errors
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/data_operations/reduce_collection_generator_spec.rb spec/services/code_generators/element_types/process/data_operations/flatten_collection_generator_spec.rb spec/services/code_generators/element_types/process/data_operations/zip_collections_generator_spec.rb spec/services/code_generators/element_types/process/data_operations/chunk_collection_generator_spec.rb --format documentation 2>&1 | tail -20
```

Expected: all tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/data_operations/{reduce_collection,flatten_collection,zip_collections,chunk_collection}_generator.rb spec/services/code_generators/element_types/process/data_operations/{reduce_collection,flatten_collection,zip_collections,chunk_collection}_generator_spec.rb
git commit -m "feat: add reduce, flatten, zip, chunk collection generators"
```

---

## Task 2: Data Operations — Collection Predicates (partition, find_in, any_all_none)

**Files:**
- Create: `app/services/code_generators/element_types/process/data_operations/partition_collection_generator.rb`
- Create: `app/services/code_generators/element_types/process/data_operations/find_in_collection_generator.rb`
- Create: `app/services/code_generators/element_types/process/data_operations/any_all_none_check_generator.rb`
- Test: corresponding spec files

- [ ] **Step 1: Write tests**

```ruby
# spec/services/code_generators/element_types/process/data_operations/partition_collection_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::PartitionCollectionGenerator do
  let(:element) { { "config" => { "collectionKey" => "orders", "filterField" => "status", "filterOperator" => "eq", "filterValue" => "approved", "matchedKey" => "approved", "unmatchedKey" => "rejected" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates partition code" do
      code = described_class.new(element, context).generate
      expect(code).to include("partition")
      expect(code).to include("ctx[:approved]")
      expect(code).to include("ctx[:rejected]")
      expect(code).to include("true")
    end

    it "uses default keys when not specified" do
      el = { "config" => { "collectionKey" => "items", "filterField" => "active", "filterOperator" => "eq", "filterValue" => "true" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("ctx[:matched]")
      expect(code).to include("ctx[:unmatched]")
    end
  end

  describe "#validate_config" do
    it "requires collectionKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("collectionKey is required")
    end

    it "requires filterField" do
      errors = described_class.new(element, {}).validate_config({ "collectionKey" => "x" })
      expect(errors).to include("filterField is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/data_operations/find_in_collection_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::FindInCollectionGenerator do
  let(:element) { { "config" => { "collectionKey" => "invoices", "filterField" => "overdue", "filterOperator" => "eq", "filterValue" => "true", "outputKey" => "found", "indexKey" => "found_index" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates find code with index" do
      code = described_class.new(element, context).generate
      expect(code).to include("ctx[:found]")
      expect(code).to include("ctx[:found_index]")
      expect(code).to include("index")
      expect(code).to include("true")
    end

    it "skips index when indexKey not set" do
      el = { "config" => { "collectionKey" => "items", "filterField" => "id", "filterOperator" => "eq", "filterValue" => "1", "outputKey" => "item" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("detect")
      expect(code).not_to include("index")
    end
  end

  describe "#validate_config" do
    it "requires collectionKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("collectionKey is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/data_operations/any_all_none_check_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::AnyAllNoneCheckGenerator do
  let(:element) { { "config" => { "collectionKey" => "line_items", "checkType" => "all", "filterField" => "price", "filterOperator" => "gt", "filterValue" => "0", "outputKey" => "all_priced" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates all? check" do
      code = described_class.new(element, context).generate
      expect(code).to include("all?")
      expect(code).to include("ctx[:all_priced]")
      expect(code).to include("true")
    end

    it "generates any? check" do
      el = { "config" => { "collectionKey" => "items", "checkType" => "any", "filterField" => "status", "filterOperator" => "eq", "filterValue" => "error", "outputKey" => "has_errors" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("any?")
    end

    it "generates none? check" do
      el = { "config" => { "collectionKey" => "items", "checkType" => "none", "filterField" => "deleted", "filterOperator" => "eq", "filterValue" => "true", "outputKey" => "none_deleted" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("none?")
    end
  end

  describe "#validate_config" do
    it "requires collectionKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("collectionKey is required")
    end

    it "validates checkType is in allowed list" do
      errors = described_class.new(element, {}).validate_config({ "collectionKey" => "x", "checkType" => "invalid" })
      expect(errors).to include(/Invalid checkType/)
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/data_operations/{partition_collection,find_in_collection,any_all_none_check}_generator_spec.rb 2>&1 | tail -5
```

- [ ] **Step 3: Implement generators**

```ruby
# app/services/code_generators/element_types/process/data_operations/partition_collection_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class PartitionCollectionGenerator < BaseGenerator
          OPERATORS = %w[eq ne gt lt gte lte includes blank present].freeze

          generator_metadata do
            description "Splits collection into two groups by predicate"
            category :data_operations
            version "1.0.0"
          end

          input_schema  :collection_key
          output_schema :matched_key, :unmatched_key

          def generate
            collection = config["collectionKey"] || "items"
            field = config["filterField"] || "id"
            operator = config["filterOperator"] || "eq"
            value = config["filterValue"]
            matched = config["matchedKey"] || "matched"
            unmatched = config["unmatchedKey"] || "unmatched"

            condition = build_item_condition(field, operator, value)
            "ctx[:#{matched}], ctx[:#{unmatched}] = ctx[:#{collection}].partition { |item| #{condition} }\ntrue"
          end

          def validate_config(cfg)
            errors = []
            errors << "collectionKey is required" if cfg["collectionKey"].blank?
            errors << "filterField is required" if cfg["filterField"].blank?
            errors
          end

          private

          def build_item_condition(field, operator, value)
            case operator
            when "eq"       then "item[:#{field}] == #{value_literal(value)}"
            when "ne"       then "item[:#{field}] != #{value_literal(value)}"
            when "gt"       then "item[:#{field}] > #{value.to_f}"
            when "lt"       then "item[:#{field}] < #{value.to_f}"
            when "gte"      then "item[:#{field}] >= #{value.to_f}"
            when "lte"      then "item[:#{field}] <= #{value.to_f}"
            when "includes" then "item[:#{field}].to_s.include?(#{value.to_s.inspect})"
            when "blank"    then "item[:#{field}].blank?"
            when "present"  then "item[:#{field}].present?"
            else "item[:#{field}] == #{value_literal(value)}"
            end
          end

          def value_literal(value)
            return "nil" if value.nil?
            value.to_s.match?(/\A-?\d+(\.\d+)?\z/) ? value.to_s : value.to_s.inspect
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/data_operations/find_in_collection_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class FindInCollectionGenerator < BaseGenerator
          OPERATORS = %w[eq ne gt lt gte lte includes blank present].freeze

          generator_metadata do
            description "Finds the first element matching a condition"
            category :data_operations
            version "1.0.0"
          end

          input_schema  :collection_key
          output_schema :output_key, :index_key

          def generate
            collection = config["collectionKey"] || "items"
            field = config["filterField"] || "id"
            operator = config["filterOperator"] || "eq"
            value = config["filterValue"]
            target = config["outputKey"] || "found"
            index_key = config["indexKey"]

            condition = build_item_condition(field, operator, value)

            if index_key.present?
              <<~RUBY.chomp
                ctx[:#{index_key}] = ctx[:#{collection}].index { |item| #{condition} }
                ctx[:#{target}] = ctx[:#{index_key}] ? ctx[:#{collection}][ctx[:#{index_key}]] : nil
                true
              RUBY
            else
              "ctx[:#{target}] = ctx[:#{collection}].detect { |item| #{condition} }\ntrue"
            end
          end

          def validate_config(cfg)
            errors = []
            errors << "collectionKey is required" if cfg["collectionKey"].blank?
            errors
          end

          private

          def build_item_condition(field, operator, value)
            case operator
            when "eq"       then "item[:#{field}] == #{value_literal(value)}"
            when "ne"       then "item[:#{field}] != #{value_literal(value)}"
            when "gt"       then "item[:#{field}] > #{value.to_f}"
            when "lt"       then "item[:#{field}] < #{value.to_f}"
            when "includes" then "item[:#{field}].to_s.include?(#{value.to_s.inspect})"
            when "blank"    then "item[:#{field}].blank?"
            when "present"  then "item[:#{field}].present?"
            else "item[:#{field}] == #{value_literal(value)}"
            end
          end

          def value_literal(value)
            return "nil" if value.nil?
            value.to_s.match?(/\A-?\d+(\.\d+)?\z/) ? value.to_s : value.to_s.inspect
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/data_operations/any_all_none_check_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class AnyAllNoneCheckGenerator < BaseGenerator
          CHECK_TYPES = %w[any all none].freeze
          OPERATORS = %w[eq ne gt lt gte lte includes blank present].freeze

          generator_metadata do
            description "Boolean check on collection: any?, all?, or none?"
            category :data_operations
            version "1.0.0"
          end

          input_schema  :collection_key
          output_schema :output_key

          def generate
            collection = config["collectionKey"] || "items"
            check_type = config["checkType"] || "any"
            field = config["filterField"] || "id"
            operator = config["filterOperator"] || "eq"
            value = config["filterValue"]
            target = config["outputKey"] || "result"

            method = case check_type
                     when "all"  then "all?"
                     when "none" then "none?"
                     else "any?"
                     end

            condition = build_item_condition(field, operator, value)
            "ctx[:#{target}] = ctx[:#{collection}].#{method} { |item| #{condition} }\ntrue"
          end

          def validate_config(cfg)
            errors = []
            errors << "collectionKey is required" if cfg["collectionKey"].blank?
            if cfg["checkType"].present? && !CHECK_TYPES.include?(cfg["checkType"])
              errors << "Invalid checkType: #{cfg['checkType']}. Must be one of: #{CHECK_TYPES.join(', ')}"
            end
            errors
          end

          private

          def build_item_condition(field, operator, value)
            case operator
            when "eq"       then "item[:#{field}] == #{value_literal(value)}"
            when "ne"       then "item[:#{field}] != #{value_literal(value)}"
            when "gt"       then "item[:#{field}] > #{value.to_f}"
            when "lt"       then "item[:#{field}] < #{value.to_f}"
            when "gte"      then "item[:#{field}] >= #{value.to_f}"
            when "lte"      then "item[:#{field}] <= #{value.to_f}"
            when "includes" then "item[:#{field}].to_s.include?(#{value.to_s.inspect})"
            when "blank"    then "item[:#{field}].blank?"
            when "present"  then "item[:#{field}].present?"
            else "item[:#{field}] == #{value_literal(value)}"
            end
          end

          def value_literal(value)
            return "nil" if value.nil?
            value.to_s.match?(/\A-?\d+(\.\d+)?\z/) ? value.to_s : value.to_s.inspect
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/data_operations/{partition_collection,find_in_collection,any_all_none_check}_generator_spec.rb --format documentation 2>&1 | tail -20
```

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/data_operations/{partition_collection,find_in_collection,any_all_none_check}_generator.rb spec/services/code_generators/element_types/process/data_operations/{partition_collection,find_in_collection,any_all_none_check}_generator_spec.rb
git commit -m "feat: add partition, find_in, any_all_none collection generators"
```

---

## Task 3: Data Operations — Value & Type (coalesce, type_cast, string_manipulate, math_operation)

**Files:**
- Create: 4 generators + 4 specs under `data_operations/`

- [ ] **Step 1: Write tests**

```ruby
# spec/services/code_generators/element_types/process/data_operations/coalesce_value_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::CoalesceValueGenerator do
  let(:element) { { "config" => { "candidates" => [{ "type" => "ctx_key", "value" => "user_name" }, { "type" => "ctx_key", "value" => "email" }, { "type" => "literal", "value" => "Anonymous" }], "outputKey" => "display_name" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates coalesce chain" do
      code = described_class.new(element, context).generate
      expect(code).to include("ctx[:user_name]")
      expect(code).to include("ctx[:email]")
      expect(code).to include('"Anonymous"')
      expect(code).to include("ctx[:display_name]")
      expect(code).to include("true")
    end

    it "handles single candidate" do
      el = { "config" => { "candidates" => [{ "type" => "ctx_key", "value" => "name" }], "outputKey" => "result" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("ctx[:name]")
    end
  end

  describe "#validate_config" do
    it "requires candidates" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("candidates is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/data_operations/type_cast_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::TypeCastGenerator do
  let(:element) { { "config" => { "sourceKey" => "raw_value", "targetType" => "integer", "outputKey" => "parsed" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates integer cast" do
      code = described_class.new(element, context).generate
      expect(code).to include("to_i")
      expect(code).to include("ctx[:parsed]")
    end

    it "generates float cast" do
      el = { "config" => { "sourceKey" => "val", "targetType" => "float", "outputKey" => "result" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("to_f")
    end

    it "generates string cast" do
      el = { "config" => { "sourceKey" => "val", "targetType" => "string", "outputKey" => "result" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("to_s")
    end

    it "generates date cast with format" do
      el = { "config" => { "sourceKey" => "val", "targetType" => "date", "format" => "%Y-%m-%d", "outputKey" => "result" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("Date.strptime")
      expect(code).to include("%Y-%m-%d")
    end

    it "generates boolean cast" do
      el = { "config" => { "sourceKey" => "val", "targetType" => "boolean", "outputKey" => "result" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("ActiveModel::Type::Boolean")
    end

    it "handles on_failure with default_value" do
      el = { "config" => { "sourceKey" => "val", "targetType" => "integer", "onFailure" => "default_value", "defaultValue" => "0", "outputKey" => "result" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("rescue")
      expect(code).to include("0")
    end
  end

  describe "#validate_config" do
    it "requires sourceKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("sourceKey is required")
    end

    it "validates targetType" do
      errors = described_class.new(element, {}).validate_config({ "sourceKey" => "x", "targetType" => "invalid" })
      expect(errors).to include(/Invalid targetType/)
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/data_operations/string_manipulate_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::StringManipulateGenerator do
  let(:element) { { "config" => { "sourceKey" => "text", "operation" => "upcase", "outputKey" => "result" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates upcase" do
      code = described_class.new(element, context).generate
      expect(code).to include("upcase")
      expect(code).to include("ctx[:result]")
    end

    it "generates split with delimiter" do
      el = { "config" => { "sourceKey" => "csv_line", "operation" => "split", "delimiter" => ",", "outputKey" => "parts" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("split")
      expect(code).to include('","')
    end

    it "generates truncate with length" do
      el = { "config" => { "sourceKey" => "desc", "operation" => "truncate", "length" => 100, "outputKey" => "short" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("truncate(100)")
    end

    it "generates gsub with pattern and replacement" do
      el = { "config" => { "sourceKey" => "text", "operation" => "gsub", "pattern" => "\\d+", "replacement" => "#", "outputKey" => "cleaned" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("gsub")
    end

    it "generates join with delimiter" do
      el = { "config" => { "sourceKey" => "parts", "operation" => "join", "delimiter" => ", ", "outputKey" => "combined" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("join")
    end
  end

  describe "#validate_config" do
    it "requires sourceKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("sourceKey is required")
    end

    it "validates operation" do
      errors = described_class.new(element, {}).validate_config({ "sourceKey" => "x", "operation" => "invalid" })
      expect(errors).to include(/Invalid operation/)
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/data_operations/math_operation_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::MathOperationGenerator do
  let(:element) { { "config" => { "operation" => "round", "sourceKey" => "tax", "precision" => 2, "outputKey" => "rounded_tax" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates round with precision" do
      code = described_class.new(element, context).generate
      expect(code).to include("round(2)")
      expect(code).to include("ctx[:rounded_tax]")
    end

    it "generates abs" do
      el = { "config" => { "operation" => "abs", "sourceKey" => "val", "outputKey" => "result" } }
      code = described_class.new(el, {}).generate
      expect(code).to include(".abs")
    end

    it "generates add with two operands" do
      el = { "config" => { "operation" => "add", "sourceKey" => "a", "secondaryKey" => "b", "outputKey" => "sum" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("ctx[:a]")
      expect(code).to include("ctx[:b]")
      expect(code).to include("+")
    end

    it "generates random number" do
      el = { "config" => { "operation" => "random", "minValue" => 100000, "maxValue" => 999999, "outputKey" => "code" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("rand")
      expect(code).to include("100000")
      expect(code).to include("999999")
    end

    it "generates modulo" do
      el = { "config" => { "operation" => "modulo", "sourceKey" => "val", "secondaryKey" => "divisor", "outputKey" => "remainder" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("%")
    end

    it "generates sqrt" do
      el = { "config" => { "operation" => "sqrt", "sourceKey" => "val", "outputKey" => "result" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("Math.sqrt")
    end
  end

  describe "#validate_config" do
    it "requires operation" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("operation is required")
    end

    it "validates operation is in allowed list" do
      errors = described_class.new(element, {}).validate_config({ "operation" => "invalid" })
      expect(errors).to include(/Invalid operation/)
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/data_operations/{coalesce_value,type_cast,string_manipulate,math_operation}_generator_spec.rb 2>&1 | tail -5
```

- [ ] **Step 3: Implement generators**

```ruby
# app/services/code_generators/element_types/process/data_operations/coalesce_value_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class CoalesceValueGenerator < BaseGenerator
          generator_metadata do
            description "Returns the first non-nil value from ordered candidates"
            category :data_operations
            version "1.0.0"
          end

          input_schema  :candidates
          output_schema :output_key

          def generate
            candidates = config["candidates"] || []
            target = config["outputKey"] || "result"

            parts = candidates.map do |c|
              if c["type"] == "ctx_key"
                "ctx[:#{c['value']}]"
              else
                c["value"].to_s.inspect
              end
            end

            if parts.empty?
              "ctx[:#{target}] = nil\ntrue"
            else
              "ctx[:#{target}] = #{parts.join(' || ')}\ntrue"
            end
          end

          def validate_config(cfg)
            errors = []
            errors << "candidates is required" if cfg["candidates"].blank?
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/data_operations/type_cast_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class TypeCastGenerator < BaseGenerator
          TARGET_TYPES = %w[string integer float boolean date datetime array hash].freeze

          generator_metadata do
            description "Converts a value between types"
            category :data_operations
            version "1.0.0"
          end

          input_schema  :source_key
          output_schema :output_key

          def generate
            source = config["sourceKey"] || "value"
            target_type = config["targetType"] || "string"
            target = config["outputKey"] || "result"
            on_failure = config["onFailure"] || "nil"
            default_val = config["defaultValue"]
            format = config["format"]

            cast_expr = case target_type
                        when "string"   then "ctx[:#{source}].to_s"
                        when "integer"  then "ctx[:#{source}].to_i"
                        when "float"    then "ctx[:#{source}].to_f"
                        when "boolean"  then "ActiveModel::Type::Boolean.new.cast(ctx[:#{source}])"
                        when "date"
                          if format.present?
                            "Date.strptime(ctx[:#{source}].to_s, #{format.inspect})"
                          else
                            "Date.parse(ctx[:#{source}].to_s)"
                          end
                        when "datetime"
                          if format.present?
                            "DateTime.strptime(ctx[:#{source}].to_s, #{format.inspect})"
                          else
                            "DateTime.parse(ctx[:#{source}].to_s)"
                          end
                        when "array"    then "Array(ctx[:#{source}])"
                        when "hash"     then "ctx[:#{source}].to_h"
                        end

            if on_failure == "default_value" && default_val.present?
              <<~RUBY.chomp
                ctx[:#{target}] = begin
                  #{cast_expr}
                rescue StandardError
                  #{default_val}
                end
                true
              RUBY
            elsif on_failure == "nil"
              <<~RUBY.chomp
                ctx[:#{target}] = begin
                  #{cast_expr}
                rescue StandardError
                  nil
                end
                true
              RUBY
            else
              "ctx[:#{target}] = #{cast_expr}\ntrue"
            end
          end

          def validate_config(cfg)
            errors = []
            errors << "sourceKey is required" if cfg["sourceKey"].blank?
            if cfg["targetType"].present? && !TARGET_TYPES.include?(cfg["targetType"])
              errors << "Invalid targetType: #{cfg['targetType']}. Must be one of: #{TARGET_TYPES.join(', ')}"
            end
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/data_operations/string_manipulate_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class StringManipulateGenerator < BaseGenerator
          OPERATIONS = %w[split join trim strip pad_left pad_right truncate upcase downcase capitalize camelize underscore reverse replace gsub].freeze

          generator_metadata do
            description "Performs structural string operations"
            category :data_operations
            version "1.0.0"
          end

          input_schema  :source_key
          output_schema :output_key

          def generate
            source = config["sourceKey"] || "text"
            operation = config["operation"] || "strip"
            target = config["outputKey"] || "result"

            expr = case operation
                   when "split"      then "ctx[:#{source}].to_s.split(#{(config['delimiter'] || ',').inspect})"
                   when "join"       then "ctx[:#{source}].join(#{(config['delimiter'] || ', ').inspect})"
                   when "trim", "strip" then "ctx[:#{source}].to_s.strip"
                   when "pad_left"   then "ctx[:#{source}].to_s.rjust(#{(config['length'] || 10).to_i}, #{(config['padChar'] || ' ').inspect})"
                   when "pad_right"  then "ctx[:#{source}].to_s.ljust(#{(config['length'] || 10).to_i}, #{(config['padChar'] || ' ').inspect})"
                   when "truncate"   then "ctx[:#{source}].to_s.truncate(#{(config['length'] || 100).to_i})"
                   when "upcase"     then "ctx[:#{source}].to_s.upcase"
                   when "downcase"   then "ctx[:#{source}].to_s.downcase"
                   when "capitalize" then "ctx[:#{source}].to_s.capitalize"
                   when "camelize"   then "ctx[:#{source}].to_s.camelize"
                   when "underscore" then "ctx[:#{source}].to_s.underscore"
                   when "reverse"    then "ctx[:#{source}].to_s.reverse"
                   when "replace"    then "ctx[:#{source}].to_s.sub(#{(config['pattern'] || '').inspect}, #{(config['replacement'] || '').inspect})"
                   when "gsub"       then "ctx[:#{source}].to_s.gsub(/#{config['pattern']}/, #{(config['replacement'] || '').inspect})"
                   end

            "ctx[:#{target}] = #{expr}\ntrue"
          end

          def validate_config(cfg)
            errors = []
            errors << "sourceKey is required" if cfg["sourceKey"].blank?
            if cfg["operation"].present? && !OPERATIONS.include?(cfg["operation"])
              errors << "Invalid operation: #{cfg['operation']}. Must be one of: #{OPERATIONS.join(', ')}"
            end
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/data_operations/math_operation_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class MathOperationGenerator < BaseGenerator
          UNARY_OPS  = %w[abs floor ceil round sqrt].freeze
          BINARY_OPS = %w[add subtract multiply divide modulo power min max].freeze
          OTHER_OPS  = %w[random].freeze
          OPERATIONS = (UNARY_OPS + BINARY_OPS + OTHER_OPS).freeze

          generator_metadata do
            description "Performs scalar math operations"
            category :data_operations
            version "1.0.0"
          end

          input_schema  :source_key
          output_schema :output_key

          def generate
            operation = config["operation"] || "add"
            source = config["sourceKey"]
            secondary = config["secondaryKey"]
            target = config["outputKey"] || "result"
            precision = config["precision"]

            expr = if UNARY_OPS.include?(operation)
                     generate_unary(operation, source, precision)
                   elsif BINARY_OPS.include?(operation)
                     generate_binary(operation, source, secondary)
                   elsif operation == "random"
                     generate_random
                   end

            "ctx[:#{target}] = #{expr}\ntrue"
          end

          def validate_config(cfg)
            errors = []
            errors << "operation is required" if cfg["operation"].blank?
            if cfg["operation"].present? && !OPERATIONS.include?(cfg["operation"])
              errors << "Invalid operation: #{cfg['operation']}. Must be one of: #{OPERATIONS.join(', ')}"
            end
            errors
          end

          private

          def generate_unary(operation, source, precision)
            src = "ctx[:#{source || 'value'}].to_f"
            case operation
            when "abs"   then "#{src}.abs"
            when "floor" then "#{src}.floor"
            when "ceil"  then "#{src}.ceil"
            when "round" then precision ? "#{src}.round(#{precision.to_i})" : "#{src}.round"
            when "sqrt"  then "Math.sqrt(#{src})"
            end
          end

          def generate_binary(operation, source, secondary)
            a = "ctx[:#{source || 'a'}].to_f"
            b = "ctx[:#{secondary || 'b'}].to_f"
            case operation
            when "add"      then "#{a} + #{b}"
            when "subtract" then "#{a} - #{b}"
            when "multiply" then "#{a} * #{b}"
            when "divide"   then "#{b}.zero? ? 0.0 : #{a} / #{b}"
            when "modulo"   then "#{a}.to_i % #{b}.to_i"
            when "power"    then "#{a} ** #{b}"
            when "min"      then "[#{a}, #{b}].min"
            when "max"      then "[#{a}, #{b}].max"
            end
          end

          def generate_random
            min_val = config["minValue"] || 0
            max_val = config["maxValue"] || 100
            "rand(#{min_val.to_i}..#{max_val.to_i})"
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/data_operations/{coalesce_value,type_cast,string_manipulate,math_operation}_generator_spec.rb --format documentation 2>&1 | tail -20
```

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/data_operations/{coalesce_value,type_cast,string_manipulate,math_operation}_generator.rb spec/services/code_generators/element_types/process/data_operations/{coalesce_value,type_cast,string_manipulate,math_operation}_generator_spec.rb
git commit -m "feat: add coalesce, type_cast, string_manipulate, math_operation generators"
```

---

## Task 4: Data Operations — Utility (hash_manipulate, base64, generate_id, compare_data)

**Files:**
- Create: 4 generators + 4 specs under `data_operations/`

- [ ] **Step 1: Write tests**

```ruby
# spec/services/code_generators/element_types/process/data_operations/hash_manipulate_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::HashManipulateGenerator do
  let(:element) { { "config" => { "sourceKey" => "user", "operation" => "pick", "keys" => ["name", "email"], "outputKey" => "payload" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates pick operation" do
      code = described_class.new(element, context).generate
      expect(code).to include("slice")
      expect(code).to include("ctx[:payload]")
    end

    it "generates omit operation" do
      el = { "config" => { "sourceKey" => "data", "operation" => "omit", "keys" => ["password"], "outputKey" => "safe" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("except")
    end

    it "generates keys operation" do
      el = { "config" => { "sourceKey" => "data", "operation" => "keys", "outputKey" => "key_list" } }
      code = described_class.new(el, {}).generate
      expect(code).to include(".keys")
    end

    it "generates values operation" do
      el = { "config" => { "sourceKey" => "data", "operation" => "values", "outputKey" => "val_list" } }
      code = described_class.new(el, {}).generate
      expect(code).to include(".values")
    end

    it "generates deep_merge operation" do
      el = { "config" => { "sourceKey" => "base", "operation" => "deep_merge", "mergeSourceKey" => "overrides", "outputKey" => "merged" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("deep_merge")
    end

    it "generates rename_keys operation" do
      el = { "config" => { "sourceKey" => "data", "operation" => "rename_keys", "renameMap" => { "old_name" => "new_name" }, "outputKey" => "renamed" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("transform_keys")
    end
  end

  describe "#validate_config" do
    it "requires sourceKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("sourceKey is required")
    end

    it "validates operation" do
      errors = described_class.new(element, {}).validate_config({ "sourceKey" => "x", "operation" => "invalid" })
      expect(errors).to include(/Invalid operation/)
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/data_operations/base64_encode_decode_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::Base64EncodeDecodeGenerator do
  let(:element) { { "config" => { "sourceKey" => "data", "operation" => "encode", "outputKey" => "encoded" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates encode" do
      code = described_class.new(element, context).generate
      expect(code).to include("Base64.strict_encode64")
      expect(code).to include("ctx[:encoded]")
    end

    it "generates decode" do
      el = { "config" => { "sourceKey" => "encoded", "operation" => "decode", "outputKey" => "decoded" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("Base64.strict_decode64")
    end

    it "generates urlsafe_encode" do
      el = { "config" => { "sourceKey" => "data", "operation" => "urlsafe_encode", "outputKey" => "encoded" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("Base64.urlsafe_encode64")
    end

    it "generates urlsafe_decode" do
      el = { "config" => { "sourceKey" => "data", "operation" => "urlsafe_decode", "outputKey" => "decoded" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("Base64.urlsafe_decode64")
    end
  end

  describe "#validate_config" do
    it "requires sourceKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("sourceKey is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/data_operations/generate_id_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::GenerateIdGenerator do
  let(:element) { { "config" => { "format" => "uuid_v4", "outputKey" => "id" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates uuid_v4" do
      code = described_class.new(element, context).generate
      expect(code).to include("SecureRandom.uuid")
      expect(code).to include("ctx[:id]")
    end

    it "generates ulid" do
      el = { "config" => { "format" => "ulid", "outputKey" => "id" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("SecureRandom")
    end

    it "generates nanoid" do
      el = { "config" => { "format" => "nanoid", "outputKey" => "id" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("SecureRandom.alphanumeric")
    end

    it "generates custom pattern" do
      el = { "config" => { "format" => "custom_pattern", "pattern" => "ORD-%Y%m%d-", "outputKey" => "order_num" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("Time.current.strftime")
      expect(code).to include("SecureRandom")
    end
  end

  describe "#validate_config" do
    it "validates format" do
      errors = described_class.new(element, {}).validate_config({ "format" => "invalid" })
      expect(errors).to include(/Invalid format/)
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/data_operations/compare_data_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::CompareDataGenerator do
  let(:element) { { "config" => { "leftKey" => "before", "rightKey" => "after", "outputKey" => "diff" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates diff code" do
      code = described_class.new(element, context).generate
      expect(code).to include("ctx[:before]")
      expect(code).to include("ctx[:after]")
      expect(code).to include("ctx[:diff]")
      expect(code).to include("added")
      expect(code).to include("removed")
      expect(code).to include("changed")
      expect(code).to include("true")
    end

    it "supports ignoreKeys" do
      el = { "config" => { "leftKey" => "a", "rightKey" => "b", "ignoreKeys" => ["updated_at"], "outputKey" => "diff" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("except")
    end
  end

  describe "#validate_config" do
    it "requires leftKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("leftKey is required")
    end

    it "requires rightKey" do
      errors = described_class.new(element, {}).validate_config({ "leftKey" => "a" })
      expect(errors).to include("rightKey is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/data_operations/{hash_manipulate,base64_encode_decode,generate_id,compare_data}_generator_spec.rb 2>&1 | tail -5
```

- [ ] **Step 3: Implement generators**

```ruby
# app/services/code_generators/element_types/process/data_operations/hash_manipulate_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class HashManipulateGenerator < BaseGenerator
          OPERATIONS = %w[pick omit keys values deep_merge diff rename_keys invert].freeze

          generator_metadata do
            description "Reshapes hash/object structures"
            category :data_operations
            version "1.0.0"
          end

          input_schema  :source_key
          output_schema :output_key

          def generate
            source = config["sourceKey"] || "data"
            operation = config["operation"] || "pick"
            target = config["outputKey"] || "result"

            expr = case operation
                   when "pick"
                     keys = (config["keys"] || []).map { |k| ":#{k}" }.join(", ")
                     "ctx[:#{source}].slice(#{keys})"
                   when "omit"
                     keys = (config["keys"] || []).map { |k| ":#{k}" }.join(", ")
                     "ctx[:#{source}].except(#{keys})"
                   when "keys"
                     "ctx[:#{source}].keys"
                   when "values"
                     "ctx[:#{source}].values"
                   when "deep_merge"
                     merge_src = config["mergeSourceKey"] || "overrides"
                     "ctx[:#{source}].deep_merge(ctx[:#{merge_src}])"
                   when "diff"
                     other = config["compareKey"] || "other"
                     <<~RUBY.chomp
                       _left = ctx[:#{source}]
                         _right = ctx[:#{other}]
                         { added: _right.except(*_left.keys), removed: _left.except(*_right.keys), changed: _left.select { |k, v| _right.key?(k) && _right[k] != v }.transform_values { |v| { from: v, to: _right[_left.key(v)] } } }
                     RUBY
                   when "rename_keys"
                     rename_map = config["renameMap"] || {}
                     map_literal = rename_map.map { |k, v| "#{k.inspect} => :#{v}" }.join(", ")
                     "_map = {#{map_literal}}; ctx[:#{source}].transform_keys { |k| _map[k.to_s] || _map[k] || k }"
                   when "invert"
                     "ctx[:#{source}].invert"
                   end

            "ctx[:#{target}] = #{expr}\ntrue"
          end

          def validate_config(cfg)
            errors = []
            errors << "sourceKey is required" if cfg["sourceKey"].blank?
            if cfg["operation"].present? && !OPERATIONS.include?(cfg["operation"])
              errors << "Invalid operation: #{cfg['operation']}. Must be one of: #{OPERATIONS.join(', ')}"
            end
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/data_operations/base64_encode_decode_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class Base64EncodeDecodeGenerator < BaseGenerator
          OPERATIONS = %w[encode decode urlsafe_encode urlsafe_decode].freeze

          generator_metadata do
            description "Encodes or decodes Base64 strings"
            category :data_operations
            version "1.0.0"
          end

          input_schema  :source_key
          output_schema :output_key

          def generate
            source = config["sourceKey"] || "data"
            operation = config["operation"] || "encode"
            target = config["outputKey"] || "result"

            expr = case operation
                   when "encode"         then "Base64.strict_encode64(ctx[:#{source}].to_s)"
                   when "decode"         then "Base64.strict_decode64(ctx[:#{source}].to_s)"
                   when "urlsafe_encode" then "Base64.urlsafe_encode64(ctx[:#{source}].to_s)"
                   when "urlsafe_decode" then "Base64.urlsafe_decode64(ctx[:#{source}].to_s)"
                   end

            "ctx[:#{target}] = #{expr}\ntrue"
          end

          def validate_config(cfg)
            errors = []
            errors << "sourceKey is required" if cfg["sourceKey"].blank?
            if cfg["operation"].present? && !OPERATIONS.include?(cfg["operation"])
              errors << "Invalid operation: #{cfg['operation']}. Must be one of: #{OPERATIONS.join(', ')}"
            end
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/data_operations/generate_id_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class GenerateIdGenerator < BaseGenerator
          FORMATS = %w[uuid_v4 ulid nanoid custom_pattern].freeze

          generator_metadata do
            description "Generates unique identifiers"
            category :data_operations
            version "1.0.0"
          end

          input_schema
          output_schema :output_key

          def generate
            format = config["format"] || "uuid_v4"
            target = config["outputKey"] || "id"

            expr = case format
                   when "uuid_v4"
                     "SecureRandom.uuid"
                   when "ulid"
                     "Time.current.strftime('%Y%m%d%H%M%S') + SecureRandom.alphanumeric(12).upcase"
                   when "nanoid"
                     length = (config["length"] || 21).to_i
                     "SecureRandom.alphanumeric(#{length})"
                   when "custom_pattern"
                     pattern = config["pattern"] || ""
                     "Time.current.strftime(#{pattern.inspect}) + SecureRandom.alphanumeric(6)"
                   end

            "ctx[:#{target}] = #{expr}\ntrue"
          end

          def validate_config(cfg)
            errors = []
            if cfg["format"].present? && !FORMATS.include?(cfg["format"])
              errors << "Invalid format: #{cfg['format']}. Must be one of: #{FORMATS.join(', ')}"
            end
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/data_operations/compare_data_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class CompareDataGenerator < BaseGenerator
          generator_metadata do
            description "Diffs two hashes, returns added/removed/changed fields"
            category :data_operations
            version "1.0.0"
          end

          input_schema  :left_key, :right_key
          output_schema :output_key

          def generate
            left = config["leftKey"] || "before"
            right = config["rightKey"] || "after"
            target = config["outputKey"] || "diff"
            ignore = config["ignoreKeys"] || []

            lines = []
            if ignore.any?
              ignore_keys = ignore.map { |k| ":#{k}" }.join(", ")
              lines << "_left = ctx[:#{left}].except(#{ignore_keys})"
              lines << "_right = ctx[:#{right}].except(#{ignore_keys})"
            else
              lines << "_left = ctx[:#{left}]"
              lines << "_right = ctx[:#{right}]"
            end

            lines << "_added = _right.except(*_left.keys)"
            lines << "_removed = _left.except(*_right.keys)"
            lines << "_changed = _left.each_with_object({}) { |(k, v), h| h[k] = { from: v, to: _right[k] } if _right.key?(k) && _right[k] != v }"
            lines << "ctx[:#{target}] = { added: _added, removed: _removed, changed: _changed }"
            lines << "true"

            lines.join("\n")
          end

          def validate_config(cfg)
            errors = []
            errors << "leftKey is required" if cfg["leftKey"].blank?
            errors << "rightKey is required" if cfg["rightKey"].blank?
            errors
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/data_operations/{hash_manipulate,base64_encode_decode,generate_id,compare_data}_generator_spec.rb --format documentation 2>&1 | tail -20
```

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/data_operations/{hash_manipulate,base64_encode_decode,generate_id,compare_data}_generator.rb spec/services/code_generators/element_types/process/data_operations/{hash_manipulate,base64_encode_decode,generate_id,compare_data}_generator_spec.rb
git commit -m "feat: add hash_manipulate, base64, generate_id, compare_data generators"
```

---

## Task 5: Model Operations (upsert, clone, soft_delete, bulk_import, raw_sql_query)

**Files:**
- Create: 5 generators + 5 specs under `model_operations/`

- [ ] **Step 1: Write tests**

```ruby
# spec/services/code_generators/element_types/process/model_operations/upsert_model_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::UpsertModelGenerator do
  let(:element) { { "config" => { "matchFields" => ["email"], "attributes" => { "name" => "ctx.name", "email" => "ctx.email" }, "outputKey" => "record", "createdKey" => "was_created" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates find_or_initialize_by + save code" do
      code = described_class.new(element, context).generate
      expect(code).to include("find_or_initialize_by")
      expect(code).to include("email:")
      expect(code).to include("assign_attributes")
      expect(code).to include("new_record?")
      expect(code).to include("save!")
      expect(code).to include("ctx[:record]")
      expect(code).to include("ctx[:was_created]")
      expect(code).to include("true")
    end

    it "uses default output keys" do
      el = { "config" => { "matchFields" => ["id"], "attributes" => {} } }
      code = described_class.new(el, {}).generate
      expect(code).to include("ctx[:model]")
    end
  end

  describe "#validate_config" do
    it "requires matchFields" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("matchFields is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/model_operations/clone_model_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::CloneModelGenerator do
  let(:element) { { "config" => { "sourceKey" => "original", "overrideAttributes" => { "name" => "Copy of original" }, "outputKey" => "clone" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates dup + override code" do
      code = described_class.new(element, context).generate
      expect(code).to include("ctx[:original]")
      expect(code).to include("dup")
      expect(code).to include("assign_attributes")
      expect(code).to include("ctx[:clone]")
      expect(code).to include("true")
    end

    it "skips override if not specified" do
      el = { "config" => { "sourceKey" => "original", "outputKey" => "clone" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("dup")
      expect(code).not_to include("assign_attributes")
    end
  end

  describe "#validate_config" do
    it "requires sourceKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("sourceKey is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/model_operations/soft_delete_model_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::SoftDeleteModelGenerator do
  let(:element) { { "config" => { "sourceKey" => "record" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates soft delete with default deleted_at field" do
      code = described_class.new(element, context).generate
      expect(code).to include("ctx[:record]")
      expect(code).to include("deleted_at")
      expect(code).to include("Time.current")
      expect(code).to include("save!")
      expect(code).to include("true")
    end

    it "uses custom deleted field" do
      el = { "config" => { "sourceKey" => "record", "deletedField" => "is_active", "deletedValue" => "false" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("is_active")
    end
  end

  describe "#validate_config" do
    it "requires sourceKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("sourceKey is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/model_operations/bulk_import_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::BulkImportGenerator do
  let(:element) { { "config" => { "dataKey" => "records", "onDuplicate" => "skip", "batchSize" => 500, "outputKey" => "import_result" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates insert_all with batching" do
      code = described_class.new(element, context).generate
      expect(code).to include("ctx[:records]")
      expect(code).to include("each_slice(500)")
      expect(code).to include("ctx[:import_result]")
      expect(code).to include("true")
    end

    it "uses upsert_all for update on_duplicate" do
      el = { "config" => { "dataKey" => "data", "onDuplicate" => "update", "outputKey" => "result" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("upsert_all")
    end

    it "defaults to batch size 1000" do
      el = { "config" => { "dataKey" => "data", "outputKey" => "result" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("each_slice(1000)")
    end
  end

  describe "#validate_config" do
    it "requires dataKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("dataKey is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/model_operations/raw_sql_query_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::RawSqlQueryGenerator do
  let(:element) { { "config" => { "sqlTemplate" => "SELECT * FROM entity_entries WHERE customer_id = $1", "bindings" => ["customer_id"], "outputKey" => "results" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates parameterized SQL execution" do
      code = described_class.new(element, context).generate
      expect(code).to include("ActiveRecord::Base.connection")
      expect(code).to include("exec_query")
      expect(code).to include("ctx[:results]")
      expect(code).to include("true")
    end

    it "supports single_result mode" do
      el = { "config" => { "sqlTemplate" => "SELECT COUNT(*) AS cnt FROM entity_entries", "bindings" => [], "singleResult" => true, "outputKey" => "count" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("first")
    end
  end

  describe "#validate_config" do
    it "requires sqlTemplate" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("sqlTemplate is required")
    end

    it "rejects string interpolation in SQL" do
      errors = described_class.new(element, {}).validate_config({ "sqlTemplate" => 'SELECT * FROM users WHERE id = #{params[:id]}' })
      expect(errors).to include(/interpolation/)
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/model_operations/{upsert_model,clone_model,soft_delete_model,bulk_import,raw_sql_query}_generator_spec.rb 2>&1 | tail -5
```

- [ ] **Step 3: Implement generators**

```ruby
# app/services/code_generators/element_types/process/model_operations/upsert_model_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class UpsertModelGenerator < BaseGenerator
          generator_metadata do
            description "Atomic find-or-create / update-or-insert"
            category :model_operations
            version "1.0.0"
          end

          input_schema  :bound_entity
          output_schema :output_key, :created_key

          def generate
            match_fields = config["matchFields"] || ["id"]
            attributes = config["attributes"] || {}
            target = config["outputKey"] || "model"
            created_key = config["createdKey"]

            match_hash = match_fields.map { |f| "#{f}: ctx[:#{f}]" }.join(", ")

            attr_lines = attributes.map do |field, value_expr|
              if value_expr.to_s.start_with?("ctx.")
                key = value_expr.sub("ctx.", "")
                "  _record.#{field} = ctx[:#{key}]"
              else
                "  _record.#{field} = #{value_expr.inspect}"
              end
            end

            lines = []
            lines << "_model_class = EntityEntry.build_for(ctx[:bound_entity])"
            lines << "_record = _model_class.find_or_initialize_by(#{match_hash})"
            lines << "ctx[:#{created_key}] = _record.new_record?" if created_key.present?
            lines << "_record.assign_attributes(customer_id: ctx[:customer_id])" if attributes.empty?
            attr_lines.each { |l| lines << l } if attr_lines.any?
            lines << "_record.save!"
            lines << "ctx[:#{target}] = _record"
            lines << "true"

            lines.join("\n")
          end

          def validate_config(cfg)
            errors = []
            errors << "matchFields is required" if cfg["matchFields"].blank?
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/model_operations/clone_model_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class CloneModelGenerator < BaseGenerator
          generator_metadata do
            description "Deep duplicates a record with optional overrides"
            category :model_operations
            version "1.0.0"
          end

          input_schema  :source_key
          output_schema :output_key

          def generate
            source = config["sourceKey"] || "model"
            overrides = config["overrideAttributes"] || {}
            target = config["outputKey"] || "clone"

            lines = []
            lines << "ctx[:#{target}] = ctx[:#{source}].dup"

            if overrides.any?
              override_hash = overrides.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
              lines << "ctx[:#{target}].assign_attributes(#{override_hash})"
            end

            lines << "true"
            lines.join("\n")
          end

          def validate_config(cfg)
            errors = []
            errors << "sourceKey is required" if cfg["sourceKey"].blank?
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/model_operations/soft_delete_model_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class SoftDeleteModelGenerator < BaseGenerator
          generator_metadata do
            description "Marks a record as deleted without removing from database"
            category :model_operations
            version "1.0.0"
          end

          input_schema  :source_key
          output_schema

          def generate
            source = config["sourceKey"] || "model"
            field = config["deletedField"] || "deleted_at"
            value = config["deletedValue"] || "Time.current"

            value_expr = value == "Time.current" ? "Time.current" : value.inspect

            <<~RUBY.chomp
              ctx[:#{source}].#{field} = #{value_expr}
              ctx[:#{source}].save!
              true
            RUBY
          end

          def validate_config(cfg)
            errors = []
            errors << "sourceKey is required" if cfg["sourceKey"].blank?
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/model_operations/bulk_import_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class BulkImportGenerator < BaseGenerator
          ON_DUPLICATE = %w[skip update raise].freeze

          generator_metadata do
            description "Efficiently inserts multiple records with batching"
            category :model_operations
            version "1.0.0"
          end

          input_schema  :bound_entity, :data_key
          output_schema :output_key

          def generate
            data_key = config["dataKey"] || "records"
            on_dup = config["onDuplicate"] || "skip"
            batch_size = (config["batchSize"] || 1000).to_i
            target = config["outputKey"] || "import_result"

            method = on_dup == "update" ? "upsert_all" : "insert_all"

            <<~RUBY.chomp
              _model_class = EntityEntry.build_for(ctx[:bound_entity])
              _total = 0
              ctx[:#{data_key}].each_slice(#{batch_size}) do |batch|
                _rows = batch.map { |row| row.merge(customer_id: ctx[:customer_id]) }
                _model_class.#{method}(_rows)
                _total += batch.size
              end
              ctx[:#{target}] = { imported_count: _total }
              true
            RUBY
          end

          def validate_config(cfg)
            errors = []
            errors << "dataKey is required" if cfg["dataKey"].blank?
            if cfg["onDuplicate"].present? && !ON_DUPLICATE.include?(cfg["onDuplicate"])
              errors << "Invalid onDuplicate: #{cfg['onDuplicate']}. Must be one of: #{ON_DUPLICATE.join(', ')}"
            end
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/model_operations/raw_sql_query_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class RawSqlQueryGenerator < BaseGenerator
          generator_metadata do
            description "Executes parameterized raw SQL queries"
            category :model_operations
            version "1.0.0"
          end

          input_schema  :sql_template, :bindings
          output_schema :output_key

          def generate
            sql = config["sqlTemplate"] || ""
            bindings = config["bindings"] || []
            target = config["outputKey"] || "results"
            single = config["singleResult"]

            bind_expr = bindings.map { |b| "ctx[:#{b}]" }.join(", ")

            lines = []
            lines << "_sql = #{sql.inspect}"
            lines << "_binds = [#{bind_expr}]"
            lines << "_result = ActiveRecord::Base.connection.exec_query(_sql, 'SQL', _binds.map.with_index { |v, i| [nil, v] })"

            if single
              lines << "ctx[:#{target}] = _result.first"
            else
              lines << "ctx[:#{target}] = _result.to_a"
            end
            lines << "true"

            lines.join("\n")
          end

          def validate_config(cfg)
            errors = []
            errors << "sqlTemplate is required" if cfg["sqlTemplate"].blank?
            if cfg["sqlTemplate"].present? && cfg["sqlTemplate"].match?(/#\{/)
              errors << "SQL must not contain string interpolation — use $1, $2 placeholders with bindings"
            end
            errors
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/model_operations/{upsert_model,clone_model,soft_delete_model,bulk_import,raw_sql_query}_generator_spec.rb --format documentation 2>&1 | tail -30
```

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/model_operations/{upsert_model,clone_model,soft_delete_model,bulk_import,raw_sql_query}_generator.rb spec/services/code_generators/element_types/process/model_operations/{upsert_model,clone_model,soft_delete_model,bulk_import,raw_sql_query}_generator_spec.rb
git commit -m "feat: add upsert, clone, soft_delete, bulk_import, raw_sql_query model generators"
```

---

## Task 6: Security (verify_token, decrypt_data, sanitize_input, mask_data)

**Files:**
- Create: 4 generators + 4 specs under `security/`

- [ ] **Step 1: Write tests**

```ruby
# spec/services/code_generators/element_types/process/security/verify_token_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Security::VerifyTokenGenerator do
  let(:element) { { "config" => { "tokenKey" => "auth_token", "algorithm" => "HS256", "secretKey" => "jwt_secret", "outputKey" => "claims" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates JWT decode code" do
      code = described_class.new(element, context).generate
      expect(code).to include("JWT.decode")
      expect(code).to include("ctx[:auth_token]")
      expect(code).to include("ctx[:jwt_secret]")
      expect(code).to include("HS256")
      expect(code).to include("ctx[:claims]")
    end

    it "handles required_claims" do
      el = { "config" => { "tokenKey" => "token", "algorithm" => "HS256", "secretKey" => "secret", "requiredClaims" => ["sub", "exp"], "outputKey" => "claims" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("sub")
      expect(code).to include("exp")
    end
  end

  describe "#validate_config" do
    it "requires tokenKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("tokenKey is required")
    end

    it "requires secretKey" do
      errors = described_class.new(element, {}).validate_config({ "tokenKey" => "x" })
      expect(errors).to include("secretKey is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/security/decrypt_data_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Security::DecryptDataGenerator do
  let(:element) { { "config" => { "sourceKey" => "encrypted", "keyReference" => "decryption_key", "outputKey" => "plaintext" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates decryption code" do
      code = described_class.new(element, context).generate
      expect(code).to include("ctx[:encrypted]")
      expect(code).to include("ctx[:decryption_key]")
      expect(code).to include("ctx[:plaintext]")
      expect(code).to include("OpenSSL")
      expect(code).to include("true")
    end
  end

  describe "#validate_config" do
    it "requires sourceKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("sourceKey is required")
    end

    it "requires keyReference" do
      errors = described_class.new(element, {}).validate_config({ "sourceKey" => "x" })
      expect(errors).to include("keyReference is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/security/sanitize_input_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Security::SanitizeInputGenerator do
  let(:element) { { "config" => { "sourceKey" => "user_input", "mode" => "strip_tags", "outputKey" => "clean" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates strip_tags sanitization" do
      code = described_class.new(element, context).generate
      expect(code).to include("strip_tags")
      expect(code).to include("ctx[:clean]")
    end

    it "generates escape_html sanitization" do
      el = { "config" => { "sourceKey" => "input", "mode" => "escape_html", "outputKey" => "safe" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("ERB::Util.html_escape")
    end

    it "generates whitelist_tags sanitization" do
      el = { "config" => { "sourceKey" => "bio", "mode" => "whitelist_tags", "allowedTags" => ["b", "i", "a"], "outputKey" => "safe_bio" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("sanitize")
      expect(code).to include("tags:")
    end
  end

  describe "#validate_config" do
    it "requires sourceKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("sourceKey is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/security/mask_data_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Security::MaskDataGenerator do
  let(:element) { { "config" => { "sourceKey" => "card_number", "maskType" => "last4", "outputKey" => "masked" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates last4 mask" do
      code = described_class.new(element, context).generate
      expect(code).to include("ctx[:card_number]")
      expect(code).to include("ctx[:masked]")
      expect(code).to include("[-4..]")
      expect(code).to include("*")
    end

    it "generates email mask" do
      el = { "config" => { "sourceKey" => "email", "maskType" => "email", "outputKey" => "masked_email" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("split")
      expect(code).to include("@")
    end

    it "generates full mask" do
      el = { "config" => { "sourceKey" => "ssn", "maskType" => "full", "outputKey" => "masked_ssn" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("*")
      expect(code).to include("length")
    end

    it "uses custom mask char" do
      el = { "config" => { "sourceKey" => "data", "maskType" => "full", "maskChar" => "X", "outputKey" => "masked" } }
      code = described_class.new(el, {}).generate
      expect(code).to include('"X"')
    end
  end

  describe "#validate_config" do
    it "requires sourceKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("sourceKey is required")
    end

    it "validates maskType" do
      errors = described_class.new(element, {}).validate_config({ "sourceKey" => "x", "maskType" => "invalid" })
      expect(errors).to include(/Invalid maskType/)
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/security/{verify_token,decrypt_data,sanitize_input,mask_data}_generator_spec.rb 2>&1 | tail -5
```

- [ ] **Step 3: Implement generators**

```ruby
# app/services/code_generators/element_types/process/security/verify_token_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Security
        class VerifyTokenGenerator < BaseGenerator
          ALGORITHMS = %w[HS256 HS384 HS512 RS256 RS384 RS512].freeze

          generator_metadata do
            description "Decodes and verifies JWT/signed tokens"
            category :security
            version "1.0.0"
          end

          input_schema  :token_key, :secret_key
          output_schema :output_key

          def generate
            token_key = config["tokenKey"] || "token"
            algorithm = config["algorithm"] || "HS256"
            secret_key = config["secretKey"] || "secret"
            required_claims = config["requiredClaims"] || []
            target = config["outputKey"] || "claims"

            lines = []
            lines << "_decoded = JWT.decode(ctx[:#{token_key}], ctx[:#{secret_key}], true, { algorithm: #{algorithm.inspect} })"
            lines << "_payload = _decoded.first"

            if required_claims.any?
              claims_check = required_claims.map { |c| "_payload.key?(#{c.inspect})" }.join(" && ")
              lines << "unless #{claims_check}"
              lines << '  raise "Missing required claims: ' + required_claims.join(", ") + '"'
              lines << "end"
            end

            lines << "ctx[:#{target}] = _payload"
            lines << "true"

            lines.join("\n")
          end

          def validate_config(cfg)
            errors = []
            errors << "tokenKey is required" if cfg["tokenKey"].blank?
            errors << "secretKey is required" if cfg["secretKey"].blank?
            if cfg["algorithm"].present? && !ALGORITHMS.include?(cfg["algorithm"])
              errors << "Invalid algorithm: #{cfg['algorithm']}. Must be one of: #{ALGORITHMS.join(', ')}"
            end
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/security/decrypt_data_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Security
        class DecryptDataGenerator < BaseGenerator
          generator_metadata do
            description "Decrypts data encrypted by encrypt_data"
            category :security
            version "1.0.0"
          end

          input_schema  :source_key, :key_reference
          output_schema :output_key

          def generate
            source = config["sourceKey"] || "encrypted"
            key_ref = config["keyReference"] || "key"
            algorithm = config["algorithm"] || "aes-256-gcm"
            target = config["outputKey"] || "decrypted"

            <<~RUBY.chomp
              _cipher = OpenSSL::Cipher.new(#{algorithm.inspect})
              _cipher.decrypt
              _raw = Base64.strict_decode64(ctx[:#{source}].to_s)
              _cipher.iv = _raw[0, _cipher.iv_len]
              _cipher.key = ctx[:#{key_ref}]
              _cipher.auth_tag = _raw[_cipher.iv_len, 16] if _cipher.authenticated?
              ctx[:#{target}] = _cipher.update(_raw[(_cipher.iv_len + (_cipher.authenticated? ? 16 : 0))..]) + _cipher.final
              true
            RUBY
          end

          def validate_config(cfg)
            errors = []
            errors << "sourceKey is required" if cfg["sourceKey"].blank?
            errors << "keyReference is required" if cfg["keyReference"].blank?
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/security/sanitize_input_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Security
        class SanitizeInputGenerator < BaseGenerator
          MODES = %w[strip_tags escape_html whitelist_tags].freeze

          generator_metadata do
            description "Sanitizes user-submitted content"
            category :security
            version "1.0.0"
          end

          input_schema  :source_key
          output_schema :output_key

          def generate
            source = config["sourceKey"] || "input"
            mode = config["mode"] || "strip_tags"
            target = config["outputKey"] || "sanitized"

            expr = case mode
                   when "strip_tags"
                     "ActionController::Base.helpers.strip_tags(ctx[:#{source}].to_s)"
                   when "escape_html"
                     "ERB::Util.html_escape(ctx[:#{source}].to_s)"
                   when "whitelist_tags"
                     tags = (config["allowedTags"] || []).map(&:inspect).join(", ")
                     "ActionController::Base.helpers.sanitize(ctx[:#{source}].to_s, tags: [#{tags}])"
                   end

            "ctx[:#{target}] = #{expr}\ntrue"
          end

          def validate_config(cfg)
            errors = []
            errors << "sourceKey is required" if cfg["sourceKey"].blank?
            if cfg["mode"].present? && !MODES.include?(cfg["mode"])
              errors << "Invalid mode: #{cfg['mode']}. Must be one of: #{MODES.join(', ')}"
            end
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/security/mask_data_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Security
        class MaskDataGenerator < BaseGenerator
          MASK_TYPES = %w[last4 first1_last1 email phone full].freeze

          generator_metadata do
            description "Masks sensitive data for display or logging"
            category :security
            version "1.0.0"
          end

          input_schema  :source_key
          output_schema :output_key

          def generate
            source = config["sourceKey"] || "data"
            mask_type = config["maskType"] || "last4"
            mask_char = config["maskChar"] || "*"
            target = config["outputKey"] || "masked"

            expr = case mask_type
                   when "last4"
                     "_val = ctx[:#{source}].to_s; (#{mask_char.inspect} * [_val.length - 4, 0].max) + _val[-4..]"
                   when "first1_last1"
                     "_val = ctx[:#{source}].to_s; _val[0] + (#{mask_char.inspect} * [_val.length - 2, 0].max) + _val[-1]"
                   when "email"
                     "_parts = ctx[:#{source}].to_s.split('@'); _parts[0][0] + (#{mask_char.inspect} * 3) + '@' + _parts[1][0] + (#{mask_char.inspect} * 3) + '.' + _parts[1].split('.').last"
                   when "phone"
                     "_val = ctx[:#{source}].to_s; (#{mask_char.inspect} * [_val.length - 4, 0].max) + _val[-4..]"
                   when "full"
                     "#{mask_char.inspect} * ctx[:#{source}].to_s.length"
                   end

            "ctx[:#{target}] = #{expr}\ntrue"
          end

          def validate_config(cfg)
            errors = []
            errors << "sourceKey is required" if cfg["sourceKey"].blank?
            if cfg["maskType"].present? && !MASK_TYPES.include?(cfg["maskType"])
              errors << "Invalid maskType: #{cfg['maskType']}. Must be one of: #{MASK_TYPES.join(', ')}"
            end
            errors
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/security/{verify_token,decrypt_data,sanitize_input,mask_data}_generator_spec.rb --format documentation 2>&1 | tail -20
```

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/security/{verify_token,decrypt_data,sanitize_input,mask_data}_generator.rb spec/services/code_generators/element_types/process/security/{verify_token,decrypt_data,sanitize_input,mask_data}_generator_spec.rb
git commit -m "feat: add verify_token, decrypt_data, sanitize_input, mask_data generators"
```

---

## Task 7: File Operations (parse_csv, generate_csv, compress_files, decompress_files)

**Files:**
- Create: 4 generators + 4 specs under `file_operations/`

- [ ] **Step 1: Write tests**

```ruby
# spec/services/code_generators/element_types/process/file_operations/parse_csv_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::FileOperations::ParseCsvGenerator do
  let(:element) { { "config" => { "sourceKey" => "csv_data", "headers" => true, "outputKey" => "rows" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates CSV parse code with headers" do
      code = described_class.new(element, context).generate
      expect(code).to include("CSV.parse")
      expect(code).to include("headers: true")
      expect(code).to include("ctx[:rows]")
      expect(code).to include("true")
    end

    it "respects custom delimiter" do
      el = { "config" => { "sourceKey" => "data", "delimiter" => ";", "headers" => true, "outputKey" => "rows" } }
      code = described_class.new(el, {}).generate
      expect(code).to include('col_sep: ";"')
    end
  end

  describe "#validate_config" do
    it "requires sourceKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("sourceKey is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/file_operations/generate_csv_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::FileOperations::GenerateCsvGenerator do
  let(:element) { { "config" => { "collectionKey" => "orders", "columns" => [{ "header" => "Name", "field" => "name" }, { "header" => "Total", "field" => "total" }], "outputKey" => "csv_output" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates CSV generation code" do
      code = described_class.new(element, context).generate
      expect(code).to include("CSV.generate")
      expect(code).to include("ctx[:orders]")
      expect(code).to include("ctx[:csv_output]")
      expect(code).to include("true")
    end

    it "includes headers" do
      code = described_class.new(element, context).generate
      expect(code).to include('"Name"')
      expect(code).to include('"Total"')
    end
  end

  describe "#validate_config" do
    it "requires collectionKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("collectionKey is required")
    end

    it "requires columns" do
      errors = described_class.new(element, {}).validate_config({ "collectionKey" => "x" })
      expect(errors).to include("columns is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/file_operations/compress_files_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::FileOperations::CompressFilesGenerator do
  let(:element) { { "config" => { "entries" => [{ "name" => "report.txt", "sourceKey" => "report_data" }], "format" => "zip", "outputKey" => "archive" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates zip creation code" do
      code = described_class.new(element, context).generate
      expect(code).to include("Zip::OutputStream")
      expect(code).to include("report.txt")
      expect(code).to include("ctx[:archive]")
      expect(code).to include("true")
    end
  end

  describe "#validate_config" do
    it "requires entries" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("entries is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/file_operations/decompress_files_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::FileOperations::DecompressFilesGenerator do
  let(:element) { { "config" => { "sourceKey" => "archive", "format" => "zip", "outputKey" => "extracted" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates zip extraction code" do
      code = described_class.new(element, context).generate
      expect(code).to include("Zip::InputStream")
      expect(code).to include("ctx[:archive]")
      expect(code).to include("ctx[:extracted]")
      expect(code).to include("true")
    end
  end

  describe "#validate_config" do
    it "requires sourceKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("sourceKey is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/file_operations/{parse_csv,generate_csv,compress_files,decompress_files}_generator_spec.rb 2>&1 | tail -5
```

- [ ] **Step 3: Implement generators**

```ruby
# app/services/code_generators/element_types/process/file_operations/parse_csv_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module FileOperations
        class ParseCsvGenerator < BaseGenerator
          generator_metadata do
            description "Parses CSV content into an array of hashes"
            category :file_operations
            version "1.0.0"
          end

          input_schema  :source_key
          output_schema :output_key

          def generate
            source = config["sourceKey"] || "csv_data"
            headers = config["headers"] != false
            delimiter = config["delimiter"] || ","
            target = config["outputKey"] || "rows"

            opts = ["headers: #{headers}"]
            opts << "col_sep: #{delimiter.inspect}" if delimiter != ","

            <<~RUBY.chomp
              _csv = CSV.parse(ctx[:#{source}].to_s, #{opts.join(', ')})
              ctx[:#{target}] = #{headers ? '_csv.map(&:to_h)' : '_csv.to_a'}
              true
            RUBY
          end

          def validate_config(cfg)
            errors = []
            errors << "sourceKey is required" if cfg["sourceKey"].blank?
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/file_operations/generate_csv_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module FileOperations
        class GenerateCsvGenerator < BaseGenerator
          generator_metadata do
            description "Generates CSV string from a collection"
            category :file_operations
            version "1.0.0"
          end

          input_schema  :collection_key, :columns
          output_schema :output_key

          def generate
            collection = config["collectionKey"] || "items"
            columns = config["columns"] || []
            target = config["outputKey"] || "csv_output"
            include_headers = config["includeHeaders"] != false

            headers_row = columns.map { |c| c["header"].inspect }.join(", ")
            field_refs = columns.map { |c| "row[:#{c['field']}]" }.join(", ")

            lines = []
            lines << "ctx[:#{target}] = CSV.generate do |csv|"
            lines << "  csv << [#{headers_row}]" if include_headers
            lines << "  ctx[:#{collection}].each do |row|"
            lines << "    csv << [#{field_refs}]"
            lines << "  end"
            lines << "end"
            lines << "true"

            lines.join("\n")
          end

          def validate_config(cfg)
            errors = []
            errors << "collectionKey is required" if cfg["collectionKey"].blank?
            errors << "columns is required" if cfg["columns"].blank?
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/file_operations/compress_files_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module FileOperations
        class CompressFilesGenerator < BaseGenerator
          generator_metadata do
            description "Creates ZIP archive from files or in-memory data"
            category :file_operations
            version "1.0.0"
          end

          input_schema  :entries
          output_schema :output_key

          def generate
            entries = config["entries"] || []
            target = config["outputKey"] || "archive"

            entry_lines = entries.map do |entry|
              name = entry["name"] || "file.dat"
              if entry["sourceKey"]
                "  _stream.put_next_entry(#{name.inspect}); _stream.write(ctx[:#{entry['sourceKey']}].to_s)"
              else
                "  _stream.put_next_entry(#{name.inspect}); _stream.write(#{(entry['literal'] || '').inspect})"
              end
            end

            <<~RUBY.chomp
              _buffer = StringIO.new
              Zip::OutputStream.write_buffer(_buffer) do |_stream|
              #{entry_lines.join("\n")}
              end
              ctx[:#{target}] = _buffer.string
              true
            RUBY
          end

          def validate_config(cfg)
            errors = []
            errors << "entries is required" if cfg["entries"].blank?
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/file_operations/decompress_files_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module FileOperations
        class DecompressFilesGenerator < BaseGenerator
          generator_metadata do
            description "Extracts entries from ZIP archives"
            category :file_operations
            version "1.0.0"
          end

          input_schema  :source_key
          output_schema :output_key

          def generate
            source = config["sourceKey"] || "archive"
            filter = config["filter"]
            target = config["outputKey"] || "extracted"

            lines = []
            lines << "_result = {}"
            lines << "Zip::InputStream.open(StringIO.new(ctx[:#{source}])) do |_stream|"
            lines << "  while (_entry = _stream.get_next_entry)"
            if filter.present?
              lines << "    next unless File.fnmatch(#{filter.inspect}, _entry.name)"
            end
            lines << "    _result[_entry.name] = _stream.read unless _entry.directory?"
            lines << "  end"
            lines << "end"
            lines << "ctx[:#{target}] = _result"
            lines << "true"

            lines.join("\n")
          end

          def validate_config(cfg)
            errors = []
            errors << "sourceKey is required" if cfg["sourceKey"].blank?
            errors
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/file_operations/{parse_csv,generate_csv,compress_files,decompress_files}_generator_spec.rb --format documentation 2>&1 | tail -20
```

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/file_operations/{parse_csv,generate_csv,compress_files,decompress_files}_generator.rb spec/services/code_generators/element_types/process/file_operations/{parse_csv,generate_csv,compress_files,decompress_files}_generator_spec.rb
git commit -m "feat: add parse_csv, generate_csv, compress, decompress file generators"
```

---

## Task 8: Caching, Concurrency & Response (cache_delete, cache_fetch, release_lock, redirect_response)

**Files:**
- Create: 4 generators + 4 specs

- [ ] **Step 1: Write tests**

```ruby
# spec/services/code_generators/element_types/process/caching/cache_delete_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Caching::CacheDeleteGenerator do
  let(:element) { { "config" => { "key" => "product_123", "mode" => "exact" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates exact key delete" do
      code = described_class.new(element, context).generate
      expect(code).to include("Rails.cache.delete")
      expect(code).to include("product_123")
    end

    it "generates pattern delete" do
      el = { "config" => { "key" => "product_*", "mode" => "pattern" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("delete_matched")
    end
  end

  describe "#validate_config" do
    it "requires key" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("key is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/caching/cache_fetch_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Caching::CacheFetchGenerator do
  let(:element) { { "config" => { "key" => "expensive_query", "ttl" => 300, "fallbackExpression" => "ctx[:bound_entity].count", "outputKey" => "count" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates fetch with ttl and fallback" do
      code = described_class.new(element, context).generate
      expect(code).to include("Rails.cache.fetch")
      expect(code).to include("expires_in: 300")
      expect(code).to include("ctx[:count]")
      expect(code).to include("true")
    end

    it "generates fetch without ttl" do
      el = { "config" => { "key" => "data", "fallbackExpression" => "nil", "outputKey" => "result" } }
      code = described_class.new(el, {}).generate
      expect(code).not_to include("expires_in")
    end
  end

  describe "#validate_config" do
    it "requires key" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("key is required")
    end

    it "requires fallbackExpression" do
      errors = described_class.new(element, {}).validate_config({ "key" => "x" })
      expect(errors).to include("fallbackExpression is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/concurrency/release_lock_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Concurrency::ReleaseLockGenerator do
  let(:element) { { "config" => { "lockKey" => "inventory_lock" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates lock release code" do
      code = described_class.new(element, context).generate
      expect(code).to include("inventory_lock")
      expect(code).to include("Rails.cache.delete")
      expect(code).to include("true")
    end
  end

  describe "#validate_config" do
    it "requires lockKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("lockKey is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/response/redirect_response_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Response::RedirectResponseGenerator do
  let(:element) { { "config" => { "url" => "/orders/confirmation", "status" => 302 } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates redirect code" do
      code = described_class.new(element, context).generate
      expect(code).to include("/orders/confirmation")
      expect(code).to include("302")
      expect(code).to include("ctx[:_redirect]")
      expect(code).to include("true")
    end

    it "appends query params" do
      el = { "config" => { "url" => "/done", "status" => 302, "queryParams" => { "ref" => "ctx.ref_id" } } }
      code = described_class.new(el, {}).generate
      expect(code).to include("query")
      expect(code).to include("ref")
    end
  end

  describe "#validate_config" do
    it "requires url" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("url is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/caching/{cache_delete,cache_fetch}_generator_spec.rb spec/services/code_generators/element_types/process/concurrency/release_lock_generator_spec.rb spec/services/code_generators/element_types/process/response/redirect_response_generator_spec.rb 2>&1 | tail -5
```

- [ ] **Step 3: Implement generators**

```ruby
# app/services/code_generators/element_types/process/caching/cache_delete_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Caching
        class CacheDeleteGenerator < BaseGenerator
          generator_metadata do
            description "Invalidates cache entries by key or pattern"
            category :caching
            version "1.0.0"
          end

          input_schema  :key
          output_schema

          def generate
            key = config["key"] || "cache_key"
            mode = config["mode"] || "exact"

            if mode == "pattern"
              "Rails.cache.delete_matched(#{key.inspect})\ntrue"
            else
              "Rails.cache.delete(#{key.inspect})\ntrue"
            end
          end

          def validate_config(cfg)
            errors = []
            errors << "key is required" if cfg["key"].blank?
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/caching/cache_fetch_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Caching
        class CacheFetchGenerator < BaseGenerator
          generator_metadata do
            description "Read-through cache with fallback computation"
            category :caching
            version "1.0.0"
          end

          input_schema  :key
          output_schema :output_key

          def generate
            key = config["key"] || "cache_key"
            ttl = config["ttl"].to_i
            fallback = config["fallbackExpression"] || "nil"
            target = config["outputKey"] || "result"

            opts = ttl > 0 ? ", expires_in: #{ttl}" : ""
            "ctx[:#{target}] = Rails.cache.fetch(#{key.inspect}#{opts}) { #{fallback} }\ntrue"
          end

          def validate_config(cfg)
            errors = []
            errors << "key is required" if cfg["key"].blank?
            errors << "fallbackExpression is required" if cfg["fallbackExpression"].blank?
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/concurrency/release_lock_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Concurrency
        class ReleaseLockGenerator < BaseGenerator
          generator_metadata do
            description "Releases a lock acquired by acquire_lock"
            category :concurrency
            version "1.0.0"
          end

          input_schema  :lock_key
          output_schema

          def generate
            lock_key = config["lockKey"] || "lock"
            "Rails.cache.delete(#{lock_key.inspect})\ntrue"
          end

          def validate_config(cfg)
            errors = []
            errors << "lockKey is required" if cfg["lockKey"].blank?
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/response/redirect_response_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Response
        class RedirectResponseGenerator < BaseGenerator
          generator_metadata do
            description "Issues an HTTP redirect response"
            category :response
            version "1.0.0"
          end

          input_schema
          output_schema :_redirect

          def generate
            url = config["url"] || "/"
            status = (config["status"] || 302).to_i
            query_params = config["queryParams"] || {}

            if query_params.any?
              params_hash = query_params.map { |k, v|
                val = v.to_s.start_with?("ctx.") ? "ctx[:#{v.sub('ctx.', '')}]" : v.inspect
                "#{k.inspect} => #{val}"
              }.join(", ")
              <<~RUBY.chomp
                _params = {#{params_hash}}
                _query = _params.map { |k, v| "\#{k}=\#{CGI.escape(v.to_s)}" }.join("&")
                ctx[:_redirect] = { url: #{url.inspect} + "?" + _query, status: #{status} }
                true
              RUBY
            else
              "ctx[:_redirect] = { url: #{url.inspect}, status: #{status} }\ntrue"
            end
          end

          def validate_config(cfg)
            errors = []
            errors << "url is required" if cfg["url"].blank?
            errors
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/caching/{cache_delete,cache_fetch}_generator_spec.rb spec/services/code_generators/element_types/process/concurrency/release_lock_generator_spec.rb spec/services/code_generators/element_types/process/response/redirect_response_generator_spec.rb --format documentation 2>&1 | tail -20
```

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/caching/{cache_delete,cache_fetch}_generator.rb spec/services/code_generators/element_types/process/caching/{cache_delete,cache_fetch}_generator_spec.rb app/services/code_generators/element_types/process/concurrency/release_lock_generator.rb spec/services/code_generators/element_types/process/concurrency/release_lock_generator_spec.rb app/services/code_generators/element_types/process/response/redirect_response_generator.rb spec/services/code_generators/element_types/process/response/redirect_response_generator_spec.rb
git commit -m "feat: add cache_delete, cache_fetch, release_lock, redirect_response generators"
```

---

## Task 9: Human Workflow (approval_gate, assign_task, user_input_request, escalation)

**Files:**
- Create: 4 generators + 4 specs under `human_workflow/`

- [ ] **Step 1: Write tests**

```ruby
# spec/services/code_generators/element_types/process/human_workflow/approval_gate_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::HumanWorkflow::ApprovalGateGenerator do
  let(:element) { { "config" => { "approvers" => [{ "type" => "role", "idKey" => "manager_id" }], "approvalMode" => "any", "deadline" => "48h", "onTimeout" => "reject", "outputKey" => "approval_result" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates approval request code" do
      code = described_class.new(element, context).generate
      expect(code).to include("ctx[:approval_result]")
      expect(code).to include("approval_mode")
      expect(code).to include("deadline")
      expect(code).to include("true")
    end
  end

  describe "#validate_config" do
    it "requires approvers" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("approvers is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/human_workflow/assign_task_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::HumanWorkflow::AssignTaskGenerator do
  let(:element) { { "config" => { "assignee" => { "type" => "user", "idKey" => "user_id" }, "title" => "Review document", "priority" => "high", "waitForCompletion" => true, "outputKey" => "task" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates task assignment code" do
      code = described_class.new(element, context).generate
      expect(code).to include("Review document")
      expect(code).to include("high")
      expect(code).to include("ctx[:task]")
      expect(code).to include("true")
    end
  end

  describe "#validate_config" do
    it "requires assignee" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("assignee is required")
    end

    it "requires title" do
      errors = described_class.new(element, {}).validate_config({ "assignee" => { "type" => "user" } })
      expect(errors).to include("title is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/human_workflow/user_input_request_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::HumanWorkflow::UserInputRequestGenerator do
  let(:element) { { "config" => { "targetUser" => "assignee_id", "fields" => [{ "name" => "reason", "type" => "text", "label" => "Reason", "required" => true }], "message" => "Please provide details", "outputKey" => "user_response" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates user input request code" do
      code = described_class.new(element, context).generate
      expect(code).to include("ctx[:user_response]")
      expect(code).to include("fields")
      expect(code).to include("reason")
      expect(code).to include("true")
    end
  end

  describe "#validate_config" do
    it "requires fields" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("fields is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/human_workflow/escalation_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::HumanWorkflow::EscalationGenerator do
  let(:element) { { "config" => { "watchedKey" => "pending_approval", "timeout" => "48h", "escalationTarget" => { "type" => "role", "idKey" => "dept_head_id" }, "escalationAction" => "reassign", "outputKey" => "escalation_result" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates escalation code" do
      code = described_class.new(element, context).generate
      expect(code).to include("ctx[:escalation_result]")
      expect(code).to include("timeout")
      expect(code).to include("reassign")
      expect(code).to include("true")
    end
  end

  describe "#validate_config" do
    it "requires watchedKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("watchedKey is required")
    end

    it "requires escalationTarget" do
      errors = described_class.new(element, {}).validate_config({ "watchedKey" => "x" })
      expect(errors).to include("escalationTarget is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/human_workflow/ 2>&1 | tail -5
```

- [ ] **Step 3: Implement generators**

```ruby
# app/services/code_generators/element_types/process/human_workflow/approval_gate_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module HumanWorkflow
        class ApprovalGateGenerator < BaseGenerator
          APPROVAL_MODES = %w[any all majority].freeze
          ON_TIMEOUT_ACTIONS = %w[approve reject escalate].freeze

          generator_metadata do
            description "Pauses workflow for human approval"
            category :human_workflow
            version "1.0.0"
          end

          input_schema  :approvers
          output_schema :output_key

          def generate
            approvers = config["approvers"] || []
            mode = config["approvalMode"] || "any"
            deadline = config["deadline"] || "48h"
            on_timeout = config["onTimeout"] || "reject"
            target = config["outputKey"] || "approval_result"

            approver_refs = approvers.map { |a| "{ type: #{a['type'].inspect}, id: ctx[:#{a['idKey']}] }" }.join(", ")

            <<~RUBY.chomp
              ctx[:#{target}] = {
                status: :pending,
                approvers: [#{approver_refs}],
                approval_mode: #{mode.inspect},
                deadline: #{deadline.inspect},
                on_timeout: #{on_timeout.inspect},
                requested_at: Time.current
              }
              ctx[:_signal_wait] = { key: "approval_\#{SecureRandom.hex(8)}", timeout: #{deadline.inspect} }
              true
            RUBY
          end

          def validate_config(cfg)
            errors = []
            errors << "approvers is required" if cfg["approvers"].blank?
            if cfg["approvalMode"].present? && !APPROVAL_MODES.include?(cfg["approvalMode"])
              errors << "Invalid approvalMode: #{cfg['approvalMode']}. Must be one of: #{APPROVAL_MODES.join(', ')}"
            end
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/human_workflow/assign_task_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module HumanWorkflow
        class AssignTaskGenerator < BaseGenerator
          PRIORITIES = %w[low medium high urgent].freeze

          generator_metadata do
            description "Creates a trackable task assigned to a user or role"
            category :human_workflow
            version "1.0.0"
          end

          input_schema  :assignee, :title
          output_schema :output_key

          def generate
            assignee = config["assignee"] || {}
            title = config["title"] || "Task"
            description = config["description"] || ""
            priority = config["priority"] || "medium"
            deadline = config["deadline"]
            wait = config["waitForCompletion"]
            target = config["outputKey"] || "task"

            lines = []
            lines << "ctx[:#{target}] = {"
            lines << "  assignee: { type: #{assignee['type'].to_s.inspect}, id: ctx[:#{assignee['idKey'] || 'user_id'}] },"
            lines << "  title: #{title.inspect},"
            lines << "  description: #{description.inspect},"
            lines << "  priority: #{priority.inspect},"
            lines << "  deadline: #{deadline.inspect}," if deadline.present?
            lines << "  status: :pending,"
            lines << "  created_at: Time.current"
            lines << "}"

            if wait
              lines << "ctx[:_signal_wait] = { key: \"task_\#{SecureRandom.hex(8)}\", timeout: #{(deadline || '7d').inspect} }"
            end

            lines << "true"
            lines.join("\n")
          end

          def validate_config(cfg)
            errors = []
            errors << "assignee is required" if cfg["assignee"].blank?
            errors << "title is required" if cfg["title"].blank?
            if cfg["priority"].present? && !PRIORITIES.include?(cfg["priority"])
              errors << "Invalid priority: #{cfg['priority']}. Must be one of: #{PRIORITIES.join(', ')}"
            end
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/human_workflow/user_input_request_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module HumanWorkflow
        class UserInputRequestGenerator < BaseGenerator
          generator_metadata do
            description "Pauses workflow to collect user input via form"
            category :human_workflow
            version "1.0.0"
          end

          input_schema  :target_user, :fields
          output_schema :output_key

          def generate
            target_user = config["targetUser"] || "user_id"
            fields = config["fields"] || []
            message = config["message"] || ""
            deadline = config["deadline"]
            target = config["outputKey"] || "user_response"

            fields_literal = fields.map { |f|
              "{ name: #{f['name'].to_s.inspect}, type: #{f['type'].to_s.inspect}, label: #{f['label'].to_s.inspect}, required: #{f['required'] || false} }"
            }.join(", ")

            lines = []
            lines << "ctx[:#{target}] = {"
            lines << "  target_user: ctx[:#{target_user}],"
            lines << "  message: #{message.inspect},"
            lines << "  fields: [#{fields_literal}],"
            lines << "  status: :pending,"
            lines << "  requested_at: Time.current"
            lines << "}"
            lines << "ctx[:_signal_wait] = { key: \"input_\#{SecureRandom.hex(8)}\", timeout: #{(deadline || '7d').inspect} }"
            lines << "true"

            lines.join("\n")
          end

          def validate_config(cfg)
            errors = []
            errors << "fields is required" if cfg["fields"].blank?
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/human_workflow/escalation_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module HumanWorkflow
        class EscalationGenerator < BaseGenerator
          ESCALATION_ACTIONS = %w[reassign notify_additional auto_approve auto_reject].freeze

          generator_metadata do
            description "Escalates pending human workflow items on timeout"
            category :human_workflow
            version "1.0.0"
          end

          input_schema  :watched_key
          output_schema :output_key

          def generate
            watched = config["watchedKey"] || "pending"
            timeout = config["timeout"] || "48h"
            esc_target = config["escalationTarget"] || {}
            action = config["escalationAction"] || "reassign"
            max_esc = (config["maxEscalations"] || 1).to_i
            target = config["outputKey"] || "escalation_result"

            <<~RUBY.chomp
              ctx[:#{target}] = {
                watched_item: ctx[:#{watched}],
                timeout: #{timeout.inspect},
                escalation_target: { type: #{esc_target['type'].to_s.inspect}, id: ctx[:#{esc_target['idKey'] || 'escalation_target_id'}] },
                action: #{action.inspect},
                max_escalations: #{max_esc},
                escalation_count: 0,
                created_at: Time.current
              }
              true
            RUBY
          end

          def validate_config(cfg)
            errors = []
            errors << "watchedKey is required" if cfg["watchedKey"].blank?
            errors << "escalationTarget is required" if cfg["escalationTarget"].blank?
            if cfg["escalationAction"].present? && !ESCALATION_ACTIONS.include?(cfg["escalationAction"])
              errors << "Invalid escalationAction: #{cfg['escalationAction']}. Must be one of: #{ESCALATION_ACTIONS.join(', ')}"
            end
            errors
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/human_workflow/ --format documentation 2>&1 | tail -20
```

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/human_workflow/ spec/services/code_generators/element_types/process/human_workflow/
git commit -m "feat: add approval_gate, assign_task, user_input_request, escalation generators"
```

---

## Task 10: Resilience (circuit_breaker, rate_limiter, retry_with_backoff, idempotency_check)

**Files:**
- Create: 4 generators + 4 specs under `resilience/`

- [ ] **Step 1: Write tests**

```ruby
# spec/services/code_generators/element_types/process/resilience/circuit_breaker_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Resilience::CircuitBreakerGenerator do
  let(:element) { { "config" => { "breakerName" => "payment_gw", "failureThreshold" => 5, "resetTimeout" => 30, "fallbackExpression" => "{ error: 'service_unavailable' }", "outputKey" => "breaker_state" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates circuit breaker code" do
      code = described_class.new(element, context).generate
      expect(code).to include("payment_gw")
      expect(code).to include("Rails.cache")
      expect(code).to include("ctx[:breaker_state]")
      expect(code).to include("true")
    end
  end

  describe "#validate_config" do
    it "requires breakerName" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("breakerName is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/resilience/rate_limiter_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Resilience::RateLimiterGenerator do
  let(:element) { { "config" => { "limiterName" => "api_quota", "maxRequests" => 100, "window" => 60, "onThrottled" => "wait", "outputKey" => "throttle_state" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates rate limiter code" do
      code = described_class.new(element, context).generate
      expect(code).to include("api_quota")
      expect(code).to include("100")
      expect(code).to include("ctx[:throttle_state]")
      expect(code).to include("true")
    end

    it "generates skip on throttle" do
      el = { "config" => { "limiterName" => "x", "maxRequests" => 10, "window" => 60, "onThrottled" => "skip", "outputKey" => "state" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("skip")
    end
  end

  describe "#validate_config" do
    it "requires limiterName" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("limiterName is required")
    end

    it "requires maxRequests" do
      errors = described_class.new(element, {}).validate_config({ "limiterName" => "x" })
      expect(errors).to include("maxRequests is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/resilience/retry_with_backoff_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Resilience::RetryWithBackoffGenerator do
  let(:element) { { "config" => { "maxAttempts" => 5, "backoffType" => "exponential", "baseDelay" => 1, "maxDelay" => 30, "jitter" => true, "outputKey" => "retry_result" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates retry with exponential backoff" do
      code = described_class.new(element, context).generate
      expect(code).to include("5")
      expect(code).to include("2**")
      expect(code).to include("ctx[:retry_result]")
      expect(code).to include("true")
    end

    it "generates linear backoff" do
      el = { "config" => { "maxAttempts" => 3, "backoffType" => "linear", "baseDelay" => 2, "outputKey" => "result" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("*")
      expect(code).not_to include("2**")
    end

    it "includes jitter" do
      code = described_class.new(element, context).generate
      expect(code).to include("rand")
    end
  end

  describe "#validate_config" do
    it "requires maxAttempts" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("maxAttempts is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/resilience/idempotency_check_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Resilience::IdempotencyCheckGenerator do
  let(:element) { { "config" => { "keyExpression" => ["order_id", "payment_ref"], "ttl" => 86400, "onDuplicate" => "skip", "outputKey" => "idempotency_result" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates idempotency check code" do
      code = described_class.new(element, context).generate
      expect(code).to include("ctx[:order_id]")
      expect(code).to include("ctx[:payment_ref]")
      expect(code).to include("Rails.cache")
      expect(code).to include("ctx[:idempotency_result]")
      expect(code).to include("true")
    end
  end

  describe "#validate_config" do
    it "requires keyExpression" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("keyExpression is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/resilience/ 2>&1 | tail -5
```

- [ ] **Step 3: Implement generators**

```ruby
# app/services/code_generators/element_types/process/resilience/circuit_breaker_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Resilience
        class CircuitBreakerGenerator < BaseGenerator
          generator_metadata do
            description "Protects against cascading failures via circuit breaker pattern"
            category :resilience
            version "1.0.0"
          end

          input_schema  :breaker_name
          output_schema :output_key

          def generate
            name = config["breakerName"] || "default"
            threshold = (config["failureThreshold"] || 5).to_i
            reset_timeout = (config["resetTimeout"] || 30).to_i
            fallback = config["fallbackExpression"] || "nil"
            target = config["outputKey"] || "breaker_state"

            <<~RUBY.chomp
              _cb_key = "circuit_breaker:#{name}"
              _cb_state = Rails.cache.read(_cb_key) || { failures: 0, state: :closed, opened_at: nil }
              if _cb_state[:state] == :open
                if Time.current.to_i - _cb_state[:opened_at].to_i > #{reset_timeout}
                  _cb_state[:state] = :half_open
                else
                  ctx[:#{target}] = { state: :open, fallback: #{fallback} }
                  true
                  next
                end
              end
              ctx[:#{target}] = { state: _cb_state[:state], failures: _cb_state[:failures], threshold: #{threshold}, reset_timeout: #{reset_timeout} }
              Rails.cache.write(_cb_key, _cb_state, expires_in: #{reset_timeout * 3})
              true
            RUBY
          end

          def validate_config(cfg)
            errors = []
            errors << "breakerName is required" if cfg["breakerName"].blank?
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/resilience/rate_limiter_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Resilience
        class RateLimiterGenerator < BaseGenerator
          ON_THROTTLED = %w[wait skip raise].freeze

          generator_metadata do
            description "Throttles operation execution to a maximum rate"
            category :resilience
            version "1.0.0"
          end

          input_schema  :limiter_name, :max_requests, :window
          output_schema :output_key

          def generate
            name = config["limiterName"] || "default"
            max = (config["maxRequests"] || 100).to_i
            window = (config["window"] || 60).to_i
            on_throttled = config["onThrottled"] || "skip"
            target = config["outputKey"] || "throttle_state"

            <<~RUBY.chomp
              _rl_key = "rate_limit:#{name}"
              _rl_count = Rails.cache.read(_rl_key).to_i
              if _rl_count >= #{max}
                ctx[:#{target}] = { throttled: true, action: #{on_throttled.inspect} }
                #{on_throttled == 'wait' ? "sleep(1) until Rails.cache.read(_rl_key).to_i < #{max}" : ''}
                #{on_throttled == 'raise' ? 'raise "Rate limit exceeded for #{name}"' : ''}
              else
                Rails.cache.write(_rl_key, _rl_count + 1, expires_in: #{window}) if _rl_count == 0
                Rails.cache.increment(_rl_key) if _rl_count > 0
                ctx[:#{target}] = { throttled: false, remaining: #{max} - _rl_count - 1 }
              end
              true
            RUBY
          end

          def validate_config(cfg)
            errors = []
            errors << "limiterName is required" if cfg["limiterName"].blank?
            errors << "maxRequests is required" if cfg["maxRequests"].blank?
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/resilience/retry_with_backoff_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Resilience
        class RetryWithBackoffGenerator < BaseGenerator
          BACKOFF_TYPES = %w[exponential linear constant].freeze

          generator_metadata do
            description "Retries failed operations with configurable backoff"
            category :resilience
            version "1.0.0"
          end

          input_schema  :max_attempts
          output_schema :output_key

          def generate
            max = (config["maxAttempts"] || 3).to_i
            backoff = config["backoffType"] || "exponential"
            base_delay = (config["baseDelay"] || 1).to_f
            max_delay = (config["maxDelay"] || 60).to_f
            jitter = config["jitter"]
            target = config["outputKey"] || "retry_result"

            delay_expr = case backoff
                         when "exponential" then "#{base_delay} * (2**_attempt)"
                         when "linear"      then "#{base_delay} * _attempt"
                         when "constant"    then base_delay.to_s
                         end

            jitter_expr = jitter ? " + rand(0.0..1.0)" : ""

            <<~RUBY.chomp
              _max_attempts = #{max}
              _last_error = nil
              _max_attempts.times do |_attempt|
                begin
                  break
                rescue StandardError => e
                  _last_error = e
                  _delay = [#{delay_expr}#{jitter_expr}, #{max_delay}].min
                  sleep(_delay) if _attempt < _max_attempts - 1
                end
              end
              ctx[:#{target}] = { attempts_made: _max_attempts, last_error: _last_error&.message }
              true
            RUBY
          end

          def validate_config(cfg)
            errors = []
            errors << "maxAttempts is required" if cfg["maxAttempts"].blank?
            if cfg["backoffType"].present? && !BACKOFF_TYPES.include?(cfg["backoffType"])
              errors << "Invalid backoffType: #{cfg['backoffType']}. Must be one of: #{BACKOFF_TYPES.join(', ')}"
            end
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/resilience/idempotency_check_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Resilience
        class IdempotencyCheckGenerator < BaseGenerator
          ON_DUPLICATE = %w[skip return_cached raise].freeze

          generator_metadata do
            description "Ensures operation executes exactly once per idempotency key"
            category :resilience
            version "1.0.0"
          end

          input_schema  :key_expression
          output_schema :output_key

          def generate
            key_parts = config["keyExpression"] || []
            ttl = (config["ttl"] || 86400).to_i
            on_dup = config["onDuplicate"] || "skip"
            target = config["outputKey"] || "idempotency_result"

            key_expr = key_parts.map { |k| 'ctx[:' + k + '].to_s' }.join(' + ":" + ')
            key_expr = '"unknown"' if key_expr.blank?

            <<~RUBY.chomp
              _idemp_key = "idempotency:" + #{key_expr}
              _cached = Rails.cache.read(_idemp_key)
              if _cached
                ctx[:#{target}] = { is_duplicate: true, cached_result: _cached }
                #{on_dup == 'raise' ? 'raise "Duplicate operation detected"' : ''}
              else
                ctx[:#{target}] = { is_duplicate: false }
                Rails.cache.write(_idemp_key, { executed_at: Time.current }, expires_in: #{ttl})
              end
              true
            RUBY
          end

          def validate_config(cfg)
            errors = []
            errors << "keyExpression is required" if cfg["keyExpression"].blank?
            errors
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/resilience/ --format documentation 2>&1 | tail -20
```

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/resilience/ spec/services/code_generators/element_types/process/resilience/
git commit -m "feat: add circuit_breaker, rate_limiter, retry_with_backoff, idempotency_check generators"
```

---

## Task 11: Scheduling/Time (deadline_check, business_hours_check, timezone_convert)

**Files:**
- Create: 3 generators + 3 specs under `scheduling_time/`

- [ ] **Step 1: Write tests**

```ruby
# spec/services/code_generators/element_types/process/scheduling_time/deadline_check_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::SchedulingTime::DeadlineCheckGenerator do
  let(:element) { { "config" => { "deadlineKey" => "due_date", "outputKey" => "deadline_status" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates deadline check code" do
      code = described_class.new(element, context).generate
      expect(code).to include("ctx[:due_date]")
      expect(code).to include("Time.current")
      expect(code).to include("passed")
      expect(code).to include("ctx[:deadline_status]")
      expect(code).to include("true")
    end
  end

  describe "#validate_config" do
    it "requires deadlineKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("deadlineKey is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/scheduling_time/business_hours_check_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::SchedulingTime::BusinessHoursCheckGenerator do
  let(:element) { { "config" => { "schedule" => { "monday" => { "start" => "09:00", "end" => "17:00" } }, "timezone" => "America/New_York", "outputKey" => "hours_status" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates business hours check code" do
      code = described_class.new(element, context).generate
      expect(code).to include("in_time_zone")
      expect(code).to include("within_hours")
      expect(code).to include("ctx[:hours_status]")
      expect(code).to include("true")
    end
  end

  describe "#validate_config" do
    it "requires schedule" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("schedule is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/scheduling_time/timezone_convert_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::SchedulingTime::TimezoneConvertGenerator do
  let(:element) { { "config" => { "sourceKey" => "event_time", "fromTimezone" => "UTC", "toTimezone" => "America/New_York", "outputKey" => "local_time" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates timezone conversion code" do
      code = described_class.new(element, context).generate
      expect(code).to include("in_time_zone")
      expect(code).to include("America/New_York")
      expect(code).to include("ctx[:local_time]")
      expect(code).to include("true")
    end
  end

  describe "#validate_config" do
    it "requires sourceKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("sourceKey is required")
    end

    it "requires toTimezone" do
      errors = described_class.new(element, {}).validate_config({ "sourceKey" => "x" })
      expect(errors).to include("toTimezone is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/scheduling_time/ 2>&1 | tail -5
```

- [ ] **Step 3: Implement generators**

```ruby
# app/services/code_generators/element_types/process/scheduling_time/deadline_check_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module SchedulingTime
        class DeadlineCheckGenerator < BaseGenerator
          generator_metadata do
            description "Evaluates whether a deadline has passed"
            category :scheduling_time
            version "1.0.0"
          end

          input_schema  :deadline_key
          output_schema :output_key

          def generate
            deadline_key = config["deadlineKey"] || "deadline"
            ref_time = config["referenceTime"]
            target = config["outputKey"] || "deadline_status"

            ref_expr = ref_time.present? ? "ctx[:#{ref_time}]" : "Time.current"

            <<~RUBY.chomp
              _deadline = ctx[:#{deadline_key}].is_a?(String) ? Time.parse(ctx[:#{deadline_key}]) : ctx[:#{deadline_key}]
              _now = #{ref_expr}
              _diff = (_deadline - _now).to_f
              ctx[:#{target}] = {
                passed: _diff <= 0,
                remaining_seconds: [_diff, 0].max,
                overdue_seconds: [_diff.abs, 0].max * (_diff <= 0 ? 1 : 0)
              }
              true
            RUBY
          end

          def validate_config(cfg)
            errors = []
            errors << "deadlineKey is required" if cfg["deadlineKey"].blank?
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/scheduling_time/business_hours_check_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module SchedulingTime
        class BusinessHoursCheckGenerator < BaseGenerator
          generator_metadata do
            description "Checks if current time is within business hours"
            category :scheduling_time
            version "1.0.0"
          end

          input_schema  :schedule
          output_schema :output_key

          def generate
            schedule = config["schedule"] || {}
            timezone = config["timezone"] || "UTC"
            time_key = config["timeKey"]
            target = config["outputKey"] || "hours_status"

            schedule_literal = schedule.inspect

            time_expr = time_key.present? ? "ctx[:#{time_key}]" : "Time.current"

            <<~RUBY.chomp
              _schedule = #{schedule_literal}
              _time = #{time_expr}.in_time_zone(#{timezone.inspect})
              _day = _time.strftime("%A").downcase
              _day_schedule = _schedule[_day] || _schedule[_day.to_sym]
              _within = false
              if _day_schedule
                _start = Time.parse(_day_schedule["start"] || _day_schedule[:start], _time)
                _end = Time.parse(_day_schedule["end"] || _day_schedule[:end], _time)
                _within = _time.between?(_start, _end)
              end
              ctx[:#{target}] = { within_hours: _within, day: _day, current_time: _time.strftime("%H:%M") }
              true
            RUBY
          end

          def validate_config(cfg)
            errors = []
            errors << "schedule is required" if cfg["schedule"].blank?
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/scheduling_time/timezone_convert_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module SchedulingTime
        class TimezoneConvertGenerator < BaseGenerator
          generator_metadata do
            description "Converts a datetime between timezones"
            category :scheduling_time
            version "1.0.0"
          end

          input_schema  :source_key
          output_schema :output_key

          def generate
            source = config["sourceKey"] || "datetime"
            to_tz = config["toTimezone"] || "UTC"
            target = config["outputKey"] || "converted"

            "ctx[:#{target}] = ctx[:#{source}].in_time_zone(#{to_tz.inspect})\ntrue"
          end

          def validate_config(cfg)
            errors = []
            errors << "sourceKey is required" if cfg["sourceKey"].blank?
            errors << "toTimezone is required" if cfg["toTimezone"].blank?
            errors
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/scheduling_time/ --format documentation 2>&1 | tail -15
```

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/scheduling_time/ spec/services/code_generators/element_types/process/scheduling_time/
git commit -m "feat: add deadline_check, business_hours_check, timezone_convert generators"
```

---

## Task 12: Utility — Core (template_render, audit_log, ai_inference)

**Files:**
- Create: 3 generators + 3 specs under `utility/`

- [ ] **Step 1: Write tests**

```ruby
# spec/services/code_generators/element_types/process/utility/template_render_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Utility::TemplateRenderGenerator do
  let(:element) { { "config" => { "template" => "Hello {{ name }}", "engine" => "liquid", "variables" => { "name" => "user_name" }, "outputKey" => "rendered" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates liquid template rendering" do
      code = described_class.new(element, context).generate
      expect(code).to include("Liquid::Template")
      expect(code).to include("ctx[:rendered]")
      expect(code).to include("true")
    end

    it "generates ERB rendering" do
      el = { "config" => { "template" => "Hello <%= name %>", "engine" => "erb", "variables" => { "name" => "user_name" }, "outputKey" => "rendered" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("ERB")
    end
  end

  describe "#validate_config" do
    it "requires template" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("template is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/utility/audit_log_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Utility::AuditLogGenerator do
  let(:element) { { "config" => { "actorKey" => "current_user", "action" => "approved", "targetKey" => "expense_report", "severity" => "info" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates audit log code" do
      code = described_class.new(element, context).generate
      expect(code).to include("ctx[:current_user]")
      expect(code).to include("approved")
      expect(code).to include("ctx[:expense_report]")
      expect(code).to include("info")
      expect(code).to include("true")
    end
  end

  describe "#validate_config" do
    it "requires action" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("action is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/utility/ai_inference_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Utility::AiInferenceGenerator do
  let(:element) { { "config" => { "provider" => "openai", "model" => "gpt-4", "promptTemplate" => "Classify: {{ text }}", "apiKeyReference" => "openai_key", "outputKey" => "ai_response" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates AI inference code" do
      code = described_class.new(element, context).generate
      expect(code).to include("gpt-4")
      expect(code).to include("ctx[:ai_response]")
      expect(code).to include("Net::HTTP")
      expect(code).to include("true")
    end

    it "includes response format for json_schema" do
      el = { "config" => { "provider" => "openai", "model" => "gpt-4", "promptTemplate" => "test", "apiKeyReference" => "key", "responseFormat" => "json_schema", "outputKey" => "result" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("JSON.parse")
    end
  end

  describe "#validate_config" do
    it "requires promptTemplate" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("promptTemplate is required")
    end

    it "requires apiKeyReference" do
      errors = described_class.new(element, {}).validate_config({ "promptTemplate" => "test" })
      expect(errors).to include("apiKeyReference is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/utility/{template_render,audit_log,ai_inference}_generator_spec.rb 2>&1 | tail -5
```

- [ ] **Step 3: Implement generators**

```ruby
# app/services/code_generators/element_types/process/utility/template_render_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Utility
        class TemplateRenderGenerator < BaseGenerator
          ENGINES = %w[liquid erb].freeze

          generator_metadata do
            description "Renders Liquid or ERB templates with dynamic variables"
            category :utility
            version "1.0.0"
          end

          input_schema  :template, :variables
          output_schema :output_key

          def generate
            template = config["template"] || ""
            engine = config["engine"] || "liquid"
            variables = config["variables"] || {}
            target = config["outputKey"] || "rendered"

            vars_hash = variables.map { |k, v| "#{k.inspect} => ctx[:#{v}].to_s" }.join(", ")

            if engine == "liquid"
              <<~RUBY.chomp
                _template = Liquid::Template.parse(#{template.inspect})
                ctx[:#{target}] = _template.render({#{vars_hash}})
                true
              RUBY
            else
              <<~RUBY.chomp
                _vars = OpenStruct.new({#{vars_hash}})
                ctx[:#{target}] = ERB.new(#{template.inspect}).result(_vars.instance_eval { binding })
                true
              RUBY
            end
          end

          def validate_config(cfg)
            errors = []
            errors << "template is required" if cfg["template"].blank?
            if cfg["engine"].present? && !ENGINES.include?(cfg["engine"])
              errors << "Invalid engine: #{cfg['engine']}. Must be one of: #{ENGINES.join(', ')}"
            end
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/utility/audit_log_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Utility
        class AuditLogGenerator < BaseGenerator
          SEVERITIES = %w[info warning critical].freeze

          generator_metadata do
            description "Writes structured audit log entries"
            category :utility
            version "1.0.0"
          end

          input_schema  :actor_key, :action, :target_key
          output_schema

          def generate
            actor = config["actorKey"] || "current_user"
            action = config["action"] || "unknown"
            target_key = config["targetKey"]
            severity = config["severity"] || "info"
            metadata = config["metadata"] || {}

            meta_hash = metadata.map { |k, v| "#{k.inspect} => ctx[:#{v}]" }.join(", ")

            lines = []
            lines << "_audit_entry = {"
            lines << "  actor: ctx[:#{actor}],"
            lines << "  action: #{action.inspect},"
            lines << "  target: #{target_key ? "ctx[:#{target_key}]" : 'nil'},"
            lines << "  severity: #{severity.inspect},"
            lines << "  metadata: {#{meta_hash}}," if metadata.any?
            lines << "  customer_id: ctx[:customer_id],"
            lines << "  timestamp: Time.current"
            lines << "}"
            lines << 'Rails.logger.info("[AUDIT] #{_audit_entry.to_json}")'
            lines << "true"

            lines.join("\n")
          end

          def validate_config(cfg)
            errors = []
            errors << "action is required" if cfg["action"].blank?
            if cfg["severity"].present? && !SEVERITIES.include?(cfg["severity"])
              errors << "Invalid severity: #{cfg['severity']}. Must be one of: #{SEVERITIES.join(', ')}"
            end
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/utility/ai_inference_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Utility
        class AiInferenceGenerator < BaseGenerator
          PROVIDERS = %w[openai anthropic custom].freeze

          generator_metadata do
            description "Calls AI/LLM models with prompt templates"
            category :utility
            version "1.0.0"
          end

          input_schema  :prompt_template, :api_key_reference
          output_schema :output_key

          def generate
            provider = config["provider"] || "openai"
            model = config["model"] || "gpt-4"
            prompt_template = config["promptTemplate"] || ""
            system_prompt = config["systemPrompt"]
            response_format = config["responseFormat"] || "text"
            api_key_ref = config["apiKeyReference"] || "api_key"
            temperature = config["temperature"] || 0.7
            max_tokens = config["maxTokens"] || 1000
            target = config["outputKey"] || "ai_response"

            lines = []

            # Build prompt from template (simple variable substitution)
            lines << "_prompt = #{prompt_template.inspect}"
            lines << 'ctx.each { |k, v| _prompt = _prompt.gsub("{{ #{k} }}", v.to_s) if v.is_a?(String) }'

            # API call based on provider
            case provider
            when "openai"
              lines << "_messages = []"
              lines << "_messages << { role: 'system', content: #{system_prompt.inspect} }" if system_prompt.present?
              lines << "_messages << { role: 'user', content: _prompt }"
              lines << "_uri = URI('https://api.openai.com/v1/chat/completions')"
              lines << "_req = Net::HTTP::Post.new(_uri)"
              lines << '_req["Authorization"] = "Bearer #{ctx[:' + api_key_ref + ']}"'
              lines << '_req["Content-Type"] = "application/json"'
              lines << "_req.body = { model: #{model.inspect}, messages: _messages, temperature: #{temperature}, max_tokens: #{max_tokens} }.to_json"
              lines << "_res = Net::HTTP.start(_uri.hostname, _uri.port, use_ssl: true) { |http| http.request(_req) }"
              lines << "_body = JSON.parse(_res.body)"
              lines << '_content = _body.dig("choices", 0, "message", "content")'
            when "anthropic"
              lines << "_uri = URI('https://api.anthropic.com/v1/messages')"
              lines << "_req = Net::HTTP::Post.new(_uri)"
              lines << '_req["x-api-key"] = ctx[:' + api_key_ref + ']'
              lines << '_req["Content-Type"] = "application/json"'
              lines << '_req["anthropic-version"] = "2023-06-01"'
              lines << "_body_hash = { model: #{model.inspect}, max_tokens: #{max_tokens}, messages: [{ role: 'user', content: _prompt }] }"
              lines << "_body_hash[:system] = #{system_prompt.inspect}" if system_prompt.present?
              lines << "_req.body = _body_hash.to_json"
              lines << "_res = Net::HTTP.start(_uri.hostname, _uri.port, use_ssl: true) { |http| http.request(_req) }"
              lines << "_body = JSON.parse(_res.body)"
              lines << '_content = _body.dig("content", 0, "text")'
            end

            if response_format == "json_schema"
              lines << "ctx[:#{target}] = JSON.parse(_content)"
            else
              lines << "ctx[:#{target}] = _content"
            end
            lines << "true"

            lines.join("\n")
          end

          def validate_config(cfg)
            errors = []
            errors << "promptTemplate is required" if cfg["promptTemplate"].blank?
            errors << "apiKeyReference is required" if cfg["apiKeyReference"].blank?
            if cfg["provider"].present? && !PROVIDERS.include?(cfg["provider"])
              errors << "Invalid provider: #{cfg['provider']}. Must be one of: #{PROVIDERS.join(', ')}"
            end
            errors
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/utility/{template_render,audit_log,ai_inference}_generator_spec.rb --format documentation 2>&1 | tail -15
```

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/utility/{template_render,audit_log,ai_inference}_generator.rb spec/services/code_generators/element_types/process/utility/{template_render,audit_log,ai_inference}_generator_spec.rb
git commit -m "feat: add template_render, audit_log, ai_inference utility generators"
```

---

## Task 13: Utility — Specialized (qr_code, barcode, geolocation, currency, i18n)

**Files:**
- Create: 5 generators + 5 specs under `utility/`

- [ ] **Step 1: Write tests**

```ruby
# spec/services/code_generators/element_types/process/utility/qr_code_generate_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Utility::QrCodeGenerateGenerator do
  let(:element) { { "config" => { "dataKey" => "url", "size" => 300, "format" => "png", "outputKey" => "qr_image" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates QR code creation code" do
      code = described_class.new(element, context).generate
      expect(code).to include("RQRCode")
      expect(code).to include("ctx[:url]")
      expect(code).to include("ctx[:qr_image]")
      expect(code).to include("true")
    end

    it "generates SVG format" do
      el = { "config" => { "dataKey" => "data", "format" => "svg", "outputKey" => "qr" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("as_svg")
    end
  end

  describe "#validate_config" do
    it "requires dataKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("dataKey is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/utility/barcode_generate_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Utility::BarcodeGenerateGenerator do
  let(:element) { { "config" => { "dataKey" => "sku", "symbology" => "code128", "outputKey" => "barcode_image" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates barcode creation code" do
      code = described_class.new(element, context).generate
      expect(code).to include("Barby")
      expect(code).to include("Code128")
      expect(code).to include("ctx[:sku]")
      expect(code).to include("ctx[:barcode_image]")
      expect(code).to include("true")
    end
  end

  describe "#validate_config" do
    it "requires dataKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("dataKey is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/utility/geolocation_lookup_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Utility::GeolocationLookupGenerator do
  let(:element) { { "config" => { "mode" => "ip_to_location", "sourceKey" => "ip_address", "outputKey" => "location" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates IP lookup code" do
      code = described_class.new(element, context).generate
      expect(code).to include("ctx[:ip_address]")
      expect(code).to include("ctx[:location]")
      expect(code).to include("true")
    end

    it "generates distance calculation" do
      el = { "config" => { "mode" => "distance", "sourceKey" => "point_a", "targetKey" => "point_b", "outputKey" => "distance" } }
      code = described_class.new(el, {}).generate
      expect(code).to include("Math")
      expect(code).to include("ctx[:distance]")
    end
  end

  describe "#validate_config" do
    it "requires sourceKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("sourceKey is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/utility/currency_convert_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Utility::CurrencyConvertGenerator do
  let(:element) { { "config" => { "amountKey" => "price", "fromCurrency" => "EUR", "toCurrency" => "USD", "ratesSource" => "ctx_key", "ratesKey" => "exchange_rates", "precision" => 2, "outputKey" => "converted_price" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates currency conversion code" do
      code = described_class.new(element, context).generate
      expect(code).to include("ctx[:price]")
      expect(code).to include("ctx[:exchange_rates]")
      expect(code).to include("round(2)")
      expect(code).to include("ctx[:converted_price]")
      expect(code).to include("true")
    end
  end

  describe "#validate_config" do
    it "requires amountKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("amountKey is required")
    end

    it "requires toCurrency" do
      errors = described_class.new(element, {}).validate_config({ "amountKey" => "x" })
      expect(errors).to include("toCurrency is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/process/utility/i18n_translate_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Utility::I18nTranslateGenerator do
  let(:element) { { "config" => { "translationKey" => "notifications.new_orders", "locale" => "user_locale", "interpolations" => { "count" => "order_count" }, "outputKey" => "message" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates I18n.t code" do
      code = described_class.new(element, context).generate
      expect(code).to include("I18n.t")
      expect(code).to include("notifications.new_orders")
      expect(code).to include("ctx[:message]")
      expect(code).to include("true")
    end

    it "includes locale" do
      code = described_class.new(element, context).generate
      expect(code).to include("locale:")
    end

    it "includes interpolations" do
      code = described_class.new(element, context).generate
      expect(code).to include("count:")
    end
  end

  describe "#validate_config" do
    it "requires translationKey" do
      errors = described_class.new(element, {}).validate_config({})
      expect(errors).to include("translationKey is required")
    end

    it "passes for valid config" do
      errors = described_class.new(element, {}).validate_config(element["config"])
      expect(errors).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/utility/{qr_code_generate,barcode_generate,geolocation_lookup,currency_convert,i18n_translate}_generator_spec.rb 2>&1 | tail -5
```

- [ ] **Step 3: Implement generators**

```ruby
# app/services/code_generators/element_types/process/utility/qr_code_generate_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Utility
        class QrCodeGenerateGenerator < BaseGenerator
          generator_metadata do
            description "Generates QR code images from string data"
            category :utility
            version "1.0.0"
          end

          input_schema  :data_key
          output_schema :output_key

          def generate
            data_key = config["dataKey"] || "data"
            size = (config["size"] || 300).to_i
            format = config["format"] || "png"
            error_correction = config["errorCorrection"] || "medium"
            target = config["outputKey"] || "qr_image"

            ec_level = case error_correction
                       when "low" then ":low"
                       when "medium" then ":medium"
                       when "quartile" then ":quartile"
                       when "high" then ":high"
                       else ":medium"
                       end

            if format == "svg"
              <<~RUBY.chomp
                _qr = RQRCode::QRCode.new(ctx[:#{data_key}].to_s, level: #{ec_level})
                ctx[:#{target}] = _qr.as_svg(module_size: 6, standalone: true)
                true
              RUBY
            else
              <<~RUBY.chomp
                _qr = RQRCode::QRCode.new(ctx[:#{data_key}].to_s, level: #{ec_level})
                ctx[:#{target}] = _qr.as_png(size: #{size}).to_s
                true
              RUBY
            end
          end

          def validate_config(cfg)
            errors = []
            errors << "dataKey is required" if cfg["dataKey"].blank?
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/utility/barcode_generate_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Utility
        class BarcodeGenerateGenerator < BaseGenerator
          SYMBOLOGIES = %w[code128 ean13 upc_a code39].freeze

          generator_metadata do
            description "Generates barcode images in standard formats"
            category :utility
            version "1.0.0"
          end

          input_schema  :data_key
          output_schema :output_key

          def generate
            data_key = config["dataKey"] || "data"
            symbology = config["symbology"] || "code128"
            target = config["outputKey"] || "barcode_image"

            barby_class = case symbology
                          when "code128" then "Barby::Code128"
                          when "ean13"   then "Barby::EAN13"
                          when "upc_a"   then "Barby::UPCA"
                          when "code39"  then "Barby::Code39"
                          else "Barby::Code128"
                          end

            <<~RUBY.chomp
              _barcode = #{barby_class}.new(ctx[:#{data_key}].to_s)
              ctx[:#{target}] = _barcode.to_png(height: 50, margin: 5).to_s
              true
            RUBY
          end

          def validate_config(cfg)
            errors = []
            errors << "dataKey is required" if cfg["dataKey"].blank?
            if cfg["symbology"].present? && !SYMBOLOGIES.include?(cfg["symbology"])
              errors << "Invalid symbology: #{cfg['symbology']}. Must be one of: #{SYMBOLOGIES.join(', ')}"
            end
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/utility/geolocation_lookup_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Utility
        class GeolocationLookupGenerator < BaseGenerator
          MODES = %w[ip_to_location coordinates_to_location distance].freeze

          generator_metadata do
            description "Resolves location data or calculates distance"
            category :utility
            version "1.0.0"
          end

          input_schema  :source_key
          output_schema :output_key

          def generate
            mode = config["mode"] || "ip_to_location"
            source = config["sourceKey"] || "source"
            target_key = config["targetKey"]
            output = config["outputKey"] || "location"

            case mode
            when "ip_to_location"
              <<~RUBY.chomp
                _reader = MaxMind::GeoIP2::Reader.new(database: Rails.root.join("db", "GeoLite2-City.mmdb").to_s)
                _record = _reader.city(ctx[:#{source}].to_s)
                ctx[:#{output}] = { country: _record.country.name, city: _record.city.name, timezone: _record.location.time_zone, lat: _record.location.latitude, lng: _record.location.longitude }
                true
              RUBY
            when "distance"
              <<~RUBY.chomp
                _lat1, _lng1 = ctx[:#{source}][:lat].to_f * Math::PI / 180, ctx[:#{source}][:lng].to_f * Math::PI / 180
                _lat2, _lng2 = ctx[:#{target_key || 'target'}][:lat].to_f * Math::PI / 180, ctx[:#{target_key || 'target'}][:lng].to_f * Math::PI / 180
                _dlat = _lat2 - _lat1
                _dlng = _lng2 - _lng1
                _a = Math.sin(_dlat / 2)**2 + Math.cos(_lat1) * Math.cos(_lat2) * Math.sin(_dlng / 2)**2
                _km = 6371 * 2 * Math.atan2(Math.sqrt(_a), Math.sqrt(1 - _a))
                ctx[:#{output}] = { km: _km.round(2), miles: (_km * 0.621371).round(2) }
                true
              RUBY
            else
              "ctx[:#{output}] = nil\ntrue"
            end
          end

          def validate_config(cfg)
            errors = []
            errors << "sourceKey is required" if cfg["sourceKey"].blank?
            if cfg["mode"].present? && !MODES.include?(cfg["mode"])
              errors << "Invalid mode: #{cfg['mode']}. Must be one of: #{MODES.join(', ')}"
            end
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/utility/currency_convert_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Utility
        class CurrencyConvertGenerator < BaseGenerator
          RATES_SOURCES = %w[static_table ctx_key].freeze

          generator_metadata do
            description "Converts monetary amounts between currencies"
            category :utility
            version "1.0.0"
          end

          input_schema  :amount_key, :from_currency, :to_currency
          output_schema :output_key

          def generate
            amount_key = config["amountKey"] || "amount"
            from = config["fromCurrency"] || "USD"
            to = config["toCurrency"] || "USD"
            rates_source = config["ratesSource"] || "ctx_key"
            rates_key = config["ratesKey"] || "exchange_rates"
            precision = (config["precision"] || 2).to_i
            target = config["outputKey"] || "converted"

            <<~RUBY.chomp
              _rates = ctx[:#{rates_key}] || {}
              _from_rate = _rates[#{from.inspect}] || 1.0
              _to_rate = _rates[#{to.inspect}] || 1.0
              _base_amount = ctx[:#{amount_key}].to_f / _from_rate
              ctx[:#{target}] = (_base_amount * _to_rate).round(#{precision})
              true
            RUBY
          end

          def validate_config(cfg)
            errors = []
            errors << "amountKey is required" if cfg["amountKey"].blank?
            errors << "toCurrency is required" if cfg["toCurrency"].blank?
            errors
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/element_types/process/utility/i18n_translate_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Utility
        class I18nTranslateGenerator < BaseGenerator
          generator_metadata do
            description "Looks up translated strings with interpolation"
            category :utility
            version "1.0.0"
          end

          input_schema  :translation_key
          output_schema :output_key

          def generate
            key = config["translationKey"] || "missing_key"
            locale_key = config["locale"]
            interpolations = config["interpolations"] || {}
            fallback = config["fallbackLocale"] || "en"
            target = config["outputKey"] || "translated"

            opts = []
            opts << "locale: ctx[:#{locale_key}]&.to_sym || #{fallback.inspect}" if locale_key.present?
            opts << "default: #{fallback.inspect}"

            interpolations.each do |name, ctx_key|
              opts << "#{name}: ctx[:#{ctx_key}]"
            end

            "ctx[:#{target}] = I18n.t(#{key.inspect}, #{opts.join(', ')})\ntrue"
          end

          def validate_config(cfg)
            errors = []
            errors << "translationKey is required" if cfg["translationKey"].blank?
            errors
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/utility/ --format documentation 2>&1 | tail -30
```

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/utility/ spec/services/code_generators/element_types/process/utility/
git commit -m "feat: add qr_code, barcode, geolocation, currency, i18n utility generators"
```

---

## Task 14: Final Verification

- [ ] **Step 1: Run all generator tests**

```bash
bundle exec rspec spec/services/code_generators/ --format documentation 2>&1 | tail -30
```

Expected: all tests PASS including existing + 51 new generators

- [ ] **Step 2: Verify registry discovers all generators**

```bash
bundle exec rails runner "
  CodeGenerators::GeneratorRegistry.reload!
  steps = CodeGenerators::GeneratorRegistry.step_action_generators
  puts \"Step action generators: #{steps.count}\"
  steps.keys.sort.each { |k| puts \"  #{k}\" }
"
```

Expected: ~110 step action generators listed

- [ ] **Step 3: Verify admin page loads**

```bash
curl -s http://localhost:3000/admin/code_generators 2>&1 | grep -c 'generator'
```

Expected: Page loads showing all generators organized by category

- [ ] **Step 4: Final commit**

```bash
git add -A
git status
# If there are any remaining unstaged files, review and add them
git commit -m "chore: complete code generator full coverage — 51 new generators across 11 categories"
```
