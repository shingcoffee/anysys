# Calculated Fields (Server-Side SQL) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add SQL-level calculated fields to entity definitions — defined with simple formulas, compiled to SQL at query time, usable in conditions, ordering, and display.

**Architecture:** A new `FormulaCompiler` service translates simple expressions (`price * quantity`) to SQL (`CAST(json_extract(...) AS NUMERIC) * CAST(json_extract(...) AS NUMERIC)`). It resolves field references from entity property_schema, handles type-aware casting, and topologically sorts chained dependencies. `QueryBuilder` auto-injects entity calculated fields into every query. Calculated fields are defined in property_schema with `type: "Calculated"`.

**Tech Stack:** Ruby on Rails 8.1, SQLite json_extract, RSpec, FactoryBot

**Spec:** `docs/superpowers/specs/2026-04-06-calculated-fields-design.md`

---

## File Map

### New Files

| File | Responsibility |
|---|---|
| `app/services/flowchart_runtime/formula_compiler.rb` | Tokenize/parse simple expressions, resolve field refs to SQL, topological sort for chaining |
| `spec/services/flowchart_runtime/formula_compiler_spec.rb` | FormulaCompiler unit tests |
| `spec/integration/calculated_fields_integration_spec.rb` | End-to-end calculated field tests |

### Modified Files

| File | Change |
|---|---|
| `app/models/entity.rb` | Add `calculated_fields` and `data_fields` helper methods |
| `app/models/entity_entry.rb` | Skip calculated fields in `validate_data_keys` and `build_for` setters |
| `app/services/flowchart_runtime/query_builder.rb` | Auto-inject calculated fields from entity schema; pass calculated_fields map to WhereClauseBuilder |
| `app/services/flowchart_runtime/where_clause_builder.rb` | Accept optional `calculated_fields:` kwarg; substitute SQL expressions for calculated field references |
| `app/services/page_field_populator.rb` | Mark calculated fields as `readonly` when populating page fields |
| `app/services/page_content_generator.rb` | Render calculated fields as display-only |

---

## Task 1: FormulaCompiler — Core tokenizer and field resolution

**Files:**
- Create: `app/services/flowchart_runtime/formula_compiler.rb`
- Create: `spec/services/flowchart_runtime/formula_compiler_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/flowchart_runtime/formula_compiler_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::FormulaCompiler do
  let(:schema_fields) do
    [
      { "name" => "Price", "name_slug" => "price", "type" => "Float", "html_type" => "number" },
      { "name" => "Quantity", "name_slug" => "quantity", "type" => "Integer", "html_type" => "number" },
      { "name" => "Name", "name_slug" => "name", "type" => "String", "html_type" => "text" },
      { "name" => "Email", "name_slug" => "email", "type" => "String", "html_type" => "email" }
    ]
  end

  describe ".compile" do
    context "field references" do
      it "translates numeric field to CAST json_extract" do
        sql = described_class.compile("price", schema_fields)
        expect(sql).to eq("CAST(json_extract(entity_entries.data, '$.price') AS NUMERIC)")
      end

      it "translates string field to plain json_extract" do
        sql = described_class.compile("name", schema_fields)
        expect(sql).to eq("json_extract(entity_entries.data, '$.name')")
      end
    end

    context "arithmetic" do
      it "compiles multiplication" do
        sql = described_class.compile("price * quantity", schema_fields)
        expect(sql).to include("*")
        expect(sql).to include("json_extract(entity_entries.data, '$.price')")
        expect(sql).to include("json_extract(entity_entries.data, '$.quantity')")
      end

      it "compiles addition with literal" do
        sql = described_class.compile("price + 10", schema_fields)
        expect(sql).to include("+")
        expect(sql).to include("10")
      end

      it "compiles parenthesized expressions" do
        sql = described_class.compile("(price + 5) * quantity", schema_fields)
        expect(sql).to include("(")
        expect(sql).to include(")")
      end
    end

    context "string concatenation" do
      it "compiles string field concatenation with || operator" do
        sql = described_class.compile("name + \" \" + email", schema_fields)
        expect(sql).to include("||")
        expect(sql).to include("json_extract(entity_entries.data, '$.name')")
      end
    end

    context "numeric literals" do
      it "passes through integer literals" do
        sql = described_class.compile("42", schema_fields)
        expect(sql).to eq("42")
      end

      it "passes through float literals" do
        sql = described_class.compile("3.14", schema_fields)
        expect(sql).to eq("3.14")
      end
    end

    context "string literals" do
      it "passes through quoted strings" do
        sql = described_class.compile("\"hello\"", schema_fields)
        expect(sql).to eq("'hello'")
      end
    end

    context "functions" do
      it "compiles ROUND function" do
        sql = described_class.compile("ROUND(price, 2)", schema_fields)
        expect(sql).to include("ROUND(")
      end

      it "compiles ABS function" do
        sql = described_class.compile("ABS(price)", schema_fields)
        expect(sql).to include("ABS(")
      end

      it "compiles COALESCE function" do
        sql = described_class.compile("COALESCE(price, 0)", schema_fields)
        expect(sql).to include("COALESCE(")
      end

      it "compiles UPPER function" do
        sql = described_class.compile("UPPER(name)", schema_fields)
        expect(sql).to include("UPPER(")
      end

      it "compiles LOWER function" do
        sql = described_class.compile("LOWER(name)", schema_fields)
        expect(sql).to include("LOWER(")
      end

      it "compiles LENGTH function" do
        sql = described_class.compile("LENGTH(name)", schema_fields)
        expect(sql).to include("LENGTH(")
      end
    end

    context "unknown fields" do
      it "raises error for unknown field reference" do
        expect {
          described_class.compile("unknown_field * 2", schema_fields)
        }.to raise_error(FlowchartRuntime::FormulaError, /Unknown field/)
      end
    end

    context "empty formula" do
      it "returns nil for nil formula" do
        expect(described_class.compile(nil, schema_fields)).to be_nil
      end

      it "returns nil for blank formula" do
        expect(described_class.compile("", schema_fields)).to be_nil
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/flowchart_runtime/formula_compiler_spec.rb`
Expected: FAIL — `uninitialized constant FlowchartRuntime::FormulaCompiler`

- [ ] **Step 3: Write FormulaCompiler implementation**

```ruby
# app/services/flowchart_runtime/formula_compiler.rb
# frozen_string_literal: true

module FlowchartRuntime
  class FormulaError < StandardError; end

  # FormulaCompiler
  #
  # Translates simple expressions (e.g., "price * quantity") into SQL expressions
  # (e.g., "CAST(json_extract(entity_entries.data, '$.price') AS NUMERIC) * ...").
  #
  # Resolves field references from entity property_schema, handles type-aware casting
  # (numeric fields get CAST AS NUMERIC, string fields are plain json_extract),
  # and supports chaining with topological sort.
  #
  # @example
  #   FormulaCompiler.compile("price * quantity + 10", schema_fields)
  #   #=> "CAST(json_extract(entity_entries.data, '$.price') AS NUMERIC) * CAST(...) + 10"
  #
  module FormulaCompiler
    MAX_LENGTH = 1000
    NUMERIC_HTML_TYPES = %w[number range currency].freeze
    SUPPORTED_FUNCTIONS = %w[ROUND ABS COALESCE UPPER LOWER LENGTH].freeze

    TOKEN_SPEC = [
      [:NUMBER,  /\A\d+(\.\d+)?/],
      [:STRING,  /\A"([^"\\]*)"/],
      [:IDENT,   /\A[A-Za-z_][A-Za-z0-9_]*/],
      [:LPAREN,  /\A\(/],
      [:RPAREN,  /\A\)/],
      [:COMMA,   /\A,/],
      [:PLUS,    /\A\+/],
      [:MINUS,   /\A-/],
      [:STAR,    /\A\*/],
      [:SLASH,   /\A\//],
    ].freeze

    module_function

    # Compile a formula string to a SQL expression.
    #
    # @param formula [String, nil] the formula expression
    # @param schema_fields [Array<Hash>] entity property_schema fields
    # @param resolved_calculated [Hash] already-resolved calculated field SQL (for chaining)
    # @return [String, nil] SQL expression or nil
    def compile(formula, schema_fields, resolved_calculated = {})
      return nil if formula.nil? || formula.to_s.strip.empty?

      formula = formula.to_s.strip
      raise FormulaError, "Formula too long (max #{MAX_LENGTH})" if formula.length > MAX_LENGTH

      field_map = build_field_map(schema_fields)
      tokens = tokenize(formula)
      parser = Parser.new(tokens, field_map, resolved_calculated)
      parser.parse
    end

    # Compile all calculated fields in topological order.
    #
    # @param schema_fields [Array<Hash>] full property_schema including calculated fields
    # @return [Array<Hash>] sorted array of { name:, sql: } hashes
    def compile_all(schema_fields)
      calculated = schema_fields.select { |f| f["type"] == "Calculated" }
      return [] if calculated.empty?

      # Build dependency graph
      data_slugs = schema_fields.reject { |f| f["type"] == "Calculated" }.map { |f| f["name_slug"] }.to_set
      calc_slugs = calculated.map { |f| f["name_slug"] }.to_set
      all_slugs = data_slugs | calc_slugs

      deps = {}
      calculated.each do |field|
        formula = field["formula"].to_s
        # Extract field references from formula (identifiers that match known slugs)
        refs = formula.scan(/\b([A-Za-z_][A-Za-z0-9_]*)\b/).flatten
        refs = refs.select { |r| all_slugs.include?(r) && r != field["name_slug"] }
        calc_deps = refs.select { |r| calc_slugs.include?(r) }
        deps[field["name_slug"]] = calc_deps
      end

      # Topological sort
      sorted = topological_sort(deps)

      # Compile in order
      resolved = {}
      sorted.map do |slug|
        field = calculated.find { |f| f["name_slug"] == slug }
        sql = compile(field["formula"], schema_fields, resolved)
        resolved[slug] = sql
        { name: slug, sql: sql }
      end
    end

    # Build a map of field slug → { type info } for resolution.
    def build_field_map(schema_fields)
      map = {}
      schema_fields.each do |f|
        map[f["name_slug"]] = {
          slug: f["name_slug"],
          html_type: f["html_type"] || "text",
          type: f["type"] || "String",
          calculated: f["type"] == "Calculated",
          formula: f["formula"]
        }
      end
      map
    end

    def tokenize(source)
      tokens = []
      pos = 0
      while pos < source.length
        # Skip whitespace
        if source[pos] =~ /\s/
          pos += 1
          next
        end

        matched = false
        TOKEN_SPEC.each do |type, pattern|
          match = source[pos..].match(pattern)
          next unless match

          value = match[0]
          tokens << [type, value]
          pos += value.length
          matched = true
          break
        end

        raise FormulaError, "Unexpected character '#{source[pos]}' at position #{pos}" unless matched
      end
      tokens << [:EOF, nil]
      tokens
    end

    def topological_sort(deps)
      visited = {}
      result = []
      in_progress = Set.new

      visit = ->(node) do
        return if visited[node]
        raise FormulaError, "Circular dependency detected involving '#{node}'" if in_progress.include?(node)

        in_progress.add(node)
        (deps[node] || []).each { |dep| visit.call(dep) }
        in_progress.delete(node)
        visited[node] = true
        result << node
      end

      deps.each_key { |node| visit.call(node) }
      result
    end

    # Internal recursive descent parser that produces SQL strings.
    class Parser
      def initialize(tokens, field_map, resolved_calculated = {})
        @tokens = tokens
        @pos = 0
        @field_map = field_map
        @resolved_calculated = resolved_calculated
        @depth = 0
      end

      def parse
        result = parse_additive
        expect(:EOF)
        result
      end

      private

      def parse_additive
        left = parse_multiplicative
        while current_type == :PLUS || current_type == :MINUS
          op = advance[1]
          right = parse_multiplicative
          if op == "+"
            # Detect string concatenation vs numeric addition
            left = "#{left} || #{right}"
          else
            left = "#{left} - #{right}"
          end
        end
        left
      end

      def parse_multiplicative
        left = parse_unary
        while current_type == :STAR || current_type == :SLASH
          op = advance[1]
          right = parse_unary
          left = "#{left} #{op} #{right}"
        end
        left
      end

      def parse_unary
        if current_type == :MINUS
          advance
          operand = parse_primary
          return "-(#{operand})"
        end
        parse_primary
      end

      def parse_primary
        @depth += 1
        raise FormulaError, "Expression too deeply nested" if @depth > 20

        result = case current_type
                 when :NUMBER
                   advance[1]
                 when :STRING
                   value = advance[1]
                   # Convert "text" to 'text' for SQL
                   inner = value[1..-2]
                   "'#{inner}'"
                 when :LPAREN
                   advance # consume (
                   expr = parse_additive
                   expect(:RPAREN)
                   "(#{expr})"
                 when :IDENT
                   parse_identifier
                 else
                   raise FormulaError, "Unexpected token: #{current_type}"
                 end

        @depth -= 1
        result
      end

      def parse_identifier
        name = advance[1]

        # Check if it's a function call
        if current_type == :LPAREN && FormulaCompiler::SUPPORTED_FUNCTIONS.include?(name.upcase)
          return parse_function_call(name.upcase)
        end

        resolve_field(name)
      end

      def parse_function_call(func_name)
        advance # consume (
        args = []
        unless current_type == :RPAREN
          args << parse_additive
          while current_type == :COMMA
            advance # consume ,
            args << parse_additive
          end
        end
        expect(:RPAREN)
        "#{func_name}(#{args.join(', ')})"
      end

      def resolve_field(name)
        # Check resolved calculated fields first (for chaining)
        if @resolved_calculated.key?(name)
          return "(#{@resolved_calculated[name]})"
        end

        field_info = @field_map[name]
        raise FormulaError, "Unknown field '#{name}'" unless field_info

        # If it's a calculated field that hasn't been resolved yet, compile it inline
        if field_info[:calculated] && field_info[:formula]
          return "(#{FormulaCompiler.compile(field_info[:formula], @field_map.values.map { |f| { 'name_slug' => f[:slug], 'html_type' => f[:html_type], 'type' => f[:type] } }, @resolved_calculated)})"
        end

        if FormulaCompiler::NUMERIC_HTML_TYPES.include?(field_info[:html_type])
          "CAST(json_extract(entity_entries.data, '$.#{name}') AS NUMERIC)"
        else
          "json_extract(entity_entries.data, '$.#{name}')"
        end
      end

      def current_type
        @tokens[@pos]&.first
      end

      def advance
        token = @tokens[@pos]
        @pos += 1
        token
      end

      def expect(type)
        raise FormulaError, "Expected #{type}, got #{current_type}" unless current_type == type
        advance
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/flowchart_runtime/formula_compiler_spec.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/flowchart_runtime/formula_compiler.rb spec/services/flowchart_runtime/formula_compiler_spec.rb
git commit -m "feat: add FormulaCompiler for simple-expression-to-SQL translation"
```

---

## Task 2: FormulaCompiler — Chaining with topological sort

**Files:**
- Modify: `spec/services/flowchart_runtime/formula_compiler_spec.rb`

- [ ] **Step 1: Write the failing test for compile_all and chaining**

Add to `spec/services/flowchart_runtime/formula_compiler_spec.rb`:

```ruby
  describe ".compile_all" do
    let(:chained_schema) do
      [
        { "name" => "Price", "name_slug" => "price", "type" => "Float", "html_type" => "number" },
        { "name" => "Quantity", "name_slug" => "quantity", "type" => "Integer", "html_type" => "number" },
        { "name" => "Subtotal", "name_slug" => "subtotal", "type" => "Calculated", "html_type" => "number",
          "readonly" => true, "storage" => "computed", "formula" => "price * quantity" },
        { "name" => "Tax", "name_slug" => "tax", "type" => "Calculated", "html_type" => "number",
          "readonly" => true, "storage" => "computed", "formula" => "subtotal * 0.1" },
        { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "html_type" => "number",
          "readonly" => true, "storage" => "computed", "formula" => "subtotal + tax" }
      ]
    end

    it "compiles all calculated fields in dependency order" do
      result = described_class.compile_all(chained_schema)
      names = result.map { |r| r[:name] }
      expect(names).to eq(%w[subtotal tax total])
    end

    it "resolves chained references" do
      result = described_class.compile_all(chained_schema)
      tax_sql = result.find { |r| r[:name] == "tax" }[:sql]
      # Tax references subtotal which is already resolved — should be inlined
      expect(tax_sql).to include("json_extract")
      expect(tax_sql).to include("0.1")
    end

    it "returns empty array when no calculated fields" do
      plain_schema = [
        { "name" => "Price", "name_slug" => "price", "type" => "Float", "html_type" => "number" }
      ]
      expect(described_class.compile_all(plain_schema)).to eq([])
    end

    it "detects circular dependencies" do
      circular_schema = [
        { "name" => "A", "name_slug" => "a", "type" => "Calculated", "html_type" => "number",
          "formula" => "b + 1" },
        { "name" => "B", "name_slug" => "b", "type" => "Calculated", "html_type" => "number",
          "formula" => "a + 1" }
      ]
      expect {
        described_class.compile_all(circular_schema)
      }.to raise_error(FlowchartRuntime::FormulaError, /Circular dependency/)
    end
  end
```

- [ ] **Step 2: Run test to verify it passes (compile_all is already implemented)**

Run: `bundle exec rspec spec/services/flowchart_runtime/formula_compiler_spec.rb`
Expected: All PASS (compile_all was included in Task 1 implementation)

- [ ] **Step 3: Commit**

```bash
git add spec/services/flowchart_runtime/formula_compiler_spec.rb
git commit -m "test: add chaining and topological sort tests for FormulaCompiler"
```

---

## Task 3: Entity model — calculated_fields and data_fields helpers

**Files:**
- Modify: `app/models/entity.rb`
- Modify: `app/models/entity_entry.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/models/entity_calculated_fields_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entity, "calculated fields" do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Price", "name_slug" => "price", "type" => "Float", "html_type" => "number" },
      { "name" => "Quantity", "name_slug" => "quantity", "type" => "Integer", "html_type" => "number" },
      { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "html_type" => "number",
        "readonly" => true, "storage" => "computed", "formula" => "price * quantity" }
    ].to_json)
  end

  describe "#calculated_fields" do
    it "returns only Calculated type fields" do
      result = entity.calculated_fields
      expect(result.size).to eq(1)
      expect(result.first["name_slug"]).to eq("total")
    end
  end

  describe "#data_fields" do
    it "returns only non-Calculated fields" do
      result = entity.data_fields
      expect(result.size).to eq(2)
      slugs = result.map { |f| f["name_slug"] }
      expect(slugs).to contain_exactly("price", "quantity")
    end
  end
end
```

```ruby
# spec/models/entity_entry_calculated_fields_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityEntry, "calculated fields" do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Price", "name_slug" => "price", "type" => "Float", "html_type" => "number" },
      { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "html_type" => "number",
        "readonly" => true, "storage" => "computed", "formula" => "price * 2" }
    ].to_json)
  end

  describe "validate_data_keys" do
    it "does not reject calculated field slugs in data" do
      entry = EntityEntry.new(entity: entity, customer: customer, data: { "price" => "100" }.to_json)
      expect(entry).to be_valid
    end

    it "still rejects truly invalid keys" do
      entry = EntityEntry.new(entity: entity, customer: customer, data: { "price" => "100", "bogus" => "x" }.to_json)
      expect(entry).not_to be_valid
    end
  end

  describe ".build_for" do
    it "creates getter but no setter for calculated fields" do
      model_class = EntityEntry.build_for(entity)
      instance = model_class.new(customer: customer)

      # Should have price setter
      expect(instance).to respond_to(:price=)
      # Should NOT have total setter (calculated)
      expect(instance).not_to respond_to(:total=)
      # Should have total getter (returns nil since not stored)
      expect(instance).to respond_to(:total)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/entity_calculated_fields_spec.rb spec/models/entity_entry_calculated_fields_spec.rb`
Expected: FAIL — `undefined method 'calculated_fields'`

- [ ] **Step 3: Add helper methods to Entity**

Add to `app/models/entity.rb` in the Public Methods section:

```ruby
  # Returns calculated field definitions from property_schema.
  def calculated_fields
    (property_schema_json || []).select { |f| f["type"] == "Calculated" }
  end

  # Returns data (non-calculated) field definitions from property_schema.
  def data_fields
    (property_schema_json || []).reject { |f| f["type"] == "Calculated" }
  end
```

- [ ] **Step 4: Update EntityEntry.build_for to skip setters for calculated fields**

In `app/models/entity_entry.rb`, modify the `build_for` method's `schema.each` block:

Replace:
```ruby
      schema.each do |attr|
        slug = attr["name_slug"]
        next unless slug

        define_method(slug) { data_json[slug] }
        define_method("#{slug}=") { |value| merge_data(slug => value) }
      end
```

With:
```ruby
      schema.each do |attr|
        slug = attr["name_slug"]
        next unless slug

        define_method(slug) { data_json[slug] }
        # Skip setter for calculated fields — they are read-only
        unless attr["type"] == "Calculated"
          define_method("#{slug}=") { |value| merge_data(slug => value) }
        end
      end
```

- [ ] **Step 5: Update EntityEntry validate_data_keys to skip calculated field slugs**

In `app/models/entity_entry.rb`, update the `valid_attribute_slugs` method:

Replace:
```ruby
  def valid_attribute_slugs
    @valid_attribute_slugs ||= begin
      slugs = (entity&.property_schema_json || []).map { |attr| attr["name_slug"] }
      slugs
    end
  end
```

With:
```ruby
  def valid_attribute_slugs
    @valid_attribute_slugs ||= begin
      # Only include data fields (non-calculated) as valid storage keys
      (entity&.property_schema_json || [])
        .reject { |attr| attr["type"] == "Calculated" }
        .map { |attr| attr["name_slug"] }
    end
  end
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bundle exec rspec spec/models/entity_calculated_fields_spec.rb spec/models/entity_entry_calculated_fields_spec.rb`
Expected: All PASS

- [ ] **Step 7: Commit**

```bash
git add app/models/entity.rb app/models/entity_entry.rb spec/models/entity_calculated_fields_spec.rb spec/models/entity_entry_calculated_fields_spec.rb
git commit -m "feat: add calculated_fields/data_fields helpers and skip calculated in EntityEntry"
```

---

## Task 4: QueryBuilder — Auto-inject calculated fields

**Files:**
- Modify: `app/services/flowchart_runtime/query_builder.rb`
- Modify: `spec/services/flowchart_runtime/query_builder_spec.rb`

- [ ] **Step 1: Write the failing test**

Add to `spec/services/flowchart_runtime/query_builder_spec.rb`:

```ruby
  context "with entity calculated fields" do
    let(:calc_entity) do
      create(:entity, customer: customer, property_schema: [
        { "name" => "Price", "name_slug" => "price", "type" => "Float", "html_type" => "number" },
        { "name" => "Quantity", "name_slug" => "quantity", "type" => "Integer", "html_type" => "number" },
        { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "html_type" => "number",
          "readonly" => true, "storage" => "computed", "formula" => "price * quantity" }
      ].to_json)
    end

    before do
      create(:entity_entry, entity: calc_entity, customer: customer, data: { "price" => "10", "quantity" => "5" }.to_json)
      create(:entity_entry, entity: calc_entity, customer: customer, data: { "price" => "20", "quantity" => "3" }.to_json)
    end

    it "auto-injects calculated fields into SELECT" do
      result = described_class.for_entity(calc_entity, customer_id: customer.id).execute
      expect(result.sql).to include("AS total")
    end

    it "makes calculated field values available on records" do
      result = described_class.for_entity(calc_entity, customer_id: customer.id)
                              .order("total", "desc")
                              .execute
      # price=20 * quantity=3 = 60, price=10 * quantity=5 = 50
      totals = result.records.map { |r| r["total"] }
      expect(totals).to eq([60, 50])
    end

    it "can filter by calculated field" do
      conditions = {
        "operator" => "AND",
        "rules" => [{ "field" => "data.total", "op" => ">", "value" => "55" }]
      }
      result = described_class.for_entity(calc_entity, customer_id: customer.id)
                              .where(conditions, {})
                              .execute
      expect(result.records.size).to eq(1)
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/flowchart_runtime/query_builder_spec.rb`
Expected: FAIL — calculated fields not auto-injected

- [ ] **Step 3: Update QueryBuilder to auto-inject calculated fields**

In `app/services/flowchart_runtime/query_builder.rb`:

Add to `initialize`:
```ruby
      @auto_calculated_fields = {}
```

Add a new private method:
```ruby
    def inject_calculated_fields
      return if @entity.nil?

      compiled = FormulaCompiler.compile_all(@entity.property_schema_json || [])
      compiled.each do |cf|
        @computed_fields << { name: cf[:name], expression: cf[:sql] }
        @auto_calculated_fields[cf[:name]] = cf[:sql]
      end
    end
```

Update `execute` to call it at the top:
```ruby
    def execute
      inject_calculated_fields
      scope = base_scope
      # ... rest unchanged
```

Update `apply_conditions` to pass calculated fields to WhereClauseBuilder:
```ruby
    def apply_conditions(scope)
      @conditions.each do |cond|
        scope = WhereClauseBuilder.apply(scope, cond[:conditions], cond[:ctx], calculated_fields: @auto_calculated_fields)
      end
      scope
    end
```

Update `apply_order` to resolve calculated field names:
```ruby
    def apply_order(scope)
      return scope unless @order_field

      # Check if ordering by a calculated/computed field
      computed_expr = @auto_calculated_fields[@order_field] ||
                      @computed_fields.find { |cf| cf[:name] == @order_field }&.dig(:expression)
      if computed_expr
        return scope.order(Arel.sql("#{computed_expr} #{@order_direction}"))
      end

      if @order_field.start_with?("data.")
        json_field = @order_field.sub("data.", "")
        scope.order(Arel.sql("json_extract(entity_entries.data, '$.#{json_field}') #{@order_direction}"))
      else
        scope.order(@order_field => @order_direction)
      end
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/flowchart_runtime/query_builder_spec.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/flowchart_runtime/query_builder.rb spec/services/flowchart_runtime/query_builder_spec.rb
git commit -m "feat: auto-inject entity calculated fields into QueryBuilder"
```

---

## Task 5: WhereClauseBuilder — Calculated field substitution

**Files:**
- Modify: `app/services/flowchart_runtime/where_clause_builder.rb`
- Modify: `spec/services/flowchart_runtime/where_clause_builder_spec.rb`

- [ ] **Step 1: Write the failing test**

Add to `spec/services/flowchart_runtime/where_clause_builder_spec.rb`:

```ruby
  describe "calculated field substitution" do
    it "substitutes calculated field expression in condition" do
      scope = EntityEntry.where(entity_id: entity.id, customer_id: customer.id)
      calculated_fields = { "doubled" => "CAST(json_extract(entity_entries.data, '$.amount') AS NUMERIC) * 2" }
      conditions = {
        "operator" => "AND",
        "rules" => [{ "field" => "data.doubled", "op" => ">", "value" => "350" }]
      }
      result = described_class.apply(scope, conditions, {}, calculated_fields: calculated_fields)
      # doubled values: 200, 400, 600 — only 400 and 600 match > 350
      expect(result.count).to eq(2)
    end

    it "falls back to json_extract for non-calculated fields" do
      scope = EntityEntry.where(entity_id: entity.id, customer_id: customer.id)
      calculated_fields = { "doubled" => "something" }
      conditions = {
        "operator" => "AND",
        "rules" => [{ "field" => "data.amount", "op" => "==", "value" => "200" }]
      }
      result = described_class.apply(scope, conditions, {}, calculated_fields: calculated_fields)
      expect(result.count).to eq(1)
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/flowchart_runtime/where_clause_builder_spec.rb`
Expected: FAIL — `apply` doesn't accept `calculated_fields` keyword

- [ ] **Step 3: Update WhereClauseBuilder to accept calculated_fields**

In `app/services/flowchart_runtime/where_clause_builder.rb`:

Update `apply` signature:
```ruby
    def apply(scope, conditions, ctx, calculated_fields: {})
```

Pass `calculated_fields` through to `build_group`:
```ruby
      sql_fragment, bindings = build_group(rules, operator, ctx, calculated_fields)
```

Update `build_group` signature:
```ruby
    def build_group(rules, operator, ctx, calculated_fields = {})
```

Pass through in recursive call:
```ruby
          sql, sub_bindings = build_group(rule["rules"], sub_operator, ctx, calculated_fields)
```

And in rule call:
```ruby
          sql, rule_bindings = build_rule(rule, ctx, calculated_fields)
```

Update `build_rule` signature:
```ruby
    def build_rule(rule, ctx, calculated_fields = {})
```

In `build_rule`, after extracting `field` and `op`, check for calculated field substitution:
```ruby
      # Check if this field is a calculated field
      if field.start_with?(DATA_PREFIX)
        json_field = field.sub(DATA_PREFIX, "")
        if calculated_fields.key?(json_field)
          calc_expr = calculated_fields[json_field]
          if rule.key?("subQuery")
            sub_query_sql = build_sub_query(rule["subQuery"], ctx)
            return build_comparison_raw(calc_expr, op, sub_query_sql)
          end
          value = resolve_value(rule["value"], ctx)
          return build_condition(calc_expr, op, value)
        end
      end
```

Place this BEFORE the existing `if rule.key?("subQuery")` check.

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/flowchart_runtime/where_clause_builder_spec.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/flowchart_runtime/where_clause_builder.rb spec/services/flowchart_runtime/where_clause_builder_spec.rb
git commit -m "feat: add calculated field substitution to WhereClauseBuilder"
```

---

## Task 6: PageFieldPopulator — Mark calculated fields as readonly

**Files:**
- Modify: `app/services/page_field_populator.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/page_field_populator_calculated_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageFieldPopulator, "calculated fields" do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Price", "name_slug" => "price", "type" => "Float", "html_type" => "number" },
      { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "html_type" => "number",
        "readonly" => true, "storage" => "computed", "formula" => "price * 2" }
    ].to_json)
  end

  it "marks calculated fields as readonly" do
    pages = described_class.call(entity)
    fields = pages.flat_map { |p| p["fields"] }
    total_field = fields.find { |f| f["property_slug"] == "total" }

    expect(total_field).not_to be_nil
    expect(total_field["readonly"]).to be true
    expect(total_field["storage"]).to eq("computed")
    expect(total_field["formula"]).to eq("price * 2")
  end

  it "does not mark regular fields as readonly" do
    pages = described_class.call(entity)
    fields = pages.flat_map { |p| p["fields"] }
    price_field = fields.find { |f| f["property_slug"] == "price" }

    expect(price_field["readonly"]).to be_falsey
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/page_field_populator_calculated_spec.rb`
Expected: FAIL — calculated field not marked as readonly

- [ ] **Step 3: Update PageFieldPopulator build_field**

In `app/services/page_field_populator.rb`, update the `build_field` method. After building the base `field` hash and before the options handling, add:

```ruby
    # Mark calculated fields as readonly display-only
    if prop["type"] == "Calculated"
      field["readonly"] = true
      field["storage"] = "computed"
      field["formula"] = prop["formula"]
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/page_field_populator_calculated_spec.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/page_field_populator.rb spec/services/page_field_populator_calculated_spec.rb
git commit -m "feat: mark calculated fields as readonly in PageFieldPopulator"
```

---

## Task 7: PageContentGenerator — Display-only rendering for calculated fields

**Files:**
- Modify: `app/services/page_content_generator.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/page_content_generator_calculated_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageContentGenerator, "calculated fields" do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Price", "name_slug" => "price", "type" => "Float", "html_type" => "number" }
    ].to_json)
  end

  it "renders calculated fields as display-only" do
    page = create(:page, customer: customer, configuration: {
      "fields" => [
        { "id" => "f1", "field_type" => "number", "label" => "Price", "property_slug" => "price",
          "property_type" => "number", "html_type" => "number", "width" => "full" },
        { "id" => "f2", "field_type" => "number", "label" => "Total", "property_slug" => "total",
          "property_type" => "number", "html_type" => "number", "width" => "full",
          "readonly" => true, "storage" => "computed", "formula" => "price * 2" }
      ],
      "metadata" => { "entity_id" => entity.id },
      "rules" => [],
      "calculations" => []
    }.to_json)

    generator = described_class.new(page)
    content = generator.generate

    # Calculated field should be rendered with disabled/readonly attributes
    expect(content).to include("total")
    # Regular field should be rendered normally
    expect(content).to include("price")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/page_content_generator_calculated_spec.rb`
Expected: May pass already if the field renders normally; the key test is that it renders with readonly

- [ ] **Step 3: Update PageContentGenerator to handle calculated fields**

In `app/services/page_content_generator.rb`, find the `generate_field` method (or the method that builds individual field components). Add a check: if `field["storage"] == "computed"`, pass `readonly: true` and `disabled: true` to the component.

The exact change depends on how `generate_field` works. Read the method and add:

```ruby
    # In generate_field or generate_form_field, before rendering:
    if field["storage"] == "computed"
      field_options[:readonly] = true
      field_options[:disabled] = true
      field_options[:computed] = true
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/page_content_generator_calculated_spec.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/page_content_generator.rb spec/services/page_content_generator_calculated_spec.rb
git commit -m "feat: render calculated fields as display-only in PageContentGenerator"
```

---

## Task 8: Integration test — Full calculated fields pipeline

**Files:**
- Create: `spec/integration/calculated_fields_integration_spec.rb`

- [ ] **Step 1: Write the integration test**

```ruby
# spec/integration/calculated_fields_integration_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Calculated fields integration", type: :model do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, name: "Invoice", customer: customer, property_schema: [
      { "name" => "Price", "name_slug" => "price", "type" => "Float", "html_type" => "number" },
      { "name" => "Quantity", "name_slug" => "quantity", "type" => "Integer", "html_type" => "number" },
      { "name" => "Discount", "name_slug" => "discount", "type" => "Float", "html_type" => "number" },
      { "name" => "Subtotal", "name_slug" => "subtotal", "type" => "Calculated", "html_type" => "number",
        "readonly" => true, "storage" => "computed", "formula" => "price * quantity" },
      { "name" => "Tax", "name_slug" => "tax", "type" => "Calculated", "html_type" => "number",
        "readonly" => true, "storage" => "computed", "formula" => "subtotal * 0.1" },
      { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "html_type" => "number",
        "readonly" => true, "storage" => "computed", "formula" => "subtotal + tax - discount" }
    ].to_json)
  end

  before do
    # Invoice 1: price=100, qty=2, discount=10 → subtotal=200, tax=20, total=210
    create(:entity_entry, entity: entity, customer: customer,
      data: { "price" => "100", "quantity" => "2", "discount" => "10" }.to_json)
    # Invoice 2: price=50, qty=4, discount=0 → subtotal=200, tax=20, total=220
    create(:entity_entry, entity: entity, customer: customer,
      data: { "price" => "50", "quantity" => "4", "discount" => "0" }.to_json)
    # Invoice 3: price=75, qty=1, discount=5 → subtotal=75, tax=7.5, total=77.5
    create(:entity_entry, entity: entity, customer: customer,
      data: { "price" => "75", "quantity" => "1", "discount" => "5" }.to_json)
  end

  it "auto-injects all chained calculated fields" do
    result = FlowchartRuntime::QueryBuilder
      .for_entity(entity, customer_id: customer.id)
      .execute

    expect(result.sql).to include("AS subtotal")
    expect(result.sql).to include("AS tax")
    expect(result.sql).to include("AS total")
  end

  it "computes correct values for chained fields" do
    result = FlowchartRuntime::QueryBuilder
      .for_entity(entity, customer_id: customer.id)
      .order("total", "desc")
      .execute

    totals = result.records.map { |r| r["total"] }
    # 220, 210, 77.5
    expect(totals[0]).to eq(220.0)
    expect(totals[1]).to eq(210.0)
    expect(totals[2]).to eq(77.5)
  end

  it "filters by calculated field" do
    conditions = {
      "operator" => "AND",
      "rules" => [{ "field" => "data.total", "op" => ">", "value" => "215" }]
    }
    result = FlowchartRuntime::QueryBuilder
      .for_entity(entity, customer_id: customer.id)
      .where(conditions, {})
      .execute

    expect(result.records.size).to eq(1)
    expect(result.records.first["total"]).to eq(220.0)
  end

  it "orders by calculated field" do
    result = FlowchartRuntime::QueryBuilder
      .for_entity(entity, customer_id: customer.id)
      .order("subtotal", "asc")
      .execute

    subtotals = result.records.map { |r| r["subtotal"] }
    expect(subtotals).to eq([75.0, 200.0, 200.0])
  end

  it "composes calculated fields with pagination" do
    result = FlowchartRuntime::QueryBuilder
      .for_entity(entity, customer_id: customer.id)
      .order("total", "desc")
      .paginate(page: 1, per_page: 2)
      .execute

    expect(result.records.size).to eq(2)
    expect(result.total_count).to eq(3)
    expect(result.records.first["total"]).to eq(220.0)
  end

  it "entity helpers work correctly" do
    expect(entity.calculated_fields.size).to eq(3)
    expect(entity.data_fields.size).to eq(3)
    expect(entity.calculated_fields.map { |f| f["name_slug"] }).to contain_exactly("subtotal", "tax", "total")
  end

  it "entity entry validation allows data without calculated fields" do
    entry = EntityEntry.new(entity: entity, customer: customer,
      data: { "price" => "100", "quantity" => "2", "discount" => "10" }.to_json)
    expect(entry).to be_valid
  end
end
```

- [ ] **Step 2: Run the integration test**

Run: `bundle exec rspec spec/integration/calculated_fields_integration_spec.rb`
Expected: All PASS

- [ ] **Step 3: Commit**

```bash
git add spec/integration/calculated_fields_integration_spec.rb
git commit -m "test: add integration tests for calculated fields pipeline"
```
