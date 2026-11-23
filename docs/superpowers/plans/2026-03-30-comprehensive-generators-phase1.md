# Comprehensive Generators Phase 1 -- Model Ops & Data Ops Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 10 new step action generators: 4 model operations (CheckExistence, CountRecords, PluckFields, AggregateQuery) and 6 data operations (GroupCollection, UniqCollection, MergeData, SerializeData, DateTimeCalc, RegexExtract).

**Architecture:** Each generator follows the existing BaseGenerator pattern. Model ops use EntityEntry.build_for(ctx[:bound_entity]) for model access. Data ops operate on ctx variables. All generators are independently testable and auto-discovered by GeneratorRegistry.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, RSpec

---

## File Structure

| File | Purpose |
|------|---------|
| `app/services/code_generators/element_types/process/model_operations/check_existence_generator.rb` | Check if records exist matching conditions |
| `app/services/code_generators/element_types/process/model_operations/count_records_generator.rb` | Count records with optional distinct |
| `app/services/code_generators/element_types/process/model_operations/pluck_fields_generator.rb` | Extract specific field values from records |
| `app/services/code_generators/element_types/process/model_operations/aggregate_query_generator.rb` | Run aggregate functions (sum, avg, min, max) |
| `app/services/code_generators/element_types/process/data_operations/group_collection_generator.rb` | Group array items by field |
| `app/services/code_generators/element_types/process/data_operations/uniq_collection_generator.rb` | Deduplicate array items |
| `app/services/code_generators/element_types/process/data_operations/merge_data_generator.rb` | Merge two hashes with strategy control |
| `app/services/code_generators/element_types/process/data_operations/serialize_data_generator.rb` | Serialize data to JSON/XML/YAML/CSV |
| `app/services/code_generators/element_types/process/data_operations/date_time_calc_generator.rb` | Date/time arithmetic and formatting |
| `app/services/code_generators/element_types/process/data_operations/regex_extract_generator.rb` | Regex match, scan, test, replace on strings |
| `spec/services/code_generators/element_types/process/model_operations/check_existence_generator_spec.rb` | CheckExistence tests |
| `spec/services/code_generators/element_types/process/model_operations/count_records_generator_spec.rb` | CountRecords tests |
| `spec/services/code_generators/element_types/process/model_operations/pluck_fields_generator_spec.rb` | PluckFields tests |
| `spec/services/code_generators/element_types/process/model_operations/aggregate_query_generator_spec.rb` | AggregateQuery tests |
| `spec/services/code_generators/element_types/process/data_operations/group_collection_generator_spec.rb` | GroupCollection tests |
| `spec/services/code_generators/element_types/process/data_operations/uniq_collection_generator_spec.rb` | UniqCollection tests |
| `spec/services/code_generators/element_types/process/data_operations/merge_data_generator_spec.rb` | MergeData tests |
| `spec/services/code_generators/element_types/process/data_operations/serialize_data_generator_spec.rb` | SerializeData tests |
| `spec/services/code_generators/element_types/process/data_operations/date_time_calc_generator_spec.rb` | DateTimeCalc tests |
| `spec/services/code_generators/element_types/process/data_operations/regex_extract_generator_spec.rb` | RegexExtract tests |

---

### Task 1: CheckExistence generator

**Files:**
- Create: `spec/services/code_generators/element_types/process/model_operations/check_existence_generator_spec.rb`
- Create: `app/services/code_generators/element_types/process/model_operations/check_existence_generator.rb`

- [ ] **Step 1: Write the spec**

```ruby
# spec/services/code_generators/element_types/process/model_operations/check_existence_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::CheckExistenceGenerator do
  let(:element) { { "config" => { "targetVariable" => "found", "checkMethod" => "exists" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates exists? check by default" do
    code = described_class.new(element, context).generate
    expect(code).to include("ctx[:found] = EntityEntry.build_for(ctx[:bound_entity]).where(nil).exists?")
    expect(code).to include("true")
  end

  it "generates any? check" do
    el = { "config" => { "targetVariable" => "has_records", "checkMethod" => "any" } }
    code = described_class.new(el, {}).generate
    expect(code).to include(".any?")
    expect(code).to include("ctx[:has_records]")
  end

  it "generates none? check" do
    el = { "config" => { "targetVariable" => "empty", "checkMethod" => "none" } }
    code = described_class.new(el, {}).generate
    expect(code).to include(".none?")
    expect(code).to include("ctx[:empty]")
  end

  it "applies static conditions" do
    el = { "config" => { "targetVariable" => "found", "checkMethod" => "exists", "conditions" => [{ "key" => "status", "value" => '"active"' }] } }
    code = described_class.new(el, {}).generate
    expect(code).to include('.where(status: "active")')
  end

  it "applies conditionVariable for dynamic conditions" do
    el = { "config" => { "targetVariable" => "found", "checkMethod" => "exists", "conditionVariable" => "search_params" } }
    code = described_class.new(el, {}).generate
    expect(code).to include(".where(ctx[:search_params])")
  end

  it "validates targetVariable is required" do
    errors = described_class.new({ "config" => {} }, {}).validate_config({})
    expect(errors).to include("targetVariable is required")
  end

  it "validates checkMethod must be in allowed list" do
    errors = described_class.new(element, {}).validate_config({ "targetVariable" => "x", "checkMethod" => "invalid" })
    expect(errors).to include(/Invalid checkMethod/)
  end

  it "accepts valid checkMethod without error" do
    errors = described_class.new(element, {}).validate_config({ "targetVariable" => "x", "checkMethod" => "exists" })
    expect(errors).to be_empty
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/model_operations/check_existence_generator_spec.rb --format documentation`
Expected: FAIL -- `uninitialized constant`

- [ ] **Step 3: Implement the generator**

```ruby
# app/services/code_generators/element_types/process/model_operations/check_existence_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class CheckExistenceGenerator < BaseGenerator
          CHECK_METHODS = %w[exists any none].freeze

          generator_metadata do
            description "Checks whether records exist matching given conditions (exists?, any?, none?)"
            category :model_operations
            version "1.0.0"
          end

          input_schema  :bound_entity
          output_schema :target_variable

          def generate
            target = config["targetVariable"] || "exists"
            check_method = config["checkMethod"] || "exists"
            query = build_query
            method_call = check_method_suffix(check_method)

            <<~RUBY.chomp
              ctx[:#{target}] = #{query}.#{method_call}
              true
            RUBY
          end

          def validate_config(cfg)
            errors = []
            errors << "targetVariable is required" if cfg["targetVariable"].blank?
            if cfg["checkMethod"].present? && !CHECK_METHODS.include?(cfg["checkMethod"])
              errors << "Invalid checkMethod: #{cfg['checkMethod']}. Must be one of: #{CHECK_METHODS.join(', ')}"
            end
            errors
          end

          def example_output
            "ctx[:exists] = EntityEntry.build_for(ctx[:bound_entity]).where(nil).exists?\ntrue"
          end

          private

          def build_query
            condition_var = config["conditionVariable"]
            if condition_var.present?
              "EntityEntry.build_for(ctx[:bound_entity]).where(ctx[:#{condition_var}])"
            else
              conditions = config["conditions"] || []
              if conditions.any?
                pairs = conditions.map { |c| "#{c['key']}: #{c['value']}" }.join(", ")
                "EntityEntry.build_for(ctx[:bound_entity]).where(#{pairs})"
              else
                "EntityEntry.build_for(ctx[:bound_entity]).where(nil)"
              end
            end
          end

          def check_method_suffix(method)
            case method
            when "any"  then "any?"
            when "none" then "none?"
            else "exists?"
            end
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/model_operations/check_existence_generator_spec.rb --format documentation`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add \
  app/services/code_generators/element_types/process/model_operations/check_existence_generator.rb \
  spec/services/code_generators/element_types/process/model_operations/check_existence_generator_spec.rb
git commit -m "$(cat <<'EOF'
feat: add CheckExistence generator

Adds model operation generator that checks for record existence
using exists?, any?, or none? with static or dynamic conditions.

Co-Authored-By: Copilot Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: CountRecords generator

**Files:**
- Create: `spec/services/code_generators/element_types/process/model_operations/count_records_generator_spec.rb`
- Create: `app/services/code_generators/element_types/process/model_operations/count_records_generator.rb`

- [ ] **Step 1: Write the spec**

```ruby
# spec/services/code_generators/element_types/process/model_operations/count_records_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::CountRecordsGenerator do
  let(:element) { { "config" => { "targetVariable" => "total" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates simple count" do
    code = described_class.new(element, context).generate
    expect(code).to include("ctx[:total] = EntityEntry.build_for(ctx[:bound_entity]).where(nil).count")
    expect(code).to include("true")
  end

  it "generates count with static conditions" do
    el = { "config" => { "targetVariable" => "active_count", "conditions" => [{ "key" => "status", "value" => '"active"' }] } }
    code = described_class.new(el, {}).generate
    expect(code).to include('.where(status: "active").count')
    expect(code).to include("ctx[:active_count]")
  end

  it "generates count with conditionVariable" do
    el = { "config" => { "targetVariable" => "count", "conditionVariable" => "filters" } }
    code = described_class.new(el, {}).generate
    expect(code).to include(".where(ctx[:filters]).count")
  end

  it "generates distinct count" do
    el = { "config" => { "targetVariable" => "unique_count", "distinct" => true, "distinctField" => "email" } }
    code = described_class.new(el, {}).generate
    expect(code).to include(".distinct.count(:email)")
  end

  it "generates distinct count without field" do
    el = { "config" => { "targetVariable" => "unique_count", "distinct" => true } }
    code = described_class.new(el, {}).generate
    expect(code).to include(".distinct.count")
    expect(code).not_to include(".count(:")
  end

  it "validates targetVariable is required" do
    errors = described_class.new({ "config" => {} }, {}).validate_config({})
    expect(errors).to include("targetVariable is required")
  end

  it "passes validation with valid config" do
    errors = described_class.new(element, {}).validate_config({ "targetVariable" => "total" })
    expect(errors).to be_empty
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/model_operations/count_records_generator_spec.rb --format documentation`
Expected: FAIL -- `uninitialized constant`

- [ ] **Step 3: Implement the generator**

```ruby
# app/services/code_generators/element_types/process/model_operations/count_records_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class CountRecordsGenerator < BaseGenerator
          generator_metadata do
            description "Counts records matching conditions with optional distinct"
            category :model_operations
            version "1.0.0"
          end

          input_schema  :bound_entity
          output_schema :target_variable

          def generate
            target = config["targetVariable"] || "count"
            distinct = config["distinct"] == true
            distinct_field = config["distinctField"]
            query = build_query

            count_chain = if distinct && distinct_field.present?
                           ".distinct.count(:#{distinct_field})"
                         elsif distinct
                           ".distinct.count"
                         else
                           ".count"
                         end

            <<~RUBY.chomp
              ctx[:#{target}] = #{query}#{count_chain}
              true
            RUBY
          end

          def validate_config(cfg)
            errors = []
            errors << "targetVariable is required" if cfg["targetVariable"].blank?
            errors
          end

          def example_output
            "ctx[:total] = EntityEntry.build_for(ctx[:bound_entity]).where(nil).count\ntrue"
          end

          private

          def build_query
            condition_var = config["conditionVariable"]
            if condition_var.present?
              "EntityEntry.build_for(ctx[:bound_entity]).where(ctx[:#{condition_var}])"
            else
              conditions = config["conditions"] || []
              if conditions.any?
                pairs = conditions.map { |c| "#{c['key']}: #{c['value']}" }.join(", ")
                "EntityEntry.build_for(ctx[:bound_entity]).where(#{pairs})"
              else
                "EntityEntry.build_for(ctx[:bound_entity]).where(nil)"
              end
            end
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/model_operations/count_records_generator_spec.rb --format documentation`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add \
  app/services/code_generators/element_types/process/model_operations/count_records_generator.rb \
  spec/services/code_generators/element_types/process/model_operations/count_records_generator_spec.rb
git commit -m "$(cat <<'EOF'
feat: add CountRecords generator

Adds model operation generator that counts records matching conditions
with support for distinct counting on specific fields.

Co-Authored-By: Copilot Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: PluckFields generator

**Files:**
- Create: `spec/services/code_generators/element_types/process/model_operations/pluck_fields_generator_spec.rb`
- Create: `app/services/code_generators/element_types/process/model_operations/pluck_fields_generator.rb`

- [ ] **Step 1: Write the spec**

```ruby
# spec/services/code_generators/element_types/process/model_operations/pluck_fields_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::PluckFieldsGenerator do
  let(:element) { { "config" => { "targetVariable" => "emails", "fields" => ["email"] } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates pluck with single field" do
    code = described_class.new(element, context).generate
    expect(code).to include("ctx[:emails] = EntityEntry.build_for(ctx[:bound_entity]).where(nil).pluck(:email)")
    expect(code).to include("true")
  end

  it "generates pluck with multiple fields" do
    el = { "config" => { "targetVariable" => "data", "fields" => ["name", "email", "age"] } }
    code = described_class.new(el, {}).generate
    expect(code).to include(".pluck(:name, :email, :age)")
  end

  it "generates pluck with static conditions" do
    el = { "config" => { "targetVariable" => "emails", "fields" => ["email"], "conditions" => [{ "key" => "active", "value" => "true" }] } }
    code = described_class.new(el, {}).generate
    expect(code).to include(".where(active: true).pluck(:email)")
  end

  it "generates pluck with conditionVariable" do
    el = { "config" => { "targetVariable" => "ids", "fields" => ["id"], "conditionVariable" => "filters" } }
    code = described_class.new(el, {}).generate
    expect(code).to include(".where(ctx[:filters]).pluck(:id)")
  end

  it "generates pluck with distinct" do
    el = { "config" => { "targetVariable" => "unique_emails", "fields" => ["email"], "uniq" => true } }
    code = described_class.new(el, {}).generate
    expect(code).to include(".distinct.pluck(:email)")
  end

  it "validates targetVariable is required" do
    errors = described_class.new({ "config" => {} }, {}).validate_config({})
    expect(errors).to include("targetVariable is required")
  end

  it "validates fields must be non-empty array" do
    errors = described_class.new({ "config" => {} }, {}).validate_config({ "targetVariable" => "x", "fields" => [] })
    expect(errors).to include("fields must be a non-empty array")
  end

  it "validates fields is required" do
    errors = described_class.new({ "config" => {} }, {}).validate_config({ "targetVariable" => "x" })
    expect(errors).to include("fields must be a non-empty array")
  end

  it "passes validation with valid config" do
    errors = described_class.new(element, {}).validate_config({ "targetVariable" => "emails", "fields" => ["email"] })
    expect(errors).to be_empty
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/model_operations/pluck_fields_generator_spec.rb --format documentation`
Expected: FAIL -- `uninitialized constant`

- [ ] **Step 3: Implement the generator**

```ruby
# app/services/code_generators/element_types/process/model_operations/pluck_fields_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class PluckFieldsGenerator < BaseGenerator
          generator_metadata do
            description "Extracts specific field values from records using pluck with optional distinct"
            category :model_operations
            version "1.0.0"
          end

          input_schema  :bound_entity
          output_schema :target_variable

          def generate
            target = config["targetVariable"] || "values"
            fields = config["fields"] || ["id"]
            uniq = config["uniq"] == true
            query = build_query

            pluck_args = fields.map { |f| ":#{f}" }.join(", ")
            distinct_chain = uniq ? ".distinct" : ""

            <<~RUBY.chomp
              ctx[:#{target}] = #{query}#{distinct_chain}.pluck(#{pluck_args})
              true
            RUBY
          end

          def validate_config(cfg)
            errors = []
            errors << "targetVariable is required" if cfg["targetVariable"].blank?
            fields = cfg["fields"]
            if !fields.is_a?(Array) || fields.empty?
              errors << "fields must be a non-empty array"
            end
            errors
          end

          def example_output
            "ctx[:emails] = EntityEntry.build_for(ctx[:bound_entity]).where(nil).pluck(:email)\ntrue"
          end

          private

          def build_query
            condition_var = config["conditionVariable"]
            if condition_var.present?
              "EntityEntry.build_for(ctx[:bound_entity]).where(ctx[:#{condition_var}])"
            else
              conditions = config["conditions"] || []
              if conditions.any?
                pairs = conditions.map { |c| "#{c['key']}: #{c['value']}" }.join(", ")
                "EntityEntry.build_for(ctx[:bound_entity]).where(#{pairs})"
              else
                "EntityEntry.build_for(ctx[:bound_entity]).where(nil)"
              end
            end
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/model_operations/pluck_fields_generator_spec.rb --format documentation`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add \
  app/services/code_generators/element_types/process/model_operations/pluck_fields_generator.rb \
  spec/services/code_generators/element_types/process/model_operations/pluck_fields_generator_spec.rb
git commit -m "$(cat <<'EOF'
feat: add PluckFields generator

Adds model operation generator that extracts specific field values
from records using pluck with optional distinct and conditions.

Co-Authored-By: Copilot Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: AggregateQuery generator

**Files:**
- Create: `spec/services/code_generators/element_types/process/model_operations/aggregate_query_generator_spec.rb`
- Create: `app/services/code_generators/element_types/process/model_operations/aggregate_query_generator.rb`

- [ ] **Step 1: Write the spec**

```ruby
# spec/services/code_generators/element_types/process/model_operations/aggregate_query_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::AggregateQueryGenerator do
  let(:element) { { "config" => { "targetVariable" => "total", "aggregateFunction" => "sum", "aggregateField" => "amount" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates simple sum" do
    code = described_class.new(element, context).generate
    expect(code).to include("ctx[:total] = EntityEntry.build_for(ctx[:bound_entity]).where(nil).sum(:amount)")
    expect(code).to include("true")
  end

  it "generates average" do
    el = { "config" => { "targetVariable" => "avg_price", "aggregateFunction" => "average", "aggregateField" => "price" } }
    code = described_class.new(el, {}).generate
    expect(code).to include(".average(:price)")
  end

  it "generates minimum" do
    el = { "config" => { "targetVariable" => "min_val", "aggregateFunction" => "minimum", "aggregateField" => "score" } }
    code = described_class.new(el, {}).generate
    expect(code).to include(".minimum(:score)")
  end

  it "generates maximum" do
    el = { "config" => { "targetVariable" => "max_val", "aggregateFunction" => "maximum", "aggregateField" => "score" } }
    code = described_class.new(el, {}).generate
    expect(code).to include(".maximum(:score)")
  end

  it "generates count aggregate" do
    el = { "config" => { "targetVariable" => "num", "aggregateFunction" => "count", "aggregateField" => "id" } }
    code = described_class.new(el, {}).generate
    expect(code).to include(".count(:id)")
  end

  it "generates grouped aggregate" do
    el = { "config" => { "targetVariable" => "totals_by_cat", "aggregateFunction" => "sum", "aggregateField" => "amount", "groupByFields" => ["category"] } }
    code = described_class.new(el, {}).generate
    expect(code).to include(".group(:category).sum(:amount)")
  end

  it "generates grouped aggregate with multiple group fields" do
    el = { "config" => { "targetVariable" => "result", "aggregateFunction" => "sum", "aggregateField" => "amount", "groupByFields" => ["category", "region"] } }
    code = described_class.new(el, {}).generate
    expect(code).to include(".group(:category, :region).sum(:amount)")
  end

  it "generates grouped aggregate with having clause" do
    el = { "config" => { "targetVariable" => "result", "aggregateFunction" => "sum", "aggregateField" => "amount", "groupByFields" => ["category"], "having" => "SUM(amount) > 100" } }
    code = described_class.new(el, {}).generate
    expect(code).to include('.having("SUM(amount) > 100")')
  end

  it "applies static conditions" do
    el = { "config" => { "targetVariable" => "total", "aggregateFunction" => "sum", "aggregateField" => "amount", "conditions" => [{ "key" => "status", "value" => '"active"' }] } }
    code = described_class.new(el, {}).generate
    expect(code).to include('.where(status: "active")')
  end

  it "applies conditionVariable" do
    el = { "config" => { "targetVariable" => "total", "aggregateFunction" => "sum", "aggregateField" => "amount", "conditionVariable" => "filters" } }
    code = described_class.new(el, {}).generate
    expect(code).to include(".where(ctx[:filters])")
  end

  it "validates targetVariable is required" do
    errors = described_class.new({ "config" => {} }, {}).validate_config({})
    expect(errors).to include("targetVariable is required")
  end

  it "validates aggregateFunction is required" do
    errors = described_class.new({ "config" => {} }, {}).validate_config({ "targetVariable" => "x" })
    expect(errors).to include("aggregateFunction is required")
  end

  it "validates aggregateField is required" do
    errors = described_class.new({ "config" => {} }, {}).validate_config({ "targetVariable" => "x", "aggregateFunction" => "sum" })
    expect(errors).to include("aggregateField is required")
  end

  it "validates aggregateFunction must be in allowed list" do
    errors = described_class.new(element, {}).validate_config({ "targetVariable" => "x", "aggregateFunction" => "invalid", "aggregateField" => "amount" })
    expect(errors).to include(/Invalid aggregateFunction/)
  end

  it "passes validation with valid config" do
    errors = described_class.new(element, {}).validate_config({ "targetVariable" => "total", "aggregateFunction" => "sum", "aggregateField" => "amount" })
    expect(errors).to be_empty
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/model_operations/aggregate_query_generator_spec.rb --format documentation`
Expected: FAIL -- `uninitialized constant`

- [ ] **Step 3: Implement the generator**

```ruby
# app/services/code_generators/element_types/process/model_operations/aggregate_query_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class AggregateQueryGenerator < BaseGenerator
          FUNCTIONS = %w[sum average minimum maximum count].freeze

          generator_metadata do
            description "Runs aggregate functions (sum, average, minimum, maximum, count) with optional grouping and having"
            category :model_operations
            version "1.0.0"
          end

          input_schema  :bound_entity
          output_schema :target_variable

          def generate
            target = config["targetVariable"] || "result"
            func = config["aggregateFunction"] || "sum"
            field = config["aggregateField"] || "id"
            group_fields = config["groupByFields"] || []
            having_clause = config["having"]
            query = build_query

            group_chain = if group_fields.any?
                           group_args = group_fields.map { |f| ":#{f}" }.join(", ")
                           ".group(#{group_args})"
                         else
                           ""
                         end

            having_chain = if having_clause.present? && group_fields.any?
                            ".having(#{having_clause.inspect})"
                          else
                            ""
                          end

            <<~RUBY.chomp
              ctx[:#{target}] = #{query}#{group_chain}#{having_chain}.#{func}(:#{field})
              true
            RUBY
          end

          def validate_config(cfg)
            errors = []
            errors << "targetVariable is required" if cfg["targetVariable"].blank?
            errors << "aggregateFunction is required" if cfg["aggregateFunction"].blank?
            errors << "aggregateField is required" if cfg["aggregateField"].blank?
            if cfg["aggregateFunction"].present? && !FUNCTIONS.include?(cfg["aggregateFunction"])
              errors << "Invalid aggregateFunction: #{cfg['aggregateFunction']}. Must be one of: #{FUNCTIONS.join(', ')}"
            end
            errors
          end

          def example_output
            "ctx[:total] = EntityEntry.build_for(ctx[:bound_entity]).where(nil).sum(:amount)\ntrue"
          end

          private

          def build_query
            condition_var = config["conditionVariable"]
            if condition_var.present?
              "EntityEntry.build_for(ctx[:bound_entity]).where(ctx[:#{condition_var}])"
            else
              conditions = config["conditions"] || []
              if conditions.any?
                pairs = conditions.map { |c| "#{c['key']}: #{c['value']}" }.join(", ")
                "EntityEntry.build_for(ctx[:bound_entity]).where(#{pairs})"
              else
                "EntityEntry.build_for(ctx[:bound_entity]).where(nil)"
              end
            end
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/model_operations/aggregate_query_generator_spec.rb --format documentation`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add \
  app/services/code_generators/element_types/process/model_operations/aggregate_query_generator.rb \
  spec/services/code_generators/element_types/process/model_operations/aggregate_query_generator_spec.rb
git commit -m "$(cat <<'EOF'
feat: add AggregateQuery generator

Adds model operation generator that runs aggregate functions
(sum, average, minimum, maximum, count) with optional grouping
and having clauses.

Co-Authored-By: Copilot Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: GroupCollection generator

**Files:**
- Create: `spec/services/code_generators/element_types/process/data_operations/group_collection_generator_spec.rb`
- Create: `app/services/code_generators/element_types/process/data_operations/group_collection_generator.rb`

- [ ] **Step 1: Write the spec**

```ruby
# spec/services/code_generators/element_types/process/data_operations/group_collection_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::GroupCollectionGenerator do
  let(:element) { { "config" => { "sourceVariable" => "orders", "targetVariable" => "grouped", "groupField" => "category" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates group_by with field" do
    code = described_class.new(element, context).generate
    expect(code).to include("ctx[:grouped] = ctx[:orders].group_by { |item| item[:category] }")
    expect(code).to end_with("true")
  end

  it "uses default variable names" do
    el = { "config" => { "groupField" => "status" } }
    code = described_class.new(el, {}).generate
    expect(code).to include("ctx[:grouped] = ctx[:items].group_by { |item| item[:status] }")
  end

  it "validates sourceVariable is required" do
    errors = described_class.new({ "config" => {} }, {}).validate_config({})
    expect(errors).to include("sourceVariable is required")
  end

  it "validates groupField is required" do
    errors = described_class.new({ "config" => {} }, {}).validate_config({ "sourceVariable" => "items" })
    expect(errors).to include("groupField is required")
  end

  it "passes validation with valid config" do
    errors = described_class.new(element, {}).validate_config({ "sourceVariable" => "orders", "groupField" => "category" })
    expect(errors).to be_empty
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/group_collection_generator_spec.rb --format documentation`
Expected: FAIL -- `uninitialized constant`

- [ ] **Step 3: Implement the generator**

```ruby
# app/services/code_generators/element_types/process/data_operations/group_collection_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class GroupCollectionGenerator < BaseGenerator
          generator_metadata do
            description "Groups an array by a field into a hash of arrays using group_by"
            category :data_operations
            version "1.0.0"
          end

          input_schema  :source_variable
          output_schema :target_variable

          def generate
            source = config["sourceVariable"] || "items"
            target = config["targetVariable"] || "grouped"
            field = config["groupField"] || "id"

            "ctx[:#{target}] = ctx[:#{source}].group_by { |item| item[:#{field}] }\ntrue"
          end

          def validate_config(cfg)
            errors = []
            errors << "sourceVariable is required" if cfg["sourceVariable"].blank?
            errors << "groupField is required" if cfg["groupField"].blank?
            errors
          end

          def example_output
            "ctx[:grouped] = ctx[:orders].group_by { |item| item[:category] }\ntrue"
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/group_collection_generator_spec.rb --format documentation`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add \
  app/services/code_generators/element_types/process/data_operations/group_collection_generator.rb \
  spec/services/code_generators/element_types/process/data_operations/group_collection_generator_spec.rb
git commit -m "$(cat <<'EOF'
feat: add GroupCollection generator

Adds data operation generator that groups array items by a field
into a hash of arrays using group_by.

Co-Authored-By: Copilot Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: UniqCollection generator

**Files:**
- Create: `spec/services/code_generators/element_types/process/data_operations/uniq_collection_generator_spec.rb`
- Create: `app/services/code_generators/element_types/process/data_operations/uniq_collection_generator.rb`

- [ ] **Step 1: Write the spec**

```ruby
# spec/services/code_generators/element_types/process/data_operations/uniq_collection_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::UniqCollectionGenerator do
  let(:element) { { "config" => { "sourceVariable" => "items", "targetVariable" => "unique_items" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates uniq without field" do
    code = described_class.new(element, context).generate
    expect(code).to include("ctx[:unique_items] = ctx[:items].uniq")
    expect(code).not_to include("{ |item|")
    expect(code).to end_with("true")
  end

  it "generates uniq with field" do
    el = { "config" => { "sourceVariable" => "users", "targetVariable" => "unique_users", "uniqField" => "email" } }
    code = described_class.new(el, {}).generate
    expect(code).to include("ctx[:unique_users] = ctx[:users].uniq { |item| item[:email] }")
  end

  it "uses default variable names" do
    el = { "config" => {} }
    code = described_class.new(el, {}).generate
    expect(code).to include("ctx[:unique] = ctx[:items].uniq")
  end

  it "validates sourceVariable is required" do
    errors = described_class.new({ "config" => {} }, {}).validate_config({})
    expect(errors).to include("sourceVariable is required")
  end

  it "passes validation with valid config" do
    errors = described_class.new(element, {}).validate_config({ "sourceVariable" => "items" })
    expect(errors).to be_empty
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/uniq_collection_generator_spec.rb --format documentation`
Expected: FAIL -- `uninitialized constant`

- [ ] **Step 3: Implement the generator**

```ruby
# app/services/code_generators/element_types/process/data_operations/uniq_collection_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class UniqCollectionGenerator < BaseGenerator
          generator_metadata do
            description "Deduplicates an array, optionally by a specific field"
            category :data_operations
            version "1.0.0"
          end

          input_schema  :source_variable
          output_schema :target_variable

          def generate
            source = config["sourceVariable"] || "items"
            target = config["targetVariable"] || "unique"
            uniq_field = config["uniqField"]

            if uniq_field.present?
              "ctx[:#{target}] = ctx[:#{source}].uniq { |item| item[:#{uniq_field}] }\ntrue"
            else
              "ctx[:#{target}] = ctx[:#{source}].uniq\ntrue"
            end
          end

          def validate_config(cfg)
            errors = []
            errors << "sourceVariable is required" if cfg["sourceVariable"].blank?
            errors
          end

          def example_output
            "ctx[:unique] = ctx[:items].uniq { |item| item[:email] }\ntrue"
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/uniq_collection_generator_spec.rb --format documentation`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add \
  app/services/code_generators/element_types/process/data_operations/uniq_collection_generator.rb \
  spec/services/code_generators/element_types/process/data_operations/uniq_collection_generator_spec.rb
git commit -m "$(cat <<'EOF'
feat: add UniqCollection generator

Adds data operation generator that deduplicates array items,
optionally by a specific field using uniq with block.

Co-Authored-By: Copilot Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: MergeData generator

**Files:**
- Create: `spec/services/code_generators/element_types/process/data_operations/merge_data_generator_spec.rb`
- Create: `app/services/code_generators/element_types/process/data_operations/merge_data_generator.rb`

- [ ] **Step 1: Write the spec**

```ruby
# spec/services/code_generators/element_types/process/data_operations/merge_data_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::MergeDataGenerator do
  let(:element) { { "config" => { "sourceVariable" => "base", "mergeVariable" => "overrides", "targetVariable" => "merged" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates shallow merge with overwrite by default" do
    code = described_class.new(element, context).generate
    expect(code).to include("ctx[:merged] = ctx[:base].merge(ctx[:overrides])")
    expect(code).to end_with("true")
  end

  it "generates deep merge with overwrite" do
    el = { "config" => { "sourceVariable" => "base", "mergeVariable" => "extra", "targetVariable" => "result", "strategy" => "deep" } }
    code = described_class.new(el, {}).generate
    expect(code).to include("ctx[:result] = ctx[:base].deep_merge(ctx[:extra])")
  end

  it "generates shallow merge with keep_original" do
    el = { "config" => { "sourceVariable" => "base", "mergeVariable" => "extra", "targetVariable" => "result", "conflictResolution" => "keep_original" } }
    code = described_class.new(el, {}).generate
    expect(code).to include("ctx[:result] = ctx[:extra].merge(ctx[:base])")
  end

  it "generates deep merge with keep_original" do
    el = { "config" => { "sourceVariable" => "base", "mergeVariable" => "extra", "targetVariable" => "result", "strategy" => "deep", "conflictResolution" => "keep_original" } }
    code = described_class.new(el, {}).generate
    expect(code).to include("ctx[:result] = ctx[:extra].deep_merge(ctx[:base])")
  end

  it "validates sourceVariable is required" do
    errors = described_class.new({ "config" => {} }, {}).validate_config({})
    expect(errors).to include("sourceVariable is required")
  end

  it "validates mergeVariable is required" do
    errors = described_class.new({ "config" => {} }, {}).validate_config({ "sourceVariable" => "a" })
    expect(errors).to include("mergeVariable is required")
  end

  it "passes validation with valid config" do
    errors = described_class.new(element, {}).validate_config({ "sourceVariable" => "base", "mergeVariable" => "overrides" })
    expect(errors).to be_empty
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/merge_data_generator_spec.rb --format documentation`
Expected: FAIL -- `uninitialized constant`

- [ ] **Step 3: Implement the generator**

```ruby
# app/services/code_generators/element_types/process/data_operations/merge_data_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class MergeDataGenerator < BaseGenerator
          generator_metadata do
            description "Merges two hashes with configurable strategy (shallow/deep) and conflict resolution (overwrite/keep_original)"
            category :data_operations
            version "1.0.0"
          end

          input_schema  :source_variable, :merge_variable
          output_schema :target_variable

          def generate
            source = config["sourceVariable"] || "base"
            merge_var = config["mergeVariable"] || "overrides"
            target = config["targetVariable"] || "merged"
            strategy = config["strategy"] || "shallow"
            conflict = config["conflictResolution"] || "overwrite"

            merge_method = strategy == "deep" ? "deep_merge" : "merge"

            expr = if conflict == "keep_original"
                     "ctx[:#{merge_var}].#{merge_method}(ctx[:#{source}])"
                   else
                     "ctx[:#{source}].#{merge_method}(ctx[:#{merge_var}])"
                   end

            "ctx[:#{target}] = #{expr}\ntrue"
          end

          def validate_config(cfg)
            errors = []
            errors << "sourceVariable is required" if cfg["sourceVariable"].blank?
            errors << "mergeVariable is required" if cfg["mergeVariable"].blank?
            errors
          end

          def example_output
            "ctx[:merged] = ctx[:base].merge(ctx[:overrides])\ntrue"
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/merge_data_generator_spec.rb --format documentation`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add \
  app/services/code_generators/element_types/process/data_operations/merge_data_generator.rb \
  spec/services/code_generators/element_types/process/data_operations/merge_data_generator_spec.rb
git commit -m "$(cat <<'EOF'
feat: add MergeData generator

Adds data operation generator that merges two hashes with configurable
shallow/deep strategy and overwrite/keep_original conflict resolution.

Co-Authored-By: Copilot Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: SerializeData generator

**Files:**
- Create: `spec/services/code_generators/element_types/process/data_operations/serialize_data_generator_spec.rb`
- Create: `app/services/code_generators/element_types/process/data_operations/serialize_data_generator.rb`

- [ ] **Step 1: Write the spec**

```ruby
# spec/services/code_generators/element_types/process/data_operations/serialize_data_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::SerializeDataGenerator do
  let(:element) { { "config" => { "sourceVariable" => "data", "targetVariable" => "output", "format" => "json" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates JSON serialization" do
    code = described_class.new(element, context).generate
    expect(code).to include("ctx[:output] = ctx[:data].to_json")
    expect(code).to end_with("true")
  end

  it "generates pretty JSON serialization" do
    el = { "config" => { "sourceVariable" => "data", "targetVariable" => "output", "format" => "json", "pretty" => true } }
    code = described_class.new(el, {}).generate
    expect(code).to include("ctx[:output] = JSON.pretty_generate(ctx[:data])")
  end

  it "generates YAML serialization" do
    el = { "config" => { "sourceVariable" => "data", "targetVariable" => "output", "format" => "yaml" } }
    code = described_class.new(el, {}).generate
    expect(code).to include("ctx[:output] = ctx[:data].to_yaml")
  end

  it "generates XML serialization" do
    el = { "config" => { "sourceVariable" => "data", "targetVariable" => "output", "format" => "xml" } }
    code = described_class.new(el, {}).generate
    expect(code).to include('ctx[:output] = ctx[:data].to_xml(root: "data")')
  end

  it "generates XML serialization with custom root" do
    el = { "config" => { "sourceVariable" => "data", "targetVariable" => "output", "format" => "xml", "rootElement" => "orders" } }
    code = described_class.new(el, {}).generate
    expect(code).to include('ctx[:output] = ctx[:data].to_xml(root: "orders")')
  end

  it "generates CSV serialization with columns" do
    el = { "config" => { "sourceVariable" => "rows", "targetVariable" => "csv_text", "format" => "csv", "csvColumns" => ["name", "email"] } }
    code = described_class.new(el, {}).generate
    expect(code).to include("CSV.generate")
    expect(code).to include("name")
    expect(code).to include("email")
  end

  it "generates CSV serialization without explicit columns" do
    el = { "config" => { "sourceVariable" => "rows", "targetVariable" => "csv_text", "format" => "csv" } }
    code = described_class.new(el, {}).generate
    expect(code).to include("CSV.generate")
    expect(code).to include("ctx[:rows]")
  end

  it "validates sourceVariable is required" do
    errors = described_class.new({ "config" => {} }, {}).validate_config({})
    expect(errors).to include("sourceVariable is required")
  end

  it "validates format must be in allowed list" do
    errors = described_class.new(element, {}).validate_config({ "sourceVariable" => "data", "format" => "binary" })
    expect(errors).to include(/Invalid format/)
  end

  it "passes validation with valid config" do
    errors = described_class.new(element, {}).validate_config({ "sourceVariable" => "data", "format" => "json" })
    expect(errors).to be_empty
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/serialize_data_generator_spec.rb --format documentation`
Expected: FAIL -- `uninitialized constant`

- [ ] **Step 3: Implement the generator**

```ruby
# app/services/code_generators/element_types/process/data_operations/serialize_data_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class SerializeDataGenerator < BaseGenerator
          FORMATS = %w[json xml yaml csv].freeze

          generator_metadata do
            description "Serializes data to JSON, XML, YAML, or CSV format"
            category :data_operations
            version "1.0.0"
          end

          input_schema  :source_variable
          output_schema :target_variable

          def generate
            source = config["sourceVariable"] || "data"
            target = config["targetVariable"] || "serialized"
            format = config["format"] || "json"
            pretty = config["pretty"] == true

            serialize_expr = case format
                             when "json"
                               build_json_expr(source, pretty)
                             when "yaml"
                               "ctx[:#{source}].to_yaml"
                             when "xml"
                               build_xml_expr(source)
                             when "csv"
                               return build_csv_code(source, target)
                             else
                               "ctx[:#{source}].to_json"
                             end

            "ctx[:#{target}] = #{serialize_expr}\ntrue"
          end

          def validate_config(cfg)
            errors = []
            errors << "sourceVariable is required" if cfg["sourceVariable"].blank?
            if cfg["format"].present? && !FORMATS.include?(cfg["format"])
              errors << "Invalid format: #{cfg['format']}. Must be one of: #{FORMATS.join(', ')}"
            end
            errors
          end

          def example_output
            "ctx[:serialized] = ctx[:data].to_json\ntrue"
          end

          private

          def build_json_expr(source, pretty)
            if pretty
              "JSON.pretty_generate(ctx[:#{source}])"
            else
              "ctx[:#{source}].to_json"
            end
          end

          def build_xml_expr(source)
            root = config["rootElement"] || "data"
            "ctx[:#{source}].to_xml(root: #{root.inspect})"
          end

          def build_csv_code(source, target)
            columns = config["csvColumns"] || []
            if columns.any?
              cols_sym = columns.map { |c| ":#{c}" }.join(", ")
              cols_str = columns.map(&:inspect).join(", ")
              <<~RUBY.chomp
                ctx[:#{target}] = CSV.generate do |csv|
                  csv << [#{cols_str}]
                  ctx[:#{source}].each { |row| csv << row.values_at(#{cols_sym}) }
                end
                true
              RUBY
            else
              <<~RUBY.chomp
                ctx[:#{target}] = CSV.generate do |csv|
                  ctx[:#{source}].each { |row| csv << (row.is_a?(Hash) ? row.values : row) }
                end
                true
              RUBY
            end
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/serialize_data_generator_spec.rb --format documentation`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add \
  app/services/code_generators/element_types/process/data_operations/serialize_data_generator.rb \
  spec/services/code_generators/element_types/process/data_operations/serialize_data_generator_spec.rb
git commit -m "$(cat <<'EOF'
feat: add SerializeData generator

Adds data operation generator that serializes data to JSON, XML,
YAML, or CSV format with options for pretty printing, custom root
elements, and CSV column selection.

Co-Authored-By: Copilot Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: DateTimeCalc generator

**Files:**
- Create: `spec/services/code_generators/element_types/process/data_operations/date_time_calc_generator_spec.rb`
- Create: `app/services/code_generators/element_types/process/data_operations/date_time_calc_generator.rb`

- [ ] **Step 1: Write the spec**

```ruby
# spec/services/code_generators/element_types/process/data_operations/date_time_calc_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::DateTimeCalcGenerator do
  let(:element) { { "config" => { "operation" => "now", "targetVariable" => "current_time" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates now operation" do
    code = described_class.new(element, context).generate
    expect(code).to include("ctx[:current_time] = Time.current")
    expect(code).to end_with("true")
  end

  it "generates now with timezone" do
    el = { "config" => { "operation" => "now", "targetVariable" => "tokyo_time", "timezone" => "Asia/Tokyo" } }
    code = described_class.new(el, {}).generate
    expect(code).to include('Time.current.in_time_zone("Asia/Tokyo")')
  end

  it "generates add operation" do
    el = { "config" => { "operation" => "add", "sourceVariable" => "start_date", "targetVariable" => "end_date", "amount" => 30, "unit" => "days" } }
    code = described_class.new(el, {}).generate
    expect(code).to include("ctx[:end_date] = ctx[:start_date] + 30.days")
  end

  it "generates subtract operation" do
    el = { "config" => { "operation" => "subtract", "sourceVariable" => "deadline", "targetVariable" => "reminder", "amount" => 2, "unit" => "weeks" } }
    code = described_class.new(el, {}).generate
    expect(code).to include("ctx[:reminder] = ctx[:deadline] - 2.weeks")
  end

  it "generates difference operation" do
    el = { "config" => { "operation" => "difference", "sourceVariable" => "start_date", "endVariable" => "end_date", "targetVariable" => "days_between" } }
    code = described_class.new(el, {}).generate
    expect(code).to include("ctx[:days_between] = (ctx[:end_date].to_date - ctx[:start_date].to_date).to_i")
  end

  it "generates format operation" do
    el = { "config" => { "operation" => "format", "sourceVariable" => "timestamp", "targetVariable" => "formatted", "formatString" => "%Y-%m-%d %H:%M" } }
    code = described_class.new(el, {}).generate
    expect(code).to include('ctx[:formatted] = ctx[:timestamp].strftime("%Y-%m-%d %H:%M")')
  end

  it "generates parse operation" do
    el = { "config" => { "operation" => "parse", "sourceVariable" => "date_string", "targetVariable" => "parsed" } }
    code = described_class.new(el, {}).generate
    expect(code).to include("ctx[:parsed] = Time.zone.parse(ctx[:date_string])")
  end

  it "generates parse with timezone" do
    el = { "config" => { "operation" => "parse", "sourceVariable" => "date_string", "targetVariable" => "parsed", "timezone" => "US/Eastern" } }
    code = described_class.new(el, {}).generate
    expect(code).to include('.in_time_zone("US/Eastern")')
  end

  it "generates add with timezone" do
    el = { "config" => { "operation" => "add", "sourceVariable" => "start", "targetVariable" => "result", "amount" => 1, "unit" => "hours", "timezone" => "UTC" } }
    code = described_class.new(el, {}).generate
    expect(code).to include("ctx[:start] + 1.hours")
    expect(code).to include('.in_time_zone("UTC")')
  end

  it "validates targetVariable is required" do
    errors = described_class.new({ "config" => {} }, {}).validate_config({})
    expect(errors).to include("targetVariable is required")
  end

  it "validates operation must be in allowed list" do
    errors = described_class.new(element, {}).validate_config({ "targetVariable" => "x", "operation" => "invalid" })
    expect(errors).to include(/Invalid operation/)
  end

  it "validates add requires amount and unit" do
    errors = described_class.new(element, {}).validate_config({ "targetVariable" => "x", "operation" => "add" })
    expect(errors).to include("amount is required for add/subtract operations")
    expect(errors).to include("unit is required for add/subtract operations")
  end

  it "validates subtract requires amount and unit" do
    errors = described_class.new(element, {}).validate_config({ "targetVariable" => "x", "operation" => "subtract" })
    expect(errors).to include("amount is required for add/subtract operations")
    expect(errors).to include("unit is required for add/subtract operations")
  end

  it "validates format requires formatString" do
    errors = described_class.new(element, {}).validate_config({ "targetVariable" => "x", "operation" => "format", "sourceVariable" => "t" })
    expect(errors).to include("formatString is required for format operation")
  end

  it "validates parse requires sourceVariable" do
    errors = described_class.new(element, {}).validate_config({ "targetVariable" => "x", "operation" => "parse" })
    expect(errors).to include("sourceVariable is required for parse operation")
  end

  it "validates difference requires sourceVariable and endVariable" do
    errors = described_class.new(element, {}).validate_config({ "targetVariable" => "x", "operation" => "difference" })
    expect(errors).to include("sourceVariable is required for difference operation")
    expect(errors).to include("endVariable is required for difference operation")
  end

  it "validates unit must be in allowed list" do
    errors = described_class.new(element, {}).validate_config({ "targetVariable" => "x", "operation" => "add", "amount" => 1, "unit" => "fortnights" })
    expect(errors).to include(/Invalid unit/)
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/date_time_calc_generator_spec.rb --format documentation`
Expected: FAIL -- `uninitialized constant`

- [ ] **Step 3: Implement the generator**

```ruby
# app/services/code_generators/element_types/process/data_operations/date_time_calc_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class DateTimeCalcGenerator < BaseGenerator
          OPERATIONS = %w[add subtract difference format parse now].freeze
          UNITS = %w[seconds minutes hours days weeks months years].freeze

          generator_metadata do
            description "Performs date/time calculations: add, subtract, difference, format, parse, now"
            category :data_operations
            version "1.0.0"
          end

          input_schema  :source_variable
          output_schema :target_variable

          def generate
            operation = config["operation"] || "now"
            target = config["targetVariable"] || "result"
            timezone = config["timezone"]

            expr = case operation
                   when "now"       then build_now_expr
                   when "add"       then build_add_expr
                   when "subtract"  then build_subtract_expr
                   when "difference" then build_difference_expr
                   when "format"    then build_format_expr
                   when "parse"     then build_parse_expr
                   else "Time.current"
                   end

            expr = apply_timezone(expr, timezone) unless %w[difference format].include?(operation)

            "ctx[:#{target}] = #{expr}\ntrue"
          end

          def validate_config(cfg)
            errors = []
            errors << "targetVariable is required" if cfg["targetVariable"].blank?
            operation = cfg["operation"]

            if operation.present? && !OPERATIONS.include?(operation)
              errors << "Invalid operation: #{operation}. Must be one of: #{OPERATIONS.join(', ')}"
            end

            if %w[add subtract].include?(operation)
              errors << "amount is required for add/subtract operations" if cfg["amount"].blank?
              if cfg["unit"].blank?
                errors << "unit is required for add/subtract operations"
              elsif !UNITS.include?(cfg["unit"])
                errors << "Invalid unit: #{cfg['unit']}. Must be one of: #{UNITS.join(', ')}"
              end
            end

            if operation == "format"
              errors << "sourceVariable is required for format operation" if cfg["sourceVariable"].blank?
              errors << "formatString is required for format operation" if cfg["formatString"].blank?
            end

            if operation == "parse"
              errors << "sourceVariable is required for parse operation" if cfg["sourceVariable"].blank?
            end

            if operation == "difference"
              errors << "sourceVariable is required for difference operation" if cfg["sourceVariable"].blank?
              errors << "endVariable is required for difference operation" if cfg["endVariable"].blank?
            end

            errors
          end

          def example_output
            "ctx[:current_time] = Time.current\ntrue"
          end

          private

          def build_now_expr
            "Time.current"
          end

          def build_add_expr
            source = config["sourceVariable"] || "time"
            amount = config["amount"].to_i
            unit = config["unit"] || "days"
            "ctx[:#{source}] + #{amount}.#{unit}"
          end

          def build_subtract_expr
            source = config["sourceVariable"] || "time"
            amount = config["amount"].to_i
            unit = config["unit"] || "days"
            "ctx[:#{source}] - #{amount}.#{unit}"
          end

          def build_difference_expr
            source = config["sourceVariable"] || "start_date"
            end_var = config["endVariable"] || "end_date"
            "(ctx[:#{end_var}].to_date - ctx[:#{source}].to_date).to_i"
          end

          def build_format_expr
            source = config["sourceVariable"] || "time"
            format_str = config["formatString"] || "%Y-%m-%d"
            "ctx[:#{source}].strftime(#{format_str.inspect})"
          end

          def build_parse_expr
            source = config["sourceVariable"] || "date_string"
            "Time.zone.parse(ctx[:#{source}])"
          end

          def apply_timezone(expr, timezone)
            return expr if timezone.blank?
            "#{expr}.in_time_zone(#{timezone.inspect})"
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/date_time_calc_generator_spec.rb --format documentation`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add \
  app/services/code_generators/element_types/process/data_operations/date_time_calc_generator.rb \
  spec/services/code_generators/element_types/process/data_operations/date_time_calc_generator_spec.rb
git commit -m "$(cat <<'EOF'
feat: add DateTimeCalc generator

Adds data operation generator for date/time calculations including
add, subtract, difference, format, parse, and now operations with
optional timezone support.

Co-Authored-By: Copilot Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: RegexExtract generator

**Files:**
- Create: `spec/services/code_generators/element_types/process/data_operations/regex_extract_generator_spec.rb`
- Create: `app/services/code_generators/element_types/process/data_operations/regex_extract_generator.rb`

- [ ] **Step 1: Write the spec**

```ruby
# spec/services/code_generators/element_types/process/data_operations/regex_extract_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::RegexExtractGenerator do
  let(:element) { { "config" => { "sourceVariable" => "text", "targetVariable" => "matches", "pattern" => '(\d+)-(\d+)', "operation" => "match" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates match without capture group" do
    code = described_class.new(element, context).generate
    expect(code).to include('_match = ctx[:text].match(/(\d+)-(\d+)/)')
    expect(code).to include("ctx[:matches] = _match ? _match.captures : []")
    expect(code).to end_with("true")
  end

  it "generates match with capture group" do
    el = { "config" => { "sourceVariable" => "text", "targetVariable" => "first_num", "pattern" => '(\d+)-(\d+)', "operation" => "match", "captureGroup" => 1 } }
    code = described_class.new(el, {}).generate
    expect(code).to include('_match = ctx[:text].match(/(\d+)-(\d+)/)')
    expect(code).to include("ctx[:first_num] = _match ? _match[1] : nil")
  end

  it "generates scan operation" do
    el = { "config" => { "sourceVariable" => "html", "targetVariable" => "urls", "pattern" => 'href="([^"]+)"', "operation" => "scan" } }
    code = described_class.new(el, {}).generate
    expect(code).to include('ctx[:urls] = ctx[:html].scan(/href="([^"]+)"/)')
  end

  it "generates test operation" do
    el = { "config" => { "sourceVariable" => "email", "targetVariable" => "valid", "pattern" => '@.+\\.', "operation" => "test" } }
    code = described_class.new(el, {}).generate
    expect(code).to include("ctx[:valid] = ctx[:email].match?")
  end

  it "generates replace operation" do
    el = { "config" => { "sourceVariable" => "text", "targetVariable" => "cleaned", "pattern" => '\\s+', "operation" => "replace", "replacement" => " " } }
    code = described_class.new(el, {}).generate
    expect(code).to include("ctx[:cleaned] = ctx[:text].gsub")
    expect(code).to include('" "')
  end

  it "validates sourceVariable is required" do
    errors = described_class.new({ "config" => {} }, {}).validate_config({})
    expect(errors).to include("sourceVariable is required")
  end

  it "validates pattern is required" do
    errors = described_class.new({ "config" => {} }, {}).validate_config({ "sourceVariable" => "text" })
    expect(errors).to include("pattern is required")
  end

  it "validates operation must be in allowed list" do
    errors = described_class.new(element, {}).validate_config({ "sourceVariable" => "text", "pattern" => "x", "operation" => "split" })
    expect(errors).to include(/Invalid operation/)
  end

  it "validates replace requires replacement" do
    errors = described_class.new(element, {}).validate_config({ "sourceVariable" => "text", "pattern" => "x", "operation" => "replace" })
    expect(errors).to include("replacement is required for replace operation")
  end

  it "passes validation with valid config" do
    errors = described_class.new(element, {}).validate_config({ "sourceVariable" => "text", "pattern" => "\\d+" })
    expect(errors).to be_empty
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/regex_extract_generator_spec.rb --format documentation`
Expected: FAIL -- `uninitialized constant`

- [ ] **Step 3: Implement the generator**

```ruby
# app/services/code_generators/element_types/process/data_operations/regex_extract_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class RegexExtractGenerator < BaseGenerator
          OPERATIONS = %w[match scan test replace].freeze

          generator_metadata do
            description "Extracts, tests, or replaces text using regular expressions"
            category :data_operations
            version "1.0.0"
          end

          input_schema  :source_variable
          output_schema :target_variable

          def generate
            source = config["sourceVariable"] || "text"
            target = config["targetVariable"] || "result"
            pattern = config["pattern"] || ".*"
            operation = config["operation"] || "match"

            case operation
            when "match"  then build_match_code(source, target, pattern)
            when "scan"   then build_scan_code(source, target, pattern)
            when "test"   then build_test_code(source, target, pattern)
            when "replace" then build_replace_code(source, target, pattern)
            else build_match_code(source, target, pattern)
            end
          end

          def validate_config(cfg)
            errors = []
            errors << "sourceVariable is required" if cfg["sourceVariable"].blank?
            errors << "pattern is required" if cfg["pattern"].blank?
            if cfg["operation"].present? && !OPERATIONS.include?(cfg["operation"])
              errors << "Invalid operation: #{cfg['operation']}. Must be one of: #{OPERATIONS.join(', ')}"
            end
            if cfg["operation"] == "replace" && cfg["replacement"].blank?
              errors << "replacement is required for replace operation"
            end
            errors
          end

          def example_output
            "_match = ctx[:text].match(/(\\d+)/)\nctx[:result] = _match ? _match.captures : []\ntrue"
          end

          private

          def build_match_code(source, target, pattern)
            capture_group = config["captureGroup"]
            if capture_group.present?
              "_match = ctx[:#{source}].match(/#{pattern}/)\nctx[:#{target}] = _match ? _match[#{capture_group.to_i}] : nil\ntrue"
            else
              "_match = ctx[:#{source}].match(/#{pattern}/)\nctx[:#{target}] = _match ? _match.captures : []\ntrue"
            end
          end

          def build_scan_code(source, target, pattern)
            "ctx[:#{target}] = ctx[:#{source}].scan(/#{pattern}/)\ntrue"
          end

          def build_test_code(source, target, pattern)
            "ctx[:#{target}] = ctx[:#{source}].match?(/#{pattern}/)\ntrue"
          end

          def build_replace_code(source, target, pattern)
            replacement = config["replacement"] || ""
            "ctx[:#{target}] = ctx[:#{source}].gsub(/#{pattern}/, #{replacement.inspect})\ntrue"
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/regex_extract_generator_spec.rb --format documentation`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add \
  app/services/code_generators/element_types/process/data_operations/regex_extract_generator.rb \
  spec/services/code_generators/element_types/process/data_operations/regex_extract_generator_spec.rb
git commit -m "$(cat <<'EOF'
feat: add RegexExtract generator

Adds data operation generator that performs regex match, scan, test,
and replace operations on string data from ctx variables.

Co-Authored-By: Copilot Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: Final verification

- [ ] **Step 1: Run all new model operations generator specs**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/model_operations/check_existence_generator_spec.rb spec/services/code_generators/element_types/process/model_operations/count_records_generator_spec.rb spec/services/code_generators/element_types/process/model_operations/pluck_fields_generator_spec.rb spec/services/code_generators/element_types/process/model_operations/aggregate_query_generator_spec.rb --format documentation`
Expected: All pass

- [ ] **Step 2: Run all new data operations generator specs**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/group_collection_generator_spec.rb spec/services/code_generators/element_types/process/data_operations/uniq_collection_generator_spec.rb spec/services/code_generators/element_types/process/data_operations/merge_data_generator_spec.rb spec/services/code_generators/element_types/process/data_operations/serialize_data_generator_spec.rb spec/services/code_generators/element_types/process/data_operations/date_time_calc_generator_spec.rb spec/services/code_generators/element_types/process/data_operations/regex_extract_generator_spec.rb --format documentation`
Expected: All pass

- [ ] **Step 3: Run the full model_operations and data_operations test suites to check for regressions**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/model_operations/ spec/services/code_generators/element_types/process/data_operations/ --format documentation`
Expected: All pass (existing + 10 new spec files), no regressions

- [ ] **Step 4: Verify generators are auto-discovered by registry**

Run: `bundle exec rails runner "names = CodeGenerators::GeneratorRegistry.instance.step_action_generators.keys.sort; puts names.join(', '); puts; puts 'Total: ' + names.count.to_s"`
Expected: Output includes `check_existence`, `count_records`, `pluck_fields`, `aggregate_query`, `group_collection`, `uniq_collection`, `merge_data`, `serialize_data`, `date_time_calc`, `regex_extract` among the existing generator names

- [ ] **Step 5: Run the full test suite**

Run: `bundle exec rspec`
Expected: All pass, no regressions from any existing functionality
