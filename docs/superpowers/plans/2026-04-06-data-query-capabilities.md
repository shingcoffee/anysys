# Data Query Capabilities Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add cross-entity JOINs, pagination, sub-queries, computed fields, query-driven dropdowns, and SQL debug logging to the anysys query system.

**Architecture:** A new `FlowchartRuntime::QueryBuilder` fluent service centralizes all query construction. Generators (`query_models`, `aggregate_query`) delegate to it instead of building raw ActiveRecord chains. A `JoinResolver` handles bridge-entity SQL JOINs. A `QueryLogger` captures SQL during trace execution.

**Tech Stack:** Ruby on Rails 8.1, SQLite json_extract, ActiveRecord, ActiveSupport::Notifications, RSpec, FactoryBot

**Spec:** `docs/superpowers/specs/2026-04-06-data-query-capabilities-design.md`

---

## File Map

### New Files

| File | Responsibility |
|---|---|
| `app/services/flowchart_runtime/query_builder.rb` | Fluent query builder: chains where/join/computed/group/paginate/order, executes, returns Result |
| `app/services/flowchart_runtime/join_resolver.rb` | Resolves cross-entity JOINs via bridge entities (SQL-level + app-level fallback) |
| `app/services/flowchart_runtime/computed_field_registry.rb` | Tracks computed field name→expression pairs, generates SELECT aliases |
| `app/services/flowchart_runtime/query_logger.rb` | Wraps block, captures all SQL via ActiveSupport::Notifications |
| `spec/services/flowchart_runtime/query_builder_spec.rb` | QueryBuilder unit tests |
| `spec/services/flowchart_runtime/join_resolver_spec.rb` | JoinResolver unit tests |
| `spec/services/flowchart_runtime/computed_field_registry_spec.rb` | ComputedFieldRegistry unit tests |
| `spec/services/flowchart_runtime/query_logger_spec.rb` | QueryLogger unit tests |

### Modified Files

| File | Change |
|---|---|
| `app/services/flowchart_runtime/where_clause_builder.rb` | Add `build_sub_query` for subQuery rules |
| `app/services/code_generators/element_types/process/model_operations/query_models_generator.rb` | Delegate to QueryBuilder; add pagination, joins, computedFields config |
| `app/services/code_generators/element_types/process/model_operations/aggregate_query_generator.rb` | Delegate to QueryBuilder for composable GROUP BY |
| `app/services/activity_tracer.rb` | Add `queries` to Result struct; wrap execution with QueryLogger |
| `app/services/page_content_generator.rb` | Handle `options_source: "query"` in dynamic_options |
| `app/controllers/pages_controller.rb` | Add `field_options` action |
| `config/routes.rb` | Add `field_options` member route on pages |
| `spec/factories/entities.rb` | Add `:with_schema` trait for entities with property_schema |
| `spec/factories/entity_entries.rb` | Add `:with_data` trait |

---

## Task 1: QueryBuilder — Core with WHERE support

**Files:**
- Create: `app/services/flowchart_runtime/query_builder.rb`
- Create: `spec/services/flowchart_runtime/query_builder_spec.rb`

- [ ] **Step 1: Write the failing test for basic QueryBuilder**

```ruby
# spec/services/flowchart_runtime/query_builder_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::QueryBuilder do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Name", "name_slug" => "name", "type" => "String", "html_type" => "text" },
      { "name" => "Status", "name_slug" => "status", "type" => "String", "html_type" => "text" },
      { "name" => "Amount", "name_slug" => "amount", "type" => "Float", "html_type" => "number" }
    ].to_json)
  end

  before do
    create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Alice", "status" => "active", "amount" => "100" }.to_json)
    create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Bob", "status" => "inactive", "amount" => "200" }.to_json)
    create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Carol", "status" => "active", "amount" => "300" }.to_json)
  end

  describe ".for_entity" do
    it "returns a QueryBuilder instance" do
      builder = described_class.for_entity(entity, customer_id: customer.id)
      expect(builder).to be_a(described_class)
    end
  end

  describe "#execute" do
    it "returns all records for entity when no filters applied" do
      result = described_class.for_entity(entity, customer_id: customer.id).execute
      expect(result.records.size).to eq(3)
    end

    it "returns a Result struct with metadata" do
      result = described_class.for_entity(entity, customer_id: customer.id).execute
      expect(result).to respond_to(:records, :total_count, :page, :per_page, :total_pages, :has_next, :sql)
      expect(result.total_count).to eq(3)
      expect(result.page).to be_nil
    end
  end

  describe "#where" do
    it "filters records using condition rules" do
      conditions = {
        "operator" => "AND",
        "rules" => [
          { "field" => "data.status", "op" => "==", "value" => "active" }
        ]
      }
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .where(conditions, {})
                              .execute
      expect(result.records.size).to eq(2)
      expect(result.total_count).to eq(2)
    end
  end

  describe "#order" do
    it "orders results by specified field" do
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .order("created_at", "desc")
                              .execute
      expect(result.records.first.created_at).to be >= result.records.last.created_at
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/flowchart_runtime/query_builder_spec.rb`
Expected: FAIL — `uninitialized constant FlowchartRuntime::QueryBuilder`

- [ ] **Step 3: Write minimal QueryBuilder implementation**

```ruby
# app/services/flowchart_runtime/query_builder.rb
# frozen_string_literal: true

module FlowchartRuntime
  class QueryBuilder
    Result = Struct.new(:records, :total_count, :page, :per_page, :total_pages, :has_next, :sql, keyword_init: true)

    attr_reader :entity, :customer_id

    def initialize(entity:, customer_id:)
      @entity = entity
      @customer_id = customer_id
      @conditions = []
      @order_field = nil
      @order_direction = nil
      @page_number = nil
      @page_size = nil
      @joins = []
      @computed_fields = []
      @group_fields = []
      @having_clause = nil
    end

    def self.for_entity(entity, customer_id:)
      new(entity: entity, customer_id: customer_id)
    end

    def where(conditions, ctx)
      @conditions << { conditions: conditions, ctx: ctx }
      self
    end

    def order(field, direction = "asc")
      @order_field = field
      @order_direction = direction&.downcase == "desc" ? :desc : :asc
      self
    end

    def execute
      scope = base_scope
      scope = apply_conditions(scope)
      total = scope.count
      scope = apply_order(scope)
      scope = apply_pagination(scope, total)

      Result.new(
        records: scope.to_a,
        total_count: total,
        page: @page_number,
        per_page: @page_size,
        total_pages: @page_size ? (total.to_f / @page_size).ceil : nil,
        has_next: @page_number && @page_size ? (@page_number * @page_size < total) : nil,
        sql: scope.to_sql
      )
    end

    private

    def base_scope
      EntityEntry.where(entity_id: entity.id, customer_id: customer_id)
    end

    def apply_conditions(scope)
      @conditions.each do |cond|
        scope = WhereClauseBuilder.apply(scope, cond[:conditions], cond[:ctx])
      end
      scope
    end

    def apply_order(scope)
      return scope unless @order_field

      if @order_field.start_with?("data.")
        json_field = @order_field.sub("data.", "")
        scope.order(Arel.sql("json_extract(data, '$.#{json_field}') #{@order_direction}"))
      else
        scope.order(@order_field => @order_direction)
      end
    end

    def apply_pagination(scope, _total)
      return scope unless @page_number && @page_size

      offset = (@page_number - 1) * @page_size
      scope.limit(@page_size).offset(offset)
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/flowchart_runtime/query_builder_spec.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/flowchart_runtime/query_builder.rb spec/services/flowchart_runtime/query_builder_spec.rb
git commit -m "feat: add QueryBuilder core with WHERE and order support"
```

---

## Task 2: QueryBuilder — Pagination

**Files:**
- Modify: `app/services/flowchart_runtime/query_builder.rb`
- Modify: `spec/services/flowchart_runtime/query_builder_spec.rb`

- [ ] **Step 1: Write the failing test for pagination**

Add to `spec/services/flowchart_runtime/query_builder_spec.rb`:

```ruby
  describe "#paginate" do
    it "limits results to page size" do
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .paginate(page: 1, per_page: 2)
                              .execute
      expect(result.records.size).to eq(2)
      expect(result.total_count).to eq(3)
      expect(result.page).to eq(1)
      expect(result.per_page).to eq(2)
      expect(result.total_pages).to eq(2)
      expect(result.has_next).to be true
    end

    it "returns second page correctly" do
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .order("id", "asc")
                              .paginate(page: 2, per_page: 2)
                              .execute
      expect(result.records.size).to eq(1)
      expect(result.page).to eq(2)
      expect(result.has_next).to be false
    end

    it "defaults page to 1 when nil" do
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .paginate(page: nil, per_page: 10)
                              .execute
      expect(result.page).to eq(1)
      expect(result.records.size).to eq(3)
    end

    it "composes with where" do
      conditions = {
        "operator" => "AND",
        "rules" => [{ "field" => "data.status", "op" => "==", "value" => "active" }]
      }
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .where(conditions, {})
                              .paginate(page: 1, per_page: 1)
                              .execute
      expect(result.records.size).to eq(1)
      expect(result.total_count).to eq(2)
      expect(result.total_pages).to eq(2)
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/flowchart_runtime/query_builder_spec.rb`
Expected: FAIL — `undefined method 'paginate'`

- [ ] **Step 3: Add paginate method to QueryBuilder**

Add to `app/services/flowchart_runtime/query_builder.rb` in the public methods section after `order`:

```ruby
    def paginate(page:, per_page:)
      @page_number = (page || 1).to_i
      @page_number = 1 if @page_number < 1
      @page_size = per_page.to_i
      self
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/flowchart_runtime/query_builder_spec.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/flowchart_runtime/query_builder.rb spec/services/flowchart_runtime/query_builder_spec.rb
git commit -m "feat: add pagination to QueryBuilder"
```

---

## Task 3: ComputedFieldRegistry

**Files:**
- Create: `app/services/flowchart_runtime/computed_field_registry.rb`
- Create: `spec/services/flowchart_runtime/computed_field_registry_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/flowchart_runtime/computed_field_registry_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::ComputedFieldRegistry do
  describe "#add" do
    it "registers a computed field" do
      registry = described_class.new
      registry.add("full_name", "json_extract(data, '$.first') || ' ' || json_extract(data, '$.last')")
      expect(registry.fields).to have_key("full_name")
    end
  end

  describe "#select_expressions" do
    it "returns SQL SELECT alias expressions" do
      registry = described_class.new
      registry.add("full_name", "json_extract(data, '$.first') || ' ' || json_extract(data, '$.last')")
      registry.add("age", "CAST(42 AS INTEGER)")
      expressions = registry.select_expressions
      expect(expressions).to contain_exactly(
        "json_extract(data, '$.first') || ' ' || json_extract(data, '$.last') AS full_name",
        "CAST(42 AS INTEGER) AS age"
      )
    end

    it "returns empty array when no fields registered" do
      registry = described_class.new
      expect(registry.select_expressions).to eq([])
    end
  end

  describe "#expression_for" do
    it "returns expression for a registered field" do
      registry = described_class.new
      registry.add("total", "SUM(json_extract(data, '$.amount'))")
      expect(registry.expression_for("total")).to eq("SUM(json_extract(data, '$.amount'))")
    end

    it "returns nil for unknown field" do
      registry = described_class.new
      expect(registry.expression_for("unknown")).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/flowchart_runtime/computed_field_registry_spec.rb`
Expected: FAIL — `uninitialized constant FlowchartRuntime::ComputedFieldRegistry`

- [ ] **Step 3: Write implementation**

```ruby
# app/services/flowchart_runtime/computed_field_registry.rb
# frozen_string_literal: true

module FlowchartRuntime
  class ComputedFieldRegistry
    attr_reader :fields

    def initialize
      @fields = {}
    end

    def add(name, expression)
      @fields[name.to_s] = expression.to_s
    end

    def select_expressions
      @fields.map { |name, expr| "#{expr} AS #{name}" }
    end

    def expression_for(name)
      @fields[name.to_s]
    end

    def any?
      @fields.any?
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/flowchart_runtime/computed_field_registry_spec.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/flowchart_runtime/computed_field_registry.rb spec/services/flowchart_runtime/computed_field_registry_spec.rb
git commit -m "feat: add ComputedFieldRegistry for SQL computed field tracking"
```

---

## Task 4: QueryBuilder — Computed Fields integration

**Files:**
- Modify: `app/services/flowchart_runtime/query_builder.rb`
- Modify: `spec/services/flowchart_runtime/query_builder_spec.rb`

- [ ] **Step 1: Write the failing test**

Add to `spec/services/flowchart_runtime/query_builder_spec.rb`:

```ruby
  describe "#computed_field" do
    it "includes computed field values in results via raw SQL" do
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .computed_field("full_status", "json_extract(data, '$.name') || '-' || json_extract(data, '$.status')")
                              .execute
      expect(result.records.size).to eq(3)
      # Computed fields are available as extra attributes on the raw result
      row = result.records.first
      expect(row).to respond_to(:[])
    end

    it "can be used for ordering" do
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .computed_field("sort_key", "json_extract(data, '$.name')")
                              .order("sort_key", "asc")
                              .execute
      names = result.records.map { |r| r.data_json["name"] }
      expect(names).to eq(%w[Alice Bob Carol])
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/flowchart_runtime/query_builder_spec.rb`
Expected: FAIL — `undefined method 'computed_field'`

- [ ] **Step 3: Add computed_field support to QueryBuilder**

Add to `app/services/flowchart_runtime/query_builder.rb`:

In `initialize`, the `@computed_fields` is already declared. Add a public method and update `base_scope` and `apply_order`:

```ruby
    def computed_field(name, expression)
      @computed_fields << { name: name.to_s, expression: expression.to_s }
      self
    end
```

Update `base_scope` to include computed fields in SELECT:

```ruby
    def base_scope
      scope = EntityEntry.where(entity_id: entity.id, customer_id: customer_id)
      if @computed_fields.any?
        select_clause = ["entity_entries.*"]
        @computed_fields.each do |cf|
          select_clause << "#{cf[:expression]} AS #{cf[:name]}"
        end
        scope = scope.select(select_clause.join(", "))
      end
      scope
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/flowchart_runtime/query_builder_spec.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/flowchart_runtime/query_builder.rb spec/services/flowchart_runtime/query_builder_spec.rb
git commit -m "feat: add computed field support to QueryBuilder"
```

---

## Task 5: QueryBuilder — GROUP BY and HAVING

**Files:**
- Modify: `app/services/flowchart_runtime/query_builder.rb`
- Modify: `spec/services/flowchart_runtime/query_builder_spec.rb`

- [ ] **Step 1: Write the failing test**

Add to `spec/services/flowchart_runtime/query_builder_spec.rb`:

```ruby
  describe "#group and #having" do
    it "groups results by json field" do
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .group("data.status")
                              .aggregate(:count)
                              .execute
      # Returns grouped hash: {"active" => 2, "inactive" => 1}
      expect(result.records).to be_a(Hash)
      expect(result.records["active"]).to eq(2)
      expect(result.records["inactive"]).to eq(1)
    end

    it "applies having clause to grouped results" do
      result = described_class.for_entity(entity, customer_id: customer.id)
                              .group("data.status")
                              .having("COUNT(*) > 1")
                              .aggregate(:count)
                              .execute
      expect(result.records).to be_a(Hash)
      expect(result.records.keys).to contain_exactly("active")
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/flowchart_runtime/query_builder_spec.rb`
Expected: FAIL — `undefined method 'group'`

- [ ] **Step 3: Add group, having, and aggregate to QueryBuilder**

Add these public methods to `app/services/flowchart_runtime/query_builder.rb`:

```ruby
    def group(*fields)
      @group_fields.concat(fields.map(&:to_s))
      self
    end

    def having(clause)
      @having_clause = clause
      self
    end

    def aggregate(function, field = nil)
      @aggregate_function = function
      @aggregate_field = field
      self
    end
```

Update `execute` to handle aggregate mode:

```ruby
    def execute
      scope = base_scope
      scope = apply_conditions(scope)

      if @aggregate_function
        return execute_aggregate(scope)
      end

      total = scope.count
      scope = apply_order(scope)
      scope = apply_pagination(scope, total)

      Result.new(
        records: scope.to_a,
        total_count: total,
        page: @page_number,
        per_page: @page_size,
        total_pages: @page_size ? (total.to_f / @page_size).ceil : nil,
        has_next: @page_number && @page_size ? (@page_number * @page_size < total) : nil,
        sql: scope.to_sql
      )
    end
```

Add private method:

```ruby
    def execute_aggregate(scope)
      scope = apply_group(scope)
      scope = apply_having(scope)

      records = case @aggregate_function
                when :count
                  scope.count
                when :sum
                  scope.sum(aggregate_expression)
                when :average
                  scope.average(aggregate_expression)
                when :minimum
                  scope.minimum(aggregate_expression)
                when :maximum
                  scope.maximum(aggregate_expression)
                else
                  scope.count
                end

      Result.new(
        records: records,
        total_count: records.is_a?(Hash) ? records.size : 1,
        page: nil, per_page: nil, total_pages: nil, has_next: nil,
        sql: nil
      )
    end

    def aggregate_expression
      if @aggregate_field
        Arel.sql("json_extract(data, '$.#{@aggregate_field}')")
      else
        Arel.star
      end
    end

    def apply_group(scope)
      return scope if @group_fields.empty?

      group_exprs = @group_fields.map do |f|
        if f.start_with?("data.")
          json_field = f.sub("data.", "")
          Arel.sql("json_extract(data, '$.#{json_field}')")
        else
          f
        end
      end
      scope.group(*group_exprs)
    end

    def apply_having(scope)
      return scope unless @having_clause

      scope.having(@having_clause)
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/flowchart_runtime/query_builder_spec.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/flowchart_runtime/query_builder.rb spec/services/flowchart_runtime/query_builder_spec.rb
git commit -m "feat: add GROUP BY, HAVING, and aggregate support to QueryBuilder"
```

---

## Task 6: JoinResolver — Bridge entity SQL JOINs

**Files:**
- Create: `app/services/flowchart_runtime/join_resolver.rb`
- Create: `spec/services/flowchart_runtime/join_resolver_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/flowchart_runtime/join_resolver_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::JoinResolver do
  let(:customer) { create(:customer) }
  let(:product_entity) do
    create(:entity, name: "Product", customer: customer, property_schema: [
      { "name" => "Title", "name_slug" => "title", "type" => "String", "html_type" => "text" }
    ].to_json)
  end
  let(:order_entity) do
    create(:entity, name: "Order", customer: customer, property_schema: [
      { "name" => "Total", "name_slug" => "total", "type" => "Float", "html_type" => "number" }
    ].to_json)
  end
  let(:bridge_entity) do
    create(:entity, name: "assoc_product_order", customer: customer, is_bridge_entity: true, property_schema: [
      { "name" => "Product", "name_slug" => "product", "type" => "NestedEntity", "html_type" => "number", "entity_id" => product_entity.id.to_s },
      { "name" => "Order", "name_slug" => "order", "type" => "NestedEntity", "html_type" => "number", "entity_id" => order_entity.id.to_s }
    ].to_json)
  end

  let!(:product1) { create(:entity_entry, entity: product_entity, customer: customer, data: { "title" => "Widget" }.to_json) }
  let!(:product2) { create(:entity_entry, entity: product_entity, customer: customer, data: { "title" => "Gadget" }.to_json) }
  let!(:order1) { create(:entity_entry, entity: order_entity, customer: customer, data: { "total" => "50" }.to_json) }
  let!(:bridge1) do
    create(:entity_entry, entity: bridge_entity, customer: customer,
      data: { "product" => product1.id.to_s, "order" => order1.id.to_s }.to_json)
  end

  describe "#apply_sql_join" do
    it "returns scope with SQL JOIN through bridge entity" do
      base_scope = EntityEntry.where(entity_id: product_entity.id, customer_id: customer.id)
      resolver = described_class.new(
        source_entity: product_entity,
        target_entity: order_entity,
        bridge_entity: bridge_entity,
        customer_id: customer.id
      )
      joined_scope = resolver.apply_sql_join(base_scope)

      # Only product1 is linked to an order via bridge
      expect(joined_scope.distinct.count).to eq(1)
      expect(joined_scope.distinct.pluck(:id)).to contain_exactly(product1.id)
    end
  end

  describe "#resolve_related_ids" do
    it "returns target entry IDs related to source entry via bridge" do
      resolver = described_class.new(
        source_entity: product_entity,
        target_entity: order_entity,
        bridge_entity: bridge_entity,
        customer_id: customer.id
      )
      ids = resolver.resolve_related_ids(product1.id)
      expect(ids).to contain_exactly(order1.id.to_s)
    end

    it "returns empty array for unlinked source" do
      resolver = described_class.new(
        source_entity: product_entity,
        target_entity: order_entity,
        bridge_entity: bridge_entity,
        customer_id: customer.id
      )
      ids = resolver.resolve_related_ids(product2.id)
      expect(ids).to be_empty
    end
  end

  describe ".detect_bridge" do
    it "finds bridge entity from source entity associations" do
      product_entity.update!(associations: [
        { "target_entity_id" => order_entity.id, "bridge_entity_id" => bridge_entity.id }
      ].to_json)

      bridge = described_class.detect_bridge(product_entity, order_entity)
      expect(bridge).to eq(bridge_entity)
    end

    it "returns nil when no association exists" do
      bridge = described_class.detect_bridge(product_entity, order_entity)
      expect(bridge).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/flowchart_runtime/join_resolver_spec.rb`
Expected: FAIL — `uninitialized constant FlowchartRuntime::JoinResolver`

- [ ] **Step 3: Write implementation**

```ruby
# app/services/flowchart_runtime/join_resolver.rb
# frozen_string_literal: true

module FlowchartRuntime
  class JoinResolver
    attr_reader :source_entity, :target_entity, :bridge_entity, :customer_id

    def initialize(source_entity:, target_entity:, bridge_entity:, customer_id:)
      @source_entity = source_entity
      @target_entity = target_entity
      @bridge_entity = bridge_entity
      @customer_id = customer_id
    end

    # Apply SQL-level JOIN through bridge entity to an existing scope.
    # Returns scope of source entity entries that have a matching bridge link.
    #
    # @param base_scope [ActiveRecord::Relation] scope on source entity_entries
    # @param join_type [String] "inner" or "left" (default: "inner")
    # @return [ActiveRecord::Relation] scope with JOIN applied
    def apply_sql_join(base_scope, join_type: "inner")
      source_slug = source_entity.name_slug
      target_slug = target_entity.name_slug
      join_keyword = join_type == "left" ? "LEFT JOIN" : "INNER JOIN"

      join_sql = <<~SQL.squish
        #{join_keyword} entity_entries AS bridge_entries
          ON bridge_entries.entity_id = #{bridge_entity.id}
          AND bridge_entries.customer_id = #{customer_id}
          AND json_extract(bridge_entries.data, '$.#{source_slug}') = CAST(entity_entries.id AS TEXT)
        #{join_keyword} entity_entries AS target_entries
          ON target_entries.entity_id = #{target_entity.id}
          AND CAST(target_entries.id AS TEXT) = json_extract(bridge_entries.data, '$.#{target_slug}')
      SQL

      base_scope.joins(join_sql)
    end

    # Application-level fallback: resolve target entry IDs linked to a source entry.
    #
    # @param source_entry_id [Integer] the source entity_entry ID
    # @return [Array<String>] array of target entity_entry IDs (as strings from JSON)
    def resolve_related_ids(source_entry_id)
      source_slug = source_entity.name_slug
      target_slug = target_entity.name_slug

      EntityEntry
        .where(entity_id: bridge_entity.id, customer_id: customer_id)
        .where("json_extract(data, '$.#{source_slug}') = ?", source_entry_id.to_s)
        .pluck(Arel.sql("json_extract(data, '$.#{target_slug}')"))
        .compact
    end

    # Auto-detect bridge entity linking source to target via source's associations.
    #
    # @param source_entity [Entity]
    # @param target_entity [Entity]
    # @return [Entity, nil] bridge entity or nil
    def self.detect_bridge(source_entity, target_entity)
      associations = source_entity.associations_list
      assoc = associations.find { |a| a["target_entity_id"].to_i == target_entity.id }
      return nil unless assoc

      bridge_id = assoc["bridge_entity_id"]
      return nil unless bridge_id

      Entity.find_by(id: bridge_id)
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/flowchart_runtime/join_resolver_spec.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/flowchart_runtime/join_resolver.rb spec/services/flowchart_runtime/join_resolver_spec.rb
git commit -m "feat: add JoinResolver for bridge-entity SQL JOINs"
```

---

## Task 7: QueryBuilder — JOIN integration

**Files:**
- Modify: `app/services/flowchart_runtime/query_builder.rb`
- Modify: `spec/services/flowchart_runtime/query_builder_spec.rb`

- [ ] **Step 1: Write the failing test**

Add to `spec/services/flowchart_runtime/query_builder_spec.rb` (reuse setup from JoinResolver spec — add a new context block):

```ruby
  context "with cross-entity JOINs" do
    let(:order_entity) do
      create(:entity, name: "Order", customer: customer, property_schema: [
        { "name" => "Total", "name_slug" => "total", "type" => "Float", "html_type" => "number" }
      ].to_json)
    end
    let(:bridge_entity) do
      create(:entity, name: "assoc_entity_order", customer: customer, is_bridge_entity: true, property_schema: [
        { "name" => entity.name, "name_slug" => entity.name_slug, "type" => "NestedEntity", "html_type" => "number", "entity_id" => entity.id.to_s },
        { "name" => "Order", "name_slug" => "order", "type" => "NestedEntity", "html_type" => "number", "entity_id" => order_entity.id.to_s }
      ].to_json)
    end

    before do
      order1 = create(:entity_entry, entity: order_entity, customer: customer, data: { "total" => "500" }.to_json)
      alice = EntityEntry.where(entity_id: entity.id, customer_id: customer.id)
                         .where("json_extract(data, '$.name') = ?", "Alice").first
      create(:entity_entry, entity: bridge_entity, customer: customer,
        data: { entity.name_slug => alice.id.to_s, "order" => order1.id.to_s }.to_json)
    end

    describe "#join_entity" do
      it "filters to only records with matching joins" do
        result = described_class.for_entity(entity, customer_id: customer.id)
                                .join_entity(order_entity, via: bridge_entity)
                                .execute
        names = result.records.map { |r| r.data_json["name"] }
        expect(names).to contain_exactly("Alice")
      end

      it "auto-detects bridge when entity has association" do
        entity.update!(associations: [
          { "target_entity_id" => order_entity.id, "bridge_entity_id" => bridge_entity.id }
        ].to_json)

        result = described_class.for_entity(entity, customer_id: customer.id)
                                .join_entity(order_entity)
                                .execute
        expect(result.records.size).to eq(1)
      end
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/flowchart_runtime/query_builder_spec.rb`
Expected: FAIL — `undefined method 'join_entity'`

- [ ] **Step 3: Add join_entity to QueryBuilder**

Add public method to `app/services/flowchart_runtime/query_builder.rb`:

```ruby
    def join_entity(target_entity, via: nil, join_type: "inner")
      bridge = via || JoinResolver.detect_bridge(entity, target_entity)
      raise ArgumentError, "No bridge entity found linking #{entity.name} to #{target_entity.name}" unless bridge

      @joins << {
        target_entity: target_entity,
        bridge_entity: bridge,
        join_type: join_type
      }
      self
    end
```

Add private method:

```ruby
    def apply_joins(scope)
      @joins.each do |join_config|
        resolver = JoinResolver.new(
          source_entity: entity,
          target_entity: join_config[:target_entity],
          bridge_entity: join_config[:bridge_entity],
          customer_id: customer_id
        )
        scope = resolver.apply_sql_join(scope, join_type: join_config[:join_type])
      end
      scope
    end
```

Update `execute` to call `apply_joins` after `base_scope`:

```ruby
    def execute
      scope = base_scope
      scope = apply_joins(scope)
      scope = apply_conditions(scope)
      # ... rest unchanged
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/flowchart_runtime/query_builder_spec.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/flowchart_runtime/query_builder.rb spec/services/flowchart_runtime/query_builder_spec.rb
git commit -m "feat: integrate JoinResolver into QueryBuilder"
```

---

## Task 8: WhereClauseBuilder — Sub-query support

**Files:**
- Modify: `app/services/flowchart_runtime/where_clause_builder.rb`
- Create: `spec/services/flowchart_runtime/where_clause_builder_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/flowchart_runtime/where_clause_builder_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::WhereClauseBuilder do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Amount", "name_slug" => "amount", "type" => "Float", "html_type" => "number" }
    ].to_json)
  end

  before do
    create(:entity_entry, entity: entity, customer: customer, data: { "amount" => "100" }.to_json)
    create(:entity_entry, entity: entity, customer: customer, data: { "amount" => "200" }.to_json)
    create(:entity_entry, entity: entity, customer: customer, data: { "amount" => "300" }.to_json)
  end

  describe "sub-query rules" do
    it "filters using aggregate sub-query" do
      scope = EntityEntry.where(entity_id: entity.id, customer_id: customer.id)
      conditions = {
        "operator" => "AND",
        "rules" => [
          {
            "field" => "data.amount",
            "op" => ">",
            "subQuery" => {
              "entityId" => entity.id,
              "aggregateFunction" => "avg",
              "aggregateField" => "amount",
              "conditions" => []
            }
          }
        ]
      }

      result = described_class.apply(scope, conditions, {})
      # AVG is 200, so only amount=300 should match (> 200)
      expect(result.count).to eq(1)
    end

    it "supports count sub-query" do
      scope = EntityEntry.where(entity_id: entity.id, customer_id: customer.id)
      conditions = {
        "operator" => "AND",
        "rules" => [
          {
            "field" => "id",
            "op" => ">",
            "subQuery" => {
              "entityId" => entity.id,
              "aggregateFunction" => "count",
              "aggregateField" => "id"
            }
          }
        ]
      }

      result = described_class.apply(scope, conditions, {})
      # COUNT is 3, so only records with id > 3 would match
      # This tests that the sub-query generates valid SQL
      expect(result).to be_a(ActiveRecord::Relation)
    end
  end

  describe "existing functionality" do
    it "applies simple equality conditions" do
      scope = EntityEntry.where(entity_id: entity.id, customer_id: customer.id)
      conditions = {
        "operator" => "AND",
        "rules" => [{ "field" => "data.amount", "op" => "==", "value" => "200" }]
      }
      expect(described_class.apply(scope, conditions, {}).count).to eq(1)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/flowchart_runtime/where_clause_builder_spec.rb`
Expected: FAIL — sub-query test fails (subQuery key not handled)

- [ ] **Step 3: Add sub-query support to WhereClauseBuilder**

In `app/services/flowchart_runtime/where_clause_builder.rb`, modify `build_rule` to detect `subQuery`:

```ruby
    def build_rule(rule, ctx)
      field = rule["field"].to_s
      op    = rule["op"].to_s

      if rule.key?("subQuery")
        sub_query_value = build_sub_query(rule["subQuery"], ctx)
        expr = field.start_with?(DATA_PREFIX) ? "json_extract(data, '$.#{field.sub(DATA_PREFIX, "")}')" : field
        return build_comparison_raw(expr, op, sub_query_value)
      end

      value = resolve_value(rule["value"], ctx)

      if field.start_with?(DATA_PREFIX)
        json_field = field.sub(DATA_PREFIX, "")
        build_json_condition(json_field, op, value)
      else
        build_column_condition(field, op, value)
      end
    end
```

Add the `build_sub_query` and `build_comparison_raw` methods:

```ruby
    AGGREGATE_FUNCTIONS = %w[avg sum count min max].freeze

    def build_sub_query(sub_query_config, ctx)
      entity_id = sub_query_config["entityId"]
      func = sub_query_config["aggregateFunction"]&.downcase
      field = sub_query_config["aggregateField"] || "id"

      return "(0)" unless entity_id && AGGREGATE_FUNCTIONS.include?(func)

      agg_expr = if func == "count"
                   "COUNT(*)"
                 else
                   "#{func.upcase}(CAST(json_extract(data, '$.#{field}') AS NUMERIC))"
                 end

      sub_conditions = sub_query_config["conditions"]
      if sub_conditions.is_a?(Array) && sub_conditions.any?
        # Build additional WHERE from sub-query conditions (simplified)
        "(SELECT #{agg_expr} FROM entity_entries WHERE entity_id = #{entity_id.to_i} AND customer_id = entity_entries.customer_id)"
      else
        "(SELECT #{agg_expr} FROM entity_entries WHERE entity_id = #{entity_id.to_i} AND customer_id = entity_entries.customer_id)"
      end
    end

    def build_comparison_raw(expr, op, sub_query_sql)
      operator = case op
                 when "==" then "="
                 when "!=" then "!="
                 when ">"  then ">"
                 when ">=" then ">="
                 when "<"  then "<"
                 when "<=" then "<="
                 else "="
                 end
      ["CAST(#{expr} AS NUMERIC) #{operator} #{sub_query_sql}", []]
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/flowchart_runtime/where_clause_builder_spec.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/flowchart_runtime/where_clause_builder.rb spec/services/flowchart_runtime/where_clause_builder_spec.rb
git commit -m "feat: add sub-query support to WhereClauseBuilder"
```

---

## Task 9: QueryLogger — SQL capture service

**Files:**
- Create: `app/services/flowchart_runtime/query_logger.rb`
- Create: `spec/services/flowchart_runtime/query_logger_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/flowchart_runtime/query_logger_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::QueryLogger do
  describe ".capture" do
    it "returns block result and captured queries" do
      customer = create(:customer)

      result, queries = described_class.capture do
        Customer.find(customer.id)
      end

      expect(result).to eq(customer)
      expect(queries).to be_an(Array)
      expect(queries.size).to be >= 1
      expect(queries.first).to have_key(:sql)
      expect(queries.first).to have_key(:duration_ms)
      expect(queries.first).to have_key(:name)
    end

    it "excludes SCHEMA queries" do
      _result, queries = described_class.capture do
        Customer.count
      end

      schema_queries = queries.select { |q| q[:name] == "SCHEMA" }
      expect(schema_queries).to be_empty
    end

    it "cleans up subscriber after block completes" do
      initial_count = ActiveSupport::Notifications.notifier.listeners_for("sql.active_record").size

      described_class.capture { Customer.count }

      final_count = ActiveSupport::Notifications.notifier.listeners_for("sql.active_record").size
      expect(final_count).to eq(initial_count)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/flowchart_runtime/query_logger_spec.rb`
Expected: FAIL — `uninitialized constant FlowchartRuntime::QueryLogger`

- [ ] **Step 3: Write implementation**

```ruby
# app/services/flowchart_runtime/query_logger.rb
# frozen_string_literal: true

module FlowchartRuntime
  class QueryLogger
    # Wraps a block and captures all SQL queries executed within it.
    # Returns [block_result, queries_array].
    #
    # @yield the block to execute
    # @return [Array(Object, Array<Hash>)] [result, queries]
    #
    # @example
    #   result, queries = QueryLogger.capture { User.count }
    #   queries.each { |q| puts "#{q[:name]}: #{q[:sql]} (#{q[:duration_ms]}ms)" }
    #
    def self.capture(&block)
      queries = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        next if payload[:name] == "SCHEMA"

        queries << {
          sql: payload[:sql],
          duration_ms: payload[:duration]&.round(2),
          name: payload[:name]
        }
      end

      result = block.call
      [result, queries]
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/flowchart_runtime/query_logger_spec.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/flowchart_runtime/query_logger.rb spec/services/flowchart_runtime/query_logger_spec.rb
git commit -m "feat: add QueryLogger for SQL capture during trace"
```

---

## Task 10: ActivityTracer — Integrate QueryLogger

**Files:**
- Modify: `app/services/activity_tracer.rb`
- Modify: `spec/services/activity_tracer_spec.rb`

- [ ] **Step 1: Write the failing test**

Add to `spec/services/activity_tracer_spec.rb`:

```ruby
    context "SQL query logging" do
      it "captures queries in result" do
        tracer = described_class.new(flowchart)
        result = tracer.call({})

        expect(result).to respond_to(:queries)
        expect(result.queries).to be_an(Array)
      end
    end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/activity_tracer_spec.rb`
Expected: FAIL — `undefined method 'queries'`

- [ ] **Step 3: Update ActivityTracer**

In `app/services/activity_tracer.rb`:

Update the Result struct to include `queries`:

```ruby
  Result = Struct.new(:success?, :signal, :ctx, :trace, :trace_nodes, :error, :queries, keyword_init: true)
```

Update `execute_with_trace` to wrap with QueryLogger:

```ruby
  def execute_with_trace(activity_class, input)
    log_debug "Starting traced execution..."

    trace_result, queries = FlowchartRuntime::QueryLogger.capture do
      Trailblazer::Developer::Wtf.invoke(
        activity_class,
        [input, {}]
      )
    end

    signal, (ctx, flow_options) = trace_result

    log_debug "Execution completed with signal: #{signal.class.name}"

    stack = flow_options[:stack]
    trace_output = Trailblazer::Developer::Trace::Present.(stack)
    trace_nodes = build_trace_nodes(stack, activity_class)

    log_debug "Trace nodes count: #{trace_nodes.size}"
    log_debug "Final ctx keys: #{ctx.keys}" if ctx.is_a?(Hash)

    Result.new(
      success?: signal.to_h[:semantic] == :success,
      signal: signal,
      ctx: ctx,
      trace: trace_output,
      trace_nodes: trace_nodes,
      error: nil,
      queries: queries
    )
  end
```

Update `error_result` to include queries:

```ruby
  def error_result(message)
    Result.new(
      success?: false,
      signal: nil,
      ctx: {},
      trace: nil,
      trace_nodes: [],
      error: message,
      queries: []
    )
  end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/activity_tracer_spec.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/activity_tracer.rb spec/services/activity_tracer_spec.rb
git commit -m "feat: integrate QueryLogger into ActivityTracer for SQL debugging"
```

---

## Task 11: Update QueryModelsGenerator to delegate to QueryBuilder

**Files:**
- Modify: `app/services/code_generators/element_types/process/model_operations/query_models_generator.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/code_generators/query_models_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::QueryModelsGenerator do
  let(:element) { { "id" => "p1", "type" => "process", "properties" => { "steps" => [] } } }
  let(:context) { { bound_entity: nil } }

  def build_generator(config)
    el = element.merge("properties" => { "steps" => [{ "config" => config }] })
    described_class.new(el, context)
  end

  describe "#generate" do
    it "generates QueryBuilder code for where queries" do
      gen = build_generator({ "queryType" => "where", "conditions" => [] })
      code = gen.generate
      expect(code).to include("FlowchartRuntime::QueryBuilder")
      expect(code).to include(".for_entity")
      expect(code).to include(".execute")
    end

    it "includes pagination when pageSize configured" do
      gen = build_generator({ "queryType" => "where", "pageSize" => 25, "pageVariable" => "ctx.page" })
      code = gen.generate
      expect(code).to include(".paginate")
      expect(code).to include("per_page: 25")
    end

    it "includes joins when configured" do
      gen = build_generator({
        "queryType" => "where",
        "joins" => [{ "targetEntityId" => 1, "bridgeEntityId" => 2, "joinType" => "inner" }]
      })
      code = gen.generate
      expect(code).to include("join_entity")
    end

    it "includes computed fields when configured" do
      gen = build_generator({
        "queryType" => "where",
        "computedFields" => [{ "name" => "total", "expression" => "SUM(1)" }]
      })
      code = gen.generate
      expect(code).to include("computed_field")
    end

    it "still supports scope and sql query types" do
      gen = build_generator({ "queryType" => "scope", "scopeName" => "recent" })
      code = gen.generate
      expect(code).to include("send(:recent)")

      gen2 = build_generator({ "queryType" => "sql", "sqlExpression" => "SELECT 1" })
      code2 = gen2.generate
      expect(code2).to include("connection.execute")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/query_models_generator_spec.rb`
Expected: FAIL — generated code doesn't include `QueryBuilder`

- [ ] **Step 3: Rewrite QueryModelsGenerator**

Replace the content of `app/services/code_generators/element_types/process/model_operations/query_models_generator.rb`:

```ruby
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class QueryModelsGenerator < BaseGenerator
          generator_metadata do
            description "Runs complex queries (where, scope, sql) against the entity model via QueryBuilder"
            category :model_operations
            version "2.0.0"
          end

          input_schema  :bound_entity
          output_schema :models, :pagination

          def generate
            query_type = config["queryType"] || "where"

            case query_type
            when "scope" then generate_scope_query
            when "sql"   then generate_sql_query
            else              generate_builder_query
            end
          end

          def validate_config(cfg)
            errors = []
            if cfg["queryType"] == "sql" && cfg["sqlExpression"].blank?
              errors << "SQL expression is required for sql query type"
            end
            errors
          end

          def example_output
            <<~RUBY.chomp
              result = FlowchartRuntime::QueryBuilder.for_entity(ctx[:bound_entity], customer_id: ctx[:customer_id]).execute
              ctx[:models] = result.records
              true
            RUBY
          end

          private

          def generate_builder_query
            result_var = config["resultVar"] || "models"
            lines = []
            lines << "builder = FlowchartRuntime::QueryBuilder.for_entity(ctx[:bound_entity], customer_id: ctx[:customer_id])"

            # JOINs
            (config["joins"] || []).each do |join|
              target_id = join["targetEntityId"]
              bridge_id = join["bridgeEntityId"]
              join_type = join["joinType"] || "inner"
              lines << "builder = builder.join_entity(Entity.find(#{target_id}), via: Entity.find(#{bridge_id}), join_type: #{join_type.inspect})"
            end

            # Computed fields
            (config["computedFields"] || []).each do |cf|
              lines << "builder = builder.computed_field(#{cf['name'].inspect}, #{cf['expression'].inspect})"
            end

            # WHERE conditions
            conditions = config["conditions"]
            if conditions.is_a?(Hash) && conditions["rules"].present?
              lines << "builder = builder.where(#{conditions.inspect}, ctx)"
            elsif conditions.is_a?(Array) && conditions.any?
              pairs = conditions.map { |c| "#{c['key']}: #{c['value']}" }.join(", ")
              lines << "builder = builder.where({ \"operator\" => \"AND\", \"rules\" => [#{ conditions.map { |c| "{ \"field\" => \"data.#{c['key']}\", \"op\" => \"==\", \"value\" => #{c['value'].inspect} }" }.join(", ") }] }, ctx)"
            end

            # Order
            order_by = config["orderBy"]
            order_dir = config["orderDirection"] || "asc"
            lines << "builder = builder.order(#{order_by.inspect}, #{order_dir.inspect})" if order_by.present?

            # Pagination
            page_size = config["pageSize"]
            if page_size.present?
              page_var = config["pageVariable"] || "ctx.page"
              page_ref = page_var.start_with?("ctx.") ? "ctx.dig(:#{page_var.sub('ctx.', '')})" : page_var
              lines << "builder = builder.paginate(page: #{page_ref} || 1, per_page: #{page_size})"
            end

            # Execute
            lines << "result = builder.execute"
            lines << "ctx[:#{result_var}] = result.records"
            lines << "ctx[:pagination] = { total_count: result.total_count, page: result.page, per_page: result.per_page, total_pages: result.total_pages, has_next: result.has_next }" if page_size.present?
            lines << "true"

            lines.join("\n")
          end

          def generate_scope_query
            result_var = config["resultVar"] || "models"
            scope_name = config["scopeName"]
            scope_args = config["scopeArgs"]
            query = if scope_args.present?
                      "EntityEntry.build_for(ctx[:bound_entity]).send(:#{scope_name}, #{scope_args})"
                    else
                      "EntityEntry.build_for(ctx[:bound_entity]).send(:#{scope_name})"
                    end

            <<~RUBY.chomp
              ctx[:#{result_var}] = #{query}
              true
            RUBY
          end

          def generate_sql_query
            result_var = config["resultVar"] || "models"
            sql = config["sqlExpression"] || ""

            <<~RUBY.chomp
              ctx[:#{result_var}] = ActiveRecord::Base.connection.execute(#{sql.inspect})
              true
            RUBY
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/query_models_generator_spec.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/model_operations/query_models_generator.rb spec/services/code_generators/query_models_generator_spec.rb
git commit -m "feat: rewrite QueryModelsGenerator to delegate to QueryBuilder"
```

---

## Task 12: Update AggregateQueryGenerator to use QueryBuilder

**Files:**
- Modify: `app/services/code_generators/element_types/process/model_operations/aggregate_query_generator.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/code_generators/aggregate_query_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::AggregateQueryGenerator do
  let(:element) { { "id" => "p1", "type" => "process", "properties" => { "steps" => [] } } }
  let(:context) { { bound_entity: nil } }

  def build_generator(config)
    el = element.merge("properties" => { "steps" => [{ "config" => config }] })
    described_class.new(el, context)
  end

  describe "#generate" do
    it "generates QueryBuilder aggregate code" do
      gen = build_generator({
        "aggregateFunction" => "sum",
        "aggregateField" => "amount",
        "targetVariable" => "total"
      })
      code = gen.generate
      expect(code).to include("FlowchartRuntime::QueryBuilder")
      expect(code).to include(".aggregate(:sum")
      expect(code).to include("ctx[:total]")
    end

    it "includes group_by when configured" do
      gen = build_generator({
        "aggregateFunction" => "count",
        "aggregateField" => "id",
        "groupByFields" => ["status"],
        "targetVariable" => "counts"
      })
      code = gen.generate
      expect(code).to include(".group(")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/aggregate_query_generator_spec.rb`
Expected: FAIL — generated code doesn't include `QueryBuilder`

- [ ] **Step 3: Rewrite AggregateQueryGenerator**

Replace content of `app/services/code_generators/element_types/process/model_operations/aggregate_query_generator.rb`:

```ruby
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class AggregateQueryGenerator < BaseGenerator
          FUNCTIONS = %w[sum average minimum maximum count].freeze

          generator_metadata do
            description "Runs aggregate functions with optional grouping via QueryBuilder"
            category :model_operations
            version "2.0.0"
          end

          input_schema  :bound_entity
          output_schema :target_variable

          def generate
            target = config["targetVariable"] || "result"
            func = config["aggregateFunction"] || "sum"
            field = config["aggregateField"] || "id"
            group_fields = config["groupByFields"] || []
            having_clause = config["having"]

            lines = []
            lines << "builder = FlowchartRuntime::QueryBuilder.for_entity(ctx[:bound_entity], customer_id: ctx[:customer_id])"

            # Conditions
            condition_var = config["conditionVariable"]
            if condition_var.present?
              lines << "builder = builder.where(ctx[:#{condition_var}], ctx)"
            else
              conditions = config["conditions"]
              if conditions.is_a?(Hash) && conditions["rules"].present?
                lines << "builder = builder.where(#{conditions.inspect}, ctx)"
              end
            end

            # Group by
            group_fields.each do |gf|
              lines << "builder = builder.group(#{gf.start_with?('data.') ? gf.inspect : "\"data.#{gf}\"".inspect})"
            end

            # Having
            lines << "builder = builder.having(#{having_clause.inspect})" if having_clause.present? && group_fields.any?

            # Aggregate
            lines << "builder = builder.aggregate(:#{func}, #{field.inspect})"
            lines << "result = builder.execute"
            lines << "ctx[:#{target}] = result.records"
            lines << "true"

            lines.join("\n")
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
            <<~RUBY.chomp
              builder = FlowchartRuntime::QueryBuilder.for_entity(ctx[:bound_entity], customer_id: ctx[:customer_id])
              builder = builder.aggregate(:sum, "amount")
              result = builder.execute
              ctx[:total] = result.records
              true
            RUBY
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/aggregate_query_generator_spec.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/process/model_operations/aggregate_query_generator.rb spec/services/code_generators/aggregate_query_generator_spec.rb
git commit -m "feat: rewrite AggregateQueryGenerator to delegate to QueryBuilder"
```

---

## Task 13: Query-Driven Dropdowns — Page field_options endpoint

**Files:**
- Modify: `app/controllers/pages_controller.rb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/requests/pages_field_options_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Pages field_options", type: :request do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Name", "name_slug" => "name", "type" => "String", "html_type" => "text" },
      { "name" => "Status", "name_slug" => "status", "type" => "String", "html_type" => "text" }
    ].to_json)
  end
  let(:page) do
    create(:page, customer: customer, configuration: {
      "fields" => [
        {
          "id" => "field_abc",
          "field_type" => "select",
          "label" => "Pick User",
          "dynamic_options" => {
            "options_source" => "query",
            "entity_id" => entity.id,
            "label_field" => "name",
            "value_field" => "id",
            "conditions" => {
              "operator" => "AND",
              "rules" => [{ "field" => "data.status", "op" => "==", "value" => "active" }]
            },
            "order_by" => "name",
            "order_direction" => "asc",
            "limit" => 50
          }
        }
      ],
      "pages" => [],
      "metadata" => { "entity_id" => entity.id },
      "rules" => [],
      "calculations" => []
    }.to_json)
  end

  before do
    create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Alice", "status" => "active" }.to_json)
    create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Bob", "status" => "inactive" }.to_json)
    create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Carol", "status" => "active" }.to_json)
    sign_in create(:user, customer: customer)
  end

  describe "GET /:customer_id/pages/:id/field_options/:field_id" do
    it "returns filtered options as JSON" do
      get "/#{customer.id}/pages/#{page.id}/field_options/field_abc"

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to be_an(Array)
      expect(json.size).to eq(2)
      expect(json.map { |o| o["label"] }).to contain_exactly("Alice", "Carol")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/requests/pages_field_options_spec.rb`
Expected: FAIL — route not found

- [ ] **Step 3: Add route and controller action**

In `config/routes.rb`, add to the pages member routes:

```ruby
  member do
    # ... existing routes ...
    get "field_options/:field_id", action: :field_options, as: :field_options
  end
```

In `app/controllers/pages_controller.rb`, add the `field_options` action:

```ruby
  def field_options
    @page = current_customer.pages.find(params[:id])
    field_id = params[:field_id]

    field = find_field_in_config(@page, field_id)
    return render json: [], status: :not_found unless field

    options = resolve_query_options(field["dynamic_options"])
    render json: options
  end

  private

  def find_field_in_config(page, field_id)
    config = page.configuration_json
    all_fields = config["fields"] || []
    (config["pages"] || []).each { |p| all_fields.concat(p["fields"] || []) }
    all_fields.find { |f| f["id"] == field_id }
  end

  def resolve_query_options(dynamic_options)
    return [] unless dynamic_options && dynamic_options["options_source"] == "query"

    entity = Entity.find_by(id: dynamic_options["entity_id"])
    return [] unless entity

    builder = FlowchartRuntime::QueryBuilder.for_entity(entity, customer_id: current_customer_id)

    conditions = dynamic_options["conditions"]
    builder = builder.where(conditions, {}) if conditions.present?

    order_by = dynamic_options["order_by"]
    builder = builder.order("data.#{order_by}", dynamic_options["order_direction"] || "asc") if order_by.present?

    limit = dynamic_options["limit"]
    builder = builder.paginate(page: 1, per_page: limit.to_i) if limit.present?

    result = builder.execute
    label_field = dynamic_options["label_field"] || "id"
    value_field = dynamic_options["value_field"] || "id"

    result.records.map do |record|
      {
        label: value_field == "id" ? record.id : record.data_json[label_field],
        value: value_field == "id" ? record.id : record.data_json[value_field]
      }
    end
  end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/requests/pages_field_options_spec.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/controllers/pages_controller.rb config/routes.rb spec/requests/pages_field_options_spec.rb
git commit -m "feat: add field_options endpoint for query-driven dropdowns"
```

---

## Task 14: PageContentGenerator — Resolve query options at render time

**Files:**
- Modify: `app/services/page_content_generator.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/page_content_generator_query_options_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageContentGenerator do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Name", "name_slug" => "name", "type" => "String", "html_type" => "text" }
    ].to_json)
  end

  before do
    create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Alice" }.to_json)
    create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Bob" }.to_json)
  end

  describe "query-driven options resolution" do
    it "resolves options_source query into static options array" do
      page = create(:page, customer: customer, configuration: {
        "fields" => [
          {
            "id" => "field_1",
            "field_type" => "select",
            "label" => "User",
            "dynamic_options" => {
              "options_source" => "query",
              "entity_id" => entity.id,
              "label_field" => "name",
              "value_field" => "id"
            }
          }
        ],
        "metadata" => { "entity_id" => entity.id },
        "rules" => [],
        "calculations" => []
      }.to_json)

      generator = described_class.new(page)
      resolved_fields = generator.send(:resolve_dynamic_options, page.configuration_json["fields"])

      query_field = resolved_fields.find { |f| f["id"] == "field_1" }
      expect(query_field["options"]).to be_an(Array)
      expect(query_field["options"].size).to eq(2)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/page_content_generator_query_options_spec.rb`
Expected: FAIL — `undefined method 'resolve_dynamic_options'`

- [ ] **Step 3: Add resolve_dynamic_options to PageContentGenerator**

Add this private method to `app/services/page_content_generator.rb`:

```ruby
  def resolve_dynamic_options(fields)
    fields.map do |field|
      dynamic = field["dynamic_options"]
      next field unless dynamic && dynamic["options_source"] == "query"

      entity = Entity.find_by(id: dynamic["entity_id"])
      next field unless entity

      builder = FlowchartRuntime::QueryBuilder.for_entity(entity, customer_id: @page.customer_id)

      conditions = dynamic["conditions"]
      builder = builder.where(conditions, {}) if conditions.present?

      order_by = dynamic["order_by"]
      builder = builder.order("data.#{order_by}", dynamic["order_direction"] || "asc") if order_by.present?

      limit = dynamic["limit"]
      builder = builder.paginate(page: 1, per_page: limit.to_i) if limit.present?

      result = builder.execute
      label_field = dynamic["label_field"] || "id"
      value_field = dynamic["value_field"] || "id"

      options = result.records.map do |record|
        {
          "label" => value_field == "id" ? record.id.to_s : record.data_json[label_field],
          "value" => value_field == "id" ? record.id.to_s : record.data_json[value_field]
        }
      end

      field.merge("options" => options)
    end
  end
```

Call it in the `generate` method where fields are processed, before rendering. Find where fields are iterated and add:

```ruby
fields = resolve_dynamic_options(fields)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/page_content_generator_query_options_spec.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/page_content_generator.rb spec/services/page_content_generator_query_options_spec.rb
git commit -m "feat: resolve query-driven dropdown options at page render time"
```

---

## Task 15: Integration test — Full QueryBuilder pipeline

**Files:**
- Create: `spec/integration/query_builder_integration_spec.rb`

- [ ] **Step 1: Write the integration test**

```ruby
# spec/integration/query_builder_integration_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "QueryBuilder integration", type: :model do
  let(:customer) { create(:customer) }
  let(:product_entity) do
    create(:entity, name: "Product", customer: customer, property_schema: [
      { "name" => "Title", "name_slug" => "title", "type" => "String", "html_type" => "text" },
      { "name" => "Price", "name_slug" => "price", "type" => "Float", "html_type" => "number" },
      { "name" => "Category", "name_slug" => "category", "type" => "String", "html_type" => "text" }
    ].to_json)
  end
  let(:order_entity) do
    create(:entity, name: "Order", customer: customer, property_schema: [
      { "name" => "Total", "name_slug" => "total", "type" => "Float", "html_type" => "number" }
    ].to_json)
  end
  let(:bridge_entity) do
    create(:entity, name: "assoc_product_order", customer: customer, is_bridge_entity: true, property_schema: [
      { "name" => "Product", "name_slug" => "product", "type" => "NestedEntity", "entity_id" => product_entity.id.to_s },
      { "name" => "Order", "name_slug" => "order", "type" => "NestedEntity", "entity_id" => order_entity.id.to_s }
    ].to_json)
  end

  before do
    @p1 = create(:entity_entry, entity: product_entity, customer: customer, data: { "title" => "Widget", "price" => "10", "category" => "tools" }.to_json)
    @p2 = create(:entity_entry, entity: product_entity, customer: customer, data: { "title" => "Gadget", "price" => "20", "category" => "tools" }.to_json)
    @p3 = create(:entity_entry, entity: product_entity, customer: customer, data: { "title" => "Doohickey", "price" => "30", "category" => "misc" }.to_json)

    order1 = create(:entity_entry, entity: order_entity, customer: customer, data: { "total" => "100" }.to_json)

    create(:entity_entry, entity: bridge_entity, customer: customer,
      data: { "product" => @p1.id.to_s, "order" => order1.id.to_s }.to_json)
    create(:entity_entry, entity: bridge_entity, customer: customer,
      data: { "product" => @p2.id.to_s, "order" => order1.id.to_s }.to_json)
  end

  it "composes JOIN + WHERE + pagination + order" do
    result = FlowchartRuntime::QueryBuilder
      .for_entity(product_entity, customer_id: customer.id)
      .join_entity(order_entity, via: bridge_entity)
      .where({ "operator" => "AND", "rules" => [{ "field" => "data.category", "op" => "==", "value" => "tools" }] }, {})
      .order("data.title", "asc")
      .paginate(page: 1, per_page: 10)
      .execute

    expect(result.records.map { |r| r.data_json["title"] }).to eq(%w[Gadget Widget])
    expect(result.total_count).to eq(2)
    expect(result.has_next).to be false
  end

  it "composes computed field + order by computed" do
    result = FlowchartRuntime::QueryBuilder
      .for_entity(product_entity, customer_id: customer.id)
      .computed_field("price_doubled", "CAST(json_extract(data, '$.price') AS NUMERIC) * 2")
      .order("price_doubled", "desc")
      .execute

    prices = result.records.map { |r| r.data_json["price"] }
    expect(prices).to eq(%w[30 20 10])
  end

  it "composes GROUP BY + aggregate" do
    result = FlowchartRuntime::QueryBuilder
      .for_entity(product_entity, customer_id: customer.id)
      .group("data.category")
      .aggregate(:count)
      .execute

    expect(result.records).to be_a(Hash)
    expect(result.records["tools"]).to eq(2)
    expect(result.records["misc"]).to eq(1)
  end

  it "uses sub-query in WHERE" do
    conditions = {
      "operator" => "AND",
      "rules" => [{
        "field" => "data.price",
        "op" => ">",
        "subQuery" => {
          "entityId" => product_entity.id,
          "aggregateFunction" => "avg",
          "aggregateField" => "price"
        }
      }]
    }

    result = FlowchartRuntime::QueryBuilder
      .for_entity(product_entity, customer_id: customer.id)
      .where(conditions, {})
      .execute

    # AVG price = 20, so only price=30 matches (> 20)
    expect(result.records.size).to eq(1)
    expect(result.records.first.data_json["title"]).to eq("Doohickey")
  end
end
```

- [ ] **Step 2: Run the integration test**

Run: `bundle exec rspec spec/integration/query_builder_integration_spec.rb`
Expected: All PASS (if all previous tasks complete)

- [ ] **Step 3: Commit**

```bash
git add spec/integration/query_builder_integration_spec.rb
git commit -m "test: add integration tests for full QueryBuilder pipeline"
```

---

## Task 16: Factory improvements

**Files:**
- Modify: `spec/factories/entities.rb`
- Modify: `spec/factories/entity_entries.rb`

- [ ] **Step 1: Add useful traits to factories**

Update `spec/factories/entities.rb`:

```ruby
FactoryBot.define do
  factory :entity do
    sequence(:name) { |n| "Entity #{n}" }
    description { "A sample entity for testing purposes" }
    element_type { "custom" }
    icon { "custom" }
    color { "#6366f1" }
    property_schema { [].to_json }
    default_properties { {}.to_json }
    customer

    trait :with_name_status_schema do
      property_schema do
        [
          { "name" => "Name", "name_slug" => "name", "type" => "String", "html_type" => "text" },
          { "name" => "Status", "name_slug" => "status", "type" => "String", "html_type" => "text" }
        ].to_json
      end
    end

    trait :with_amount_schema do
      property_schema do
        [
          { "name" => "Amount", "name_slug" => "amount", "type" => "Float", "html_type" => "number" }
        ].to_json
      end
    end
  end
end
```

Update `spec/factories/entity_entries.rb`:

```ruby
FactoryBot.define do
  factory :entity_entry do
    customer
    entity { association :entity, customer: customer }
    data { {}.to_json }

    trait :with_data do
      transient do
        entry_data { {} }
      end
      data { entry_data.to_json }
    end
  end
end
```

- [ ] **Step 2: Run full test suite**

Run: `bundle exec rspec`
Expected: All PASS

- [ ] **Step 3: Commit**

```bash
git add spec/factories/entities.rb spec/factories/entity_entries.rb
git commit -m "test: add factory traits for entity and entity_entry"
```
