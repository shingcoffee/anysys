# Data Operations Generators Design (Batch 1 of 2)

## Overview

Add 6 new step action generators under the `data_operations` category. These fill gaps in collection manipulation, string formatting, data parsing, and value mapping — common operations in real-world business workflows that the current 33 generators don't cover.

All generators follow the existing `BaseGenerator` pattern and operate on configurable ctx variables (source/target).

## Generators

### 1. FilterCollection

Filters an array in ctx by one or more conditions.

- **Category**: `data_operations`
- **Config**: `sourceVariable` (string), `targetVariable` (string), `filterField` (string), `filterOperator` (enum: eq, ne, gt, lt, gte, lte, includes, blank, present), `filterValue` (string)
- **Input schema**: source variable (dynamic)
- **Output schema**: target variable (dynamic)
- **Generated code**: `ctx[:target] = ctx[:source].select { |item| item[:field] <op> value }`
- **Operators**:
  - `eq` → `==`
  - `ne` → `!=`
  - `gt` → `>`
  - `lt` → `<`
  - `gte` → `>=`
  - `lte` → `<=`
  - `includes` → `.to_s.include?(value)`
  - `blank` → `.blank?` (no filterValue needed)
  - `present` → `.present?` (no filterValue needed)
- **Validation**: sourceVariable and filterField required. filterOperator must be in allowed list.
- **Example output**: `ctx[:filtered] = ctx[:items].select { |item| item[:status] == "active" }\ntrue`

### 2. SortCollection

Sorts an array in ctx by a field and direction.

- **Category**: `data_operations`
- **Config**: `sourceVariable` (string), `targetVariable` (string), `sortField` (string), `sortDirection` (enum: asc, desc, default asc)
- **Input schema**: source variable (dynamic)
- **Output schema**: target variable (dynamic)
- **Generated code**:
  - asc: `ctx[:target] = ctx[:source].sort_by { |item| item[:field] }`
  - desc: `ctx[:target] = ctx[:source].sort_by { |item| item[:field] }.reverse`
- **Validation**: sourceVariable and sortField required.
- **Example output**: `ctx[:sorted] = ctx[:items].sort_by { |item| item[:name] }\ntrue`

### 3. MapCollection

Transforms each item in an array, extracting/renaming fields.

- **Category**: `data_operations`
- **Config**: `sourceVariable` (string), `targetVariable` (string), `fieldMappings` (array of `{ "from": "source_field", "to": "target_field" }` objects)
- **Input schema**: source variable (dynamic)
- **Output schema**: target variable (dynamic)
- **Generated code**: `ctx[:target] = ctx[:source].map { |item| { to1: item[:from1], to2: item[:from2] } }`
- **Validation**: sourceVariable required, fieldMappings must be a non-empty array with `from` and `to` keys.
- **Example output**: `ctx[:mapped] = ctx[:items].map { |item| { name: item[:full_name], email: item[:contact_email] } }\ntrue`

### 4. FormatString

Interpolates ctx variables into a template string using `{{variable}}` placeholders.

- **Category**: `data_operations`
- **Config**: `template` (string with `{{variable}}` placeholders), `targetVariable` (string)
- **Input schema**: referenced variables (dynamic)
- **Output schema**: target variable (dynamic)
- **Generated code**: Builds a string by replacing each `{{var}}` with `ctx[:var].to_s`
  - Generates: `ctx[:target] = "template".gsub("{{var1}}", ctx[:var1].to_s).gsub("{{var2}}", ctx[:var2].to_s)`
- **Validation**: template and targetVariable required.
- **Example output**: `ctx[:message] = "Hello {{name}}".gsub("{{name}}", ctx[:name].to_s)\ntrue`

### 5. ParseData

Parses a JSON or CSV string into structured data.

- **Category**: `data_operations`
- **Config**: `sourceVariable` (string), `targetVariable` (string), `format` (enum: json, csv), `csvHeaders` (boolean, default true)
- **Input schema**: source variable (dynamic)
- **Output schema**: target variable (dynamic)
- **Generated code**:
  - json: `ctx[:target] = JSON.parse(ctx[:source])`
  - csv (with headers): `ctx[:target] = CSV.parse(ctx[:source], headers: true).map(&:to_h)`
  - csv (without headers): `ctx[:target] = CSV.parse(ctx[:source])`
- **Validation**: sourceVariable required. format must be json or csv.
- **Example output**: `ctx[:data] = JSON.parse(ctx[:raw_json])\ntrue`

### 6. MapValue

Maps a value through a lookup table (switch-case pattern) with optional default.

- **Category**: `data_operations`
- **Config**: `sourceVariable` (string), `targetVariable` (string), `mappings` (hash of string→string), `defaultValue` (string, optional)
- **Input schema**: source variable (dynamic)
- **Output schema**: target variable (dynamic)
- **Generated code**: `ctx[:target] = { "key1" => "val1", "key2" => "val2" }.fetch(ctx[:source].to_s, "default")`
- **When no defaultValue**: uses `.fetch(key, nil)` so unmapped values become nil
- **Validation**: sourceVariable required, mappings must be a non-empty hash.
- **Example output**: `ctx[:label] = {"draft"=>"Draft", "published"=>"Live"}.fetch(ctx[:status].to_s, "Unknown")\ntrue`

## File Structure

Each generator creates two files:

```
app/services/code_generators/element_types/process/data_operations/<name>_generator.rb
spec/services/code_generators/element_types/process/data_operations/<name>_generator_spec.rb
```

New files (12 total):
- `filter_collection_generator.rb` + spec
- `sort_collection_generator.rb` + spec
- `map_collection_generator.rb` + spec
- `format_string_generator.rb` + spec
- `parse_data_generator.rb` + spec
- `map_value_generator.rb` + spec

## Generator Pattern

All generators follow the existing `BaseGenerator` contract:

```ruby
module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class XxxGenerator < BaseGenerator
          generator_metadata do
            description "..."
            category :data_operations
            version "1.0.0"
          end

          input_schema :source_var
          output_schema :target_var

          def generate
            # Return Ruby code string
          end

          def validate_config(cfg)
            # Return array of error strings
          end

          def example_output
            # Return example code string
          end
        end
      end
    end
  end
end
```

## Testing

Each spec file tests:
- `it_behaves_like "a code generator"` (shared examples verifying interface)
- Default output with minimal config
- Each config variant (operators for Filter, directions for Sort, formats for Parse, etc.)
- `validate_config` returns errors for invalid/missing config
- `example_output` returns a non-empty string
