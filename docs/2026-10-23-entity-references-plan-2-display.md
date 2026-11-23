# Entity References Implementation Plan (Plan 2 of 3): Showing Values

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The entries list, the CSV export, the detail drawer and member surfaces show what a person would read:

- option labels;
- referenced records' names;
- computed and calculated values, counted correctly;
- yes/no.

They no longer show raw option codes, ids and dashes.

**Architecture:** One expression source, `Entities::DerivedExpressions`, feeds three consumers:

- the flowchart query builder;
- the entries-list sort;
- a new one-query loader, `Entities::DerivedValues`, which replaces `Entities::ComputedLoader` and fixes the uncast id comparison (P1).

`Entities::EntryDisplay` turns stored and derived values into text for one audience. It preloads a page of entries in one pass, and every surface goes through it.

**Tech Stack:** Rails 8.1.2, Ruby 3.2.8, ViewComponent, RSpec, SQLite `json_extract`.

**Spec:** `docs/2026-10-23-entity-references-display-lifecycle-design.md`. This plan covers §4, the `seats_remaining` part of §7, the Plan 2 rows of §9 and §10, and the Plan 1 deferral of `seats_remaining`.

**Depends on:** Plan 1 (`docs/2026-10-23-entity-references-plan-1-references.md`). Plan 2 uses `Entities::ReferenceLabels` and `Entities::ReferenceOptions`, and Plan 1's rewrite of the Course example. Plan 1 must be in the working tree. Plan 3 (`docs/2026-10-23-entity-references-plan-3-forms.md`) can run in parallel with this plan.

## Global Constraints

- No hard-coded user-facing strings. This plan adds no locale keys; it reuses `common.labels.{em_dash,yes,no}` and `common.references.*`.
- No backward-compatibility shims. `ComputedLoader`, `ComputedDefinition#loader_sql`, `EntityEntry#computed_values` and `#prime_computed_values!` are deleted outright (Task 6).
- Do NOT run `git commit`. Leave changes in the working tree. `git add -N <new file>` is allowed.
- Only edit files your task owns (see the table below). If a file outside your task needs a change, stop and report it.
- Ignore `app/services/page_layout_templates/templates/**`.
- RSpec isolation: each task uses its own database, `TEST_ENV_NUMBER=<40 + task number>`. Prepare it once with `RAILS_ENV=test TEST_ENV_NUMBER=<n> bin/rails db:schema:load`, then run `TEST_ENV_NUMBER=<n> bundle exec rspec <files>`.
- Never claim tests pass without pasting the real command output.
- Subagents inherit the parent model: omit `model` (or pass `inherit`).
- Docs change in the same plan. Task 7 owns every `doc/reference/**` edit for Plan 2.
- No layout or styling changes. Components change only the text they print, so there is no shadcn consultation in this plan.

## Waves and file ownership

| Wave | Task | Agent | Owns |
|---|---|---|---|
| 1 | T1 Derived expressions and values | anysys-backend-developer | `app/services/entities/{derived_expressions,derived_values,computed_compiler}.rb`, `app/services/flowchart_runtime/query_builder.rb` (`inject_calculated_fields` only), `app/models/entity_entry.rb`, `spec/services/entities/{derived_expressions,derived_values,computed_compiler}_spec.rb` |
| 2 | T2 Entry display and member readers | anysys-backend-developer | `app/services/entities/entry_display.rb`, `app/services/entities/reference_options.rb` (`#labels`), `app/models/entity_entry.rb`, `app/services/member/{entity_surface_builder,surface_template_applier}.rb`, `spec/services/entities/{entry_display,reference_options}_spec.rb`, `spec/services/member/{entity_surface_builder,surface_template_applier}_spec.rb` |
| 3 | T3 Entries-list columns | anysys-backend-developer | `app/services/admin/entities/columns_builder.rb`, `app/concepts/entity_index_settings/operation/update.rb`, `spec/services/admin/entities/{columns_builder,entries_csv}_spec.rb`, `spec/components/admin/entities/entries_table_component_spec.rb`, `spec/concepts/entity_index_settings/operation/update_spec.rb` |
| 3 | T4 Detail drawer and column picker | anysys-frontend-developer | `app/components/admin/entities/{entry_detail,column_picker}_component.rb`, `app/views/admin/entity_entries/show.html.erb`, `spec/components/admin/entities/{entry_detail,column_picker}_component_spec.rb` |
| 4 | T5 Controllers | anysys-security-engineer | `app/controllers/admin/entities_controller.rb`, `app/controllers/admin/entity_entries_controller.rb` (`show` only), `app/controllers/member/surfaces_controller.rb`, `spec/requests/admin/entities_spec.rb`, `spec/requests/admin/entity_entries_spec.rb`, `spec/requests/member/surfaces_spec.rb` |
| 5 | T6 Remove the computed loader; `seats_remaining` example | anysys-backend-developer | delete `app/services/entities/computed_loader.rb` and `spec/services/entities/computed_loader_spec.rb`; `app/services/entities/computed_definition.rb`, `app/models/entity_entry.rb`, `spec/services/entities/computed_definition_spec.rb`, `spec/models/entity_entry_spec.rb`, `spec/integration/computed_fields_integration_spec.rb`, `app/services/ai_assistant/assistant/prompt/documents/entity_examples.md` |
| 5 | T7 Plan 2 docs | anysys-backend-developer | `doc/reference/{en,zh-CN}/entity-builder.md` and any other `doc/reference/**` hit of the removed names |
| 6 | T8 Verification | anysys-release-engineer | nothing (runs commands only) |

Why the waves are ordered this way:

- The old loader keeps working until T6, so every wave leaves the suite green except for one gap. T4 passes `display: @display` from `admin/entity_entries/show.html.erb`, and T5 sets `@display` in the next wave. Between the two, the entry-show request specs fail. T4 runs only component specs, and T5 runs the request specs.
- T3 owns `entries_table_component_spec.rb` because it calls `ColumnsBuilder.call`, whose signature T3 changes.

## Spec coverage

| Spec | Task |
|---|---|
| §4.1 `DerivedExpressions`, used by `QueryBuilder`, the list sort and `DerivedValues` | T1, T3 |
| §4.2 `DerivedValues`, `prime!`, `derived_values`; `ComputedLoader` and `loader_sql` removed | T1, T6 |
| §4.3 `EntryDisplay` table | T2 |
| §4.4 Entities list, CSV, detail drawer | T3, T4, T5 |
| §4.4 Member surfaces | T2 (readers), T5 (controller) |
| §7 `seats_remaining` example and reply | T6 |
| §9 `entity-builder`: list, CSV and detail display, calculated columns | T7 |
| §10 `DerivedExpressions`, `DerivedValues` (P1 regression, calculated reads computed, broken formula), `EntryDisplay`, components | T1, T2, T3, T4, T5 |

Six decisions apply the spec:

- **Checkbox columns become text columns.** Their cells now return "Yes" or "No" as text, but the table renders `:boolean` cells as `value ? yes : no`, so "No" would show as "Yes". A checkbox group with options becomes its option labels.
- **Member columns read display text only for the `:string` and `:number` formats.** Dates and money keep the stored value, because `Member::Formatters` calls `I18n.l` or formats cents on it.
- **The display is attached to each entry.** Member descriptor lambdas receive only the entry. `EntryDisplay.prime!` attaches the display to each entry, and `EntityEntry#display_text` reads it. Without a primed display, `display_text` returns the raw stored or derived value, which is the same as today.
- **`EntryDisplay#text` is defined for the entries it was built with.** Derived values for other entries still resolve on demand. Reference labels are preloaded only for those entries.
- **The entries list takes derived SQL for the session tenant.** It passes `customer_id: current_customer.id` to `DerivedExpressions`, instead of `@entity.customer_id`, so sorting and display read the same tenant's rows.
- **Calculated fields join the column picker and the saved column preference**, next to computed fields.

---

### Task 1: Derived expressions and values

**Agent:** anysys-backend-developer

**Files:**
- Create: `app/services/entities/derived_expressions.rb`
- Create: `app/services/entities/derived_values.rb`
- Modify: `app/services/entities/computed_compiler.rb`
- Modify: `app/services/flowchart_runtime/query_builder.rb` (`inject_calculated_fields`)
- Modify: `app/models/entity_entry.rb`. Add `derived_values` and `prime_derived_values!`; leave `computed_values` in place until T6.
- Create: `spec/services/entities/derived_expressions_spec.rb`, `spec/services/entities/derived_values_spec.rb`
- Modify: `spec/services/entities/computed_compiler_spec.rb`

**Interfaces:**
- Produces:
  - `ComputedCompiler.compile_all` returns `[{ name:, sql:, definition: }]`.
  - `Entities::DerivedExpressions.for(entity, customer_id:)` returns `[{ name:, sql:, kind: :computed | :calculated, definition: (computed only) }]`.
  - `Entities::DerivedValues.call(entity:, customer_id:, entry_ids:)` returns `{ Integer => { slug => value } }`.
  - `Entities::DerivedValues.prime!(entries, customer_id:)`.
  - `EntityEntry#derived_values` and `#prime_derived_values!(hash)`.

- [ ] **Step 1: Prepare the test database**

Run: `RAILS_ENV=test TEST_ENV_NUMBER=41 bin/rails db:schema:load`

- [ ] **Step 2: Write the failing expressions spec**

Create `spec/services/entities/derived_expressions_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::DerivedExpressions do
  let_it_be(:customer) { create(:customer) }
  let!(:student) { create(:entity, name: "Student", customer: customer) }
  let!(:klass) { create(:entity, name: "Class", customer: customer) }
  let!(:bridge) do
    create(:entity, name: "assoc_student_class", customer: customer, category: :bridge, property_schema: [
      { "name" => "Student", "name_slug" => "student", "type" => "EntityReference", "entity_id" => student.id.to_s },
      { "name" => "Class", "name_slug" => "class", "type" => "EntityReference", "entity_id" => klass.id.to_s },
      { "name" => "Score", "name_slug" => "score", "type" => "Float", "html_type" => "number" }
    ].to_json)
  end

  let(:average) do
    { "name" => "Average", "name_slug" => "average_score", "type" => "Computed",
      "config" => { "bridge_entity_id" => bridge.id, "bridge_role" => "source", "source_slug" => "score", "function" => "avg" } }
  end

  def calculated(slug, formula)
    { "name" => slug.titleize, "name_slug" => slug, "type" => "Calculated", "html_type" => "number", "formula" => formula }
  end

  def with_schema(*fields)
    student.property_schema_json = fields
    student.save(validate: false)
    student.reload
  end

  def expressions = described_class.for(student, customer_id: customer.id)

  it "lists computed subqueries, then calculated formulas that may read them" do
    with_schema(average, calculated("double_average", "average_score * 2"))

    expect(expressions.map { |row| [row[:name], row[:kind]] }).to eq([["average_score", :computed], ["double_average", :calculated]])
    computed_sql = expressions.first[:sql]
    expect(expressions.first[:definition]).to be_a(Entities::ComputedDefinition)
    expect(expressions.last[:sql]).to include("(#{computed_sql})")
  end

  it "drops every calculated field when a formula does not compile, keeping computed ones" do
    with_schema(average, calculated("broken", "average_score +"))

    expect(expressions.map { |row| row[:name] }).to eq(%w[average_score])
  end

  it "drops a computed field that does not resolve and a name that is not a safe alias" do
    with_schema(average.merge("config" => { "bridge_entity_id" => 0 }), calculated("bad-name", "1 + 1"))

    expect(expressions).to eq([])
  end

  it "is empty for a nil entity or an entity without derived fields" do
    expect(described_class.for(nil, customer_id: customer.id)).to eq([])
    expect(described_class.for(klass, customer_id: customer.id)).to eq([])
  end
end
```

Run: `TEST_ENV_NUMBER=41 bundle exec rspec spec/services/entities/derived_expressions_spec.rb`
Expected: FAIL with `uninitialized constant Entities::DerivedExpressions`.

- [ ] **Step 3: `compile_all` carries the definition**

In `app/services/entities/computed_compiler.rb`, replace `compile_all` and `compile` with:

```ruby
    # => [{ name: "average_score", sql: "(SELECT ...)" or nil, definition: ComputedDefinition or nil }, ...]
    def self.compile_all(entity, customer_id:)
      Array(entity&.computed_fields).each_with_index.map do |field, idx|
        definition = ComputedDefinition.resolve(field, entity, customer_id: customer_id)
        { name: field["name_slug"].to_s, sql: subquery(definition, "b#{idx}"), definition: definition }
      end
    end

    # => "(SELECT ...)" or nil. Never raises.
    def self.compile(computed_field, entity, customer_id:, table_alias: "b0")
      subquery(ComputedDefinition.resolve(computed_field, entity, customer_id: customer_id), table_alias)
    end

    def self.subquery(definition, table_alias)
      definition&.subquery_sql(safe_table_alias(table_alias))
    rescue StandardError
      nil
    end
    private_class_method :subquery
```

In `spec/services/entities/computed_compiler_spec.rb`, in "never raises for a nil entity or malformed fields", change `{ name: "broken", sql: nil }` to `{ name: "broken", sql: nil, definition: nil }`.

- [ ] **Step 4: Implement `Entities::DerivedExpressions`**

Create `app/services/entities/derived_expressions.rb`:

```ruby
# frozen_string_literal: true

module Entities
  # The SQL of an entity's derived fields for one tenant: computed (bridge
  # aggregate) subqueries, then calculated formulas that may read them.
  # FlowchartRuntime::QueryBuilder, the entries-list sort and DerivedValues all
  # use it, so a value sorts, filters and displays the same way everywhere.
  module DerivedExpressions
    SAFE_NAME = FlowchartRuntime::QueryBuilder::SAFE_ALIAS_RE

    module_function

    # => [{ name:, sql:, kind: :computed | :calculated, definition: (computed only) }]
    def for(entity, customer_id:)
      return [] if entity.nil?

      computed = ComputedCompiler.compile_all(entity, customer_id: customer_id)
                                 .select { |row| usable?(row) }
                                 .map { |row| row.merge(kind: :computed) }
      computed + calculated(entity, computed.to_h { |row| [row[:name], row[:sql]] })
    end

    # A malformed formula degrades to "no calculated fields" rather than
    # failing the read; only the compiler's own error is absorbed.
    def calculated(entity, resolved)
      schema = Array(entity.property_schema_json).grep(Hash)
      FlowchartRuntime::FormulaCompiler.compile_all(schema, resolved: resolved)
                                       .select { |row| usable?(row) }
                                       .map { |row| row.merge(kind: :calculated) }
    rescue FlowchartRuntime::FormulaError
      []
    end

    def usable?(row)
      row[:sql].present? && SAFE_NAME.match?(row[:name].to_s)
    end
  end
end
```

- [ ] **Step 5: `QueryBuilder` reads the same expressions**

In `app/services/flowchart_runtime/query_builder.rb`, replace `inject_calculated_fields` with:

```ruby
    def inject_calculated_fields
      return if @entity.nil? || @calculated_injected

      ::Entities::DerivedExpressions.for(@entity, customer_id: customer_id).each { |expression| register_computed_field(expression) }
      @calculated_injected = true
    end
```

Run: `TEST_ENV_NUMBER=41 bundle exec rspec spec/services/entities/derived_expressions_spec.rb spec/services/entities/computed_compiler_spec.rb spec/services/flowchart_runtime/query_builder_spec.rb spec/services/flowchart_runtime/formula_compiler_spec.rb`
Expected: all pass. That includes "degrades to no calculated fields when FormulaCompiler.compile_all raises" and "keeps the error boundary narrow…".

- [ ] **Step 6: Write the failing values spec**

Create `spec/services/entities/derived_values_spec.rb`. It reuses the bridge setup of the current `computed_loader_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::DerivedValues do
  let_it_be(:customer) { create(:customer) }
  let!(:student) { create(:entity, name: "Student", customer: customer) }
  let!(:klass) { create(:entity, name: "Class", customer: customer) }
  let!(:bridge) do
    create(:entity, name: "assoc_student_class", customer: customer, category: :bridge, property_schema: [
      { "name" => "Student", "name_slug" => "student", "type" => "EntityReference", "entity_id" => student.id.to_s },
      { "name" => "Class", "name_slug" => "class", "type" => "EntityReference", "entity_id" => klass.id.to_s },
      { "name" => "Score", "name_slug" => "score", "type" => "Float", "html_type" => "number" }
    ].to_json)
  end
  let!(:john) { create(:entity_entry, entity: student, customer: customer, data: {}.to_json) }
  let!(:jane) { create(:entity_entry, entity: student, customer: customer, data: {}.to_json) }
  let!(:empty) { create(:entity_entry, entity: student, customer: customer, data: {}.to_json) }
  let!(:math) { create(:entity_entry, entity: klass, customer: customer, data: {}.to_json) }

  def enroll(pupil_id, score:, owner: customer)
    create(:entity_entry, entity: bridge, customer: owner,
                          data: { "student" => pupil_id, "class" => math.id.to_s, "score" => score.to_s }.to_json)
  end

  def computed(slug, function, source_slug: "score")
    { "name" => slug.titleize, "name_slug" => slug, "type" => "Computed",
      "config" => { "bridge_entity_id" => bridge.id, "bridge_role" => "source", "source_slug" => source_slug,
                    "function" => function, "precision" => 2 } }
  end

  def calculated(slug, formula)
    { "name" => slug.titleize, "name_slug" => slug, "type" => "Calculated", "html_type" => "number", "formula" => formula }
  end

  def with_schema(*fields)
    student.property_schema_json = fields
    student.save(validate: false)
    student.reload
  end

  def load_for(*entries) = described_class.call(entity: student.reload, customer_id: customer.id, entry_ids: entries.map(&:id))

  def value_queries(&block)
    sqls = []
    subscriber = ->(*, payload) { sqls << payload[:sql].to_s if payload[:sql].to_s.match?(/\ASELECT "entity_entries"\."id", /) }
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record", &block)
    sqls
  end

  before do
    enroll(john.id.to_s, score: 90)
    enroll(john.id.to_s, score: 85)
    enroll(jane.id.to_s, score: 80)
  end

  it "counts a link whose parent id is stored as a JSON number (P1)" do
    with_schema(computed("enrolments", "count", source_slug: ""))
    enroll(jane.id, score: 70)

    expect(load_for(jane)[jane.id]["enrolments"]).to eq(2)
  end

  it "keeps today's coercion and empty defaults" do
    with_schema(computed("average_score", "avg"), computed("lowest", "min"), computed("total_score", "sum"),
                computed("enrolments", "count", source_slug: ""))

    result = load_for(john, empty)
    expect(result[john.id]).to eq("average_score" => 87.5, "lowest" => 85.0, "total_score" => 175.0, "enrolments" => 2)
    expect(result[empty.id]).to eq("average_score" => nil, "lowest" => nil, "total_score" => 0, "enrolments" => 0)
  end

  it "returns a calculated field that reads a computed one" do
    with_schema(computed("average_score", "avg"), calculated("double_average", "average_score * 2"))

    expect(load_for(john)[john.id]["double_average"]).to eq(175.0)
  end

  it "leaves calculated values blank when a formula does not compile" do
    with_schema(computed("average_score", "avg"), calculated("broken", "average_score +"))

    expect(load_for(john)[john.id]).to eq("average_score" => 87.5, "broken" => nil)
  end

  it "uses the definition's default for a computed field that does not resolve" do
    with_schema(computed("enrolments", "count").merge("config" => { "function" => "count" }),
                computed("odd", "avg").merge("config" => "nope"))

    expect(load_for(john)[john.id]).to eq("enrolments" => 0, "odd" => nil)
  end

  it "never counts another tenant's link rows" do
    with_schema(computed("enrolments", "count", source_slug: ""))
    enroll(john.id.to_s, score: 10, owner: create(:customer))

    expect(load_for(john)[john.id]["enrolments"]).to eq(2)
  end

  it "reads any number of entries in one query" do
    with_schema(computed("average_score", "avg"), computed("total_score", "sum"), calculated("double_average", "average_score * 2"))
    many = [john, jane, empty] + Array.new(5) { create(:entity_entry, entity: student, customer: customer, data: {}.to_json) }

    expect(value_queries { load_for(*many) }.size).to eq(1)
  end

  it "returns {} for no ids or a nil entity, and empty hashes without derived fields" do
    expect(described_class.call(entity: student, customer_id: customer.id, entry_ids: [])).to eq({})
    expect(described_class.call(entity: nil, customer_id: customer.id, entry_ids: [john.id])).to eq({})
    expect(load_for(john)).to eq(john.id => {})
  end

  describe ".prime!" do
    it "memoizes values on each entry of the tenant and skips the rest" do
      with_schema(computed("average_score", "avg"))
      fresh = EntityEntry.find(john.id)
      foreign = create(:entity_entry, entity: student, customer: create(:customer), data: {}.to_json)

      described_class.prime!([fresh, "skip", foreign], customer_id: customer.id)

      expect(value_queries { expect(fresh.derived_values["average_score"]).to eq(87.5) }).to eq([])
      expect(foreign.instance_variable_get(:@derived_values)).to be_nil
      expect { described_class.prime!(nil, customer_id: customer.id) }.not_to raise_error
    end
  end

  describe "EntityEntry#derived_values" do
    it "resolves a lone entry in one query" do
      with_schema(computed("average_score", "avg"), calculated("double_average", "average_score * 2"))

      expect(EntityEntry.find(john.id).derived_values).to eq("average_score" => 87.5, "double_average" => 175.0)
    end
  end
end
```

Run: `TEST_ENV_NUMBER=41 bundle exec rspec spec/services/entities/derived_values_spec.rb`
Expected: FAIL with `uninitialized constant Entities::DerivedValues`.

- [ ] **Step 7: Implement `Entities::DerivedValues`**

Create `app/services/entities/derived_values.rb`:

```ruby
# frozen_string_literal: true

module Entities
  # Derived (computed and calculated) values of an entity's entries for one
  # tenant, in one query for any number of entries. It selects the same
  # DerivedExpressions SQL the entries list sorts by, so a link stored with a
  # numeric parent id counts the same in both.
  module DerivedValues
    module_function

    # => { entry_id => { slug => value } } for every requested id.
    def call(entity:, customer_id:, entry_ids:)
      ids = Array(entry_ids).map(&:to_i).uniq
      return {} if ids.empty? || entity.nil?

      fields = entity.computed_fields + entity.calculated_fields
      return ids.index_with { {} } if fields.empty?

      expressions = DerivedExpressions.for(entity, customer_id: customer_id)
      defaults = fields.to_h { |field| [field["name_slug"].to_s, empty_default(field, expressions)] }
      result = ids.index_with { defaults.dup }
      return result if expressions.empty?

      EntityEntry.where(customer_id: customer_id, entity_id: entity.id, id: ids)
                 .pluck(:id, *expressions.map { |expression| Arel.sql(expression[:sql]) })
                 .each do |id, *values|
                   expressions.zip(values).each { |expression, raw| result[id][expression[:name]] = coerce(raw, expression) }
                 end
      result
    end

    # One query per entity for the entries of the tenant; other records and
    # other tenants' rows are skipped.
    def prime!(entries, customer_id:)
      cid = customer_id.to_i
      Array(entries).grep(EntityEntry).select { |entry| entry.customer_id.to_i == cid }
                    .group_by(&:entity_id).each_value do |group|
        values = call(entity: group.first.entity, customer_id: cid, entry_ids: group.map(&:id))
        group.each { |entry| entry.prime_derived_values!(values.fetch(entry.id, {})) }
      end
    end

    # Count is an integer and other aggregates are floats; calculated values
    # stay as SQLite returns them.
    def coerce(raw, expression)
      return raw unless expression[:kind] == :computed

      definition = expression[:definition]
      return definition.empty_default if raw.nil?
      return raw.to_i if definition.function == "count"

      Float(raw)
    rescue ArgumentError, TypeError
      raw
    end

    def empty_default(field, expressions)
      return unless field["type"] == Entity::COMPUTED_TYPE

      definition = expressions.find { |expression| expression[:name] == field["name_slug"].to_s }&.dig(:definition)
      return definition.empty_default if definition

      config = field["config"]
      %w[sum count].include?(config.is_a?(Hash) ? config["function"].to_s : "") ? 0 : nil
    end
  end
end
```

- [ ] **Step 8: `EntityEntry#derived_values`**

In `app/models/entity_entry.rb`, above `prime_computed_values!`, add:

```ruby
  # Derived (computed and calculated) values for this entry, never stored in
  # `data`. List paths call Entities::DerivedValues.prime! first so this is a
  # hash lookup; a lone record resolves here in one query.
  def prime_derived_values!(hash)
    @derived_values = hash.is_a?(Hash) ? hash : {}
  end

  def derived_values
    @derived_values ||= if entity.nil? || id.nil?
      {}
    else
      Entities::DerivedValues.call(entity: entity, customer_id: customer_id, entry_ids: [id]).fetch(id, {})
    end
  end
```

- [ ] **Step 9: Run the task's specs**

Run: `TEST_ENV_NUMBER=41 bundle exec rspec spec/services/entities spec/services/flowchart_runtime spec/models/entity_entry_spec.rb spec/integration/computed_fields_integration_spec.rb`
Expected: all pass. The old loader is still in place, so its specs pass too.

- [ ] **Step 10: Leave the changes uncommitted**

Run: `git add -N app/services/entities/derived_expressions.rb app/services/entities/derived_values.rb spec/services/entities/derived_expressions_spec.rb spec/services/entities/derived_values_spec.rb && git status --short`. Do not commit.

---

### Task 2: Entry display and member readers

**Agent:** anysys-backend-developer

**Files:**
- Create: `app/services/entities/entry_display.rb`
- Create: `spec/services/entities/entry_display_spec.rb`
- Modify: `app/services/entities/reference_options.rb` (add `#labels`) and `spec/services/entities/reference_options_spec.rb`
- Modify: `app/models/entity_entry.rb` (add `prime_display!` and `display_text`)
- Modify: `app/services/member/entity_surface_builder.rb`, `app/services/member/surface_template_applier.rb`
- Modify: `spec/services/member/entity_surface_builder_spec.rb`, `spec/services/member/surface_template_applier_spec.rb`

**Interfaces:**
- Consumes: `Entities::DerivedValues.prime!` and `EntityEntry#derived_values` (T1); `Entities::ReferenceLabels` and `Entities::ReferenceOptions` (Plan 1).
- Produces:
  - `Entities::EntryDisplay.new(entity:, entries:, customer_id:, audience:)` and `#text(entry, slug)`, which returns a String.
  - `Entities::EntryDisplay.prime!(entries, customer_id:, audience:)`.
  - `ReferenceOptions#labels(ids)`, which returns `{ id_string => raw_label }`, or nil when the display field can't label for the audience.
  - `EntityEntry#prime_display!(display)` and `#display_text(slug)`.

- [ ] **Step 1: Prepare the test database**

Run: `RAILS_ENV=test TEST_ENV_NUMBER=42 bin/rails db:schema:load`

- [ ] **Step 2: Write the failing `ReferenceOptions#labels` examples**

Append to `spec/services/entities/reference_options_spec.rb`, inside the top-level `describe`:

```ruby
  describe "#labels" do
    def source(audience: EntityAttributeAudience::PUBLIC, label_field: "code")
      described_class.new(entity_id: student.id, label_field: label_field, customer_id: customer.id, audience: audience)
    end

    it "maps the given ids of the tenant's records to their raw labels" do
      ada = entry("code" => "Ada")
      untitled = entry({})
      foreign = entry({ "code" => "X" }, owner: other_customer)

      expect(source.labels([ada.id, untitled.id.to_s, foreign.id, "abc", ""])).to eq(ada.id.to_s => "Ada", untitled.id.to_s => nil)
      expect(source.labels([])).to eq({})
    end

    it "is nil when the display field can't label for the audience" do
      expect(source(label_field: "phone").labels([1])).to be_nil
      expect(source(label_field: "bio", audience: EntityAttributeAudience::ADMIN).labels([1])).to be_nil
    end
  end
```

Run: `TEST_ENV_NUMBER=42 bundle exec rspec spec/services/entities/reference_options_spec.rb`
Expected: FAIL with `undefined method 'labels'`.

In `app/services/entities/reference_options.rb`, after `#label_taken?`, add:

```ruby
    # { id string => raw label } for the given ids that are records of the
    # target in this tenant, or nil when the display field can't label them
    # for the audience.
    def labels(ids)
      return unless usable?

      wanted = Array(ids).map(&:to_s).select { |id| id.match?(ID) }.uniq
      return {} if wanted.empty?

      entries.where(id: wanted).pluck(:id, Arel.sql(label_sql)).to_h { |id, raw| [id.to_s, raw] }
    rescue ActiveRecord::StatementInvalid
      {}
    end
```

Run the spec again. Expected: PASS.

- [ ] **Step 3: Write the failing `EntryDisplay` spec**

Create `spec/services/entities/entry_display_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::EntryDisplay do
  let_it_be(:customer) { create(:customer) }
  let(:em_dash) { I18n.t("common.labels.em_dash") }
  let(:admin_only) { { "admin" => true, "member" => false, "public" => false } }

  let!(:instructor) do
    create(:entity, customer: customer, name: "Instructor", property_schema: [
      { "name" => "Name", "name_slug" => "name", "html_type" => "text" },
      { "name" => "Badge", "name_slug" => "badge", "html_type" => "text", "visibility" => admin_only }
    ].to_json)
  end
  let!(:jenny) { create(:entity_entry, customer: customer, entity: instructor, data: { name: "Jenny", badge: "J1" }.to_json) }
  let!(:unnamed) { create(:entity_entry, customer: customer, entity: instructor, data: {}.to_json) }

  def reference(slug, label_field: "name", html_type: "select")
    { "name" => slug.titleize, "name_slug" => slug, "html_type" => html_type,
      "config" => { "options_source" => "entity_entries", "entity_id" => instructor.id.to_s, "label_field" => label_field } }
  end

  let!(:course) do
    create(:entity, customer: customer, name: "Course", property_schema: [
      { "name" => "Title", "name_slug" => "title", "html_type" => "text" },
      { "name" => "Mode", "name_slug" => "mode", "html_type" => "select",
        "config" => { "options" => [{ "label" => "In person", "value" => "in_person" }] } },
      { "name" => "Tags", "name_slug" => "tags", "html_type" => "checkbox",
        "config" => { "options" => [{ "label" => "Lab", "value" => "lab" }, { "label" => "Field", "value" => "field" }] } },
      { "name" => "Active", "name_slug" => "active", "html_type" => "checkbox" },
      { "name" => "Starts", "name_slug" => "starts_on", "html_type" => "date" },
      { "name" => "Seats", "name_slug" => "seats", "html_type" => "number" },
      { "name" => "Double seats", "name_slug" => "double_seats", "type" => "Calculated", "html_type" => "number",
        "formula" => "seats * 2" },
      reference("instructor"),
      reference("assistant", label_field: "badge")
    ].to_json)
  end

  def build(data, audience: EntityAttributeAudience::ADMIN)
    entry = create(:entity_entry, customer: customer, entity: course, data: data.to_json)
    [described_class.new(entity: course, entries: [entry], customer_id: customer.id, audience: audience), entry]
  end

  it "shows the em dash for blank values" do
    display, entry = build("title" => "", "tags" => [])
    expect(%w[title tags mode instructor].map { |slug| display.text(entry, slug) }).to all(eq(em_dash))
  end

  it "shows static option labels, joining several, and the value when no option matches" do
    display, entry = build("mode" => "in_person", "tags" => %w[lab field])
    expect(display.text(entry, "mode")).to eq("In person")
    expect(display.text(entry, "tags")).to eq("Lab, Field")

    display, entry = build("mode" => "remote")
    expect(display.text(entry, "mode")).to eq("remote")
  end

  it "labels references, names missing records and falls back to Untitled" do
    display, entry = build("instructor" => jenny.id.to_s)
    expect(display.text(entry, "instructor")).to eq("Jenny")

    display, entry = build("instructor" => unnamed.id.to_s)
    expect(display.text(entry, "instructor")).to eq("Untitled (##{unnamed.id})")

    display, entry = build("instructor" => "999999")
    expect(display.text(entry, "instructor")).to eq("Missing record (#999999)")
  end

  it "keeps the raw id when the display field is hidden from the audience" do
    display, entry = build({ "assistant" => jenny.id.to_s }, audience: EntityAttributeAudience::MEMBER)
    expect(display.text(entry, "assistant")).to eq(jenny.id.to_s)

    display, entry = build({ "assistant" => jenny.id.to_s })
    expect(display.text(entry, "assistant")).to eq("J1")
  end

  it "never numbers duplicate labels" do
    twin = create(:entity_entry, customer: customer, entity: instructor, data: { name: "Jenny" }.to_json)
    display, entry = build("instructor" => twin.id.to_s)
    expect(display.text(entry, "instructor")).to eq("Jenny")
  end

  it "shows derived values" do
    display, entry = build("seats" => 12)
    expect(display.text(entry, "double_seats")).to eq("24")
  end

  it "shows yes and no for a checkbox without options" do
    display, entry = build("active" => true)
    expect(display.text(entry, "active")).to eq(I18n.t("common.labels.yes"))

    display, entry = build("active" => "false")
    expect(display.text(entry, "active")).to eq(I18n.t("common.labels.no"))
  end

  it "shows dates, numbers and unknown slugs as stored" do
    display, entry = build("starts_on" => "2026-11-02", "seats" => 12)
    expect(display.text(entry, "starts_on")).to eq("2026-11-02")
    expect(display.text(entry, "seats")).to eq("12")

    # EntityEntry rejects keys outside the schema, so the unknown slug is stubbed in.
    allow(entry).to receive(:data_json).and_return(entry.data_json.merge("legacy" => "x"))
    expect(display.text(entry, "legacy")).to eq("x")
  end

  it "preloads a page: one label query per reference field, however many entries" do
    entries = Array.new(4) { create(:entity_entry, customer: customer, entity: course, data: { "instructor" => jenny.id.to_s }.to_json) }
    display = described_class.new(entity: course, entries: entries, customer_id: customer.id, audience: EntityAttributeAudience::ADMIN)
    queries = []
    subscriber = ->(*, payload) { queries << payload[:sql] if payload[:sql].to_s.include?("json_extract(entity_entries.data") }

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      entries.each { |entry| display.text(entry, "instructor") }
    end
    expect(queries.size).to eq(1)
  end

  describe ".prime! and EntityEntry#display_text" do
    it "attaches one display per entity to the tenant's entries" do
      entry = create(:entity_entry, customer: customer, entity: course, data: { "mode" => "in_person" }.to_json)
      foreign = create(:entity_entry, customer: create(:customer), entity: course, data: { "mode" => "in_person" }.to_json)

      described_class.prime!([entry, foreign, "skip"], customer_id: customer.id, audience: EntityAttributeAudience::ADMIN)

      expect(entry.display_text("mode")).to eq("In person")
      expect(foreign.display_text("mode")).to eq("in_person")
    end
  end
end
```

Run: `TEST_ENV_NUMBER=42 bundle exec rspec spec/services/entities/entry_display_spec.rb`
Expected: FAIL with `uninitialized constant Entities::EntryDisplay`.

- [ ] **Step 4: Implement `Entities::EntryDisplay`**

Create `app/services/entities/entry_display.rb`:

```ruby
# frozen_string_literal: true

module Entities
  # Display text for an entity's entries as one audience may see it: option
  # labels, referenced records' labels, derived values and yes/no instead of
  # stored codes and ids. Built for a page of entries, it loads their derived
  # values in one query and each reference field's labels in one query.
  class EntryDisplay
    BOOLEAN_TYPES = %w[checkbox switch].freeze

    # Attaches a display to each of the tenant's entries, one per entity, for
    # readers that only see the entry (EntityEntry#display_text).
    def self.prime!(entries, customer_id:, audience:)
      cid = customer_id.to_i
      Array(entries).grep(EntityEntry).select { |entry| entry.customer_id.to_i == cid }
                    .group_by(&:entity_id).each_value do |group|
        entity = group.first.entity
        next unless entity

        display = new(entity: entity, entries: group, customer_id: cid, audience: audience)
        group.each { |entry| entry.prime_display!(display) }
      end
    end

    def initialize(entity:, entries:, customer_id:, audience:)
      @entries = Array(entries)
      @customer_id = customer_id
      @audience = audience
      @attributes = Array(entity.property_schema_json).grep(Hash).index_by { |attribute| attribute["name_slug"].to_s }
      @derived_slugs = (entity.computed_fields + entity.calculated_fields).map { |field| field["name_slug"].to_s }.to_set
      @reference_labels = {}
      @option_labels = {}
      DerivedValues.prime!(@entries, customer_id: customer_id) if @derived_slugs.any?
    end

    # Defined for the entries this display was built with. Never raises; an
    # unknown slug shows its stored value, and duplicate labels are never
    # numbered here (only dropdowns number them).
    def text(entry, slug)
      key = slug.to_s
      derived = @derived_slugs.include?(key)
      value = derived ? entry.derived_values[key] : entry.data_json[key]
      return I18n.t("common.labels.em_dash") if blank?(value)

      attribute = @attributes[key]
      return plain(value) if derived || attribute.nil?

      if ReferenceLabels.reference?(attribute)
        reference_text(key, attribute, value)
      elsif (labels = option_labels(key, attribute)).any?
        Array(value).map { |item| labels.fetch(item.to_s, item.to_s) }.join(", ")
      elsif BOOLEAN_TYPES.include?(attribute["html_type"].to_s)
        I18n.t(ActiveModel::Type::Boolean.new.cast(value) ? "common.labels.yes" : "common.labels.no")
      else
        plain(value)
      end
    end

    private

    def blank?(value)
      value.nil? || value == "" || (value.is_a?(Array) && value.all? { |item| item.nil? || item == "" })
    end

    def plain(value)
      value.is_a?(Array) ? value.map(&:to_s).join(", ") : value.to_s
    end

    # A record that is gone reads "Missing record (#id)"; a display field the
    # audience may not see leaves the stored id.
    def reference_text(slug, attribute, value)
      labels = reference_labels(slug, attribute)
      return plain(value) if labels.nil?

      reference_ids(value).map do |id|
        labels.key?(id) ? ReferenceLabels.text(labels[id], id) : ReferenceLabels.missing(id)
      end.join(", ")
    end

    def reference_labels(slug, attribute)
      return @reference_labels[slug] if @reference_labels.key?(slug)

      config = attribute["config"]
      ids = @entries.flat_map { |entry| reference_ids(entry.data_json[slug]) }
      @reference_labels[slug] = ReferenceOptions.new(
        entity_id: config["entity_id"], label_field: config["label_field"],
        customer_id: @customer_id, audience: @audience
      ).labels(ids)
    end

    def reference_ids(value)
      Array(value).map { |id| id.to_s.strip }.reject(&:empty?)
    end

    def option_labels(slug, attribute)
      @option_labels[slug] ||= begin
        config = attribute["config"]
        Array(config.is_a?(Hash) ? config["options"] : nil).each_with_object({}) do |option, labels|
          if option.is_a?(Hash)
            labels[option["value"].to_s] = option["label"].presence&.to_s || option["value"].to_s
          elsif !option.nil?
            labels[option.to_s] = option.to_s
          end
        end
      end
    end
  end
end
```

- [ ] **Step 5: `EntityEntry#display_text`**

In `app/models/entity_entry.rb`, below `derived_values`, add:

```ruby
  # Display text through the Entities::EntryDisplay a list attached to this
  # entry (EntryDisplay.prime!); the raw stored or derived value without one.
  def prime_display!(display)
    @entry_display = display
  end

  def display_text(slug)
    return @entry_display.text(self, slug) if @entry_display

    key = slug.to_s
    data_json.key?(key) ? data_json[key] : derived_values[key]
  end
```

Run: `TEST_ENV_NUMBER=42 bundle exec rspec spec/services/entities/entry_display_spec.rb spec/services/entities/reference_options_spec.rb`
Expected: PASS.

- [ ] **Step 6: Member readers use display text (test first)**

In `spec/services/member/entity_surface_builder_spec.rb`, rewrite "includes a visible computed and reads it through computed_values, not data_json" (line 164) as "includes a visible computed and reads it through display_text". It stubs `allow(entry).to receive(:display_text).with("average_score").and_return("87.5")`, expects the column value to be `"87.5"`, and expects `entry` to have received `display_text`.

Add two examples:

- A text attribute's column reads `display_text` (stub it to return `"In person"`).
- A `Date`-typed attribute's column reads `data_json` (stub `data_json` to return `{ "starts_on" => Date.new(2026, 11, 2) }`).

Update any other example that stubs `data_json` for a string or number column to stub `display_text`.

In `spec/services/member/surface_template_applier_spec.rb`, rewrite "produces a detail row whose value lambda reads computed_values, not data_json" (line 174) the same way. Every row now reads `display_text`; update other examples that stub `data_json` for row values.

Run: `TEST_ENV_NUMBER=42 bundle exec rspec spec/services/member/entity_surface_builder_spec.rb spec/services/member/surface_template_applier_spec.rb`
Expected: FAIL. The readers still call `computed_values` and `data_json`.

In `app/services/member/entity_surface_builder.rb`:

- Add, under `DEFAULT_POSITION_BASE`:

```ruby
    # Formats that print text as-is read display text (option labels,
    # referenced records, derived values); dates and money keep the stored
    # value their formatter expects.
    TEXT_FORMATS = %i[string number].freeze
```

- In `call`, replace the column hash body with:

```ruby
        computed = f["type"] == Entity::COMPUTED_TYPE
        format = computed ? :number : format_for(f["type"])
        {
          key:      slug.to_sym,
          label:    f["display_label"].presence || f["name"].presence || slug.to_s,
          value:    TEXT_FORMATS.include?(format) ? display_reader(slug) : data_reader(slug),
          format:   format,
          align:    computed ? :right : align_for(f["type"]),
          hideable: true
        }
```

- Replace `computed_reader` and its comment with:

```ruby
    # Display text from the Entities::EntryDisplay the controller attached.
    def self.display_reader(slug)
      ->(entry) { entry.respond_to?(:display_text) ? entry.display_text(slug) : nil }
    end
```

- Change the `private_class_method` line to `private_class_method :member_surface_field?, :data_reader, :display_reader`.

In `app/services/member/surface_template_applier.rb`:

- Delete `computed_slugs` and its comment.
- In `build_row`, delete the `computed = ...` line, and replace the `value:` entry with `value: ->(entry) { entry.respond_to?(:display_text) ? entry.display_text(slug) : nil }`.
- Keep the comment above `synthesize_fields` saying that computed fields render on the member detail.

Run the two member specs again. Expected: PASS.

- [ ] **Step 7: Run the task's specs**

Run: `TEST_ENV_NUMBER=42 bundle exec rspec spec/services/entities spec/services/member spec/models/entity_entry_spec.rb spec/requests/member/surfaces_spec.rb`
Expected: all pass. The member request spec still passes: its custom descriptor reads `computed_values`, which T5 replaces.

- [ ] **Step 8: Leave the changes uncommitted**

Run: `git add -N app/services/entities/entry_display.rb spec/services/entities/entry_display_spec.rb && git status --short`. Do not commit.

---

### Task 3: Entries-list columns

**Agent:** anysys-backend-developer

**Files:**
- Modify: `app/services/admin/entities/columns_builder.rb`
- Modify: `app/concepts/entity_index_settings/operation/update.rb`
- Modify: `spec/services/admin/entities/columns_builder_spec.rb`, `spec/services/admin/entities/entries_csv_spec.rb`
- Modify: `spec/components/admin/entities/entries_table_component_spec.rb` (its `ColumnsBuilder.call` only)
- Modify: `spec/concepts/entity_index_settings/operation/update_spec.rb`

**Interfaces:**
- Consumes: `Entities::DerivedExpressions` (T1), `Entities::EntryDisplay` (T2).
- Produces:
  - `Admin::Entities::ColumnsBuilder.call(entity:, setting:, customer_id:, display:, t: I18n.method(:t))`.
    - Cells and badge labels come from `display.text`.
    - Calculated fields are selectable, sortable derived columns (`derived: true`).
    - Checkbox columns are `:text`.
  - The column preference accepts calculated slugs.

- [ ] **Step 1: Prepare the test database**

Run: `RAILS_ENV=test TEST_ENV_NUMBER=43 bin/rails db:schema:load`

- [ ] **Step 2: Update the builder spec (failing)**

In `spec/services/admin/entities/columns_builder_spec.rb`:

- Add `let(:display) { Entities::EntryDisplay.new(entity: entity, entries: [], customer_id: entity.customer_id, audience: EntityAttributeAudience::ADMIN) }`. Pass `customer_id: entity.customer_id, display: display` to every `described_class.call`, including the subject. For the `other` entity at line 130, build its own display.
- "maps html_type to column type" (line 158): `:active` is now `:text`.
- In "computed columns":
  - Rename `computed: true` in the "builds a number column…" expectation to `derived: true`.
  - Replace the two `values:` examples (lines 243–255) with one: "reads the cell from the display", using `display = instance_double(Entities::EntryDisplay)`, `allow(display).to receive(:text).with(row, "average_score").and_return("87.5")`, and expecting `col[:cell].call(row)` to eq `"87.5"`.
- Replace the attribute cell examples (lines 172–187) with "reads attribute cells and badge labels from the display":

```ruby
    context "with a choice and a text field" do
      before do
        entity.property_schema_json = [
          { "name_slug" => "grade", "name" => "Grade", "html_type" => "select", "type" => "String",
            "config" => { "options" => [{ "label" => "Grade A", "value" => "A" }] } },
          { "name_slug" => "first_name", "name" => "First name", "html_type" => "text", "type" => "String" }
        ]
        entity.save!
        setting.write_overlay(visible_column_keys: %w[grade first_name])
        setting.save!
      end

      it "reads attribute cells and badge labels from the display" do
        display = instance_double(Entities::EntryDisplay)
        row = instance_double(EntityEntry)
        allow(display).to receive(:text).with(row, "grade").and_return("Grade A")
        allow(display).to receive(:text).with(row, "first_name").and_return(I18n.t("common.labels.em_dash"))
        cols = described_class.call(entity: entity, setting: setting, customer_id: entity.customer_id, display: display, t: t)

        grade = cols.find { |c| c[:key] == :grade }
        expect(grade[:badge].call(row)).to eq(label: "Grade A", variant: :default)
        first_name = cols.find { |c| c[:key] == :first_name }
        expect(first_name[:cell].call(row)).to eq(I18n.t("common.labels.em_dash"))
      end

      it "has no badge for a blank choice" do
        display = instance_double(Entities::EntryDisplay, text: I18n.t("common.labels.em_dash"))
        grade = described_class.call(entity: entity, setting: setting, customer_id: entity.customer_id, display: display, t: t)
                               .find { |c| c[:key] == :grade }
        expect(grade[:badge].call(instance_double(EntityEntry))).to be_nil
      end
    end
```
- Add a "calculated columns" describe: give the entity a calculated `{ "name" => "Total", "name_slug" => "total", "type" => "Calculated", "html_type" => "number", "formula" => "price * 2" }` (and a `price` number attribute). Then:
  - With preference `[:total]`, the column is `{ key: :total, type: :number, sortable: true, searchable: false, derived: true }`, and its `sql` includes `json_extract(entity_entries.data, '$.price')`.
  - With no preference, `total` is not a default column.
  - A calculated field with a broken formula is not selectable, even when preferred.

In `spec/components/admin/entities/entries_table_component_spec.rb` (line 47), pass `customer_id: <the spec's customer>.id, display: Entities::EntryDisplay.new(entity: <entity>, entries: <rows>, customer_id: <customer>.id, audience: EntityAttributeAudience::ADMIN)`. Then add an example: a `select` attribute's cell renders the option label, not the stored value.

In `spec/services/admin/entities/entries_csv_spec.rb`, add "exports display text": build columns with `ColumnsBuilder.call` for an entity with a select option `{ "label" => "In person", "value" => "in_person" }`, then check that the CSV row contains `In person`, not `in_person`.

In `spec/concepts/entity_index_settings/operation/update_spec.rb`, add an example: a calculated slug is accepted and saved.

Run: `TEST_ENV_NUMBER=43 bundle exec rspec spec/services/admin/entities spec/components/admin/entities/entries_table_component_spec.rb spec/concepts/entity_index_settings`
Expected: FAIL, with `unknown keyword: :customer_id` and the calculated-slug rejection.

- [ ] **Step 3: Rewrite `ColumnsBuilder`**

Replace the body of `Admin::Entities::ColumnsBuilder` with:

```ruby
    # Resolves admin entity-entry index columns from schema + per-customer preference.
    # Sorting and search read each column's `sql:`; cells read the
    # Entities::EntryDisplay built for the rows being rendered.
    class ColumnsBuilder
      SYSTEM_KEYS = %i[id created_at updated_at].freeze
      TYPE_MAP = {
        "number" => :number, "range" => :number,
        "date" => :date, "month" => :date, "week" => :date,
        "datetime-local" => :datetime, "time" => :datetime,
        "select" => :badge, "radio" => :badge,
        "textarea" => :truncate
      }.freeze
      NUMERIC_HTML_TYPES = FlowchartRuntime::FormulaCompiler::NUMERIC_HTML_TYPES

      def self.call(entity:, setting:, customer_id:, display:, t: I18n.method(:t))
        new(entity:, setting:, customer_id:, display:, t:).call
      end

      def initialize(entity:, setting:, customer_id:, display:, t:)
        @entity = entity
        @setting = setting
        @customer_id = customer_id
        @display = display
        @t = t
      end

      def call
        [system_column(:id)] + attribute_columns + [system_column(:created_at), system_column(:updated_at)]
      end

      private

      def attribute_columns
        selected_slugs.map { |slug| derived_fields_by_slug.key?(slug) ? derived_column(slug) : attribute_column(slug) }
      end

      def selected_slugs
        preferred = @setting.visible_column_keys
        if preferred.nil?
          default_slugs
        else
          preferred.map(&:to_s) & (candidate_slugs + derived_candidate_slugs)
        end
      end

      def default_slugs
        from_searchable = Array(@entity.searchable_field_keys).map(&:to_s) & candidate_slugs
        return from_searchable if from_searchable.any?

        candidate_slugs.first(3)
      end

      def candidate_slugs
        @candidate_slugs ||= begin
          system = SYSTEM_KEYS.map(&:to_s)
          @entity.input_fields
                 .filter_map { |f| f["name_slug"].presence }
                 .reject { |slug| system.include?(slug) }
        end
      end

      def fields_by_slug
        @fields_by_slug ||= @entity.input_fields.index_by { |f| f["name_slug"] }
      end

      def attribute_column(slug)
        field = fields_by_slug[slug] || {}
        type = TYPE_MAP.fetch(field["html_type"].to_s, :text)
        display = @display

        col = {
          key: slug.to_sym,
          label: heading_for(field, slug),
          type: type,
          sortable: true,
          searchable: %i[text truncate badge].include?(type),
          sql: "json_extract(entity_entries.data, '$.#{slug}')",
          cell: ->(row) { display.text(row, slug) }
        }
        col[:align] = :right if type == :number
        col[:relative] = true if type == :datetime
        col[:truncate] = 60 if type == :truncate
        col[:badge] = badge_for(slug) if type == :badge
        col
      end

      def badge_for(slug)
        display = @display
        blank = I18n.t("common.labels.em_dash")
        ->(row) {
          label = display.text(row, slug)
          label == blank ? nil : { label: label, variant: :default }
        }
      end

      def derived_expressions
        @derived_expressions ||= ::Entities::DerivedExpressions.for(@entity, customer_id: @customer_id)
      end

      def derived_candidate_slugs
        derived_expressions.map { |expression| expression[:name] }
      end

      def derived_fields_by_slug
        @derived_fields_by_slug ||= (@entity.computed_fields + @entity.calculated_fields).index_by { |f| f["name_slug"] }
      end

      def derived_column(slug)
        field = derived_fields_by_slug[slug] || {}
        number = field["type"] == Entity::COMPUTED_TYPE || NUMERIC_HTML_TYPES.include?(field["html_type"].to_s)
        display = @display

        col = {
          key: slug.to_sym,
          label: heading_for(field, slug),
          type: number ? :number : :text,
          sortable: true,
          searchable: false,
          derived: true,
          sql: derived_expressions.find { |expression| expression[:name] == slug }&.dig(:sql),
          cell: ->(row) { display.text(row, slug) }
        }
        col[:align] = :right if number
        col
      end

      def heading_for(field, slug)
        field["display_label"].presence || field["name"].presence || slug.to_s
      end

      def system_column(key)
        {
          key: key,
          label: @t.call("admin_misc.entities.columns.#{key}"),
          sortable: true,
          type: (key == :id ? :number : :datetime),
          relative: (key != :id),
          align: (key == :id ? :right : :left)
        }
      end
    end
```

- [ ] **Step 4: Calculated slugs are selectable**

In `app/concepts/entity_index_settings/operation/update.rb`:

- `selectable` becomes `entity.input_fields + entity.computed_fields + entity.calculated_fields`.
- The comment above it becomes: `# Derived slugs (computed and calculated) are offered by the column picker even though nothing is stored for them, so they must be selectable here.`

- [ ] **Step 5: Run the task's specs**

Run: `TEST_ENV_NUMBER=43 bundle exec rspec spec/services/admin/entities spec/components/admin/entities/entries_table_component_spec.rb spec/concepts/entity_index_settings spec/requests/admin/entity_index_settings_spec.rb`
Expected: all pass. `spec/requests/admin/entities_spec.rb` fails until T5 moves the controller to the new signature, so don't run it here.

- [ ] **Step 6: Leave the changes uncommitted**

Run: `git status --short`. Do not commit.

---

### Task 4: Detail drawer and column picker

**Agent:** anysys-frontend-developer

**Files:**
- Modify: `app/components/admin/entities/entry_detail_component.rb`
- Modify: `app/views/admin/entity_entries/show.html.erb`
- Modify: `app/components/admin/entities/column_picker_component.rb`
- Modify: `spec/components/admin/entities/entry_detail_component_spec.rb`, `spec/components/admin/entities/column_picker_component_spec.rb`

**Interfaces:**
- Consumes: `Entities::EntryDisplay#text` (T2).
- Produces: `Admin::Entities::EntryDetailComponent.new(entity:, entry:, display:, close_path:)`. The column picker offers calculated fields next to computed ones.

- [ ] **Step 1: Prepare the test database**

Run: `RAILS_ENV=test TEST_ENV_NUMBER=44 bin/rails db:schema:load`

- [ ] **Step 2: Update the specs (failing)**

In `spec/components/admin/entities/entry_detail_component_spec.rb`:

- Pass `display: Entities::EntryDisplay.new(entity: entity, entries: [entry], customer_id: entry.customer_id, audience: EntityAttributeAudience::ADMIN)` to every `described_class.new`.
- Add an example: the entity has a select attribute `{ "label" => "In person", "value" => "in_person" }` and a calculated `seats * 2`. With `data: { "mode" => "in_person", "seats" => 12 }`, the drawer shows `In person` and `24`, and doesn't show `in_person`.

In `spec/components/admin/entities/column_picker_component_spec.rb`, add an example: a calculated attribute appears as a choice.

Run: `TEST_ENV_NUMBER=44 bundle exec rspec spec/components/admin/entities/entry_detail_component_spec.rb spec/components/admin/entities/column_picker_component_spec.rb`
Expected: FAIL, with `unknown keyword: :display` and the missing calculated choice.

- [ ] **Step 3: Implement**

In `entry_detail_component.rb`:

- `attr_reader :entity, :entry, :display, :close_path`.
- `initialize(entity:, entry:, display:, close_path:)`, which sets `@display = display`.
- `attribute_value(slug)` becomes `display.text(entry, slug)`.
- Delete the now-unused `blank_value?`.

In `app/views/admin/entity_entries/show.html.erb`, add `display: @display,` after `entry: @entry,`.

In `column_picker_component.rb` `candidate_fields`, change `extra = Array(entity.computed_fields)` to `extra = entity.computed_fields + entity.calculated_fields`.

Run the two component specs again. Expected: PASS.

- [ ] **Step 4: Leave the changes uncommitted**

Run: `git status --short`. Do not commit. `spec/requests/admin/entity_entries_spec.rb` fails until T5 sets `@display`.

---

### Task 5: Controllers

**Agent:** anysys-security-engineer

**Files:**
- Modify: `app/controllers/admin/entities_controller.rb`
- Modify: `app/controllers/admin/entity_entries_controller.rb` (`show` only)
- Modify: `app/controllers/member/surfaces_controller.rb`
- Modify: `spec/requests/admin/entities_spec.rb`, `spec/requests/admin/entity_entries_spec.rb`, `spec/requests/member/surfaces_spec.rb`

**Interfaces:**
- Consumes: `ColumnsBuilder` with `customer_id:` and `display:` (T3), `EntryDetailComponent` with `display:` (T4), and `Entities::EntryDisplay` (T2).

Authorization doesn't change. Every display is built for `current_customer.id`. Admin surfaces use `EntityAttributeAudience::ADMIN`. Member surfaces use `EntityAttributeAudience.for_user(current_user, customer_id: current_customer.id)`.

- [ ] **Step 1: Prepare the test database**

Run: `RAILS_ENV=test TEST_ENV_NUMBER=45 bin/rails db:schema:load`

- [ ] **Step 2: Write the failing request examples**

In `spec/requests/admin/entities_spec.rb`, add a "display" describe. Use the file's signed-in admin and `customer`, and build:

- an Instructor entity with a text `name`;
- a Course entity with:
  - a `select` attribute `mode` with options `[{ "label" => "In person", "value" => "in_person" }]`;
  - a reference dropdown `instructor` (`options_source: "entity_entries"`, `label_field: "name"`);
  - a number `seats`, and a calculated `double_seats` (`"seats * 2"`).

Then add these examples:

- The list (`get admin_entity_path(customer.id, course)`, with an `EntityIndexSetting` preference `%w[mode instructor seats double_seats]`) shows `In person`, `Jenny` and `24`. It doesn't show the instructor's id as a cell.
- The CSV export (`get admin_entity_path(customer.id, course, format: :csv)`) has the row `In person`, `Jenny` and `24` under the columns' headings.
- Sorting by `double_seats` (`sort: "double_seats", dir: "desc"`) puts the entry with more seats first.
- A computed count on a bridge row whose parent id is a JSON number shows `1`. Reuse the bridge setup of `spec/services/entities/derived_values_spec.rb`, and set an `EntityIndexSetting` preference that includes the computed slug.

In `spec/requests/admin/entity_entries_spec.rb`, add an example: the entry show (detail drawer) shows the referenced instructor's name and the calculated value.

In `spec/requests/member/surfaces_spec.rb`, update the computed-surface example (around line 158):

- Both value lambdas become `->(r) { r.display_text("average_score") }`.
- Replace the `GROUP BY` subscriber with one that counts SQL matching `/\ASELECT "entity_entries"\."id", /`, and expect exactly 1.
- The body still includes `87.5` and `80`.

Add a member example: a descriptor column reading `r.display_text("instructor")` shows the instructor's name when `name` is visible to members, and the raw id when `name` has `"visibility" => { "member" => false }`.

Run: `TEST_ENV_NUMBER=45 bundle exec rspec spec/requests/admin/entities_spec.rb spec/requests/admin/entity_entries_spec.rb spec/requests/member/surfaces_spec.rb`
Expected: FAIL, with `missing keyword: :customer_id` from `ColumnsBuilder`, `missing keyword: :display`, and the member display assertions.

- [ ] **Step 3: Entities list and CSV**

In `app/controllers/admin/entities_controller.rb` `show`:

- Replace `@columns = Admin::Entities::ColumnsBuilder.call(entity: @entity, setting: @setting)` with `@columns = columns_for([])`.
- In `format.html`, replace `hydrate_computed_columns!(@rows)` with `@columns = columns_for(@rows)`.
- In `format.csv`, delete `hydrate_computed_columns!(result[:rows])`, and change the CSV line to `csv = Admin::Entities::EntriesCsv.call(rows: result[:rows], columns: columns_for(result[:rows]))`.

Replace `hydrate_computed_columns!` and its comment with:

```ruby
    # Sorting, search and filters read the columns' SQL, so the first build
    # needs no rows; cells read display text for the rows being rendered,
    # preloaded in one pass. customer_id is always the session tenant —
    # never params, never Current.
    def columns_for(rows)
      display = ::Entities::EntryDisplay.new(entity: @entity, entries: rows, customer_id: current_customer.id,
                                             audience: EntityAttributeAudience::ADMIN)
      Admin::Entities::ColumnsBuilder.call(entity: @entity, setting: @setting, customer_id: current_customer.id,
                                           display: display)
    end
```

- [ ] **Step 4: Detail drawer**

In `app/controllers/admin/entity_entries_controller.rb`, `show` becomes:

```ruby
    def show
      @display = ::Entities::EntryDisplay.new(entity: @entity, entries: [@entry], customer_id: current_customer.id,
                                              audience: EntityAttributeAudience::ADMIN)
    end
```

- [ ] **Step 5: Member surfaces**

In `app/controllers/member/surfaces_controller.rb`:

- Replace `Entities::ComputedLoader.prime!(@records, customer_id: current_customer.id)` with `prime_display!(@records)`.
- In `show`, after `authorize_owned!(@record)`, add `prime_display!([@record])`.
- Add these private methods:

```ruby
    # Entity-backed rows read display text for the member's audience; other
    # records pass through untouched.
    def prime_display!(records)
      ::Entities::EntryDisplay.prime!(records, customer_id: current_customer.id,
                                               audience: EntityAttributeAudience.for_user(current_user, customer_id: current_customer.id))
    end
```

- [ ] **Step 6: Run the specs**

Run: `TEST_ENV_NUMBER=45 bundle exec rspec spec/requests/admin/entities_spec.rb spec/requests/admin/entity_entries_spec.rb spec/requests/member spec/requests/admin/entity_entry_creation_spec.rb spec/requests/admin/entity_index_settings_spec.rb`
Expected: all pass.

Run: `rg -n "ComputedLoader|computed_values|hydrate_computed_columns" app`
Expected: hits only in `app/services/entities/computed_loader.rb` and `app/models/entity_entry.rb`, which T6 removes.

- [ ] **Step 7: Leave the changes uncommitted**

Run: `git status --short`. Do not commit.

---

### Task 6: Remove the computed loader; `seats_remaining` example

**Agent:** anysys-backend-developer

**Files:**
- Delete: `app/services/entities/computed_loader.rb`, `spec/services/entities/computed_loader_spec.rb`
- Modify: `app/services/entities/computed_definition.rb` (delete `loader_sql`; update the class comment)
- Modify: `app/models/entity_entry.rb` (delete `computed_values` and `prime_computed_values!`)
- Modify: `spec/services/entities/computed_definition_spec.rb`, `spec/models/entity_entry_spec.rb`, `spec/integration/computed_fields_integration_spec.rb`
- Modify: `app/services/ai_assistant/assistant/prompt/documents/entity_examples.md`

- [ ] **Step 1: Prepare the test database**

Run: `RAILS_ENV=test TEST_ENV_NUMBER=46 bin/rails db:schema:load`

- [ ] **Step 2: Move the remaining specs to the new names**

- `spec/models/entity_entry_spec.rb` (lines 471–528): rename `computed_values` to `derived_values`, and `Entities::ComputedLoader.prime!` to `Entities::DerivedValues.prime!`. Keep the examples' expectations.
- `spec/integration/computed_fields_integration_spec.rb` (lines 86, 154, 161, 174): replace `Entities::ComputedLoader.call` with `Entities::DerivedValues.call`. The arguments are the same.
- `spec/services/entities/computed_definition_spec.rb`:
  - Delete "neutralizes a hostile alias in loader_sql to b0".
  - In the numeric filter example, check only `subquery`. Change `[subquery, loader].each do |sql|` to `[subquery].each do |sql|`, and delete the `loader =` line.
  - In the text filter example, delete the `loader_sql` expectation.

- [ ] **Step 3: Delete the old code**

Run: `rm -f app/services/entities/computed_loader.rb spec/services/entities/computed_loader_spec.rb`

The deletions stay unstaged in the working tree.

In `app/services/entities/computed_definition.rb`:

- Delete `loader_sql`.
- Change the class comment to: `# Resolved computed: live join slug + aggregate pieces behind the subquery that sorting, filtering and display (Entities::DerivedExpressions) all select.`

In `app/models/entity_entry.rb`, delete `prime_computed_values!`, `computed_values` and their comment.

- [ ] **Step 4: Add `seats_remaining` to the Course example (§7)**

In `entity_examples.md`, in the Course `create_entity` line (Plan 1 Task 2 rewrote it), replace:

```text
"filter":{"attribute":"status","operator":"=","value":"Enrolled"}}}
```

with:

```text
"filter":{"attribute":"status","operator":"=","value":"Enrolled"}}},{"name":"Seats remaining","slug":"seats_remaining","kind":"calculated","html_type":"number","group":"capacity","formula":"seats - enrolled_students"}
```

Replace the Course reply line with:

```json
{"intent":"chat","reply":"Created Course and linked it to Student through an enrolment that records the enrolment date, a status (Enrolled, Waitlisted, Dropped or Completed) and an admin-only grade. Enrolled students counts only enrolled rows, and Seats remaining is seats minus enrolled students."}
```

- [ ] **Step 5: Run the specs and the leftover check**

Run: `TEST_ENV_NUMBER=46 bundle exec rspec spec/services/entities spec/models/entity_entry_spec.rb spec/integration/computed_fields_integration_spec.rb spec/services/ai_assistant/assistant/prompt spec/services/operations/contract_lint_spec.rb`
Expected: all pass, including `tool_examples_contract_spec`.

Run: `rg -n "ComputedLoader|computed_values|prime_computed_values|loader_sql" app spec config`
Expected: no output.

- [ ] **Step 6: Leave the changes uncommitted**

Run: `git status --short`. Expect the two deletions and the modified files. Do not commit.

---

### Task 7: Plan 2 docs

**Agent:** anysys-backend-developer

**Files:**
- Modify: `doc/reference/en/entity-builder.md`, `doc/reference/zh-CN/entity-builder.md`

- [ ] **Step 1: Replace the computed-columns paragraph**

In `doc/reference/en/entity-builder.md`, replace the paragraph that starts `HTML lists and CSV exports call \`Admin::EntitiesController#hydrate_computed_columns!\`` (line 107) with:

```markdown
HTML lists and CSV exports build `::Entities::EntryDisplay` for their result rows once those are known (`Admin::EntitiesController#columns_for`) and pass it to `Admin::Entities::ColumnsBuilder`, whose cells and badges read `EntryDisplay#text`; sorting, search and filters read each column's `sql:` only. Derived values come from `Entities::DerivedValues`: one query selecting `entity_entries.id` plus every `Entities::DerivedExpressions` expression — the same SQL the list sorts by and `FlowchartRuntime::QueryBuilder` selects, so a link stored with a numeric parent id counts the same everywhere. The leading `::` resolves the top-level service namespace rather than `Admin::Entities`. The browser GET after Create Entry's 303 uses this same read path. Derived values are loaded for display, never written into the new entry's `data` or created as related records.
```

In `doc/reference/zh-CN/entity-builder.md`, replace the matching paragraph (line 107, starting `HTML 列表与 CSV 导出在确定结果条目后调用`) with:

```markdown
HTML 列表与 CSV 导出在确定结果条目后构建 `::Entities::EntryDisplay`（`Admin::EntitiesController#columns_for`），并传给 `Admin::Entities::ColumnsBuilder`；单元格与徽标读取 `EntryDisplay#text`，排序、搜索和筛选只读取各列的 `sql:`。派生值来自 `Entities::DerivedValues`：一次查询选出 `entity_entries.id` 与每个 `Entities::DerivedExpressions` 表达式，与列表排序及 `FlowchartRuntime::QueryBuilder` 使用同一 SQL，因此以数字保存父记录 ID 的关联行在各处计数一致。开头的 `::` 指向顶层服务命名空间，而非 `Admin::Entities`。创建条目后 303 跳转的浏览器 GET 走同一读取路径。派生值只用于显示，不会写入新条目的 `data`，也不会生成关联记录。
```

- [ ] **Step 2: Add the display rules to "Admin entries list"**

After the second paragraph of `### Admin entries list`, add to the en page:

```markdown
**Display text.** `Entities::EntryDisplay.new(entity:, entries:, customer_id:, audience:)` turns stored values into text for the list, the CSV export, the detail drawer (admin audience) and member surfaces (the member's audience): blank → `—`; select, radio and checkbox options → their labels, several joined with ", "; an `entity_entries` reference → the referenced record's display field (`Untitled (#id)` when blank, `Missing record (#id)` when the record is gone, the raw id when the display field is hidden from the audience); calculated and computed fields → their value; a checkbox or switch without options → Yes / No; anything else, including dates, as stored. Duplicate labels are numbered only in dropdowns, never here. Calculated fields can be picked as columns next to computed ones and sort by the same expression they display. Member surfaces attach the display with `EntryDisplay.prime!`, and descriptor lambdas read `EntityEntry#display_text(slug)`; dates and money keep their stored value for `Member::Formatters`.
```

and to the zh-CN page, at the same place:

```markdown
**显示文本。** `Entities::EntryDisplay.new(entity:, entries:, customer_id:, audience:)` 为列表、CSV 导出、详情抽屉（管理员受众）和成员页面（成员受众）把保存值转为文本：空值显示“—”；下拉、单选和复选框选项显示其标签，多个以“, ”连接；`entity_entries` 引用显示被引用记录的显示字段（为空时为“未命名（#id）”，记录不存在时为“记录不存在（#id）”，显示字段对该受众不可见时为原始 ID）；计算字段和汇总字段显示其值；无选项的复选框或开关显示“是 / 否”；其他值（包括日期）按原样显示。重复标签只在下拉列表中编号，这里不编号。计算字段可与汇总字段一样选为列，并按其显示所用的同一表达式排序。成员页面通过 `EntryDisplay.prime!` 挂载显示对象，描述符中的 lambda 读取 `EntityEntry#display_text(slug)`；日期与金额保留原值，交由 `Member::Formatters` 格式化。
```

- [ ] **Step 3: Check the docs**

Run: `rg -n "ComputedLoader|computed_values|hydrate_computed_columns|loader_sql" doc/reference/`
Expected: no output. If any other page matches, rewrite that sentence in both locales to name `Entities::DerivedValues` or `EntityEntry#derived_values`.

Run: `rg -c "EntryDisplay|DerivedValues" doc/reference/en/entity-builder.md doc/reference/zh-CN/entity-builder.md`
Expected: equal counts.

- [ ] **Step 4: Leave the changes uncommitted**

Run: `git status --short`. Do not commit.

---

### Task 8: Plan 2 verification

**Agent:** anysys-release-engineer

- [ ] **Step 1: Run the full RSpec suite in parallel**

Run: `bin/rails parallel:prepare && bin/rails parallel:spec`
Expected: 0 failures. Paste the summary lines. Report any failure (file, example, first error) without editing.

- [ ] **Step 2: Run the repository checks**

```bash
rg -n "ComputedLoader|computed_values|prime_computed_values|loader_sql|hydrate_computed_columns" app spec config doc/reference
rg -n "value_field" app config doc/reference --glob '!app/services/page_layout_templates/templates/**'
```

Expected: no output from either.

- [ ] **Step 3: Smoke-test the entries list**

Start the server in the background: `rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000`. Then:

- Pick an entity id that has entries: `bin/rails runner 'e = EntityEntry.where(customer_id: 81721200).first; puts e&.entity_id'`.
- `curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/81721200/admin/entities/<id>`. Expected: `200`.
- `curl -s http://localhost:3000/81721200/admin/entities/<id>.csv | head -3`. Expected: a header row and data rows.

Stop the server afterwards.

- [ ] **Step 4: Report**

Report PASS or FAIL with the trimmed output of each step. Do not commit.
