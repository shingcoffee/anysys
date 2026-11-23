# Code Generator Pages UI Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign all code generator admin pages to use a light theme matching entity pages, with sidebar + adaptive content layout, lazy-loaded categories, merged detail component, and side-by-side form editing.

**Architecture:** Single-page master-detail pattern. Fixed sidebar with category navigation. Main content area morphs between card grid (browse) and detail view (selected generator) via Turbo Frame. Form page uses side-by-side layout with live preview. All pages switch from dark theme to light theme matching entity pages.

**Tech Stack:** Rails 8.1, ViewComponent, TailwindCSS, StimulusJS, Turbo Frames

**Spec:** `docs/superpowers/specs/2026-04-09-code-generator-ui-redesign.md`

---

### Task 1: Update Controller for Category-Based Loading

**Files:**
- Modify: `app/controllers/admin/code_generators_controller.rb`
- Test: `spec/controllers/admin/code_generators_controller_spec.rb`

The controller needs to support category-filtered index requests and render the sidebar layout for direct show URL visits.

- [ ] **Step 1: Write failing test for category-filtered index**

Add to `spec/controllers/admin/code_generators_controller_spec.rb` inside the `describe "GET #index"` block:

```ruby
it "filters by step action category when category param is present" do
  get :index, params: { category: "model_operations", kind: "step_action" }
  expect(response).to have_http_status(:success)
  expect(assigns(:category)).to eq("model_operations")
  expect(assigns(:kind)).to eq("step_action")
  expect(assigns(:filtered_generators)).to be_a(Array)
  expect(assigns(:filtered_generators)).to all(
    satisfy { |_name, klass| klass._metadata[:category].to_s == "model_operations" }
  )
end

it "filters by element type when element_type param is present" do
  get :index, params: { element_type: "start" }
  expect(response).to have_http_status(:success)
  expect(assigns(:element_type)).to eq("start")
  expect(assigns(:filtered_generators)).to be_a(Array)
end

it "assigns sidebar_data for all requests" do
  get :index
  expect(response).to have_http_status(:success)
  expect(assigns(:sidebar_data)).to be_a(Array)
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/controllers/admin/code_generators_controller_spec.rb -v`
Expected: 3 FAIL (undefined method `category`, `element_type`, `filtered_generators`, `sidebar_data`)

- [ ] **Step 3: Implement controller changes**

Replace the `index` and `show` methods in `app/controllers/admin/code_generators_controller.rb`:

```ruby
def index
  registry = ::CodeGenerators::GeneratorRegistry.instance
  @step_actions = registry.step_action_generators
  @element_types = registry.element_type_generators
  @sidebar_data = build_sidebar_data

  @category = params[:category]
  @kind = params[:kind]
  @element_type = params[:element_type]

  @filtered_generators = filter_generators
end

def show
  @source_code = File.read(@file_path)
  @generator_class = @registry_entry

  # For direct URL visits (non-turbo-frame), also load sidebar data
  unless turbo_frame_request?
    registry = ::CodeGenerators::GeneratorRegistry.instance
    @step_actions = registry.step_action_generators
    @element_types = registry.element_type_generators
    @sidebar_data = build_sidebar_data
  end
end
```

Add these private methods at the bottom of the private section:

```ruby
def build_sidebar_data
  registry = ::CodeGenerators::GeneratorRegistry.instance
  step_actions = registry.step_action_generators
  element_types = registry.element_type_generators

  sidebar = []

  # Element types
  element_types.each do |name, _klass|
    sidebar << { kind: "element_type", key: name.to_s, label: name.to_s.titleize, count: 1 }
  end

  # Step action categories
  subcats = step_actions.group_by { |_name, klass| klass._metadata[:category].to_s }
  subcats.each do |category, generators|
    sidebar << { kind: "step_action", key: category, label: category.tr("_", " ").titleize, count: generators.size }
  end

  sidebar
end

def filter_generators
  if @element_type.present?
    registry = ::CodeGenerators::GeneratorRegistry.instance
    et = registry.element_type_generators
    gen = et[@element_type]
    gen ? [[@element_type, gen]] : []
  elsif @category.present?
    @step_actions.select { |_name, klass| klass._metadata[:category].to_s == @category }
      .to_a
  else
    # Default: show first element type (start)
    registry = ::CodeGenerators::GeneratorRegistry.instance
    et = registry.element_type_generators
    first_key = et.keys.first
    first_key ? [[first_key, et[first_key]]] : []
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/controllers/admin/code_generators_controller_spec.rb -v`
Expected: All PASS

- [ ] **Step 5: Update existing show spec for sidebar_data on direct visit**

Add to the `describe "GET #show"` block:

```ruby
it "assigns sidebar_data for direct URL visits" do
  get :show, params: { path: "element_types/process/model_operations/new_model_generator" }
  expect(assigns(:sidebar_data)).to be_a(Array)
  expect(assigns(:sidebar_data).size).to be > 0
end
```

- [ ] **Step 6: Run full controller spec**

Run: `bundle exec rspec spec/controllers/admin/code_generators_controller_spec.rb -v`
Expected: All PASS

- [ ] **Step 7: Commit**

```bash
git add app/controllers/admin/code_generators_controller.rb spec/controllers/admin/code_generators_controller_spec.rb
git commit -m "feat: add category filtering and sidebar data to code generators controller"
```

---

### Task 2: Create SidebarComponent

**Files:**
- Create: `app/components/admin/code_generators/sidebar_component.rb`
- Create: `app/components/admin/code_generators/sidebar_component.html.erb`

The sidebar displays element types and step action categories as a flat navigation list.

- [ ] **Step 1: Create the SidebarComponent Ruby class**

Create `app/components/admin/code_generators/sidebar_component.rb`:

```ruby
# frozen_string_literal: true

module Admin
  module CodeGenerators
    class SidebarComponent < ApplicationComponent
      ELEMENT_TYPE_DOTS = {
        "start" => "bg-green-500", "end" => "bg-red-500", "decision" => "bg-amber-500",
        "loop" => "bg-cyan-500", "timer" => "bg-orange-500", "error_handler" => "bg-rose-500",
        "subflow" => "bg-purple-500", "fork" => "bg-teal-500", "join" => "bg-sky-500",
        "parallel_for_each" => "bg-violet-500", "switch" => "bg-lime-500",
        "saga" => "bg-fuchsia-500", "signal_wait" => "bg-yellow-500", "transaction" => "bg-blue-500"
      }.freeze

      STEP_ACTION_ICONS = {
        "model_operations" => "M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7",
        "validation" => "M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z",
        "data_operations" => "M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15",
        "communication" => "M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z",
        "security" => "M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z",
        "background" => "M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z",
        "file_operations" => "M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z",
        "realtime" => "M13 10V3L4 14h7v7l9-11h-7z",
        "response" => "M3 10h10a8 8 0 018 8v2M3 10l6 6m-6-6l6-6",
        "concurrency" => "M8 7h12m-12 5h12m-12 5h12M4 7h.01M4 12h.01M4 17h.01",
        "service_invocation" => "M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4",
        "caching" => "M5 8h14M5 8a2 2 0 110-4h14a2 2 0 110 4M5 8v10a2 2 0 002 2h10a2 2 0 002-2V8",
        "human_workflow" => "M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z",
        "resilience" => "M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z",
        "scheduling_time" => "M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z",
        "utility" => "M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.066 2.573c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.573 1.066c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.066-2.573c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
      }.freeze

      def initialize(sidebar_data:, active_category: nil, active_element_type: nil, total_count: 0)
        @sidebar_data = sidebar_data
        @active_category = active_category
        @active_element_type = active_element_type
        @total_count = total_count
      end

      def element_types
        @sidebar_data.select { |item| item[:kind] == "element_type" }
      end

      def step_action_categories
        @sidebar_data.select { |item| item[:kind] == "step_action" }
      end

      def active?(item)
        if item[:kind] == "element_type"
          @active_element_type == item[:key]
        else
          @active_category == item[:key]
        end
      end

      def item_url(item)
        if item[:kind] == "element_type"
          admin_code_generators_path(element_type: item[:key])
        else
          admin_code_generators_path(category: item[:key], kind: "step_action")
        end
      end

      def dot_color(key)
        ELEMENT_TYPE_DOTS[key] || "bg-gray-400"
      end

      def step_action_icon(key)
        STEP_ACTION_ICONS[key] || "M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4"
      end
    end
  end
end
```

- [ ] **Step 2: Create the SidebarComponent template**

Create `app/components/admin/code_generators/sidebar_component.html.erb`:

```erb
<nav class="w-64 flex-shrink-0 bg-white border-r border-gray-200 flex flex-col h-[calc(100vh-64px)] sticky top-16"
     data-controller="generator-search">
  <%# Header %>
  <div class="px-4 pt-4 pb-3 border-b border-gray-100">
    <div class="flex items-center gap-2">
      <div class="w-7 h-7 rounded-lg bg-gradient-to-br from-indigo-500 to-indigo-600 flex items-center justify-center">
        <svg class="w-4 h-4 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4"/></svg>
      </div>
      <div>
        <h1 class="text-sm font-bold text-gray-900">Code Generators</h1>
        <p class="text-[10px] text-gray-400"><%= @total_count %> generators</p>
      </div>
    </div>
  </div>

  <%# Search %>
  <div class="px-3 py-2.5">
    <div class="relative">
      <svg class="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/></svg>
      <input type="text"
        data-generator-search-target="input"
        data-action="input->generator-search#filter"
        placeholder="Search generators..."
        class="w-full pl-8 pr-3 py-1.5 text-xs bg-gray-50 border border-gray-200 text-gray-900 rounded-lg focus:ring-indigo-500 focus:border-indigo-500 placeholder-gray-400">
    </div>
  </div>

  <%# Scrollable category list %>
  <div class="flex-1 overflow-y-auto px-2 pb-2" data-generator-search-target="tree">
    <%# No results %>
    <div data-generator-search-target="noResults" class="hidden px-3 py-6 text-center">
      <p class="text-xs text-gray-400">No generators found</p>
    </div>

    <%# Element Types %>
    <div class="px-2 pt-2 pb-1">
      <span class="text-[10px] font-semibold uppercase tracking-wider text-gray-400">Element Types</span>
    </div>
    <% element_types.each do |item| %>
      <a href="<%= item_url(item) %>"
         data-turbo-frame="generator-content"
         data-generator-search-target="leaf"
         data-name="<%= item[:label] %>"
         data-description="<%= item[:key] %>"
         class="flex items-center gap-2.5 px-3 py-1.5 rounded-md text-sm transition-colors
                <%= active?(item) ? 'bg-indigo-50 text-indigo-700 font-medium' : 'text-gray-600 hover:bg-gray-50 hover:text-gray-900' %>">
        <span class="w-1.5 h-1.5 rounded-full flex-shrink-0 <%= dot_color(item[:key]) %>"></span>
        <span class="truncate"><%= item[:label] %></span>
        <span class="ml-auto text-[10px] flex-shrink-0
              <%= active?(item) ? 'text-indigo-500 bg-indigo-100 px-1.5 rounded-full' : 'text-gray-400' %>">
          <%= item[:count] %>
        </span>
      </a>
    <% end %>

    <%# Step Actions %>
    <div class="px-2 pt-4 pb-1">
      <span class="text-[10px] font-semibold uppercase tracking-wider text-gray-400">Step Actions</span>
    </div>
    <% step_action_categories.each do |item| %>
      <a href="<%= item_url(item) %>"
         data-turbo-frame="generator-content"
         data-generator-search-target="leaf"
         data-name="<%= item[:label] %>"
         data-description="<%= item[:key] %>"
         class="flex items-center gap-2.5 px-3 py-1.5 rounded-md text-sm transition-colors
                <%= active?(item) ? 'bg-indigo-50 text-indigo-700 font-medium' : 'text-gray-600 hover:bg-gray-50 hover:text-gray-900' %>">
        <svg class="w-3.5 h-3.5 flex-shrink-0 <%= active?(item) ? 'text-indigo-500' : 'text-gray-400' %>" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="<%= step_action_icon(item[:key]) %>"/>
        </svg>
        <span class="truncate"><%= item[:label] %></span>
        <span class="ml-auto text-[10px] flex-shrink-0
              <%= active?(item) ? 'text-indigo-500 bg-indigo-100 px-1.5 rounded-full' : 'text-gray-400' %>">
          <%= item[:count] %>
        </span>
      </a>
    <% end %>
  </div>

  <%# New Generator button (pinned to bottom) %>
  <div class="p-3 border-t border-gray-100">
    <%= render ButtonComponent.new(tag: :a, variant: :primary, href: new_admin_code_generator_path(kind: "step_action")) do %>
      <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/></svg>
      New Generator
    <% end %>
  </div>
</nav>
```

- [ ] **Step 3: Commit**

```bash
git add app/components/admin/code_generators/sidebar_component.rb app/components/admin/code_generators/sidebar_component.html.erb
git commit -m "feat: add SidebarComponent for code generator navigation"
```

---

### Task 3: Create CardGridComponent

**Files:**
- Create: `app/components/admin/code_generators/card_grid_component.rb`
- Create: `app/components/admin/code_generators/card_grid_component.html.erb`

The card grid displays generators for a selected category.

- [ ] **Step 1: Create the CardGridComponent Ruby class**

Create `app/components/admin/code_generators/card_grid_component.rb`:

```ruby
# frozen_string_literal: true

module Admin
  module CodeGenerators
    class CardGridComponent < ApplicationComponent
      def initialize(generators:, category_label:, category_icon: nil, category_count: 0)
        @generators = generators
        @category_label = category_label
        @category_icon = category_icon
        @category_count = category_count
      end

      def generator_path(name, klass)
        relative = klass.name
                       .delete_prefix("CodeGenerators::")
                       .underscore
                       .gsub("::", "/")
        "/admin/code_generators/#{relative.gsub('/', '%2F')}"
      end

      def generator_io(klass)
        result = ::CodeGenerators::TestRunner.run(klass, config: klass.sample_input)
        { inputs: result[:inputs], outputs: result[:outputs] }
      rescue StandardError
        { inputs: [], outputs: [] }
      end
    end
  end
end
```

- [ ] **Step 2: Create the CardGridComponent template**

Create `app/components/admin/code_generators/card_grid_component.html.erb`:

```erb
<%# Top bar %>
<div class="bg-white border-b border-gray-200 px-6 py-4 flex items-center justify-between">
  <div class="flex items-center gap-2.5">
    <% if @category_icon %>
      <svg class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="<%= @category_icon %>"/>
      </svg>
    <% end %>
    <h2 class="text-base font-semibold text-gray-900"><%= @category_label %></h2>
    <span class="text-xs text-gray-400 bg-gray-100 px-2 py-0.5 rounded-full"><%= @category_count %> generators</span>
  </div>
</div>

<%# Card grid %>
<div class="p-6">
  <% if @generators.empty? %>
    <%= render EmptyStateComponent.new(
      title: "No generators",
      description: "No generators found in this category.",
      action_path: new_admin_code_generator_path(kind: "step_action"),
      action_text: "New Generator"
    ) %>
  <% else %>
    <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
      <% @generators.each do |name, klass| %>
        <a href="<%= generator_path(name, klass) %>"
           data-turbo-frame="generator-content"
           class="group block bg-white border border-gray-200 rounded-lg p-4 shadow-sm hover:border-indigo-300 hover:shadow-md transition-all duration-200">
          <div class="flex items-start justify-between mb-1.5">
            <h3 class="font-mono text-sm font-semibold text-gray-900 group-hover:text-indigo-600 transition-colors"><%= name %></h3>
            <span class="text-[10px] text-gray-400 bg-gray-100 px-1.5 py-0.5 rounded flex-shrink-0">v<%= klass._metadata[:version] %></span>
          </div>
          <p class="text-xs text-gray-500 leading-relaxed line-clamp-2 mb-3"><%= klass._metadata[:description] %></p>
          <div class="flex items-center gap-3 pt-2.5 border-t border-gray-100">
            <% io = generator_io(klass) %>
            <% if io[:inputs].any? %>
              <div class="flex items-center gap-1">
                <span class="w-1.5 h-1.5 rounded-full bg-amber-500"></span>
                <span class="text-[10px] text-gray-500"><%= io[:inputs].size %> in</span>
              </div>
            <% end %>
            <% if io[:outputs].any? %>
              <div class="flex items-center gap-1">
                <span class="w-1.5 h-1.5 rounded-full bg-green-500"></span>
                <span class="text-[10px] text-gray-500"><%= io[:outputs].size %> out</span>
              </div>
            <% end %>
            <svg class="w-4 h-4 text-gray-300 group-hover:text-indigo-400 ml-auto transition-colors" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/></svg>
          </div>
        </a>
      <% end %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 3: Commit**

```bash
git add app/components/admin/code_generators/card_grid_component.rb app/components/admin/code_generators/card_grid_component.html.erb
git commit -m "feat: add CardGridComponent for category-based generator browsing"
```

---

### Task 4: Create DetailComponent (Merged from DetailPanel + Show)

**Files:**
- Create: `app/components/admin/code_generators/detail_component.rb`
- Create: `app/components/admin/code_generators/detail_component.html.erb`

This merges `DetailPanelComponent` and `ShowComponent` into one unified component.

- [ ] **Step 1: Create the DetailComponent Ruby class**

Create `app/components/admin/code_generators/detail_component.rb`:

```ruby
# frozen_string_literal: true

module Admin
  module CodeGenerators
    class DetailComponent < ApplicationComponent
      def initialize(generator_class:, source_code:, path:)
        @generator_class = generator_class
        @source_code = source_code
        @path = path
      end

      def metadata
        @generator_class&._metadata || {}
      end

      def test_result
        @test_result ||= begin
          config = @generator_class&.sample_input || {}
          ::CodeGenerators::TestRunner.run(@generator_class, config: config)
        rescue StandardError
          { code: nil, body: nil, inputs: [], outputs: [], validation_errors: [] }
        end
      end

      def input_keys
        test_result[:inputs]
      end

      def output_keys
        test_result[:outputs]
      end

      def deps
        @generator_class ? @generator_class.new({}, {}).dependencies : []
      end

      def generator_name
        @generator_class&.generator_name || "unknown"
      end

      def kind_label
        @generator_class&.generator_kind == :element_type ? "Element Type" : "Step Action"
      end

      def category_label
        metadata[:category].to_s.tr("_", " ").titleize
      end

      def back_url
        if @generator_class&.generator_kind == :element_type
          admin_code_generators_path(element_type: metadata[:category].to_s)
        else
          admin_code_generators_path(category: metadata[:category].to_s, kind: "step_action")
        end
      end

      def edit_path
        "/admin/code_generators/#{@path.gsub('/', '%2F')}/edit"
      end

      def delete_path
        "/admin/code_generators/#{@path.gsub('/', '%2F')}"
      end

      def test_run_path
        "/admin/code_generators/#{@path.gsub('/', '%2F')}/test_run"
      end

      def sample_json
        (@generator_class&.sample_input || {}).to_json
      end

      def sample_code
        test_result[:code]
      end

      def line_count
        @source_code.lines.count
      end
    end
  end
end
```

- [ ] **Step 2: Create the DetailComponent template**

Create `app/components/admin/code_generators/detail_component.html.erb`:

```erb
<div>
  <%# Breadcrumb bar %>
  <div class="bg-white border-b border-gray-200 px-6 py-3 flex items-center justify-between">
    <div class="flex items-center gap-2">
      <a href="<%= back_url %>" data-turbo-frame="generator-content"
         class="inline-flex items-center gap-1 text-sm text-indigo-600 hover:text-indigo-700 font-medium transition-colors">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/></svg>
        Back
      </a>
      <span class="text-gray-300">·</span>
      <span class="text-sm text-gray-400"><%= category_label %></span>
      <span class="text-gray-300">/</span>
      <span class="font-mono text-sm font-semibold text-gray-900"><%= generator_name %></span>
      <span class="text-[10px] text-gray-400 bg-gray-100 px-1.5 py-0.5 rounded">v<%= metadata[:version] %></span>
    </div>
    <div class="flex items-center gap-2">
      <%= render ButtonComponent.new(tag: :a, variant: :primary, size: :sm, href: edit_path, data: { turbo_frame: "_top" }) do %>
        <svg class="w-3.5 h-3.5 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"/></svg>
        Edit
      <% end %>
      <%= button_to delete_path, method: :delete,
          data: { turbo_confirm: "Delete this generator? This cannot be undone.", turbo_frame: "_top" },
          class: "#{ButtonComponent::BASE_CLASSES} #{ButtonComponent::VARIANTS[:danger]} #{ButtonComponent::SIZES[:sm]}" do %>
        <svg class="w-3.5 h-3.5 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/></svg>
        Delete
      <% end %>
    </div>
  </div>

  <div class="p-6">
    <%# Description %>
    <p class="text-sm text-gray-500 mb-5 max-w-2xl"><%= metadata[:description] %></p>

    <%# I/O Panel — horizontal flow %>
    <div class="flex gap-3 mb-5">
      <%# Inputs %>
      <div class="flex-1 bg-amber-50 border border-amber-200 rounded-lg p-4">
        <div class="flex items-center gap-1.5 mb-2.5">
          <span class="w-1.5 h-1.5 rounded-full bg-amber-500"></span>
          <span class="text-[10px] font-semibold text-amber-800 uppercase tracking-wide">Inputs</span>
        </div>
        <div class="flex flex-wrap gap-1.5">
          <% if input_keys.any? %>
            <% input_keys.each do |key| %>
              <span class="inline-flex items-center px-2 py-0.5 text-[10px] font-mono bg-white text-amber-900 rounded border border-amber-200">ctx[:<%= key %>]</span>
            <% end %>
          <% else %>
            <span class="text-xs text-amber-600 italic">None detected</span>
          <% end %>
        </div>
      </div>

      <%# Arrow %>
      <div class="flex items-center flex-shrink-0">
        <span class="text-lg text-gray-300">→</span>
      </div>

      <%# Outputs %>
      <div class="flex-1 bg-green-50 border border-green-200 rounded-lg p-4">
        <div class="flex items-center gap-1.5 mb-2.5">
          <span class="w-1.5 h-1.5 rounded-full bg-green-500"></span>
          <span class="text-[10px] font-semibold text-green-800 uppercase tracking-wide">Outputs</span>
        </div>
        <div class="flex flex-wrap gap-1.5">
          <% if output_keys.any? %>
            <% output_keys.each do |key| %>
              <span class="inline-flex items-center px-2 py-0.5 text-[10px] font-mono bg-white text-green-900 rounded border border-green-200">ctx[:<%= key %>]</span>
            <% end %>
          <% else %>
            <span class="text-xs text-green-600 italic">None detected</span>
          <% end %>
        </div>
      </div>

      <%# Dependencies %>
      <% if deps.any? %>
        <div class="flex-[0.6] bg-indigo-50 border border-indigo-200 rounded-lg p-4">
          <div class="flex items-center gap-1.5 mb-2.5">
            <span class="w-1.5 h-1.5 rounded-full bg-indigo-500"></span>
            <span class="text-[10px] font-semibold text-indigo-800 uppercase tracking-wide">Deps</span>
          </div>
          <div class="flex flex-wrap gap-1.5">
            <% deps.each do |dep| %>
              <span class="inline-flex items-center px-2 py-0.5 text-[10px] font-mono bg-white text-indigo-900 rounded border border-indigo-200"><%= dep %></span>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>

    <%# Test Runner %>
    <div class="bg-white border border-gray-200 rounded-lg overflow-hidden shadow-sm mb-5"
         data-controller="generator-test-runner"
         data-generator-test-runner-url-value="<%= test_run_path %>"
         data-generator-test-runner-sample-value="<%= sample_json %>">
      <div class="px-4 py-3 border-b border-gray-100 flex items-center justify-between">
        <div class="flex items-center gap-2">
          <span class="w-1.5 h-1.5 rounded-full bg-indigo-500"></span>
          <h3 class="text-sm font-semibold text-gray-900">Test Runner</h3>
        </div>
        <div class="flex items-center gap-2">
          <svg data-generator-test-runner-target="spinner" class="hidden w-4 h-4 text-indigo-500 animate-spin" fill="none" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path>
          </svg>
          <button data-generator-test-runner-target="runButton"
                  data-action="click->generator-test-runner#run"
                  class="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-white bg-indigo-600 rounded-lg hover:bg-indigo-700 transition shadow-sm">
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"/></svg>
            Run Test
          </button>
        </div>
      </div>
      <div class="flex divide-x divide-gray-100">
        <%# Config pane %>
        <div class="flex-1 p-4">
          <label class="block text-[10px] font-semibold text-gray-400 uppercase tracking-wide mb-1.5">Config (JSON)</label>
          <textarea data-generator-test-runner-target="configInput"
            rows="4" spellcheck="false"
            class="w-full font-mono text-xs rounded-lg bg-gray-50 border border-gray-200 text-gray-900 focus:ring-indigo-500 focus:border-indigo-500"
            placeholder='{ "key": "value" }'>{}</textarea>
        </div>
        <%# Output pane %>
        <div class="flex-[1.2] p-4">
          <label class="block text-[10px] font-semibold text-gray-400 uppercase tracking-wide mb-1.5">Generated Output</label>
          <div data-generator-test-runner-target="resultsPanel" class="hidden space-y-3">
            <div data-generator-test-runner-target="validationErrors" class="hidden p-2.5 bg-red-50 rounded-lg border border-red-200 space-y-1"></div>
            <div class="flex gap-4">
              <div>
                <span class="text-[10px] font-medium text-gray-400 uppercase">Input</span>
                <div class="flex flex-wrap gap-1 mt-1" data-generator-test-runner-target="inputBadges"></div>
              </div>
              <div>
                <span class="text-[10px] font-medium text-gray-400 uppercase">Output</span>
                <div class="flex flex-wrap gap-1 mt-1" data-generator-test-runner-target="outputBadges"></div>
              </div>
            </div>
            <div class="bg-gray-50 rounded-lg p-3 overflow-x-auto border border-gray-200" data-generator-test-runner-target="codeOutput"></div>
          </div>
          <div data-generator-test-runner-target="placeholder" class="text-xs text-gray-400 italic bg-gray-50 rounded-lg p-3 border border-gray-200">
            Click "Run Test" to execute...
          </div>
        </div>
      </div>
    </div>

    <%# Generated Step Preview %>
    <% if sample_code.present? %>
      <div class="mb-5">
        <%= render CodeBlockComponent.new(code: sample_code, language: "ruby", filename: "generated_step_preview.rb") %>
      </div>
    <% end %>

    <%# Source Code (collapsible) %>
    <details class="bg-white border border-gray-200 rounded-lg overflow-hidden shadow-sm">
      <summary class="px-4 py-3 flex items-center justify-between cursor-pointer select-none hover:bg-gray-50 transition">
        <div class="flex items-center gap-2">
          <svg class="w-3.5 h-3.5 text-gray-400 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"/></svg>
          <span class="text-sm font-semibold text-gray-900">Source Code</span>
          <span class="text-[10px] text-gray-400"><%= line_count %> lines</span>
        </div>
        <span class="font-mono text-[10px] text-gray-400"><%= generator_name %>_generator.rb</span>
      </summary>
      <div class="border-t border-gray-200">
        <%= render CodeBlockComponent.new(code: @source_code, language: "ruby", filename: "#{generator_name}_generator.rb") %>
      </div>
    </details>
  </div>
</div>
```

- [ ] **Step 3: Commit**

```bash
git add app/components/admin/code_generators/detail_component.rb app/components/admin/code_generators/detail_component.html.erb
git commit -m "feat: add unified DetailComponent merging DetailPanel + Show"
```

---

### Task 5: Rewrite IndexComponent

**Files:**
- Modify: `app/components/admin/code_generators/index_component.rb`
- Modify: `app/components/admin/code_generators/index_component.html.erb`
- Modify: `app/views/admin/code_generators/index.html.erb`

The IndexComponent now composes the sidebar + content area (either card grid or detail view).

- [ ] **Step 1: Rewrite IndexComponent Ruby class**

Replace the entire content of `app/components/admin/code_generators/index_component.rb`:

```ruby
# frozen_string_literal: true

module Admin
  module CodeGenerators
    class IndexComponent < ApplicationComponent
      ELEMENT_TYPE_ICONS = {
        start: "M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z",
        end: "M21 12a9 9 0 11-18 0 9 9 0 0118 0z",
        decision: "M8 9l4-4 4 4m0 6l-4 4-4-4",
        loop: "M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15",
        timer: "M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z",
        error_handler: "M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z",
        subflow: "M4 5a1 1 0 011-1h14a1 1 0 011 1v2a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM4 13a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1 1H5a1 1 0 01-1-1v-6zM16 13a1 1 0 011-1h2a1 1 0 011 1v6a1 1 0 01-1 1h-2a1 1 0 01-1-1v-6z",
        fork: "M8 7h12m-12 5h12m-12 5h12M4 7h.01M4 12h.01M4 17h.01",
        join: "M17 8l4 4m0 0l-4 4m4-4H3",
        process: "M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4"
      }.freeze

      ELEMENT_TYPE_COLORS = {
        start: { bg: "bg-green-50", text: "text-green-700", border: "border-green-200", dot: "bg-green-400" },
        end: { bg: "bg-red-50", text: "text-red-700", border: "border-red-200", dot: "bg-red-400" },
        decision: { bg: "bg-amber-50", text: "text-amber-700", border: "border-amber-200", dot: "bg-amber-400" },
        loop: { bg: "bg-cyan-50", text: "text-cyan-700", border: "border-cyan-200", dot: "bg-cyan-400" },
        timer: { bg: "bg-orange-50", text: "text-orange-700", border: "border-orange-200", dot: "bg-orange-400" },
        error_handler: { bg: "bg-rose-50", text: "text-rose-700", border: "border-rose-200", dot: "bg-rose-400" },
        subflow: { bg: "bg-purple-50", text: "text-purple-700", border: "border-purple-200", dot: "bg-purple-400" },
        fork: { bg: "bg-teal-50", text: "text-teal-700", border: "border-teal-200", dot: "bg-teal-400" },
        join: { bg: "bg-sky-50", text: "text-sky-700", border: "border-sky-200", dot: "bg-sky-400" },
        process: { bg: "bg-indigo-50", text: "text-indigo-700", border: "border-indigo-200", dot: "bg-indigo-400" }
      }.freeze

      def initialize(sidebar_data:, filtered_generators:, category: nil, element_type: nil, kind: nil, total_count: 0)
        @sidebar_data = sidebar_data
        @filtered_generators = filtered_generators
        @category = category
        @element_type = element_type
        @kind = kind
        @total_count = total_count
      end

      def category_label
        if @element_type.present?
          @element_type.titleize
        elsif @category.present?
          @category.tr("_", " ").titleize
        else
          @sidebar_data.first&.dig(:label) || "Code Generators"
        end
      end

      def category_icon
        if @element_type.present?
          SidebarComponent::STEP_ACTION_ICONS[@element_type] || SidebarComponent::STEP_ACTION_ICONS.values.first
        elsif @category.present?
          SidebarComponent::STEP_ACTION_ICONS[@category]
        end
      end

      def category_count
        @filtered_generators.size
      end
    end
  end
end
```

- [ ] **Step 2: Rewrite IndexComponent template**

Replace the entire content of `app/components/admin/code_generators/index_component.html.erb`:

```erb
<div class="min-h-screen bg-gray-50 flex">
  <%# Sidebar %>
  <%= render Admin::CodeGenerators::SidebarComponent.new(
    sidebar_data: @sidebar_data,
    active_category: @category,
    active_element_type: @element_type,
    total_count: @total_count
  ) %>

  <%# Main content area %>
  <main class="flex-1 min-w-0">
    <turbo-frame id="generator-content">
      <%= render Admin::CodeGenerators::CardGridComponent.new(
        generators: @filtered_generators,
        category_label: category_label,
        category_icon: category_icon,
        category_count: category_count
      ) %>
    </turbo-frame>
  </main>
</div>
```

- [ ] **Step 3: Update the index view to pass new params**

Replace the entire content of `app/views/admin/code_generators/index.html.erb`:

```erb
<%= render Admin::CodeGenerators::IndexComponent.new(
  sidebar_data: @sidebar_data,
  filtered_generators: @filtered_generators,
  category: @category,
  element_type: @element_type,
  kind: @kind,
  total_count: @step_actions.size + @element_types.size
) %>
```

- [ ] **Step 4: Run controller spec to make sure index still works**

Run: `bundle exec rspec spec/controllers/admin/code_generators_controller_spec.rb -v`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/components/admin/code_generators/index_component.rb app/components/admin/code_generators/index_component.html.erb app/views/admin/code_generators/index.html.erb
git commit -m "feat: rewrite IndexComponent with sidebar + card grid layout"
```

---

### Task 6: Update Show View for Turbo Frame + Direct URL

**Files:**
- Modify: `app/views/admin/code_generators/show.html.erb`

The show view needs to render within the sidebar layout for direct URL visits, or just the detail component for Turbo Frame requests.

- [ ] **Step 1: Rewrite show.html.erb**

Replace the entire content of `app/views/admin/code_generators/show.html.erb`:

```erb
<% if turbo_frame_request? %>
  <%# Turbo Frame request: just the detail component %>
  <turbo-frame id="generator-content">
    <%= render Admin::CodeGenerators::DetailComponent.new(
      generator_class: @generator_class,
      source_code: @source_code,
      path: params[:path]
    ) %>
  </turbo-frame>
<% else %>
  <%# Direct URL visit: full page with sidebar + detail %>
  <div class="min-h-screen bg-gray-50 flex">
    <%= render Admin::CodeGenerators::SidebarComponent.new(
      sidebar_data: @sidebar_data,
      active_category: @generator_class&._metadata&.dig(:category).to_s,
      active_element_type: @generator_class&.generator_kind == :element_type ? @generator_class&.generator_name : nil,
      total_count: @step_actions&.size.to_i + @element_types&.size.to_i
    ) %>

    <main class="flex-1 min-w-0">
      <turbo-frame id="generator-content">
        <%= render Admin::CodeGenerators::DetailComponent.new(
          generator_class: @generator_class,
          source_code: @source_code,
          path: params[:path]
        ) %>
      </turbo-frame>
    </main>
  </div>
<% end %>
```

- [ ] **Step 2: Run controller spec**

Run: `bundle exec rspec spec/controllers/admin/code_generators_controller_spec.rb -v`
Expected: All PASS

- [ ] **Step 3: Commit**

```bash
git add app/views/admin/code_generators/show.html.erb
git commit -m "feat: update show view with sidebar layout for direct URL visits"
```

---

### Task 7: Rewrite FormComponent with Side-by-Side Layout

**Files:**
- Modify: `app/components/admin/code_generators/form_component.rb`
- Modify: `app/components/admin/code_generators/form_component.html.erb`
- Modify: `app/views/admin/code_generators/new.html.erb`
- Modify: `app/views/admin/code_generators/edit.html.erb`

- [ ] **Step 1: Update FormComponent Ruby class (minor — no logic changes needed)**

The existing `FormComponent` class at `app/components/admin/code_generators/form_component.rb` can stay as-is. The CATEGORY_OPTIONS, `creating?`, `title`, `subtitle`, `form_url`, `form_method`, `preview_source_url`, and `field` methods are all still needed. No changes required.

- [ ] **Step 2: Rewrite FormComponent template**

Replace the entire content of `app/components/admin/code_generators/form_component.html.erb`:

```erb
<div class="min-h-screen bg-gray-50">
  <%# Top bar %>
  <div class="bg-white border-b border-gray-200">
    <div class="max-w-[1400px] mx-auto px-6 py-3 flex items-center justify-between">
      <div class="flex items-center gap-3">
        <%= link_to admin_code_generators_path, class: "inline-flex items-center gap-1 text-sm text-indigo-600 hover:text-indigo-700 font-medium transition-colors" do %>
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/></svg>
          Back
        <% end %>
        <span class="text-gray-300">·</span>
        <h1 class="text-sm font-semibold text-gray-900"><%= title %></h1>
        <% unless creating? %>
          <span class="font-mono text-xs text-gray-500 bg-gray-100 px-2 py-0.5 rounded"><%= field(:version) %></span>
          <span class="text-[10px] text-gray-400">auto-increments on save</span>
        <% end %>
      </div>
    </div>
  </div>

  <div class="max-w-[1400px] mx-auto px-6 py-6">
    <%# Validation errors %>
    <% if @errors.any? %>
      <div class="mb-4">
        <%= render AlertComponent.new(message: @errors.join(". "), type: :error) %>
      </div>
    <% end %>

    <%= form_with url: form_url, method: form_method,
        data: {
          controller: "generator-form",
          generator_form_preview_url_value: preview_source_url
        } do |f| %>

      <%# Side-by-side layout %>
      <div class="flex gap-6">
        <%# Left column: Form %>
        <div class="flex-1 min-w-0 space-y-4">

          <% if creating? %>
            <%# Identity section (create only) %>
            <div class="bg-white border border-gray-200 rounded-lg p-4 shadow-sm">
              <div class="flex items-center gap-2 mb-3">
                <span class="w-1.5 h-1.5 rounded-full bg-violet-500"></span>
                <h2 class="text-sm font-semibold text-gray-900">Generator Identity</h2>
                <span class="text-[10px] text-gray-400 bg-gray-100 px-1.5 py-0.5 rounded">create only</span>
              </div>
              <div class="grid grid-cols-3 gap-3">
                <div>
                  <label class="block text-xs font-medium text-gray-500 mb-1">Kind</label>
                  <select name="kind" data-action="change->generator-form#fieldChanged"
                    class="w-full rounded-lg bg-gray-50 border-gray-200 text-gray-900 text-sm focus:ring-indigo-500 focus:border-indigo-500">
                    <option value="step_action" <%= "selected" if @kind == "step_action" %>>Step Action</option>
                    <option value="element_type" <%= "selected" if @kind == "element_type" %>>Element Type</option>
                  </select>
                </div>
                <div>
                  <label class="block text-xs font-medium text-gray-500 mb-1">File Name</label>
                  <input type="text" name="file_name" value="" placeholder="my_action"
                    data-action="input->generator-form#fieldChanged"
                    class="w-full rounded-lg bg-gray-50 border-gray-200 text-gray-900 text-sm focus:ring-indigo-500 focus:border-indigo-500">
                  <p class="text-[10px] text-gray-400 mt-0.5">Auto-suffixed with _generator.rb</p>
                </div>
                <div>
                  <label class="block text-xs font-medium text-gray-500 mb-1">Category</label>
                  <select name="category" data-action="change->generator-form#fieldChanged"
                    class="w-full rounded-lg bg-gray-50 border-gray-200 text-gray-900 text-sm focus:ring-indigo-500 focus:border-indigo-500">
                    <% CATEGORY_OPTIONS.each do |label, value| %>
                      <option value="<%= value %>" <%= "selected" if field(:category) == value %>><%= label %></option>
                    <% end %>
                  </select>
                </div>
              </div>
            </div>
          <% else %>
            <input type="hidden" name="kind" value="<%= @kind %>">
            <input type="hidden" name="category" value="<%= field(:category) %>">
            <input type="hidden" name="file_name" value="<%= @path&.split('/')&.last %>">
          <% end %>

          <%# Metadata section %>
          <div class="bg-white border border-gray-200 rounded-lg p-4 shadow-sm">
            <div class="flex items-center gap-2 mb-3">
              <span class="w-1.5 h-1.5 rounded-full bg-indigo-500"></span>
              <h2 class="text-sm font-semibold text-gray-900">Metadata</h2>
            </div>
            <div class="grid grid-cols-3 gap-3">
              <div class="col-span-2">
                <label class="block text-xs font-medium text-gray-500 mb-1">Description</label>
                <input type="text" name="description" value="<%= field(:description) %>"
                  placeholder="What does this generator do?"
                  data-action="input->generator-form#fieldChanged"
                  class="w-full rounded-lg bg-gray-50 border-gray-200 text-gray-900 text-sm focus:ring-indigo-500 focus:border-indigo-500">
              </div>
              <div>
                <% if creating? %>
                  <label class="block text-xs font-medium text-gray-500 mb-1">Version</label>
                  <input type="text" name="version" value="<%= field(:version) %>" placeholder="1.0.0"
                    data-action="input->generator-form#fieldChanged"
                    class="w-full rounded-lg bg-gray-50 border-gray-200 text-gray-900 text-sm focus:ring-indigo-500 focus:border-indigo-500">
                <% else %>
                  <label class="block text-xs font-medium text-gray-500 mb-1">Category</label>
                  <select name="category" data-action="change->generator-form#fieldChanged"
                    class="w-full rounded-lg bg-gray-50 border-gray-200 text-gray-900 text-sm focus:ring-indigo-500 focus:border-indigo-500">
                    <% CATEGORY_OPTIONS.each do |label, value| %>
                      <option value="<%= value %>" <%= "selected" if field(:category) == value %>><%= label %></option>
                    <% end %>
                  </select>
                <% end %>
              </div>
            </div>

            <%# Registration %>
            <div class="mt-3">
              <label class="block text-xs font-medium text-gray-500 mb-1">Registered Names <span class="font-normal text-gray-400">(optional)</span></label>
              <input type="text" name="registered_names" value="<%= field(:registered_names) %>"
                placeholder="validate_contract, validate"
                data-action="input->generator-form#fieldChanged"
                class="w-full rounded-lg bg-gray-50 border-gray-200 text-gray-900 text-sm font-mono focus:ring-indigo-500 focus:border-indigo-500">
              <p class="text-[10px] text-gray-400 mt-0.5">Override action names for registry lookup.</p>
            </div>

            <% unless creating? %>
              <input type="hidden" name="version" value="<%= field(:version) %>">
            <% end %>

            <div class="mt-3 p-2.5 bg-indigo-50 rounded-lg border border-indigo-200">
              <p class="text-[10px] text-indigo-700">
                <strong>Tip:</strong> Input &amp; Output are derived automatically from <code class="bg-indigo-100 px-1 rounded">ctx[:key]</code> usage in your code.
              </p>
            </div>
          </div>

          <%# Code Editor (hero) %>
          <div class="bg-white border border-gray-200 rounded-lg overflow-hidden shadow-sm">
            <div class="px-4 py-3 border-b border-gray-100 flex items-center justify-between">
              <div class="flex items-center gap-2">
                <span class="w-1.5 h-1.5 rounded-full bg-green-500"></span>
                <h2 class="text-sm font-semibold text-gray-900">Methods</h2>
              </div>
              <span class="text-[10px] text-gray-400">generate_body · validate_config · dependencies · private helpers</span>
            </div>
            <textarea name="methods_body" rows="25"
              data-generator-form-target="methodsEditor"
              data-action="input->generator-form#fieldChanged keydown->generator-form#handleTab"
              spellcheck="false"
              class="w-full font-mono text-sm border-0 focus:ring-0 leading-relaxed p-5 resize-y bg-[#1e1e2e] text-gray-100"
              style="tab-size: 2"><%= field(:methods_body) %></textarea>
          </div>

          <%# Actions %>
          <div class="flex items-center gap-3">
            <%= render ButtonComponent.new(variant: :primary, type: "submit") do %>
              <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/></svg>
              <%= creating? ? "Create Generator" : "Save Changes" %>
            <% end %>
            <%= render ButtonComponent.new(tag: :a, variant: :secondary, href: admin_code_generators_path) do %>
              Cancel
            <% end %>
          </div>
        </div>

        <%# Right column: Live Source Preview %>
        <div class="w-[420px] flex-shrink-0">
          <div class="bg-white border border-gray-200 rounded-lg overflow-hidden shadow-sm sticky top-20">
            <div class="px-4 py-3 border-b border-gray-100 flex items-center justify-between">
              <div class="flex items-center gap-2">
                <span class="w-1.5 h-1.5 rounded-full bg-violet-500"></span>
                <h2 class="text-sm font-semibold text-gray-900">Generated Source Preview</h2>
              </div>
              <span data-generator-form-target="previewLineCount" class="text-[10px] text-gray-400">0 lines</span>
            </div>
            <div class="overflow-x-auto overflow-y-auto max-h-[calc(100vh-180px)] p-4 bg-gray-50" data-generator-form-target="previewPanel">
              <div class="text-xs text-gray-400 italic">Edit the form to see a preview...</div>
            </div>
          </div>
        </div>
      </div>
    <% end %>
  </div>
</div>
```

- [ ] **Step 3: Commit**

```bash
git add app/components/admin/code_generators/form_component.html.erb
git commit -m "feat: rewrite FormComponent with side-by-side layout and light theme"
```

---

### Task 8: Update Stimulus Controllers

**Files:**
- Modify: `app/javascript/controllers/generator_nav_controller.js`
- Modify: `app/javascript/controllers/generator_search_controller.js`
- Modify: `app/javascript/controllers/generator_test_runner_controller.js`

- [ ] **Step 1: Update generator_nav_controller.js for light theme classes**

Replace the entire content of `app/javascript/controllers/generator_nav_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["link"]

  activate(event) {
    this.linkTargets.forEach(link => {
      link.classList.remove("bg-indigo-50", "text-indigo-700", "font-medium")
      link.classList.add("text-gray-600")
    })

    const clicked = event.currentTarget
    clicked.classList.remove("text-gray-600")
    clicked.classList.add("bg-indigo-50", "text-indigo-700", "font-medium")
  }
}
```

- [ ] **Step 2: Simplify generator_search_controller.js for flat sidebar**

Replace the entire content of `app/javascript/controllers/generator_search_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

/**
 * Generator Search Controller
 *
 * Filters sidebar navigation items based on name/description matching.
 * The card grid is now loaded per-category via Turbo Frame, so we only
 * filter the sidebar items here.
 */
export default class extends Controller {
  static targets = ["input", "tree", "noResults", "leaf"]

  filter() {
    const query = this.inputTarget.value.trim().toLowerCase()

    if (query === "") {
      this.resetAll()
      return
    }

    let anyMatch = false

    this.leafTargets.forEach(leaf => {
      const match = this.matchesQuery(leaf, query)
      leaf.classList.toggle("hidden", !match)
      if (match) anyMatch = true
    })

    if (this.hasNoResultsTarget) {
      this.noResultsTarget.classList.toggle("hidden", anyMatch)
    }
  }

  matchesQuery(el, query) {
    const name = (el.dataset.name || "").toLowerCase()
    const desc = (el.dataset.description || "").toLowerCase()
    return name.includes(query) || desc.includes(query)
  }

  resetAll() {
    this.leafTargets.forEach(l => l.classList.remove("hidden"))
    if (this.hasNoResultsTarget) this.noResultsTarget.classList.add("hidden")
  }
}
```

- [ ] **Step 3: Update generator_test_runner_controller.js badge colors for light theme**

In `app/javascript/controllers/generator_test_runner_controller.js`, update the `renderBadges` method and the `displayResults` method to use light-theme colors. Also add a `placeholder` target to hide it when results appear.

Replace the entire content of `app/javascript/controllers/generator_test_runner_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "configInput", "runButton", "resultsPanel", "codeOutput",
    "inputBadges", "outputBadges", "validationErrors", "spinner", "placeholder"
  ]
  static values = { url: String, sample: String }

  connect() {
    if (this.hasConfigInputTarget) {
      const sample = this.hasSampleValue ? this.sampleValue : "{}"
      if (!this.configInputTarget.value || this.configInputTarget.value === "{}") {
        try {
          const parsed = JSON.parse(sample)
          this.configInputTarget.value = JSON.stringify(parsed, null, 2)
        } catch {
          this.configInputTarget.value = sample
        }
      }
    }
  }

  async run() {
    if (this.hasRunButtonTarget) this.runButtonTarget.disabled = true
    if (this.hasSpinnerTarget) this.spinnerTarget.classList.remove("hidden")

    const config = this.hasConfigInputTarget ? this.configInputTarget.value : "{}"

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "",
          "Accept": "application/json"
        },
        body: JSON.stringify({ sample_config: config })
      })

      const data = await response.json()

      if (data.error) {
        this.showError(data.error)
        return
      }

      this.displayResults(data)
    } catch (e) {
      this.showError("Request failed: " + e.message)
    } finally {
      if (this.hasRunButtonTarget) this.runButtonTarget.disabled = false
      if (this.hasSpinnerTarget) this.spinnerTarget.classList.add("hidden")
    }
  }

  displayResults(data) {
    if (this.hasPlaceholderTarget) this.placeholderTarget.classList.add("hidden")
    if (this.hasResultsPanelTarget) this.resultsPanelTarget.classList.remove("hidden")

    if (this.hasCodeOutputTarget) {
      if (data.code_highlighted) {
        this.codeOutputTarget.innerHTML = `<pre class="text-sm leading-relaxed"><code class="highlight">${data.code_highlighted}</code></pre>`
      } else {
        this.codeOutputTarget.innerHTML = `<pre class="text-sm text-gray-400 italic">No code generated (nil)</pre>`
      }
    }

    if (this.hasInputBadgesTarget) {
      this.inputBadgesTarget.innerHTML = this.renderBadges(data.inputs || [], "amber")
    }

    if (this.hasOutputBadgesTarget) {
      this.outputBadgesTarget.innerHTML = this.renderBadges(data.outputs || [], "green")
    }

    if (this.hasValidationErrorsTarget) {
      if (data.validation_errors && data.validation_errors.length > 0) {
        this.validationErrorsTarget.innerHTML = data.validation_errors
          .map(e => `<div class="text-sm text-red-700 flex items-center gap-1.5"><svg class="w-3.5 h-3.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01"/></svg>${this.escapeHtml(e)}</div>`)
          .join("")
        this.validationErrorsTarget.classList.remove("hidden")
      } else {
        this.validationErrorsTarget.classList.add("hidden")
      }
    }
  }

  showError(message) {
    if (this.hasPlaceholderTarget) this.placeholderTarget.classList.add("hidden")
    if (this.hasResultsPanelTarget) this.resultsPanelTarget.classList.remove("hidden")
    if (this.hasCodeOutputTarget) {
      this.codeOutputTarget.innerHTML = `<div class="text-sm text-red-600">${this.escapeHtml(message)}</div>`
    }
  }

  renderBadges(keys, color) {
    if (keys.length === 0) return `<span class="text-xs text-gray-400 italic">none detected</span>`
    return keys.map(k =>
      `<span class="inline-flex items-center px-2 py-0.5 text-[10px] font-mono bg-${color}-50 text-${color}-800 rounded border border-${color}-200">ctx[:${this.escapeHtml(k)}]</span>`
    ).join(" ")
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
```

- [ ] **Step 4: Update generator_form_controller.js preview styling for light theme**

In `app/javascript/controllers/generator_form_controller.js`, update the `updatePreview` method to use light theme classes. Replace the `updatePreview` method:

```javascript
  updatePreview(data) {
    if (this.hasPreviewPanelTarget) {
      const lineCount = data.line_count || 0
      let lineNumbers = ""
      for (let i = 1; i <= lineCount; i++) {
        lineNumbers += `<div class="leading-6">${i}</div>`
      }

      this.previewPanelTarget.innerHTML = `
        <div class="flex font-mono text-sm">
          <div class="select-none border-r border-gray-200 pr-4 text-right text-gray-400">
            ${lineNumbers}
          </div>
          <div class="pl-4 flex-1">
            <pre class="leading-6"><code class="highlight">${data.highlighted}</code></pre>
          </div>
        </div>
      `
    }
    if (this.hasPreviewLineCountTarget) {
      this.previewLineCountTarget.textContent = `${data.line_count || 0} lines`
    }
  }
```

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/generator_nav_controller.js app/javascript/controllers/generator_search_controller.js app/javascript/controllers/generator_test_runner_controller.js app/javascript/controllers/generator_form_controller.js
git commit -m "feat: update Stimulus controllers for light theme and flat sidebar"
```

---

### Task 9: Remove Old Components

**Files:**
- Remove: `app/components/admin/code_generators/show_component.rb`
- Remove: `app/components/admin/code_generators/show_component.html.erb`
- Remove: `app/components/admin/code_generators/detail_panel_component.rb`
- Remove: `app/components/admin/code_generators/detail_panel_component.html.erb`

- [ ] **Step 1: Delete the old components**

```bash
rm app/components/admin/code_generators/show_component.rb
rm app/components/admin/code_generators/show_component.html.erb
rm app/components/admin/code_generators/detail_panel_component.rb
rm app/components/admin/code_generators/detail_panel_component.html.erb
```

- [ ] **Step 2: Verify no references remain**

Search for any remaining references to `ShowComponent` or `DetailPanelComponent` in the codebase:

```bash
grep -r "ShowComponent\|DetailPanelComponent" app/ --include="*.rb" --include="*.erb" --include="*.js"
```

Expected: No matches. If matches found, update those files to use `DetailComponent` instead.

- [ ] **Step 3: Run full controller spec**

Run: `bundle exec rspec spec/controllers/admin/code_generators_controller_spec.rb -v`
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add -A app/components/admin/code_generators/
git commit -m "refactor: remove ShowComponent and DetailPanelComponent (replaced by DetailComponent)"
```

---

### Task 10: Update Controller Spec for Full Coverage

**Files:**
- Modify: `spec/controllers/admin/code_generators_controller_spec.rb`

- [ ] **Step 1: Update the full spec**

Replace the entire content of `spec/controllers/admin/code_generators_controller_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::CodeGeneratorsController, type: :controller do
  before do
    allow(controller).to receive(:require_admin_role!).and_return(true)
  end

  describe "GET #index" do
    it "returns success" do
      get :index
      expect(response).to have_http_status(:success)
    end

    it "assigns sidebar_data, filtered_generators, step_actions, element_types" do
      get :index
      expect(assigns(:sidebar_data)).to be_a(Array)
      expect(assigns(:sidebar_data).size).to be > 0
      expect(assigns(:filtered_generators)).to be_a(Array)
      expect(assigns(:step_actions)).to be_a(Hash)
      expect(assigns(:element_types)).to be_a(Hash)
    end

    it "filters by step action category when category param is present" do
      get :index, params: { category: "model_operations", kind: "step_action" }
      expect(response).to have_http_status(:success)
      expect(assigns(:category)).to eq("model_operations")
      expect(assigns(:kind)).to eq("step_action")
      expect(assigns(:filtered_generators)).to be_a(Array)
      expect(assigns(:filtered_generators)).to all(
        satisfy { |_name, klass| klass._metadata[:category].to_s == "model_operations" }
      )
    end

    it "filters by element type when element_type param is present" do
      get :index, params: { element_type: "start" }
      expect(response).to have_http_status(:success)
      expect(assigns(:element_type)).to eq("start")
      expect(assigns(:filtered_generators)).to be_a(Array)
    end
  end

  describe "GET #show" do
    it "returns success and assigns source_code" do
      get :show, params: { path: "element_types/process/model_operations/new_model_generator" }
      expect(response).to have_http_status(:success)
      expect(assigns(:source_code)).to be_present
    end

    it "assigns sidebar_data for direct URL visits" do
      get :show, params: { path: "element_types/process/model_operations/new_model_generator" }
      expect(assigns(:sidebar_data)).to be_a(Array)
      expect(assigns(:sidebar_data).size).to be > 0
    end
  end

  describe "GET #new" do
    it "returns success with methods_body including def generate_body" do
      get :new, params: { kind: "step_action" }
      expect(response).to have_http_status(:success)
      expect(assigns(:form_data)).to be_a(Hash)
      expect(assigns(:form_data)[:methods_body]).to include("def generate_body")
    end
  end

  describe "GET #edit" do
    it "returns success and extracts form data" do
      get :edit, params: { path: "element_types/process/model_operations/new_model_generator" }
      expect(response).to have_http_status(:success)
      expect(assigns(:form_data)).to be_a(Hash)
      expect(assigns(:form_data)[:description]).to be_present
    end
  end

  describe "POST #validate" do
    it "returns valid for source using generate_body" do
      source = <<~RUBY
        class CodeGenerators::ElementTypes::Process::Test::TestValidGenerator < CodeGenerators::BaseGenerator
          generator_metadata do
            description "Test"
            category :test
            version "1.0.0"
          end
          def generate_body; "true"; end
          def validate_config(config); []; end
        end
      RUBY

      post :validate, params: { path: "element_types/process/model_operations/new_model_generator", source_code: source }
      json = JSON.parse(response.body)
      expect(json["valid"]).to be true
    end

    it "returns errors for bad syntax" do
      post :validate, params: { path: "element_types/process/model_operations/new_model_generator", source_code: "def foo(" }
      json = JSON.parse(response.body)
      expect(json["valid"]).to be false
      expect(json["errors"]).not_to be_empty
    end
  end

  describe "POST #test_run" do
    it "sends sample_config JSON and returns code with (ctx, **), body with ctx refs, inputs/outputs arrays" do
      post :test_run, params: {
        path: "element_types/process/data_operations/assign_value_generator",
        sample_config: '{"targetVar":"result","valueType":"string","stringValue":"hello"}'
      }
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["code"]).to include("(ctx, **)")
      expect(json["body"]).to include("ctx[")
      expect(json["inputs"]).to be_an(Array)
      expect(json["outputs"]).to be_an(Array)
      expect(json["outputs"]).to include("result")
    end

    it "returns 422 for invalid JSON" do
      post :test_run, params: {
        path: "element_types/process/data_operations/assign_value_generator",
        sample_config: "{bad json"
      }
      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json["error"]).to include("Invalid JSON")
    end
  end

  describe "POST #preview_source" do
    it "returns source using generate_body without input_keys/output_keys" do
      post :preview_source, params: {
        kind: "step_action",
        file_name: "test_action",
        category: "model_operations",
        description: "A test generator",
        version: "1.0.0",
        methods_body: "def generate_body\n  \"true\"\nend\n\ndef validate_config(config)\n  []\nend"
      }
      json = JSON.parse(response.body)
      expect(json["source"]).to include("class TestActionGenerator")
      expect(json["source"]).to include("model_operations")
      expect(json["source"]).to include("generate_body")
      expect(json["source"]).to include("sample_input")
      expect(json["source"]).not_to include("input_keys")
      expect(json["source"]).not_to include("output_keys")
      expect(json["highlighted"]).to be_present
      expect(json["line_count"]).to be > 0
    end
  end
end
```

- [ ] **Step 2: Run the full spec suite**

Run: `bundle exec rspec spec/controllers/admin/code_generators_controller_spec.rb -v`
Expected: All PASS

- [ ] **Step 3: Commit**

```bash
git add spec/controllers/admin/code_generators_controller_spec.rb
git commit -m "test: update controller spec for category filtering and sidebar data"
```

---

### Task 11: Build Tailwind CSS and Smoke Test

**Files:**
- No new files; just build and verify

- [ ] **Step 1: Build Tailwind CSS**

Run: `bin/rails tailwindcss:build`
Expected: CSS compiled successfully

- [ ] **Step 2: Run the full spec suite**

Run: `bundle exec rspec spec/controllers/admin/code_generators_controller_spec.rb -v`
Expected: All PASS

- [ ] **Step 3: Start the Rails server and verify pages load**

Run: `bin/rails server -d` (or verify manually)

Check these URLs:
- `http://localhost:3000/admin/code_generators` — should show sidebar + card grid
- `http://localhost:3000/admin/code_generators?category=model_operations&kind=step_action` — should show Model Operations cards
- `http://localhost:3000/admin/code_generators?element_type=start` — should show Start element type
- `http://localhost:3000/admin/code_generators/element_types%2Fprocess%2Fmodel_operations%2Fnew_model_generator` — should show detail view with sidebar
- `http://localhost:3000/admin/code_generators/new?kind=step_action` — should show side-by-side form
- `http://localhost:3000/admin/code_generators/element_types%2Fprocess%2Fmodel_operations%2Fnew_model_generator/edit` — should show edit form

- [ ] **Step 4: Commit any fixes needed**

If any issues are found during smoke testing, fix them and commit.
