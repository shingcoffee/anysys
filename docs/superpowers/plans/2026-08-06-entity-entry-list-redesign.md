# Admin Entity Entry List Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the admin entity entry list (`GET /:cid/admin/entities/:id`) actionable (open / delete / bulk-delete), searchable/sortable/filterable against JSON attribute values, type-aware in presentation, and stably ordered.

**Architecture:** A bespoke `Admin::Entities::EntriesTableComponent` owns this page's markup, composed from the same visual primitives as `AdminTableComponent` (card, table-header/row, input-field, Badge/Button, pagy pager). Shared data layer stays in `ModuleEntriesResolver`, which gains additive `col[:sql]` support for `json_extract` search/sort. `ColumnsBuilder` emits type-aware columns with SQL expressions; new `FiltersBuilder` and `EntriesCsv` cover filters and export. Entry detail is a Turbo-frame slide-over (no new Stimulus controller).

**Tech Stack:** Rails 8.1.2, SQLite JSON1 (`json_extract`), ViewComponent, Stimulus (`batch_select` only), Pagy, RSpec + Vitest.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-06-entity-entry-list-redesign-design.md` (approved).
- SQLite only — attribute queries via `json_extract(entity_entries.data, '$.slug')`; never interpolate `params` into SQL expressions (slugs come only from entity schema).
- `ModuleEntriesResolver` changes must be strictly additive — absent `col[:sql]`, behaviour stays identical for all existing callers.
- Pagination via `ModuleEntriesResolver.paginate` / pagy — no hand-rolled offset math.
- No create/edit forms; detail is read-only. No changes to Maintenance › Entities › Entries or member surfaces. No rollout to other `AdminTableComponent` callers.
- I18n hard rule: every new user-facing string in both `en` and `zh-CN`. English value byte-identical to the would-be hard-coded string.
- JS under `app/javascript/**` stays at 100% Vitest lines + branches. Only JS file touched: `batch_select_controller.js`. Slide-over uses Turbo Frame + CSS only.
- Auth: re-verify admin/owner guard, `Entity.for_customer`, and dual `customer_id` + `entity_id` scoping on list, show, CSV, destroy, batch_destroy.
- **Git:** do **not** create commits unless the user explicitly asks. Skip every "Commit" step.
- Cross-cutting validation: after all tasks, run full parallel RSpec (or `bundle exec rspec`) plus `npx vitest run --coverage`.

## File Map

| File | Responsibility |
|---|---|
| `app/services/module_entries_resolver.rb` | Honour `col[:sql]` in search/sort |
| `app/services/admin/entities/columns_builder.rb` | Type map, `sql:`, ID-first order, titleized labels |
| `app/services/admin/entities/filters_builder.rb` | **new** — select/radio/checkbox filters |
| `app/services/admin/entities/entries_csv.rb` | **new** — filtered unpaginated CSV |
| `app/models/entity_index_setting.rb` | Persist `per_page` / `density` |
| `app/components/admin/entities/entries_table_component.{rb,html.erb}` | **new** — list UI |
| `app/components/admin/entities/entry_detail_component.{rb,html.erb}` | **new** — slide-over body |
| `app/views/admin/entities/show.html.erb` | Thin caller; ColumnPicker in header actions |
| `app/controllers/admin/entities_controller.rb` | Default order, filters, prefs, `format.csv` |
| `app/controllers/admin/entity_entries_controller.rb` | `#show` + admin `#destroy` |
| `config/routes.rb` | `entries` gains `show` + `destroy` |
| `app/javascript/controllers/batch_select_controller.js` | Indeterminate + selected-count + toolbar/bulkbar toggle |
| Specs in design Testing table | Coverage |

**Binding decisions (not in spec, locked here):**
1. Single-row delete via member `destroy` on admin `entries` (bulk keeps `batch_destroy`).
2. Slide-over: Turbo Frame `entity-entry-detail` + CSS panel; no new Stimulus.
3. List prefs via new `EntityIndexSetting#write_list_prefs` (column picker keeps `write_overlay`).

---

### Task 1: ModuleEntriesResolver `sql:` support

**Files:**
- Modify: `app/services/module_entries_resolver.rb`
- Test: `spec/services/module_entries_resolver_spec.rb`

**Interfaces:**
- Consumes: optional `col[:sql]` (String), `col[:type] == :number` for CAST
- Produces: search/sort use expression; bare-column path unchanged when `:sql` absent and type not `:number`

- [ ] **Step 1: Write the failing tests**

Append to `spec/services/module_entries_resolver_spec.rb`:

```ruby
describe "sql: expression columns" do
  let_it_be(:entity_for_entries) { create(:entity, customer: customer) }

  def create_entry!(data)
    create(:entity_entry, customer: customer, entity: entity_for_entries, data: data)
  end

  let(:sql_columns) do
    [
      {
        key: :first_name,
        label: "First name",
        sortable: true,
        searchable: true,
        sql: "json_extract(entity_entries.data, '$.first_name')"
      },
      {
        key: :age,
        label: "Age",
        type: :number,
        sortable: true,
        searchable: false,
        sql: "json_extract(entity_entries.data, '$.age')"
      }
    ]
  end

  before do
    EntityEntry.where(customer_id: customer.id, entity_id: entity_for_entries.id).delete_all
    @a = create_entry!("first_name" => "Alice", "age" => "10")
    @b = create_entry!("first_name" => "Bob", "age" => "9")
    @c = create_entry!("first_name" => "Carol", "age" => "11")
  end

  def scope
    EntityEntry.where(customer_id: customer.id, entity_id: entity_for_entries.id)
  end

  it "searches via col[:sql]" do
    result = described_class.call(scope: scope, columns: sql_columns, params: { q: "ali" })
    expect(result[:rows].map(&:id)).to eq([@a.id])
  end

  it "sorts via col[:sql]" do
    result = described_class.call(scope: scope, columns: sql_columns, params: { sort: "first_name", dir: "desc" })
    expect(result[:rows].map { |r| r["first_name"] }).to eq(%w[Carol Bob Alice])
  end

  it "CAST()s :number columns so 9 < 10" do
    result = described_class.call(scope: scope, columns: sql_columns, params: { sort: "age", dir: "asc" })
    expect(result[:rows].map { |r| r["age"] }).to eq(%w[9 10 11])
  end

  it "keeps bare-column SQL when :sql is absent (regression)" do
    pages = Page.for_customer(customer.id)
    result = described_class.call(
      scope: pages,
      columns: [{ key: :name, label: "Name", sortable: true, searchable: true }],
      params: { q: "alph" }
    )
    expect(result[:rows].map(&:name)).to eq(["Alpha"])
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/module_entries_resolver_spec.rb -e "sql: expression" --format documentation`

Expected: FAIL.

- [ ] **Step 3: Implement**

Replace `apply_search` and `apply_sort` in `app/services/module_entries_resolver.rb`:

```ruby
def self.apply_search(rel, columns, query)
  searchable = columns.select { |c| c[:searchable] }
  return rel if searchable.empty?

  clauses = searchable.map do |col|
    expr = col[:sql] || "#{rel.table_name}.#{col[:key]}"
    "LOWER(#{expr}) LIKE :q"
  end
  rel.where(clauses.join(" OR "), q: "%#{query.downcase}%")
end

def self.apply_sort(rel, columns, sort_key, dir)
  return rel if sort_key.blank?
  col = columns.find { |c| c[:sortable] && c[:key].to_s == sort_key.to_s }
  return rel unless col

  direction = dir.to_s.downcase == "desc" ? "DESC" : "ASC"
  if col[:sql]
    expr = col[:sql]
    expr = "CAST(#{expr} AS REAL)" if col[:type] == :number
    rel.reorder(Arel.sql("#{expr} #{direction}"))
  else
    rel.reorder(col[:key] => direction.downcase.to_sym)
  end
end
```

When `:sql` is absent, keep `reorder(key => :asc|:desc)` so existing callers stay byte-identical.

- [ ] **Step 4: Run tests — expect PASS**

Run: `bundle exec rspec spec/services/module_entries_resolver_spec.rb --format documentation`

- [ ] **Step 5: Commit** — SKIP.

---

### Task 2: ColumnsBuilder — type awareness, `sql:`, ID-first

**Files:**
- Modify: `app/services/admin/entities/columns_builder.rb`
- Test: `spec/services/admin/entities/columns_builder_spec.rb`

**Interfaces:**
- Consumes: `entity.data_fields` with `html_type`, `config.options` (`[{ "label", "value" }, ...]`)
- Produces: `[id] + attrs + [created_at, updated_at]`; attrs have `:type`, `:sortable`, `:searchable`, `:sql`, `:cell`, optional `:badge` / `:align` / `:relative` / `:truncate`

Type map:

| html_type | type |
|---|---|
| number, range | `:number` (align: :right) |
| date, month, week | `:date` |
| datetime-local, time | `:datetime` (relative: true) |
| checkbox | `:boolean` |
| select, radio | `:badge` |
| textarea | `:truncate` |
| else | `:text` |

- [ ] **Step 1: Update/extend failing expectations**

- Change order expectations from attributes-then-system to **ID first**, timestamps last (e.g. `%i[id title status score created_at updated_at]`).
- Replace "sortable/searchable false" with sql/type examples:

```ruby
it "marks attribute columns sortable/searchable with sql: expressions" do
  title = columns.find { |c| c[:key] == :title }
  expect(title).to include(sortable: true, searchable: true, type: :text)
  expect(title[:sql]).to eq("json_extract(entity_entries.data, '$.title')")
end

it "maps html_type to column type" do
  entity.property_schema_json = [
    { "name_slug" => "age", "name" => "age", "html_type" => "number", "type" => "Integer" },
    { "name_slug" => "grade", "name" => "grade", "html_type" => "select", "type" => "String",
      "config" => { "options" => [{ "label" => "A", "value" => "A" }] } },
    { "name_slug" => "active", "name" => "active", "html_type" => "checkbox", "type" => "Boolean" },
    { "name_slug" => "bio", "name" => "bio", "html_type" => "textarea", "type" => "Text" }
  ]
  entity.save!
  cols = described_class.call(entity: entity, setting: setting, t: t)
  expect(cols.find { |c| c[:key] == :age }).to include(type: :number, align: :right)
  expect(cols.find { |c| c[:key] == :grade }[:type]).to eq(:badge)
  expect(cols.find { |c| c[:key] == :active }[:type]).to eq(:boolean)
  expect(cols.find { |c| c[:key] == :bio }[:type]).to eq(:truncate)
end

it "titleizes labels (First name, not first name)" do
  entity.property_schema_json = [
    { "name_slug" => "first_name", "name" => "first name", "display_label" => "first name",
      "html_type" => "text", "type" => "String" }
  ]
  entity.save!
  col = described_class.call(entity: entity, setting: setting, t: t).find { |c| c[:key] == :first_name }
  expect(col[:label]).to eq("First name")
end

it "cell lambda returns em-dash for blank text values" do
  title = columns.find { |c| c[:key] == :title }
  entry = instance_double(EntityEntry)
  allow(entry).to receive(:[]).with("title").and_return(nil)
  expect(title[:cell].call(entry)).to eq("—")
end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bundle exec rspec spec/services/admin/entities/columns_builder_spec.rb --format documentation`

- [ ] **Step 3: Implement**

```ruby
# frozen_string_literal: true

module Admin
  module Entities
    class ColumnsBuilder
      SYSTEM_KEYS = %i[id created_at updated_at].freeze
      TYPE_MAP = {
        "number" => :number, "range" => :number,
        "date" => :date, "month" => :date, "week" => :date,
        "datetime-local" => :datetime, "time" => :datetime,
        "checkbox" => :boolean,
        "select" => :badge, "radio" => :badge,
        "textarea" => :truncate
      }.freeze

      def self.call(entity:, setting:, t: I18n.method(:t))
        new(entity:, setting:, t:).call
      end

      def initialize(entity:, setting:, t:)
        @entity = entity
        @setting = setting
        @t = t
      end

      def call
        [system_column(:id)] + attribute_columns + [system_column(:created_at), system_column(:updated_at)]
      end

      private

      def attribute_columns
        selected_slugs.map { |slug| attribute_column(slug) }
      end

      def selected_slugs
        preferred = @setting.visible_column_keys
        if preferred.nil?
          default_slugs
        else
          preferred.map(&:to_s) & candidate_slugs
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
          @entity.data_fields
                 .filter_map { |f| f["name_slug"].presence }
                 .reject { |slug| system.include?(slug) }
        end
      end

      def fields_by_slug
        @fields_by_slug ||= @entity.data_fields.index_by { |f| f["name_slug"] }
      end

      def attribute_column(slug)
        field = fields_by_slug[slug] || {}
        html_type = field["html_type"].to_s
        type = TYPE_MAP.fetch(html_type, :text)
        raw_label = field["display_label"].presence || field["name"].presence || slug.to_s
        label = raw_label.to_s.humanize
        expr = "json_extract(entity_entries.data, '$.#{slug}')"

        col = {
          key: slug.to_sym,
          label: label,
          type: type,
          sortable: true,
          searchable: %i[text truncate badge].include?(type),
          sql: expr,
          cell: ->(row) {
            value = row[slug]
            value.nil? || value == "" ? "—" : value
          }
        }
        col[:align] = :right if type == :number
        col[:relative] = true if type == :datetime
        col[:truncate] = 60 if type == :truncate
        if type == :badge
          options = Array(field.dig("config", "options"))
          col[:badge] = ->(row) {
            value = row[slug]
            return nil if value.nil? || value == ""
            opt = options.find { |o| o["value"].to_s == value.to_s }
            { label: (opt && opt["label"].presence) || value.to_s, variant: :default }
          }
        end
        if type == :boolean
          col[:cell] = ->(row) {
            value = row[slug]
            return nil if value.nil? || value == ""
            ActiveModel::Type::Boolean.new.cast(value)
          }
          col[:searchable] = false
        end
        col
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
  end
end
```

- [ ] **Step 4: Run — expect PASS**

Run: `bundle exec rspec spec/services/admin/entities/columns_builder_spec.rb spec/components/admin/entities/column_picker_component_spec.rb`

- [ ] **Step 5: Commit** — SKIP.

---

### Task 3: FiltersBuilder

**Files:**
- Create: `app/services/admin/entities/filters_builder.rb`
- Create: `spec/services/admin/entities/filters_builder_spec.rb`

**Interfaces:**
- `Admin::Entities::FiltersBuilder.call(entity:) -> Array<{ key:, label:, options:, scope: }>`
- One filter per select/radio/checkbox; checkbox options Yes/No (`"true"`/`"false"`); select/radio from `config.options`

- [ ] **Step 1: Write failing spec**

```ruby
# frozen_string_literal: true
require "rails_helper"

RSpec.describe Admin::Entities::FiltersBuilder do
  let_it_be(:customer) { create(:customer) }
  let(:entity) do
    e = Entity.new(customer_id: customer.id, name: "Student", type: :customer_specific)
    e.property_schema_json = [
      { "name_slug" => "grade", "name" => "grade", "display_label" => "grade",
        "html_type" => "select", "type" => "String",
        "config" => { "options" => [{ "label" => "A", "value" => "A" }, { "label" => "B", "value" => "B" }] } },
      { "name_slug" => "active", "name" => "active", "html_type" => "checkbox", "type" => "Boolean" },
      { "name_slug" => "notes", "name" => "notes", "html_type" => "textarea", "type" => "Text" }
    ]
    e.save!
    e
  end

  subject(:filters) { described_class.call(entity: entity) }

  it "builds filters for select/radio/checkbox only" do
    expect(filters.map { |f| f[:key] }).to eq(%i[grade active])
  end

  it "titleizes labels and maps options" do
    grade = filters.find { |f| f[:key] == :grade }
    expect(grade[:label]).to eq("Grade")
    expect(grade[:options]).to eq([["A", "A"], ["B", "B"]])
  end

  it "checkbox filter uses Yes/No" do
    active = filters.find { |f| f[:key] == :active }
    expect(active[:options]).to eq([
      [I18n.t("common.labels.yes"), "true"],
      [I18n.t("common.labels.no"), "false"]
    ])
  end

  it "scope filters via json_extract" do
    create(:entity_entry, customer: customer, entity: entity, data: { "grade" => "A" })
    create(:entity_entry, customer: customer, entity: entity, data: { "grade" => "B" })
    rel = EntityEntry.where(customer_id: customer.id, entity_id: entity.id)
    grade = filters.find { |f| f[:key] == :grade }
    expect(grade[:scope].call(rel, "A").count).to eq(1)
  end
end
```

- [ ] **Step 2: Run — expect FAIL** (missing constant)

- [ ] **Step 3: Implement**

```ruby
# frozen_string_literal: true

module Admin
  module Entities
    class FiltersBuilder
      FILTER_TYPES = %w[select radio checkbox].freeze

      def self.call(entity:)
        new(entity: entity).call
      end

      def initialize(entity:)
        @entity = entity
      end

      def call
        @entity.data_fields.filter_map { |field| build_filter(field) }
      end

      private

      def build_filter(field)
        html_type = field["html_type"].to_s
        return nil unless FILTER_TYPES.include?(html_type)

        slug = field["name_slug"].to_s
        return nil if slug.blank?

        {
          key: slug.to_sym,
          label: (field["display_label"].presence || field["name"].presence || slug).to_s.humanize,
          options: options_for(field, html_type),
          scope: ->(rel, value) {
            rel.where("json_extract(entity_entries.data, '$.#{slug}') = ?", value)
          }
        }
      end

      def options_for(field, html_type)
        if html_type == "checkbox"
          [[I18n.t("common.labels.yes"), "true"], [I18n.t("common.labels.no"), "false"]]
        else
          Array(field.dig("config", "options")).filter_map do |opt|
            next if opt["value"].to_s.blank?
            [(opt["label"].presence || opt["value"]).to_s, opt["value"].to_s]
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: PASS** — `bundle exec rspec spec/services/admin/entities/filters_builder_spec.rb`

- [ ] **Step 5: Commit** — SKIP.

---

### Task 4: EntriesCsv

**Files:**
- Create: `app/services/admin/entities/entries_csv.rb`
- Create: `spec/services/admin/entities/entries_csv_spec.rb`

**Interfaces:**
- `Admin::Entities::EntriesCsv.call(rows:, columns:) -> String` (CSV with headers)

- [ ] **Step 1: Failing spec**

```ruby
# frozen_string_literal: true
require "rails_helper"

RSpec.describe Admin::Entities::EntriesCsv do
  let_it_be(:customer) { create(:customer) }
  let(:entity) { create(:entity, customer: customer) }
  let(:columns) do
    [
      { key: :id, label: "ID" },
      { key: :first_name, label: "First name", cell: ->(r) { r["first_name"] } },
      { key: :grade, label: "Grade", cell: ->(r) { r["grade"] } }
    ]
  end

  it "renders headers and rows" do
    a = create(:entity_entry, customer: customer, entity: entity, data: { "first_name" => "Alice", "grade" => "A" })
    b = create(:entity_entry, customer: customer, entity: entity, data: { "first_name" => "Bob", "grade" => "B" })
    csv = described_class.call(rows: [a, b], columns: columns)
    expect(csv).to include("ID,First name,Grade")
    expect(csv).to include("Alice")
    expect(csv).to include("Bob")
  end

  it "honours the columns list (visible columns only)" do
    a = create(:entity_entry, customer: customer, entity: entity, data: { "first_name" => "Alice", "grade" => "A" })
    csv = described_class.call(rows: [a], columns: columns.first(2))
    expect(csv).to include("ID,First name")
    expect(csv).not_to include("Grade")
  end
end
```

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement**

```ruby
# frozen_string_literal: true
require "csv"

module Admin
  module Entities
    class EntriesCsv
      def self.call(rows:, columns:)
        new(rows: rows, columns: columns).call
      end

      def initialize(rows:, columns:)
        @rows = rows
        @columns = columns
      end

      def call
        CSV.generate(headers: true) do |csv|
          csv << @columns.map { |c| c[:label] }
          @rows.each do |row|
            csv << @columns.map { |c| cell_for(row, c) }
          end
        end
      end

      private

      def cell_for(row, column)
        value = if column[:cell].respond_to?(:call)
                  column[:cell].call(row)
                elsif row.respond_to?(column[:key])
                  row.public_send(column[:key])
                else
                  row[column[:key]]
                end
        value.to_s
      end
    end
  end
end
```

- [ ] **Step 4: PASS** — `bundle exec rspec spec/services/admin/entities/entries_csv_spec.rb`

- [ ] **Step 5: Commit** — SKIP.

---

### Task 5: EntityIndexSetting per_page / density

**Files:**
- Modify: `app/models/entity_index_setting.rb`
- Create or modify: `spec/models/entity_index_setting_spec.rb`

**Interfaces:**
- `per_page -> Integer|nil`
- `density -> String|nil` (`"comfortable"` / `"compact"`)
- `write_list_prefs(per_page: nil, density: nil)` — writes only provided keys; does not touch `visible_column_keys`

- [ ] **Step 1: Failing model examples** for read/write prefs

- [ ] **Step 2: Implement**

```ruby
def per_page
  v = (config_json || {})["per_page"]
  v.present? ? v.to_i : nil
end

def density
  (config_json || {})["density"].presence
end

def write_list_prefs(per_page: nil, density: nil)
  next_config = (config_json || {}).dup
  next_config["per_page"] = per_page.to_i if !per_page.nil? && per_page.to_s.present?
  next_config["density"] = density.to_s if density.present?
  self.config_json = next_config
end
```

Keep `write_overlay(visible_column_keys:)` unchanged.

- [ ] **Step 3: PASS**

- [ ] **Step 4: Commit** — SKIP.

---

### Task 6: batch_select — indeterminate + selected count

**Files:**
- Modify: `app/javascript/controllers/batch_select_controller.js`
- Modify: `spec/javascript/controllers/batch_select_controller.test.js`
- Locales: `comp_admin.batch_select.selected` = `"{count} selected"` (en + zh-CN)

**Interfaces:**
- Targets: existing + optional `count`, `toolbar`, `bulkbar`
- Value: `countTemplate` default `"{count} selected"`

- [ ] **Step 1: Extend Vitest**

```js
it("sets indeterminate when selection is partial", () => {
  items()[0].checked = true
  change(items()[0])
  expect(all().indeterminate).toBe(true)
  expect(all().checked).toBe(false)
})

it("clears indeterminate when all selected", () => {
  items().forEach((cb) => { cb.checked = true; change(cb) })
  expect(all().indeterminate).toBe(false)
  expect(all().checked).toBe(true)
})

it("updates selected-count from countTemplate default", async () => {
  const markup =
    `<div data-controller="batch-select">` +
    `<input type="checkbox" data-batch-select-target="all" data-action="change->batch-select#toggleAll">` +
    `<input type="checkbox" data-batch-select-target="item" data-action="change->batch-select#refresh">` +
    `<input type="checkbox" data-batch-select-target="item" data-action="change->batch-select#refresh">` +
    `<span data-batch-select-target="count"></span>` +
    `<div data-batch-select-target="toolbar"></div>` +
    `<div data-batch-select-target="bulkbar" class="hidden"></div>` +
    `<button data-batch-select-target="submit">Apply</button>` +
    `</div>`
  ;({ element } = await mountController("batch-select", Controller, markup))
  items()[0].checked = true
  change(items()[0])
  expect(element.querySelector("[data-batch-select-target='count']").textContent).toBe("1 selected")
  expect(element.querySelector("[data-batch-select-target='toolbar']").classList.contains("hidden")).toBe(true)
  expect(element.querySelector("[data-batch-select-target='bulkbar']").classList.contains("hidden")).toBe(false)
})
```

Assert against the Stimulus Value default (not a data attribute), per AGENTS.md.

- [ ] **Step 2: Run — FAIL** — `npx vitest run spec/javascript/controllers/batch_select_controller.test.js --coverage`

- [ ] **Step 3: Implement**

```js
static targets = ["all", "item", "submit", "count", "toolbar", "bulkbar"]
static values = {
  countTemplate: { type: String, default: "{count} selected" }
}

refresh() {
  const selected = this.itemTargets.filter((cb) => cb.checked)
  const anyChecked = selected.length > 0
  const allChecked = this.itemTargets.length > 0 && selected.length === this.itemTargets.length

  if (this.hasSubmitTarget) this.submitTarget.disabled = !anyChecked

  if (this.hasAllTarget) {
    this.allTarget.checked = allChecked
    this.allTarget.indeterminate = anyChecked && !allChecked
  }

  if (this.hasCountTarget) {
    this.countTarget.textContent = this.countTemplateValue.replace("{count}", String(selected.length))
  }

  if (this.hasToolbarTarget) this.toolbarTarget.classList.toggle("hidden", anyChecked)
  if (this.hasBulkbarTarget) this.bulkbarTarget.classList.toggle("hidden", !anyChecked)
}
```

- [ ] **Step 4: PASS at 100% lines/branches** — `npx vitest run --coverage`

- [ ] **Step 5: Commit** — SKIP.

---

### Task 7: EntryDetailComponent

**Files:**
- Create: `app/components/admin/entities/entry_detail_component.rb`
- Create: `app/components/admin/entities/entry_detail_component.html.erb`
- Create: `spec/components/admin/entities/entry_detail_component_spec.rb`
- Locales: `admin_misc.entities.entry_detail.*` (en + zh-CN)

**Interfaces:**
- `initialize(entity:, entry:, close_path:)`
- Body from `entity.grouped_property_schema`; values via `entry[slug]`; blank → `—`; no form controls

- [ ] **Step 1: Component spec** — grouped headings, titleized labels, values, no inputs

- [ ] **Step 2: Implement** — fixed right panel markup suitable for turbo-frame host; close link clears/hides frame

- [ ] **Step 3: PASS**

- [ ] **Step 4: Commit** — SKIP.

---

### Task 8: EntriesTableComponent

**Files:**
- Create: `app/components/admin/entities/entries_table_component.rb`
- Create: `app/components/admin/entities/entries_table_component.html.erb`
- Create: `spec/components/admin/entities/entries_table_component_spec.rb`
- Locales: `comp_admin.entries_table.*`, `comp_admin.batch_select.selected` (en + zh-CN)

**Interfaces:**
- `initialize(rows:, columns:, pagination:, params:, filters:, search:, empty_state:, base_path:, batch_path:, entry_path:, destroy_path:, density: "comfortable")`
- `entry_path` / `destroy_path` — lambdas `->(row) { ... }`
- Checkbox column in markup only; bulk bar via batch-select targets
- Footer: `per_page` select, density toggle, pagination links (same visual language as AdminTableComponent)
- Mobile `sm:hidden` cards; two empty states; badge/boolean/datetime/em-dash rendering
- Do **not** modify `AdminTableComponent`; duplicate thin helper methods as needed (YAGNI vs shared extraction)

- [ ] **Step 1: Specs** — column order (checkbox before ID), em-dash, badges, bulk-bar targets, both empty states

- [ ] **Step 2: Implement** using `card`, `table-row`, `input-field`, `BadgeComponent`, `ButtonComponent`

- [ ] **Step 3: PASS**

- [ ] **Step 4: Commit** — SKIP.

---

### Task 9: Routes, controllers, show view

**Files:**
- Modify: `config/routes.rb` — change nested entries to `only: %i[show destroy]` + existing collection `delete :batch`
- Modify: `app/controllers/admin/entities_controller.rb`
- Modify: `app/controllers/admin/entity_entries_controller.rb`
- Modify: `app/views/admin/entities/show.html.erb`
- Create: `app/views/admin/entity_entries/show.html.erb`
- Locales for export / density / rows / delete selected / clear search / no matches (en + zh-CN)

**`Admin::EntitiesController#show` sketch:**

```ruby
def show
  @entity = Entity.for_customer(current_customer.id).find(params[:id])
  @setting = EntityIndexSetting.for(customer_id: current_customer.id, entity_id: @entity.id)

  if params[:per_page].present? || params[:density].present?
    @setting.write_list_prefs(per_page: params[:per_page], density: params[:density])
    @setting.save if @setting.has_changes_to_save?
  end

  @columns = Admin::Entities::ColumnsBuilder.call(entity: @entity, setting: @setting)
  @filters = Admin::Entities::FiltersBuilder.call(entity: @entity)
  per_page = params[:per_page].presence || @setting.per_page || Listable::DEFAULT_PER_PAGE
  @density = params[:density].presence || @setting.density || "comfortable"

  scope = EntityEntry.where(customer_id: current_customer.id, entity_id: @entity.id)
                     .order(created_at: :desc)

  respond_to do |format|
    format.html do
      result = listable(scope, columns: @columns, filters: @filters, per_page: per_page)
      @rows = result[:rows]
      @pagination = result[:pagination]
    end
    format.csv do
      param_hash = params.to_unsafe_h.symbolize_keys.merge(page: 1, per_page: 100_000)
      result = ModuleEntriesResolver.call(
        scope: scope, columns: @columns, params: param_hash, filters: @filters, per_page: 100_000
      )
      csv = Admin::Entities::EntriesCsv.call(rows: result[:rows], columns: @columns)
      filename = "#{@entity.name.to_s.parameterize}-entries-#{Date.current.strftime('%Y%m%d')}.csv"
      send_data csv, filename: filename, type: "text/csv"
    end
  end
end
```

**EntityEntriesController additions:**

```ruby
before_action :find_entry, only: %i[show destroy]

def show
  # renders entry_detail inside turbo-frame entity-entry-detail
end

def destroy
  @entry.destroy
  redirect_to admin_entity_path(current_customer.id, @entity),
              notice: t("common.flash.entry_deleted")
end
```

**`show.html.erb`:** `AdminPageComponent` actions = Export CSV + `ColumnPickerComponent`; body = `EntriesTableComponent` + host turbo-frame for detail slide-over.

- [ ] **Step 1: Implement wiring**

- [ ] **Step 2: Manual sanity** — load page under `SKIP_AUTH=1` if needed after Task 10 greens

- [ ] **Step 3: Commit** — SKIP.

---

### Task 10: Request specs

**Files:**
- Create/Modify: `spec/requests/admin/entities_spec.rb`
- Create/Modify: `spec/requests/admin/entity_entries_spec.rb`

Cover:
- HTML 200; default `created_at desc` order
- Search / sort / filter against JSON attrs
- CSV 200, filename pattern, filtered/visible columns
- Cross-tenant entity → 404
- Entry `#show` 200 in-tenant; 404 cross-tenant
- `destroy` + `batch_destroy` tenant-scoped

- [ ] **Step 1: Write specs**
- [ ] **Step 2: Run until green**
- [ ] **Step 3: Commit** — SKIP.

---

### Task 11: Full-suite verification

- [ ] **Step 1:** `npx vitest run --coverage` — confirm 100% on touched JS
- [ ] **Step 2:** `bin/rails parallel:prepare && bin/rails parallel:spec` (fallback `bundle exec rspec`)
- [ ] **Step 3:** Report evidence; no green claims without output

---

## Self-Review (plan vs spec)

| Spec requirement | Task |
|---|---|
| Open / delete / bulk-delete | 8, 9, 10 |
| Search/sort on attribute JSON | 1, 2, 9 |
| Type-aware columns + em-dash | 2, 8 |
| Default `ORDER BY created_at DESC` | 9 |
| Columns in header; ID-first; titleized labels | 2, 8, 9 |
| Slide-over detail grouped fields | 7, 9 |
| Bulk bar + indeterminate + count | 6, 8 |
| Mobile cards | 8 |
| Two empty states | 8 |
| Filters + chips | 3, 8, 9 |
| CSV export | 4, 9, 10 |
| per_page/density persistence | 5, 9 |
| Resolver additive only | 1 |
| I18n en+zh-CN | 6–9 |
| Vitest 100% + full RSpec | 6, 11 |
| No create/edit; no other AdminTable callers | respected |

No TBD placeholders. Types/signatures consistent across tasks.
