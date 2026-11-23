# Data Operations Generators Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 6 new data operations step action generators: FilterCollection, SortCollection, MapCollection, FormatString, ParseData, MapValue.

**Architecture:** Each generator follows the existing `BaseGenerator` pattern — a Ruby class under `CodeGenerators::ElementTypes::Process::DataOperations` with `generator_metadata`, `input_schema`/`output_schema`, `generate`, `validate_config`, `example_output` methods. All operate on configurable ctx variables via config hash.

**Tech Stack:** Ruby 3.2, Rails 8.1, RSpec, CodeGenerators::BaseGenerator

---

## File Structure

| File | Purpose |
|------|---------|
| `app/services/code_generators/element_types/process/data_operations/filter_collection_generator.rb` | Filter array by condition |
| `app/services/code_generators/element_types/process/data_operations/sort_collection_generator.rb` | Sort array by field |
| `app/services/code_generators/element_types/process/data_operations/map_collection_generator.rb` | Transform each item in array |
| `app/services/code_generators/element_types/process/data_operations/format_string_generator.rb` | Template string interpolation |
| `app/services/code_generators/element_types/process/data_operations/parse_data_generator.rb` | Parse JSON/CSV strings |
| `app/services/code_generators/element_types/process/data_operations/map_value_generator.rb` | Lookup table value mapping |
| `spec/services/code_generators/element_types/process/data_operations/filter_collection_generator_spec.rb` | FilterCollection tests |
| `spec/services/code_generators/element_types/process/data_operations/sort_collection_generator_spec.rb` | SortCollection tests |
| `spec/services/code_generators/element_types/process/data_operations/map_collection_generator_spec.rb` | MapCollection tests |
| `spec/services/code_generators/element_types/process/data_operations/format_string_generator_spec.rb` | FormatString tests |
| `spec/services/code_generators/element_types/process/data_operations/parse_data_generator_spec.rb` | ParseData tests |
| `spec/services/code_generators/element_types/process/data_operations/map_value_generator_spec.rb` | MapValue tests |

---

### Task 1: FilterCollection generator

**Files:**
- Create: `spec/services/code_generators/element_types/process/data_operations/filter_collection_generator_spec.rb`
- Create: `app/services/code_generators/element_types/process/data_operations/filter_collection_generator.rb`

- [ ] **Step 1: Write the spec**

```ruby
# spec/services/code_generators/element_types/process/data_operations/filter_collection_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::FilterCollectionGenerator do
  let(:element) { { "config" => { "sourceVariable" => "items", "targetVariable" => "filtered", "filterField" => "status", "filterOperator" => "eq", "filterValue" => "active" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates eq filter" do
    code = described_class.new(element, context).generate
    expect(code).to include('ctx[:filtered]')
    expect(code).to include('ctx[:items]')
    expect(code).to include('item[:status] == "active"')
  end

  it "generates ne filter" do
    el = { "config" => { "sourceVariable" => "items", "targetVariable" => "filtered", "filterField" => "status", "filterOperator" => "ne", "filterValue" => "deleted" } }
    code = described_class.new(el, {}).generate
    expect(code).to include('item[:status] != "deleted"')
  end

  it "generates gt filter" do
    el = { "config" => { "sourceVariable" => "items", "targetVariable" => "filtered", "filterField" => "price", "filterOperator" => "gt", "filterValue" => "100" } }
    code = described_class.new(el, {}).generate
    expect(code).to include("item[:price] > 100")
  end

  it "generates includes filter" do
    el = { "config" => { "sourceVariable" => "items", "targetVariable" => "filtered", "filterField" => "name", "filterOperator" => "includes", "filterValue" => "test" } }
    code = described_class.new(el, {}).generate
    expect(code).to include('item[:name].to_s.include?("test")')
  end

  it "generates present filter" do
    el = { "config" => { "sourceVariable" => "items", "targetVariable" => "filtered", "filterField" => "email", "filterOperator" => "present" } }
    code = described_class.new(el, {}).generate
    expect(code).to include("item[:email].present?")
  end

  it "generates blank filter" do
    el = { "config" => { "sourceVariable" => "items", "targetVariable" => "filtered", "filterField" => "email", "filterOperator" => "blank" } }
    code = described_class.new(el, {}).generate
    expect(code).to include("item[:email].blank?")
  end

  it "validates required fields" do
    errors = described_class.new({ "config" => {} }, {}).validate_config({})
    expect(errors).to include("sourceVariable is required")
    expect(errors).to include("filterField is required")
  end

  it "validates operator" do
    errors = described_class.new(element, {}).validate_config({ "filterOperator" => "invalid" })
    expect(errors).to include(/Invalid filter operator/)
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/filter_collection_generator_spec.rb`
Expected: FAIL — `uninitialized constant`

- [ ] **Step 3: Implement the generator**

```ruby
# app/services/code_generators/element_types/process/data_operations/filter_collection_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class FilterCollectionGenerator < BaseGenerator
          OPERATORS = %w[eq ne gt lt gte lte includes blank present].freeze

          generator_metadata do
            description "Filters an array by field condition (eq, ne, gt, lt, includes, blank, present)"
            category :data_operations
            version "1.0.0"
          end

          input_schema  :source_variable
          output_schema :target_variable

          def generate
            source = config["sourceVariable"] || "items"
            target = config["targetVariable"] || "filtered"
            field = config["filterField"] || "id"
            operator = config["filterOperator"] || "eq"
            value = config["filterValue"]

            condition = build_condition(field, operator, value)
            "ctx[:#{target}] = ctx[:#{source}].select { |item| #{condition} }\ntrue"
          end

          def validate_config(cfg)
            errors = []
            errors << "sourceVariable is required" if cfg["sourceVariable"].blank?
            errors << "filterField is required" if cfg["filterField"].blank?
            if cfg["filterOperator"].present? && !OPERATORS.include?(cfg["filterOperator"])
              errors << "Invalid filter operator: #{cfg['filterOperator']}. Must be one of: #{OPERATORS.join(', ')}"
            end
            errors
          end

          def example_output
            "ctx[:filtered] = ctx[:items].select { |item| item[:status] == \"active\" }\ntrue"
          end

          private

          def build_condition(field, operator, value)
            case operator
            when "eq"       then "item[:#{field}] == #{value_literal(value)}"
            when "ne"       then "item[:#{field}] != #{value_literal(value)}"
            when "gt"       then "item[:#{field}] > #{numeric_value(value)}"
            when "lt"       then "item[:#{field}] < #{numeric_value(value)}"
            when "gte"      then "item[:#{field}] >= #{numeric_value(value)}"
            when "lte"      then "item[:#{field}] <= #{numeric_value(value)}"
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

          def numeric_value(value)
            value.to_s.include?(".") ? value.to_f.to_s : value.to_i.to_s
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/filter_collection_generator_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/data_operations/filter_collection_generator.rb spec/services/code_generators/element_types/process/data_operations/filter_collection_generator_spec.rb
git commit -m "feat: add FilterCollection generator"
```

---

### Task 2: SortCollection generator

**Files:**
- Create: `spec/services/code_generators/element_types/process/data_operations/sort_collection_generator_spec.rb`
- Create: `app/services/code_generators/element_types/process/data_operations/sort_collection_generator.rb`

- [ ] **Step 1: Write the spec**

```ruby
# spec/services/code_generators/element_types/process/data_operations/sort_collection_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::SortCollectionGenerator do
  let(:element) { { "config" => { "sourceVariable" => "items", "targetVariable" => "sorted", "sortField" => "name" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates ascending sort by default" do
    code = described_class.new(element, context).generate
    expect(code).to include("ctx[:sorted] = ctx[:items].sort_by")
    expect(code).to include("item[:name]")
    expect(code).not_to include(".reverse")
  end

  it "generates descending sort" do
    el = { "config" => { "sourceVariable" => "items", "targetVariable" => "sorted", "sortField" => "price", "sortDirection" => "desc" } }
    code = described_class.new(el, {}).generate
    expect(code).to include("item[:price]")
    expect(code).to include(".reverse")
  end

  it "validates required fields" do
    errors = described_class.new({ "config" => {} }, {}).validate_config({})
    expect(errors).to include("sourceVariable is required")
    expect(errors).to include("sortField is required")
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/sort_collection_generator_spec.rb`
Expected: FAIL

- [ ] **Step 3: Implement the generator**

```ruby
# app/services/code_generators/element_types/process/data_operations/sort_collection_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class SortCollectionGenerator < BaseGenerator
          generator_metadata do
            description "Sorts an array by a field with ascending or descending direction"
            category :data_operations
            version "1.0.0"
          end

          input_schema  :source_variable
          output_schema :target_variable

          def generate
            source = config["sourceVariable"] || "items"
            target = config["targetVariable"] || "sorted"
            field = config["sortField"] || "id"
            direction = config["sortDirection"] || "asc"

            sort_expr = "ctx[:#{source}].sort_by { |item| item[:#{field}] }"
            sort_expr += ".reverse" if direction == "desc"
            "ctx[:#{target}] = #{sort_expr}\ntrue"
          end

          def validate_config(cfg)
            errors = []
            errors << "sourceVariable is required" if cfg["sourceVariable"].blank?
            errors << "sortField is required" if cfg["sortField"].blank?
            errors
          end

          def example_output
            "ctx[:sorted] = ctx[:items].sort_by { |item| item[:name] }\ntrue"
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/sort_collection_generator_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/data_operations/sort_collection_generator.rb spec/services/code_generators/element_types/process/data_operations/sort_collection_generator_spec.rb
git commit -m "feat: add SortCollection generator"
```

---

### Task 3: MapCollection generator

**Files:**
- Create: `spec/services/code_generators/element_types/process/data_operations/map_collection_generator_spec.rb`
- Create: `app/services/code_generators/element_types/process/data_operations/map_collection_generator.rb`

- [ ] **Step 1: Write the spec**

```ruby
# spec/services/code_generators/element_types/process/data_operations/map_collection_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::MapCollectionGenerator do
  let(:element) { { "config" => { "sourceVariable" => "users", "targetVariable" => "mapped", "fieldMappings" => [{ "from" => "full_name", "to" => "name" }, { "from" => "contact_email", "to" => "email" }] } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates map with field mappings" do
    code = described_class.new(element, context).generate
    expect(code).to include("ctx[:mapped] = ctx[:users].map")
    expect(code).to include("name: item[:full_name]")
    expect(code).to include("email: item[:contact_email]")
  end

  it "handles single mapping" do
    el = { "config" => { "sourceVariable" => "items", "targetVariable" => "ids", "fieldMappings" => [{ "from" => "id", "to" => "id" }] } }
    code = described_class.new(el, {}).generate
    expect(code).to include("id: item[:id]")
  end

  it "validates required fields" do
    errors = described_class.new({ "config" => {} }, {}).validate_config({})
    expect(errors).to include("sourceVariable is required")
    expect(errors).to include("fieldMappings must be a non-empty array")
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/map_collection_generator_spec.rb`
Expected: FAIL

- [ ] **Step 3: Implement the generator**

```ruby
# app/services/code_generators/element_types/process/data_operations/map_collection_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class MapCollectionGenerator < BaseGenerator
          generator_metadata do
            description "Transforms each item in an array by mapping fields to new names"
            category :data_operations
            version "1.0.0"
          end

          input_schema  :source_variable
          output_schema :target_variable

          def generate
            source = config["sourceVariable"] || "items"
            target = config["targetVariable"] || "mapped"
            mappings = config["fieldMappings"] || []

            if mappings.any?
              fields = mappings.map { |m| "#{m['to']}: item[:#{m['from']}]" }.join(", ")
              "ctx[:#{target}] = ctx[:#{source}].map { |item| { #{fields} } }\ntrue"
            else
              "ctx[:#{target}] = ctx[:#{source}].dup\ntrue"
            end
          end

          def validate_config(cfg)
            errors = []
            errors << "sourceVariable is required" if cfg["sourceVariable"].blank?
            mappings = cfg["fieldMappings"]
            if !mappings.is_a?(Array) || mappings.empty?
              errors << "fieldMappings must be a non-empty array"
            end
            errors
          end

          def example_output
            "ctx[:mapped] = ctx[:items].map { |item| { name: item[:full_name], email: item[:contact_email] } }\ntrue"
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/map_collection_generator_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/data_operations/map_collection_generator.rb spec/services/code_generators/element_types/process/data_operations/map_collection_generator_spec.rb
git commit -m "feat: add MapCollection generator"
```

---

### Task 4: FormatString generator

**Files:**
- Create: `spec/services/code_generators/element_types/process/data_operations/format_string_generator_spec.rb`
- Create: `app/services/code_generators/element_types/process/data_operations/format_string_generator.rb`

- [ ] **Step 1: Write the spec**

```ruby
# spec/services/code_generators/element_types/process/data_operations/format_string_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::FormatStringGenerator do
  let(:element) { { "config" => { "template" => "Hello {{name}}, order #{{order_id}}", "targetVariable" => "message" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates gsub chain for placeholders" do
    code = described_class.new(element, context).generate
    expect(code).to include('ctx[:message]')
    expect(code).to include('.gsub("{{name}}", ctx[:name].to_s)')
    expect(code).to include('.gsub("{{order_id}}", ctx[:order_id].to_s)')
  end

  it "handles template with no placeholders" do
    el = { "config" => { "template" => "Static text", "targetVariable" => "msg" } }
    code = described_class.new(el, {}).generate
    expect(code).to include('ctx[:msg] = "Static text"')
  end

  it "validates required fields" do
    errors = described_class.new({ "config" => {} }, {}).validate_config({})
    expect(errors).to include("template is required")
    expect(errors).to include("targetVariable is required")
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/format_string_generator_spec.rb`
Expected: FAIL

- [ ] **Step 3: Implement the generator**

```ruby
# app/services/code_generators/element_types/process/data_operations/format_string_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class FormatStringGenerator < BaseGenerator
          generator_metadata do
            description "Interpolates ctx variables into a template string using {{variable}} placeholders"
            category :data_operations
            version "1.0.0"
          end

          input_schema  # dynamic — depends on template placeholders
          output_schema :target_variable

          def generate
            template = config["template"] || ""
            target = config["targetVariable"] || "result"

            placeholders = template.scan(/\{\{(\w+)\}\}/).flatten.uniq

            if placeholders.empty?
              "ctx[:#{target}] = #{template.inspect}\ntrue"
            else
              gsub_chain = placeholders.map { |var| ".gsub(\"{{#{var}}}\", ctx[:#{var}].to_s)" }.join
              "ctx[:#{target}] = #{template.inspect}#{gsub_chain}\ntrue"
            end
          end

          def validate_config(cfg)
            errors = []
            errors << "template is required" if cfg["template"].blank?
            errors << "targetVariable is required" if cfg["targetVariable"].blank?
            errors
          end

          def example_output
            "ctx[:message] = \"Hello {{name}}\".gsub(\"{{name}}\", ctx[:name].to_s)\ntrue"
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/format_string_generator_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/data_operations/format_string_generator.rb spec/services/code_generators/element_types/process/data_operations/format_string_generator_spec.rb
git commit -m "feat: add FormatString generator"
```

---

### Task 5: ParseData generator

**Files:**
- Create: `spec/services/code_generators/element_types/process/data_operations/parse_data_generator_spec.rb`
- Create: `app/services/code_generators/element_types/process/data_operations/parse_data_generator.rb`

- [ ] **Step 1: Write the spec**

```ruby
# spec/services/code_generators/element_types/process/data_operations/parse_data_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::ParseDataGenerator do
  let(:element) { { "config" => { "sourceVariable" => "raw_json", "targetVariable" => "data", "format" => "json" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates JSON parsing" do
    code = described_class.new(element, context).generate
    expect(code).to include("JSON.parse(ctx[:raw_json])")
    expect(code).to include("ctx[:data]")
  end

  it "generates CSV parsing with headers" do
    el = { "config" => { "sourceVariable" => "csv_text", "targetVariable" => "rows", "format" => "csv", "csvHeaders" => true } }
    code = described_class.new(el, {}).generate
    expect(code).to include("CSV.parse(ctx[:csv_text], headers: true)")
    expect(code).to include(".map(&:to_h)")
  end

  it "generates CSV parsing without headers" do
    el = { "config" => { "sourceVariable" => "csv_text", "targetVariable" => "rows", "format" => "csv", "csvHeaders" => false } }
    code = described_class.new(el, {}).generate
    expect(code).to include("CSV.parse(ctx[:csv_text])")
    expect(code).not_to include("headers: true")
  end

  it "validates required fields" do
    errors = described_class.new({ "config" => {} }, {}).validate_config({})
    expect(errors).to include("sourceVariable is required")
  end

  it "validates format" do
    errors = described_class.new(element, {}).validate_config({ "format" => "xml" })
    expect(errors).to include(/Invalid format/)
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/parse_data_generator_spec.rb`
Expected: FAIL

- [ ] **Step 3: Implement the generator**

```ruby
# app/services/code_generators/element_types/process/data_operations/parse_data_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class ParseDataGenerator < BaseGenerator
          FORMATS = %w[json csv].freeze

          generator_metadata do
            description "Parses a JSON or CSV string into structured data"
            category :data_operations
            version "1.0.0"
          end

          input_schema  :source_variable
          output_schema :target_variable

          def generate
            source = config["sourceVariable"] || "raw_data"
            target = config["targetVariable"] || "data"
            format = config["format"] || "json"

            parse_expr = case format
                         when "csv"
                           headers = config.fetch("csvHeaders", true)
                           if headers
                             "CSV.parse(ctx[:#{source}], headers: true).map(&:to_h)"
                           else
                             "CSV.parse(ctx[:#{source}])"
                           end
                         else
                           "JSON.parse(ctx[:#{source}])"
                         end

            "ctx[:#{target}] = #{parse_expr}\ntrue"
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
            "ctx[:data] = JSON.parse(ctx[:raw_json])\ntrue"
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/parse_data_generator_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/data_operations/parse_data_generator.rb spec/services/code_generators/element_types/process/data_operations/parse_data_generator_spec.rb
git commit -m "feat: add ParseData generator"
```

---

### Task 6: MapValue generator

**Files:**
- Create: `spec/services/code_generators/element_types/process/data_operations/map_value_generator_spec.rb`
- Create: `app/services/code_generators/element_types/process/data_operations/map_value_generator.rb`

- [ ] **Step 1: Write the spec**

```ruby
# spec/services/code_generators/element_types/process/data_operations/map_value_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::MapValueGenerator do
  let(:element) { { "config" => { "sourceVariable" => "status", "targetVariable" => "label", "mappings" => { "draft" => "Draft", "published" => "Live", "archived" => "Hidden" }, "defaultValue" => "Unknown" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates fetch with mappings and default" do
    code = described_class.new(element, context).generate
    expect(code).to include("ctx[:label]")
    expect(code).to include('"draft"=>"Draft"')
    expect(code).to include('"published"=>"Live"')
    expect(code).to include('.fetch(ctx[:status].to_s, "Unknown")')
  end

  it "uses nil default when no defaultValue" do
    el = { "config" => { "sourceVariable" => "code", "targetVariable" => "name", "mappings" => { "us" => "United States" } } }
    code = described_class.new(el, {}).generate
    expect(code).to include(".fetch(ctx[:code].to_s, nil)")
  end

  it "validates required fields" do
    errors = described_class.new({ "config" => {} }, {}).validate_config({})
    expect(errors).to include("sourceVariable is required")
    expect(errors).to include("mappings must be a non-empty hash")
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/map_value_generator_spec.rb`
Expected: FAIL

- [ ] **Step 3: Implement the generator**

```ruby
# app/services/code_generators/element_types/process/data_operations/map_value_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class MapValueGenerator < BaseGenerator
          generator_metadata do
            description "Maps a value through a lookup table (switch-case pattern) with optional default"
            category :data_operations
            version "1.0.0"
          end

          input_schema  :source_variable
          output_schema :target_variable

          def generate
            source = config["sourceVariable"] || "value"
            target = config["targetVariable"] || "result"
            mappings = config["mappings"] || {}
            default_value = config["defaultValue"]

            lookup = mappings.map { |k, v| "#{k.to_s.inspect}=>#{v.to_s.inspect}" }.join(", ")
            default = default_value.present? ? default_value.to_s.inspect : "nil"

            "ctx[:#{target}] = {#{lookup}}.fetch(ctx[:#{source}].to_s, #{default})\ntrue"
          end

          def validate_config(cfg)
            errors = []
            errors << "sourceVariable is required" if cfg["sourceVariable"].blank?
            mappings = cfg["mappings"]
            if !mappings.is_a?(Hash) || mappings.empty?
              errors << "mappings must be a non-empty hash"
            end
            errors
          end

          def example_output
            "ctx[:label] = {\"draft\"=>\"Draft\", \"published\"=>\"Live\"}.fetch(ctx[:status].to_s, \"Unknown\")\ntrue"
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/map_value_generator_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/data_operations/map_value_generator.rb spec/services/code_generators/element_types/process/data_operations/map_value_generator_spec.rb
git commit -m "feat: add MapValue generator"
```

---

### Task 7: Final verification

- [ ] **Step 1: Run all data operations generator specs**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/`
Expected: All pass (existing + 6 new spec files)

- [ ] **Step 2: Verify generators are auto-discovered by registry**

Run: `bundle exec rails runner "puts CodeGenerators::GeneratorRegistry.instance.step_action_generators.keys.sort.join(', ')"`
Expected: Output includes `filter_collection`, `sort_collection`, `map_collection`, `format_string`, `parse_data`, `map_value` among the existing generator names

- [ ] **Step 3: Run full test suite**

Run: `bundle exec rspec`
Expected: All pass, no regressions

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: verify all 6 data operations generators registered and passing"
```
