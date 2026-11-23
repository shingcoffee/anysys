# Composite Pages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the Page model to support composite layouts with multiple modules (list + form) on one page, inter-module events via Stimulus, and conditional module visibility.

**Architecture:** A Page with `"layout": "composite"` in its config renders via `CompositePageRenderer`, which iterates `"modules"` and renders each as a `ModuleWrapperComponent` containing either a `ListComponent` (new) or existing form content. A Stimulus `composite-page` controller handles event dispatch between modules. List module uses `QueryBuilder` for data and Turbo Frames for sorting/pagination.

**Tech Stack:** Ruby on Rails 8.1, ViewComponent, StimulusJS, Turbo Frames, TailwindCSS, RSpec

**Spec:** `docs/superpowers/specs/2026-04-06-composite-pages-design.md`

---

## File Map

### New Files

| File | Responsibility |
|---|---|
| `app/services/composite_page_renderer.rb` | Orchestrates rendering of composite page modules |
| `app/components/composite_modules/list_component.rb` | Table ViewComponent: columns, sorting, pagination, row actions |
| `app/components/composite_modules/list_component.html.erb` | Table HTML template |
| `app/components/composite_modules/module_wrapper_component.rb` | Wrapper: width grid, visibility, event data attributes |
| `app/components/composite_modules/module_wrapper_component.html.erb` | Wrapper HTML template |
| `app/javascript/controllers/composite_page_controller.js` | Event relay between modules, visibility toggling |
| `app/javascript/controllers/list_module_controller.js` | Row selection dispatch, sort/paginate via Turbo |
| `spec/services/composite_page_renderer_spec.rb` | Renderer unit tests |
| `spec/components/composite_modules/list_component_spec.rb` | List component tests |
| `spec/integration/composite_page_integration_spec.rb` | End-to-end test |

### Modified Files

| File | Change |
|---|---|
| `app/services/page_content_generator.rb` | Detect `layout: "composite"` and delegate to CompositePageRenderer |
| `app/controllers/pages_controller.rb` | Add `module_data` action for Turbo Frame list data |
| `config/routes.rb` | Add `module_data` route |

---

## Task 1: CompositePageRenderer Service

**Files:**
- Create: `app/services/composite_page_renderer.rb`
- Create: `spec/services/composite_page_renderer_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/composite_page_renderer_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CompositePageRenderer do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Name", "name_slug" => "name", "type" => "String", "html_type" => "text" },
      { "name" => "Status", "name_slug" => "status", "type" => "String", "html_type" => "text" }
    ].to_json)
  end

  describe "#render_modules" do
    it "returns array of module render data for composite layout" do
      modules_config = [
        {
          "id" => "mod_1",
          "module_type" => "list",
          "title" => "Items",
          "entity_id" => entity.id,
          "width" => "half",
          "config" => { "columns" => ["name", "status"], "pageSize" => 10 }
        },
        {
          "id" => "mod_2",
          "module_type" => "form",
          "title" => "Details",
          "entity_id" => entity.id,
          "width" => "half",
          "config" => { "fields" => [] }
        }
      ]

      renderer = described_class.new(modules_config, customer_id: customer.id)
      result = renderer.render_modules

      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
      expect(result[0][:id]).to eq("mod_1")
      expect(result[0][:module_type]).to eq("list")
      expect(result[0][:width]).to eq("half")
      expect(result[1][:module_type]).to eq("form")
    end

    it "loads entity for list modules" do
      modules_config = [
        {
          "id" => "mod_1",
          "module_type" => "list",
          "title" => "Items",
          "entity_id" => entity.id,
          "width" => "full",
          "config" => { "columns" => ["name"] }
        }
      ]

      renderer = described_class.new(modules_config, customer_id: customer.id)
      result = renderer.render_modules

      expect(result[0][:entity]).to eq(entity)
    end

    it "fetches list data via QueryBuilder" do
      create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Alice", "status" => "active" }.to_json)
      create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Bob", "status" => "inactive" }.to_json)

      modules_config = [
        {
          "id" => "mod_1",
          "module_type" => "list",
          "title" => "Items",
          "entity_id" => entity.id,
          "width" => "full",
          "config" => { "columns" => ["name", "status"], "pageSize" => 10 }
        }
      ]

      renderer = described_class.new(modules_config, customer_id: customer.id)
      result = renderer.render_modules

      expect(result[0][:records].size).to eq(2)
      expect(result[0][:pagination][:total_count]).to eq(2)
    end

    it "applies conditions to list queries" do
      create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Alice", "status" => "active" }.to_json)
      create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Bob", "status" => "inactive" }.to_json)

      modules_config = [
        {
          "id" => "mod_1",
          "module_type" => "list",
          "entity_id" => entity.id,
          "width" => "full",
          "config" => {
            "columns" => ["name"],
            "conditions" => { "operator" => "AND", "rules" => [{ "field" => "data.status", "op" => "==", "value" => "active" }] }
          }
        }
      ]

      renderer = described_class.new(modules_config, customer_id: customer.id)
      result = renderer.render_modules

      expect(result[0][:records].size).to eq(1)
    end

    it "returns empty array for no modules" do
      renderer = described_class.new([], customer_id: customer.id)
      expect(renderer.render_modules).to eq([])
    end

    it "handles missing entity gracefully" do
      modules_config = [
        { "id" => "mod_1", "module_type" => "list", "entity_id" => 99999, "width" => "full", "config" => {} }
      ]

      renderer = described_class.new(modules_config, customer_id: customer.id)
      result = renderer.render_modules

      expect(result[0][:entity]).to be_nil
      expect(result[0][:records]).to eq([])
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/composite_page_renderer_spec.rb`
Expected: FAIL — `uninitialized constant CompositePageRenderer`

- [ ] **Step 3: Write implementation**

```ruby
# app/services/composite_page_renderer.rb
# frozen_string_literal: true

# CompositePageRenderer
#
# Orchestrates rendering of composite page modules. For each module in the
# configuration, resolves the entity, fetches data (for list modules), and
# returns structured render data for ViewComponents.
#
# @example
#   renderer = CompositePageRenderer.new(modules_config, customer_id: 123)
#   modules = renderer.render_modules
#   modules.each { |m| render_module_component(m) }
#
class CompositePageRenderer
  WIDTH_CLASSES = {
    "full" => "col-span-12",
    "half" => "col-span-6",
    "third" => "col-span-4",
    "two_thirds" => "col-span-8"
  }.freeze

  def initialize(modules_config, customer_id:, params: {})
    @modules_config = modules_config || []
    @customer_id = customer_id
    @params = params
  end

  def render_modules
    @modules_config.map { |mod_config| build_module_data(mod_config) }
  end

  private

  def build_module_data(mod_config)
    entity = resolve_entity(mod_config["entity_id"])
    config = mod_config["config"] || {}

    base = {
      id: mod_config["id"],
      module_type: mod_config["module_type"] || "form",
      title: mod_config["title"],
      entity: entity,
      width: mod_config["width"] || "full",
      width_class: WIDTH_CLASSES[mod_config["width"]] || WIDTH_CLASSES["full"],
      visibility: mod_config["visibility"],
      events: mod_config["events"] || {},
      config: config
    }

    if base[:module_type] == "list"
      list_data = fetch_list_data(entity, config)
      base.merge!(
        records: list_data[:records],
        pagination: list_data[:pagination],
        columns: resolve_columns(entity, config["columns"])
      )
    end

    base
  end

  def resolve_entity(entity_id)
    return nil unless entity_id

    Entity.find_by(id: entity_id, customer_id: @customer_id)
  end

  def fetch_list_data(entity, config)
    return { records: [], pagination: { total_count: 0 } } unless entity

    builder = FlowchartRuntime::QueryBuilder.for_entity(entity, customer_id: @customer_id)

    conditions = config["conditions"]
    builder = builder.where(conditions, {}) if conditions.present?

    sort_field = @params[:sort] || config["defaultSort"] || "created_at"
    sort_dir = @params[:direction] || config["defaultDirection"] || "desc"
    sort_ref = sort_field.start_with?("data.") ? sort_field : "data.#{sort_field}"
    builder = builder.order(sort_ref, sort_dir)

    page_size = (config["pageSize"] || 25).to_i
    page_num = (@params[:page] || 1).to_i
    builder = builder.paginate(page: page_num, per_page: page_size)

    result = builder.execute
    {
      records: result.records,
      pagination: {
        total_count: result.total_count,
        page: result.page,
        per_page: result.per_page,
        total_pages: result.total_pages,
        has_next: result.has_next
      }
    }
  end

  def resolve_columns(entity, column_slugs)
    return [] unless entity && column_slugs

    schema = entity.property_schema_json || []
    column_slugs.filter_map do |slug|
      field = schema.find { |f| f["name_slug"] == slug }
      next unless field

      { slug: slug, name: field["name"], html_type: field["html_type"] || "text" }
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/composite_page_renderer_spec.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/composite_page_renderer.rb spec/services/composite_page_renderer_spec.rb
git commit -m "feat: add CompositePageRenderer for multi-module page orchestration"
```

---

## Task 2: ListComponent ViewComponent

**Files:**
- Create: `app/components/composite_modules/list_component.rb`
- Create: `app/components/composite_modules/list_component.html.erb`
- Create: `spec/components/composite_modules/list_component_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/components/composite_modules/list_component_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CompositeModules::ListComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Name", "name_slug" => "name", "type" => "String", "html_type" => "text" },
      { "name" => "Status", "name_slug" => "status", "type" => "String", "html_type" => "text" }
    ].to_json)
  end

  let(:records) do
    [
      create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Alice", "status" => "active" }.to_json),
      create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Bob", "status" => "inactive" }.to_json)
    ]
  end

  let(:columns) do
    [
      { slug: "name", name: "Name", html_type: "text" },
      { slug: "status", name: "Status", html_type: "text" }
    ]
  end

  let(:pagination) do
    { total_count: 2, page: 1, per_page: 25, total_pages: 1, has_next: false }
  end

  it "renders a table with column headers" do
    html = render_inline(described_class.new(
      module_id: "mod_1",
      records: records,
      columns: columns,
      pagination: pagination
    ))

    expect(html.css("table")).to be_present
    expect(html.css("th").map(&:text)).to include("Name", "Status")
  end

  it "renders data rows" do
    html = render_inline(described_class.new(
      module_id: "mod_1",
      records: records,
      columns: columns,
      pagination: pagination
    ))

    rows = html.css("tbody tr")
    expect(rows.size).to eq(2)
    expect(rows.first.text).to include("Alice")
  end

  it "renders empty state when no records" do
    html = render_inline(described_class.new(
      module_id: "mod_1",
      records: [],
      columns: columns,
      pagination: { total_count: 0, page: 1, per_page: 25, total_pages: 0, has_next: false }
    ))

    expect(html.text).to include("No records found")
  end

  it "renders pagination info" do
    html = render_inline(described_class.new(
      module_id: "mod_1",
      records: records,
      columns: columns,
      pagination: { total_count: 50, page: 1, per_page: 25, total_pages: 2, has_next: true }
    ))

    expect(html.text).to include("50")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/composite_modules/list_component_spec.rb`
Expected: FAIL — `uninitialized constant CompositeModules::ListComponent`

- [ ] **Step 3: Write implementation**

```ruby
# app/components/composite_modules/list_component.rb
# frozen_string_literal: true

module CompositeModules
  class ListComponent < ApplicationComponent
    def initialize(module_id:, records:, columns:, pagination:, sortable: true, row_actions: [])
      @module_id = module_id
      @records = records
      @columns = columns
      @pagination = pagination
      @sortable = sortable
      @row_actions = row_actions
    end

    private

    attr_reader :module_id, :records, :columns, :pagination, :sortable, :row_actions

    def cell_value(record, column)
      record.data_json[column[:slug].to_s] || record[column[:slug].to_s]
    rescue StandardError
      ""
    end

    def empty?
      records.empty?
    end

    def showing_range
      return "0" if pagination[:total_count] == 0

      start_idx = ((pagination[:page] || 1) - 1) * (pagination[:per_page] || 25) + 1
      end_idx = [start_idx + records.size - 1, pagination[:total_count]].min
      "#{start_idx}-#{end_idx} of #{pagination[:total_count]}"
    end
  end
end
```

```erb
<%# app/components/composite_modules/list_component.html.erb %>
<div id="<%= module_id %>_list"
     data-controller="list-module"
     data-list-module-module-id-value="<%= module_id %>"
     class="overflow-hidden">

  <% if empty? %>
    <div class="px-6 py-12 text-center text-gray-500">
      <p class="text-sm">No records found</p>
    </div>
  <% else %>
    <div class="overflow-x-auto">
      <table class="min-w-full divide-y divide-gray-200">
        <thead class="bg-gray-50">
          <tr>
            <% columns.each do |col| %>
              <th scope="col" class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                <%= col[:name] %>
              </th>
            <% end %>
            <% if row_actions.any? %>
              <th scope="col" class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Actions
              </th>
            <% end %>
          </tr>
        </thead>
        <tbody class="bg-white divide-y divide-gray-200">
          <% records.each do |record| %>
            <tr class="hover:bg-gray-50 cursor-pointer"
                data-action="click->list-module#selectRow"
                data-record-id="<%= record.id %>">
              <% columns.each do |col| %>
                <td class="px-4 py-3 text-sm text-gray-900 whitespace-nowrap">
                  <%= cell_value(record, col) %>
                </td>
              <% end %>
              <% if row_actions.any? %>
                <td class="px-4 py-3 text-right text-sm">
                  <% row_actions.each do |action| %>
                    <button class="text-indigo-600 hover:text-indigo-900 ml-2 text-xs font-medium"
                            data-action="click->list-module#rowAction"
                            data-row-action="<%= action %>"
                            data-record-id="<%= record.id %>">
                      <%= action.capitalize %>
                    </button>
                  <% end %>
                </td>
              <% end %>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>

    <div class="px-4 py-3 bg-gray-50 border-t border-gray-200 flex items-center justify-between text-sm text-gray-500">
      <span>Showing <%= showing_range %></span>
      <% if pagination[:total_pages] && pagination[:total_pages] > 1 %>
        <div class="flex gap-2">
          <% if pagination[:page] && pagination[:page] > 1 %>
            <button class="px-3 py-1 border rounded text-xs hover:bg-gray-100"
                    data-action="click->list-module#prevPage">
              Previous
            </button>
          <% end %>
          <% if pagination[:has_next] %>
            <button class="px-3 py-1 border rounded text-xs hover:bg-gray-100"
                    data-action="click->list-module#nextPage">
              Next
            </button>
          <% end %>
        </div>
      <% end %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/composite_modules/list_component_spec.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/components/composite_modules/list_component.rb app/components/composite_modules/list_component.html.erb spec/components/composite_modules/list_component_spec.rb
git commit -m "feat: add ListComponent for composite page table display"
```

---

## Task 3: ModuleWrapperComponent

**Files:**
- Create: `app/components/composite_modules/module_wrapper_component.rb`
- Create: `app/components/composite_modules/module_wrapper_component.html.erb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/components/composite_modules/module_wrapper_component_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CompositeModules::ModuleWrapperComponent, type: :component do
  it "renders with correct width class" do
    html = render_inline(described_class.new(
      module_id: "mod_1",
      title: "Orders",
      width: "half",
      visibility: nil,
      events: {}
    )) { "content" }

    wrapper = html.css("[data-module-id='mod_1']").first
    expect(wrapper["class"]).to include("col-span-6")
  end

  it "renders title" do
    html = render_inline(described_class.new(
      module_id: "mod_1",
      title: "My Module",
      width: "full",
      visibility: nil,
      events: {}
    )) { "content" }

    expect(html.text).to include("My Module")
  end

  it "starts hidden when visibility has on_event" do
    html = render_inline(described_class.new(
      module_id: "mod_2",
      title: "Details",
      width: "half",
      visibility: { "on_event" => "row:selected" },
      events: { "listen" => ["row:selected"] }
    )) { "content" }

    wrapper = html.css("[data-module-id='mod_2']").first
    expect(wrapper["class"]).to include("hidden")
  end

  it "renders content block" do
    html = render_inline(described_class.new(
      module_id: "mod_1",
      title: "Test",
      width: "full",
      visibility: nil,
      events: {}
    )) { "<p>Hello</p>".html_safe }

    expect(html.text).to include("Hello")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/composite_modules/module_wrapper_component_spec.rb`
Expected: FAIL — `uninitialized constant`

- [ ] **Step 3: Write implementation**

```ruby
# app/components/composite_modules/module_wrapper_component.rb
# frozen_string_literal: true

module CompositeModules
  class ModuleWrapperComponent < ApplicationComponent
    WIDTH_CLASSES = {
      "full" => "col-span-12",
      "half" => "col-span-6",
      "third" => "col-span-4",
      "two_thirds" => "col-span-8"
    }.freeze

    def initialize(module_id:, title:, width:, visibility:, events:)
      @module_id = module_id
      @title = title
      @width = width
      @visibility = visibility
      @events = events
    end

    private

    attr_reader :module_id, :title, :width, :visibility, :events

    def width_class
      WIDTH_CLASSES[width] || WIDTH_CLASSES["full"]
    end

    def hidden?
      visibility.is_a?(Hash) && visibility["on_event"].present?
    end

    def wrapper_classes
      classes = [width_class, "bg-white rounded-lg shadow border border-gray-200 overflow-hidden"]
      classes << "hidden" if hidden?
      classes.join(" ")
    end

    def listen_events
      (events["listen"] || []).join(",")
    end
  end
end
```

```erb
<%# app/components/composite_modules/module_wrapper_component.html.erb %>
<div data-module-id="<%= module_id %>"
     data-listen-events="<%= listen_events %>"
     class="<%= wrapper_classes %>">
  <% if title.present? %>
    <div class="px-4 py-3 border-b border-gray-200 bg-gray-50">
      <h3 class="text-sm font-semibold text-gray-700"><%= title %></h3>
    </div>
  <% end %>
  <div class="module-content">
    <%= content %>
  </div>
</div>
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/composite_modules/module_wrapper_component_spec.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/components/composite_modules/module_wrapper_component.rb app/components/composite_modules/module_wrapper_component.html.erb spec/components/composite_modules/module_wrapper_component_spec.rb
git commit -m "feat: add ModuleWrapperComponent with width, visibility, events"
```

---

## Task 4: Stimulus Controllers

**Files:**
- Create: `app/javascript/controllers/composite_page_controller.js`
- Create: `app/javascript/controllers/list_module_controller.js`

- [ ] **Step 1: Create composite page controller**

```javascript
// app/javascript/controllers/composite_page_controller.js
import { Controller } from "@hotwired/stimulus"

// Manages inter-module communication in composite pages.
// Relays custom events between child modules and handles visibility toggling.
export default class extends Controller {
  static targets = ["module"]

  connect() {
    this.element.addEventListener("list-module:row-selected", this.handleRowSelected.bind(this))
    this.element.addEventListener("list-module:row-action", this.handleRowAction.bind(this))
  }

  disconnect() {
    this.element.removeEventListener("list-module:row-selected", this.handleRowSelected.bind(this))
    this.element.removeEventListener("list-module:row-action", this.handleRowAction.bind(this))
  }

  handleRowSelected(event) {
    const { recordId, moduleId } = event.detail
    this.showModulesListeningTo("row:selected")
    this.dispatch("row-selected", { detail: { recordId, moduleId } })
  }

  handleRowAction(event) {
    const { action, recordId, moduleId } = event.detail
    this.dispatch("row-action", { detail: { action, recordId, moduleId } })
  }

  showModulesListeningTo(eventName) {
    this.element.querySelectorAll("[data-module-id]").forEach(mod => {
      const listenEvents = (mod.dataset.listenEvents || "").split(",")
      if (listenEvents.includes(eventName)) {
        mod.classList.remove("hidden")
      }
    })
  }
}
```

- [ ] **Step 2: Create list module controller**

```javascript
// app/javascript/controllers/list_module_controller.js
import { Controller } from "@hotwired/stimulus"

// Handles row selection and dispatches events for list modules in composite pages.
export default class extends Controller {
  static values = { moduleId: String, page: { type: Number, default: 1 } }

  selectRow(event) {
    const row = event.currentTarget
    const recordId = row.dataset.recordId

    // Highlight selected row
    this.element.querySelectorAll("tr").forEach(tr => tr.classList.remove("bg-indigo-50"))
    row.classList.add("bg-indigo-50")

    // Dispatch event for composite page controller
    this.dispatch("row-selected", {
      detail: { recordId, moduleId: this.moduleIdValue },
      bubbles: true
    })
  }

  rowAction(event) {
    event.stopPropagation()
    const action = event.currentTarget.dataset.rowAction
    const recordId = event.currentTarget.dataset.recordId

    this.dispatch("row-action", {
      detail: { action, recordId, moduleId: this.moduleIdValue },
      bubbles: true
    })
  }

  prevPage() {
    this.pageValue = Math.max(1, this.pageValue - 1)
    this.reload()
  }

  nextPage() {
    this.pageValue += 1
    this.reload()
  }

  reload() {
    // Turbo Frame reload would go here for server-side pagination
    // For now, dispatch a page change event
    this.dispatch("page-changed", {
      detail: { page: this.pageValue, moduleId: this.moduleIdValue },
      bubbles: true
    })
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/composite_page_controller.js app/javascript/controllers/list_module_controller.js
git commit -m "feat: add Stimulus controllers for composite page events"
```

---

## Task 5: PageContentGenerator — Composite layout delegation

**Files:**
- Modify: `app/services/page_content_generator.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/page_content_generator_composite_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageContentGenerator, "composite layout" do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Name", "name_slug" => "name", "type" => "String", "html_type" => "text" }
    ].to_json)
  end

  before do
    create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Alice" }.to_json)
  end

  it "generates composite layout with list module" do
    page = create(:page, customer: customer, configuration: {
      "layout" => "composite",
      "modules" => [
        {
          "id" => "mod_1",
          "module_type" => "list",
          "title" => "Items",
          "entity_id" => entity.id,
          "width" => "full",
          "config" => { "columns" => ["name"], "pageSize" => 10 }
        }
      ],
      "metadata" => { "entity_id" => entity.id },
      "rules" => [],
      "calculations" => []
    }.to_json)

    generator = described_class.new(page)
    content = generator.generate

    expect(content).to include("composite-page")
    expect(content).to include("Items")
  end

  it "falls back to standard rendering for non-composite layout" do
    page = create(:page, customer: customer, configuration: {
      "pages" => [{ "id" => "page_1", "name" => "Test", "order" => 1, "fields" => [
        { "id" => "f1", "field_type" => "text", "label" => "Name", "property_slug" => "name",
          "property_type" => "string", "html_type" => "text", "width" => "full" }
      ] }],
      "metadata" => { "entity_id" => entity.id },
      "rules" => [],
      "calculations" => []
    }.to_json)

    generator = described_class.new(page)
    content = generator.generate

    expect(content).not_to include("composite-page")
    expect(content).to include("Name")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/page_content_generator_composite_spec.rb`
Expected: FAIL — composite layout not detected

- [ ] **Step 3: Update PageContentGenerator**

In `app/services/page_content_generator.rb`, update the `generate` method. Add a check for composite layout at the top, before the existing pages_config logic:

```ruby
  def generate
    return "" if page.configuration.blank?

    # Composite layout — delegate to CompositePageRenderer
    if page.configuration_json["layout"] == "composite"
      return generate_composite
    end

    # ... existing code unchanged
  end
```

Add the private method:

```ruby
  def generate_composite
    modules_config = page.configuration_json["modules"] || []
    return "" if modules_config.empty?

    renderer = CompositePageRenderer.new(modules_config, customer_id: page.customer_id)
    modules_data = renderer.render_modules

    lines = []
    lines << '<div data-controller="composite-page" class="grid grid-cols-12 gap-4">'

    modules_data.each do |mod|
      lines << render_composite_module(mod)
    end

    lines << '</div>'
    lines.join("\n")
  end

  def render_composite_module(mod)
    wrapper_classes = CompositePageRenderer::WIDTH_CLASSES[mod[:width]] || "col-span-12"
    hidden = mod[:visibility].is_a?(Hash) && mod[:visibility]["on_event"].present?
    listen_events = (mod.dig(:events, "listen") || []).join(",")

    visibility_class = hidden ? " hidden" : ""
    lines = []
    lines << "<div data-module-id=\"#{mod[:id]}\" data-listen-events=\"#{listen_events}\" class=\"#{wrapper_classes} bg-white rounded-lg shadow border border-gray-200 overflow-hidden#{visibility_class}\">"

    if mod[:title].present?
      lines << "  <div class=\"px-4 py-3 border-b border-gray-200 bg-gray-50\">"
      lines << "    <h3 class=\"text-sm font-semibold text-gray-700\">#{ERB::Util.html_escape(mod[:title])}</h3>"
      lines << "  </div>"
    end

    lines << "  <div class=\"module-content\">"

    case mod[:module_type]
    when "list"
      lines << render_list_module(mod)
    when "form"
      lines << "    <!-- Form module content rendered via existing form fields -->"
    end

    lines << "  </div>"
    lines << "</div>"
    lines.join("\n")
  end

  def render_list_module(mod)
    return "    <div class=\"px-6 py-12 text-center text-gray-500\"><p class=\"text-sm\">No records found</p></div>" if mod[:records].empty?

    lines = []
    lines << "    <div class=\"overflow-x-auto\" data-controller=\"list-module\" data-list-module-module-id-value=\"#{mod[:id]}\">"
    lines << "      <table class=\"min-w-full divide-y divide-gray-200\">"
    lines << "        <thead class=\"bg-gray-50\"><tr>"
    mod[:columns].each do |col|
      lines << "          <th class=\"px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider\">#{ERB::Util.html_escape(col[:name])}</th>"
    end
    lines << "        </tr></thead>"
    lines << "        <tbody class=\"bg-white divide-y divide-gray-200\">"
    mod[:records].each do |record|
      lines << "          <tr class=\"hover:bg-gray-50 cursor-pointer\" data-action=\"click->list-module#selectRow\" data-record-id=\"#{record.id}\">"
      mod[:columns].each do |col|
        value = record.data_json[col[:slug].to_s] rescue ""
        lines << "            <td class=\"px-4 py-3 text-sm text-gray-900\">#{ERB::Util.html_escape(value)}</td>"
      end
      lines << "          </tr>"
    end
    lines << "        </tbody>"
    lines << "      </table>"
    lines << "      <div class=\"px-4 py-3 bg-gray-50 border-t text-sm text-gray-500\">Showing #{mod[:pagination][:total_count]} records</div>"
    lines << "    </div>"
    lines.join("\n")
  end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/page_content_generator_composite_spec.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/page_content_generator.rb spec/services/page_content_generator_composite_spec.rb
git commit -m "feat: detect composite layout in PageContentGenerator and render list modules"
```

---

## Task 6: Route and controller for module data

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/pages_controller.rb`

- [ ] **Step 1: Add route and action**

In `config/routes.rb`, inside the pages `member do` block, add:
```ruby
get "module_data/:module_id", action: :module_data, as: :module_data
```

In `app/controllers/pages_controller.rb`, add:
```ruby
  def module_data
    @page = Page.for_current_customer.find(params[:id])
    module_id = params[:module_id]
    modules_config = @page.configuration_json["modules"] || []
    mod_config = modules_config.find { |m| m["id"] == module_id }

    return render json: { error: "Module not found" }, status: :not_found unless mod_config

    renderer = CompositePageRenderer.new([mod_config], customer_id: current_customer_id, params: {
      page: params[:page],
      sort: params[:sort],
      direction: params[:direction]
    })
    result = renderer.render_modules.first

    render json: {
      records: result[:records].map { |r| r.as_json.merge(r.data_json) },
      pagination: result[:pagination],
      columns: result[:columns]
    }
  end
```

- [ ] **Step 2: Verify syntax**

Run: `bundle exec ruby -c app/controllers/pages_controller.rb && bundle exec ruby -c config/routes.rb`
Expected: Syntax OK

- [ ] **Step 3: Commit**

```bash
git add config/routes.rb app/controllers/pages_controller.rb
git commit -m "feat: add module_data endpoint for composite page module requests"
```

---

## Task 7: Integration test

**Files:**
- Create: `spec/integration/composite_page_integration_spec.rb`

- [ ] **Step 1: Write the integration test**

```ruby
# spec/integration/composite_page_integration_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Composite page integration", type: :model do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, name: "Order", customer: customer, property_schema: [
      { "name" => "Customer Name", "name_slug" => "customer_name", "type" => "String", "html_type" => "text" },
      { "name" => "Amount", "name_slug" => "amount", "type" => "Float", "html_type" => "number" },
      { "name" => "Status", "name_slug" => "status", "type" => "String", "html_type" => "text" }
    ].to_json)
  end

  before do
    create(:entity_entry, entity: entity, customer: customer, data: { "customer_name" => "Alice", "amount" => "100", "status" => "pending" }.to_json)
    create(:entity_entry, entity: entity, customer: customer, data: { "customer_name" => "Bob", "amount" => "250", "status" => "shipped" }.to_json)
    create(:entity_entry, entity: entity, customer: customer, data: { "customer_name" => "Carol", "amount" => "75", "status" => "pending" }.to_json)
  end

  describe "CompositePageRenderer with list module" do
    it "renders list module with all records" do
      modules_config = [
        {
          "id" => "orders_list",
          "module_type" => "list",
          "title" => "Orders",
          "entity_id" => entity.id,
          "width" => "full",
          "config" => { "columns" => ["customer_name", "amount", "status"], "pageSize" => 25 }
        }
      ]

      renderer = CompositePageRenderer.new(modules_config, customer_id: customer.id)
      result = renderer.render_modules

      expect(result.size).to eq(1)
      mod = result.first
      expect(mod[:records].size).to eq(3)
      expect(mod[:columns].map { |c| c[:slug] }).to eq(%w[customer_name amount status])
      expect(mod[:pagination][:total_count]).to eq(3)
    end

    it "applies conditions to filter list" do
      modules_config = [
        {
          "id" => "pending_orders",
          "module_type" => "list",
          "entity_id" => entity.id,
          "width" => "half",
          "config" => {
            "columns" => ["customer_name", "amount"],
            "conditions" => { "operator" => "AND", "rules" => [{ "field" => "data.status", "op" => "==", "value" => "pending" }] }
          }
        }
      ]

      renderer = CompositePageRenderer.new(modules_config, customer_id: customer.id)
      result = renderer.render_modules.first

      expect(result[:records].size).to eq(2)
      names = result[:records].map { |r| r.data_json["customer_name"] }
      expect(names).to contain_exactly("Alice", "Carol")
    end

    it "renders multiple modules side by side" do
      modules_config = [
        { "id" => "list_mod", "module_type" => "list", "entity_id" => entity.id, "width" => "half",
          "config" => { "columns" => ["customer_name"] } },
        { "id" => "form_mod", "module_type" => "form", "entity_id" => entity.id, "width" => "half",
          "config" => { "fields" => [] } }
      ]

      renderer = CompositePageRenderer.new(modules_config, customer_id: customer.id)
      result = renderer.render_modules

      expect(result.size).to eq(2)
      expect(result[0][:width_class]).to eq("col-span-6")
      expect(result[1][:width_class]).to eq("col-span-6")
    end

    it "generates HTML via PageContentGenerator" do
      page = create(:page, customer: customer, configuration: {
        "layout" => "composite",
        "modules" => [
          { "id" => "mod_1", "module_type" => "list", "title" => "Orders",
            "entity_id" => entity.id, "width" => "full",
            "config" => { "columns" => ["customer_name", "status"], "pageSize" => 10 } }
        ],
        "metadata" => { "entity_id" => entity.id },
        "rules" => [], "calculations" => []
      }.to_json)

      content = PageContentGenerator.new(page).generate

      expect(content).to include("composite-page")
      expect(content).to include("Orders")
      expect(content).to include("Alice")
      expect(content).to include("Bob")
      expect(content).to include("Carol")
      expect(content).to include("list-module")
    end

    it "handles visibility configuration" do
      modules_config = [
        { "id" => "mod_1", "module_type" => "list", "entity_id" => entity.id, "width" => "half",
          "config" => { "columns" => ["customer_name"] }, "visibility" => nil, "events" => { "emit" => ["row:selected"] } },
        { "id" => "mod_2", "module_type" => "form", "entity_id" => entity.id, "width" => "half",
          "config" => {}, "visibility" => { "on_event" => "row:selected" }, "events" => { "listen" => ["row:selected"] } }
      ]

      renderer = CompositePageRenderer.new(modules_config, customer_id: customer.id)
      result = renderer.render_modules

      expect(result[0][:visibility]).to be_nil
      expect(result[1][:visibility]).to eq({ "on_event" => "row:selected" })
    end
  end
end
```

- [ ] **Step 2: Run the integration test**

Run: `bundle exec rspec spec/integration/composite_page_integration_spec.rb`
Expected: All PASS

- [ ] **Step 3: Commit**

```bash
git add spec/integration/composite_page_integration_spec.rb
git commit -m "test: add integration tests for composite pages"
```
