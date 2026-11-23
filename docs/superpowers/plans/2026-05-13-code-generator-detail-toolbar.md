# Code Generator Detail Toolbar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the code generator detail page (`Maintenance / Platform / Code Generators / :slug`) so its top bar and breadcrumb match the page-edit screen at `Maintenance / Pages / :id/edit`.

**Architecture:** Replace the existing `BreadcrumbsComponent + flex-row card` shell on the show view with the page-edit edge shell (`content_for :container_width, :edge` + `h-12` toolbar header + flex sidebar/main row). Introduce a new `Platform::CodeGenerators::ToolbarComponent` that mirrors `PageBuilder::ToolbarComponent`'s back-button, breadcrumb-style title, and right-side actions (Edit, Delete) — but omits the editor-only affordances (center tabs, viewport toggles, undo/redo, preview, save). Drop the previously cute turbo-frame partial-swap navigation in favor of full page reloads, matching the page-edit pattern.

**Tech Stack:** Rails 8.1.2, ViewComponent, TailwindCSS, RSpec, StimulusJS (existing controllers, no changes).

---

## File Map

**New files:**
- `app/components/platform/code_generators/toolbar_component.rb` — toolbar Ruby class
- `app/components/platform/code_generators/toolbar_component.html.erb` — toolbar template
- `spec/components/platform/code_generators/toolbar_component_spec.rb` — toolbar spec

**Modified files:**
- `app/views/admin/maintenance/platform/code_generators/show.html.erb` — full rewrite
- `app/components/platform/code_generators/detail_component.rb` — remove unused helpers
- `app/components/platform/code_generators/detail_component.html.erb` — remove inner header bar
- `app/components/platform/code_generators/sidebar_component.rb` — drop turbo_frame data attr
- `app/components/platform/code_generators/sidebar_component.html.erb` — drop turbo_frame data attrs
- `app/components/platform/code_generators/card_grid_component.html.erb` — drop turbo_frame data attr
- `app/components/platform/code_generators/index_component.html.erb` — drop turbo-frame wrapper
- `app/javascript/controllers/generator_search_controller.js` — drop turbo-frame attr in rendered template

---

### Task 1: Add a failing spec for the new ToolbarComponent

**Files:**
- Create: `spec/components/platform/code_generators/toolbar_component_spec.rb`

- [ ] **Step 1: Write the failing spec**

Create the file with these contents:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::CodeGenerators::ToolbarComponent, type: :component do
  let(:customer_id) { "81721200" }
  let(:slug) { "element_types/process/validation/version_check_generator" }

  let(:generator_class) do
    Class.new do
      def self._metadata
        { category: :validation, version: "1.2.3", description: "checks version" }
      end

      def self.generator_kind = :step_action
      def self.generator_name = "version_check"
    end
  end

  subject(:rendered) do
    render_inline(described_class.new(
      generator_class: generator_class,
      path: slug,
      customer_id: customer_id
    ))
  end

  it "renders a back link to the code generators index" do
    expected_href = "/#{customer_id}/admin/maintenance/code_generators"
    expect(rendered.css("a[href='#{expected_href}']")).not_to be_empty
  end

  it "renders the category, generator name, and version" do
    expect(rendered.text).to include("Validation")
    expect(rendered.text).to include("version_check")
    expect(rendered.text).to include("v1.2.3")
  end

  it "renders an Edit link to the generator edit path" do
    expected_href = "/#{customer_id}/admin/maintenance/code_generators/#{slug}/edit"
    expect(rendered.css("a[href='#{expected_href}']")).not_to be_empty
    expect(rendered.text).to include("Edit")
  end

  it "renders a Delete button with turbo confirm" do
    expect(rendered.text).to include("Delete")
    delete_form = rendered.css("form[action*='code_generators/#{slug}'][method='post']")
    expect(delete_form).not_to be_empty
    expect(rendered.css("[data-turbo-confirm]")).not_to be_empty
  end

  it "uses the h-12 fixed header layout from the page-edit toolbar" do
    expect(rendered.css("header.bg-white.border-b")).not_to be_empty
    expect(rendered.css(".h-12")).not_to be_empty
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/components/platform/code_generators/toolbar_component_spec.rb`
Expected: FAIL with `NameError: uninitialized constant Platform::CodeGenerators::ToolbarComponent`.

- [ ] **Step 3: Commit the failing spec**

```bash
git add spec/components/platform/code_generators/toolbar_component_spec.rb
git commit -m "test(code_generators): add failing spec for new ToolbarComponent"
```

---

### Task 2: Implement the ToolbarComponent

**Files:**
- Create: `app/components/platform/code_generators/toolbar_component.rb`
- Create: `app/components/platform/code_generators/toolbar_component.html.erb`

- [ ] **Step 1: Create the Ruby class**

Create `app/components/platform/code_generators/toolbar_component.rb`:

```ruby
# frozen_string_literal: true

module Platform
  module CodeGenerators
    class ToolbarComponent < ApplicationComponent
      def initialize(generator_class:, path:, customer_id:)
        @generator_class = generator_class
        @path = path
        @customer_id = customer_id
      end

      private

      attr_reader :generator_class, :path, :customer_id

      def metadata
        generator_class&._metadata || {}
      end

      def generator_name
        generator_class&.generator_name || "unknown"
      end

      def category_label
        metadata[:category].to_s.tr("_", " ").titleize
      end

      def version
        metadata[:version]
      end

      def back_path
        helpers.admin_maintenance_platform_code_generators_path(customer_id)
      end

      def edit_path
        helpers.edit_admin_maintenance_platform_code_generator_path(customer_id, slug: path)
      end

      def delete_path
        helpers.admin_maintenance_platform_code_generator_path(customer_id, slug: path)
      end
    end
  end
end
```

- [ ] **Step 2: Create the template**

Create `app/components/platform/code_generators/toolbar_component.html.erb`:

```erb
<header class="bg-white border-b border-slate-200 flex-shrink-0 z-30">
  <div class="flex items-center h-12 px-4">

    <%# Left: back + breadcrumb-style title %>
    <div class="flex items-center gap-2 min-w-0">
      <%= link_to back_path,
          class: "flex items-center justify-center w-8 h-8 text-slate-500 hover:text-slate-900 hover:bg-slate-100 rounded-md transition-colors",
          title: "Back to Code Generators" do %>
        <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 19.5L8.25 12l7.5-7.5" />
        </svg>
      <% end %>

      <div class="h-4 w-px bg-slate-200"></div>

      <div class="flex items-center gap-1.5 min-w-0">
        <span class="text-sm font-semibold text-slate-900 truncate"><%= category_label %></span>
        <span class="text-slate-300">/</span>
        <span class="text-sm font-mono text-slate-700 truncate"><%= generator_name %></span>
        <% if version.present? %>
          <span class="text-[10px] font-medium text-slate-500 bg-slate-100 px-1.5 py-0.5 rounded">v<%= version %></span>
        <% end %>
      </div>
    </div>

    <%# Center spacer (no tabs for read-only detail) %>
    <div class="flex-1"></div>

    <%# Right: Edit + Delete %>
    <div class="flex items-center gap-1.5">
      <%= render ButtonComponent.new(tag: :a, variant: :primary, size: :sm, href: edit_path) do %>
        <svg class="w-3.5 h-3.5 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"/>
        </svg>
        Edit
      <% end %>

      <%= button_to delete_path, method: :delete,
          data: { turbo_confirm: "Delete this generator? This cannot be undone." },
          class: "#{ButtonComponent::BASE_CLASSES} #{ButtonComponent::VARIANTS[:danger]} #{ButtonComponent::SIZES[:sm]}" do %>
        <svg class="w-3.5 h-3.5 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/>
        </svg>
        Delete
      <% end %>
    </div>
  </div>
</header>
```

- [ ] **Step 3: Run the spec to verify it passes**

Run: `bundle exec rspec spec/components/platform/code_generators/toolbar_component_spec.rb`
Expected: all 5 examples pass.

- [ ] **Step 4: Commit**

```bash
git add app/components/platform/code_generators/toolbar_component.rb \
        app/components/platform/code_generators/toolbar_component.html.erb
git commit -m "feat(code_generators): add ToolbarComponent matching page-edit shell"
```

---

### Task 3: Rewrite the show view to use the edge shell

**Files:**
- Modify: `app/views/admin/maintenance/platform/code_generators/show.html.erb`

- [ ] **Step 1: Replace the entire show view**

Overwrite `app/views/admin/maintenance/platform/code_generators/show.html.erb` with:

```erb
<% content_for :container_width, :edge %>

<div class="h-full flex flex-col bg-canvas">
  <%= render Platform::CodeGenerators::ToolbarComponent.new(
    generator_class: @generator_class,
    path: params[:slug],
    customer_id: current_customer_id
  ) %>

  <div class="flex-1 flex overflow-hidden">
    <aside class="flex-shrink-0">
      <%= render Platform::CodeGenerators::SidebarComponent.new(
        sidebar_data: @sidebar_data,
        search_index: @search_index || [],
        customer_id: current_customer_id,
        active_category: @generator_class&._metadata&.dig(:category).to_s,
        active_element_type: @generator_class&.generator_kind == :element_type ? @generator_class&.generator_name : nil,
        total_count: @step_actions&.size.to_i + @element_types&.size.to_i
      ) %>
    </aside>

    <main class="flex-1 min-w-0 overflow-y-auto bg-canvas">
      <%= render Platform::CodeGenerators::DetailComponent.new(
        generator_class: @generator_class,
        source_code: @source_code,
        path: params[:slug],
        customer_id: current_customer_id
      ) %>
    </main>
  </div>
</div>
```

- [ ] **Step 2: Verify the page renders without 500s**

Note: the controller's `show` action has an `unless turbo_frame_request?` guard that conditionally loads `@sidebar_data` / `@search_index`. With the turbo-frame removed, those are loaded always — no controller change needed because `turbo_frame_request?` will be false for normal navigation.

Remove the manifest cache and start the server:

```
rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000
```

Visit `http://<host>:3000/81721200/admin/maintenance/code_generators` then click any generator card. Expected:
- The edge-to-edge layout fills the viewport
- A single `h-12` white toolbar appears at the top with back arrow, "Category / generator_name v1.x.x", and Edit / Delete buttons on the right
- The sidebar appears beneath the toolbar on the left
- The detail body (description / I/O / Test Runner / Source Code) renders on the right

The DetailComponent still has its own inner breadcrumb bar — that gets removed in Task 4. Leave that for now.

- [ ] **Step 3: Commit**

```bash
git add app/views/admin/maintenance/platform/code_generators/show.html.erb
git commit -m "refactor(code_generators): rewrite show view to use edge shell + ToolbarComponent"
```

---

### Task 4: Remove the inner header bar from DetailComponent

**Files:**
- Modify: `app/components/platform/code_generators/detail_component.html.erb`
- Modify: `app/components/platform/code_generators/detail_component.rb`

- [ ] **Step 1: Strip the breadcrumb bar from the template**

Edit `app/components/platform/code_generators/detail_component.html.erb`. Replace the file's entire contents with the body-only version below (this removes the `<div>` opening through the breadcrumb bar's closing `</div>` — currently lines 1–28 — and reframes the body):

```erb
<div class="p-6">
  <%# Description %>
  <p class="text-body-sm mb-5 max-w-2xl"><%= metadata[:description] %></p>

  <%# I/O Panel — horizontal flow %>
  <div class="flex gap-3 mb-5">
    <%# Inputs %>
    <div class="flex-1 bg-warning-subtle border border-warning/30 rounded-lg p-4">
      <div class="flex items-center gap-1.5 mb-2.5">
        <span class="w-1.5 h-1.5 rounded-full bg-warning"></span>
        <span class="text-[10px] font-semibold text-warning uppercase tracking-wide">Inputs</span>
      </div>
      <div class="flex flex-wrap gap-1.5">
        <% if input_keys.any? %>
          <% input_keys.each do |key| %>
            <span class="inline-flex items-center px-2 py-0.5 text-[10px] font-mono bg-surface text-warning rounded border border-warning/30">ctx[:<%= key %>]</span>
          <% end %>
        <% else %>
          <span class="text-xs text-warning italic">None detected</span>
        <% end %>
      </div>
    </div>

    <%# Arrow %>
    <div class="flex items-center flex-shrink-0">
      <span class="text-lg text-text-muted">→</span>
    </div>

    <%# Outputs %>
    <div class="flex-1 bg-success-subtle border border-success/30 rounded-lg p-4">
      <div class="flex items-center gap-1.5 mb-2.5">
        <span class="w-1.5 h-1.5 rounded-full bg-success"></span>
        <span class="text-[10px] font-semibold text-success uppercase tracking-wide">Outputs</span>
      </div>
      <div class="flex flex-wrap gap-1.5">
        <% if output_keys.any? %>
          <% output_keys.each do |key| %>
            <span class="inline-flex items-center px-2 py-0.5 text-[10px] font-mono bg-surface text-success rounded border border-success/30">ctx[:<%= key %>]</span>
          <% end %>
        <% else %>
          <span class="text-xs text-success italic">None detected</span>
        <% end %>
      </div>
    </div>

    <%# Dependencies %>
    <% if deps.any? %>
      <div class="flex-[0.6] bg-canvas-elevated border border-border-subtle rounded-lg p-4">
        <div class="flex items-center gap-1.5 mb-2.5">
          <span class="w-1.5 h-1.5 rounded-full bg-accent"></span>
          <span class="text-[10px] font-semibold text-accent uppercase tracking-wide">Deps</span>
        </div>
        <div class="flex flex-wrap gap-1.5">
          <% deps.each do |dep| %>
            <span class="inline-flex items-center px-2 py-0.5 text-[10px] font-mono bg-surface text-text-primary rounded border border-border-subtle"><%= dep %></span>
          <% end %>
        </div>
      </div>
    <% end %>
  </div>

  <%# Test Runner %>
  <div class="card overflow-hidden mb-5"
       data-controller="generator-test-runner"
       data-generator-test-runner-url-value="<%= test_run_path %>"
       data-generator-test-runner-sample-value="<%= sample_json %>">
    <div class="px-4 py-3 border-b border-border-subtle flex items-center justify-between">
      <div class="flex items-center gap-2">
        <span class="w-1.5 h-1.5 rounded-full bg-accent"></span>
        <h3 class="section-header">Test Runner</h3>
      </div>
      <div class="flex items-center gap-2">
        <svg data-generator-test-runner-target="spinner" class="hidden w-4 h-4 text-accent animate-spin" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path>
        </svg>
        <button data-generator-test-runner-target="runButton"
                data-action="click->generator-test-runner#run"
                class="btn btn-primary text-xs">
          <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"/></svg>
          Run Test
        </button>
      </div>
    </div>
    <div class="flex divide-x divide-border-subtle">
      <%# Config pane %>
      <div class="flex-1 p-4">
        <label class="block text-[10px] font-semibold text-text-muted uppercase tracking-wide mb-1.5">Config (JSON)</label>
        <textarea data-generator-test-runner-target="configInput"
          rows="4" spellcheck="false"
          class="input-field text-mono text-xs"
          placeholder='{ "key": "value" }'>{}</textarea>
      </div>
      <%# Output pane %>
      <div class="flex-[1.2] p-4">
        <label class="block text-[10px] font-semibold text-text-muted uppercase tracking-wide mb-1.5">Generated Output</label>
        <div data-generator-test-runner-target="resultsPanel" class="hidden space-y-3">
          <div data-generator-test-runner-target="validationErrors" class="hidden p-2.5 bg-danger-subtle rounded-lg border border-danger/20 space-y-1"></div>
          <div class="flex gap-4">
            <div>
              <span class="text-[10px] font-medium text-text-muted uppercase">Input</span>
              <div class="flex flex-wrap gap-1 mt-1" data-generator-test-runner-target="inputBadges"></div>
            </div>
            <div>
              <span class="text-[10px] font-medium text-text-muted uppercase">Output</span>
              <div class="flex flex-wrap gap-1 mt-1" data-generator-test-runner-target="outputBadges"></div>
            </div>
          </div>
          <div class="bg-canvas-elevated rounded-lg p-3 overflow-x-auto border border-border-subtle" data-generator-test-runner-target="codeOutput"></div>
        </div>
        <div data-generator-test-runner-target="placeholder" class="text-caption italic bg-canvas-elevated rounded-lg p-3 border border-border-subtle">
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
  <details class="card overflow-hidden">
    <summary class="px-4 py-3 flex items-center justify-between cursor-pointer select-none hover:bg-canvas-elevated transition">
      <div class="flex items-center gap-2">
        <svg class="w-3.5 h-3.5 text-text-muted transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"/></svg>
        <span class="section-header">Source Code</span>
        <span class="text-caption"><%= line_count %> lines</span>
      </div>
      <span class="text-mono text-caption"><%= generator_name %>_generator.rb</span>
    </summary>
    <div class="border-t border-border-subtle">
      <%= render CodeBlockComponent.new(code: @source_code, language: "ruby", filename: "#{generator_name}_generator.rb") %>
    </div>
  </details>
</div>
```

- [ ] **Step 2: Drop the unused helpers from the Ruby class**

Edit `app/components/platform/code_generators/detail_component.rb` so it reads exactly:

```ruby
# frozen_string_literal: true

module Platform
  module CodeGenerators
    class DetailComponent < ApplicationComponent
      def initialize(generator_class:, source_code:, path:, customer_id:)
        @generator_class = generator_class
        @source_code = source_code
        @path = path
        @customer_id = customer_id
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

      def test_run_path
        helpers.admin_maintenance_platform_code_generator_test_run_path(@customer_id, code_generator_slug: @path)
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

- [ ] **Step 3: Visually verify**

Reload the show page in the browser. Expected:
- Only one toolbar at the top of the page
- The previous "Back · Process / version_check v1.0.0 [Edit] [Delete]" inner bar is gone
- Description, I/O, Test Runner, Source Code render as before

- [ ] **Step 4: Run the existing test suite for this area**

Run: `bundle exec rspec spec/components/platform/code_generators/ 2>/dev/null; bundle exec rspec spec/requests/admin/maintenance/platform/code_generators_spec.rb 2>/dev/null`

If a `detail_component_spec.rb` exists and asserts on the deleted inner header (e.g., asserts on Edit/Delete inside the detail body, or on `back_url`), update those assertions or move them to `toolbar_component_spec.rb`. If no such spec exists, this command produces no failures from the detail component.

Expected: green or empty run.

- [ ] **Step 5: Commit**

```bash
git add app/components/platform/code_generators/detail_component.html.erb \
        app/components/platform/code_generators/detail_component.rb
git commit -m "refactor(code_generators): drop inner header from DetailComponent"
```

---

### Task 5: Drop turbo-frame partial-swap navigation

**Files:**
- Modify: `app/components/platform/code_generators/sidebar_component.rb:111`
- Modify: `app/components/platform/code_generators/sidebar_component.html.erb:55-58`
- Modify: `app/components/platform/code_generators/card_grid_component.html.erb:27`
- Modify: `app/components/platform/code_generators/index_component.html.erb`
- Modify: `app/javascript/controllers/generator_search_controller.js:62-72`

The detail page now owns the toolbar breadcrumb that must update on every navigation. Frame-targeted swaps would leave a stale breadcrumb. Drop the turbo-frame entirely and let every link full-render — that matches the page-edit pattern.

- [ ] **Step 1: Edit `sidebar_component.rb` line 111**

Change:
```ruby
                    data: { turbo_frame: "generator-content", generator_nav_target: "link", action: "click->generator-nav#activate" },
```
To:
```ruby
                    data: { generator_nav_target: "link", action: "click->generator-nav#activate" },
```

- [ ] **Step 2: Edit `sidebar_component.html.erb`**

Find the step-action link block (around lines 54–60):

```erb
        <% step_action_categories.each do |item| %>
          <a href="<%= item_url(item) %>"
             data-turbo-frame="generator-content"
             data-generator-nav-target="link"
             data-action="click->generator-nav#activate"
```

Remove the `data-turbo-frame="generator-content"` line so the block becomes:

```erb
        <% step_action_categories.each do |item| %>
          <a href="<%= item_url(item) %>"
             data-generator-nav-target="link"
             data-action="click->generator-nav#activate"
```

- [ ] **Step 3: Edit `card_grid_component.html.erb`**

Find the card link (around line 26–28):
```erb
        <a href="<%= generator_path(name, klass) %>"
           data-turbo-frame="generator-content"
           class="group block card p-4 hover:border-accent/40 hover:shadow-md transition-all duration-200">
```

Remove the `data-turbo-frame` line so it becomes:
```erb
        <a href="<%= generator_path(name, klass) %>"
           class="group block card p-4 hover:border-accent/40 hover:shadow-md transition-all duration-200">
```

- [ ] **Step 4: Edit `index_component.html.erb`**

Replace the file with:

```erb
<div class="bg-canvas-elevated flex rounded-lg border border-border-subtle overflow-hidden" style="min-height: 600px;">
  <%# Sidebar %>
  <%= render Platform::CodeGenerators::SidebarComponent.new(
    sidebar_data: @sidebar_data,
    customer_id: @customer_id,
    search_index: @search_index || [],
    active_category: @category,
    active_element_type: @element_type,
    total_count: @total_count
  ) %>

  <%# Main content area %>
  <main class="flex-1 min-w-0 overflow-y-auto">
    <%= render Platform::CodeGenerators::CardGridComponent.new(
      generators: @filtered_generators,
      customer_id: @customer_id,
      category_label: category_label,
      category_icon: category_icon,
      category_count: category_count
    ) %>
  </main>
</div>
```

(The change is removing the `<turbo-frame id="generator-content"> … </turbo-frame>` wrapper around `CardGridComponent`.)

- [ ] **Step 5: Edit `generator_search_controller.js`**

In `app/javascript/controllers/generator_search_controller.js`, locate the template literal in `renderResult` (around lines 62–72):

```javascript
    return `
      <a href="${gen.path}"
         data-turbo-frame="generator-content"
         class="block px-3 py-2 rounded-md hover:bg-gray-50 transition-colors group mb-0.5">
```

Remove the `data-turbo-frame="generator-content"` line:

```javascript
    return `
      <a href="${gen.path}"
         class="block px-3 py-2 rounded-md hover:bg-gray-50 transition-colors group mb-0.5">
```

- [ ] **Step 6: Verify no turbo-frame "generator-content" references remain**

Run: `grep -rn "generator-content" /home/ec2-user/anysys/app /home/ec2-user/anysys/spec`
Expected: empty output (zero matches).

- [ ] **Step 7: Run the full code_generators spec area**

Run: `bundle exec rspec spec/components/platform/code_generators/ spec/requests/admin/maintenance/platform/code_generators_spec.rb 2>/dev/null`
Expected: passing or empty (no new failures).

- [ ] **Step 8: Manual verification of the navigation flow**

1. `rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000`
2. Visit `/81721200/admin/maintenance/code_generators`
3. Click any card → lands on the show page; the new toolbar shows the correct category / generator name / version
4. From the show page, click another category in the sidebar → full-page reload, toolbar breadcrumb updates correctly
5. From the show page, click a different generator inside the same category sub-list → full-page reload, breadcrumb updates
6. Use the sidebar search box → results render → click a result → lands on the show page for that generator
7. Click the back-arrow in the toolbar → returns to the index
8. Click Edit → goes to the edit form. Click Delete → confirm dialog appears

- [ ] **Step 9: Commit**

```bash
git add app/components/platform/code_generators/sidebar_component.rb \
        app/components/platform/code_generators/sidebar_component.html.erb \
        app/components/platform/code_generators/card_grid_component.html.erb \
        app/components/platform/code_generators/index_component.html.erb \
        app/javascript/controllers/generator_search_controller.js
git commit -m "refactor(code_generators): drop turbo-frame nav, use full-page reloads"
```

---

### Task 6: Final verification pass

- [ ] **Step 1: Run the targeted test groups**

```bash
bundle exec rspec spec/components/platform/code_generators/
```

Expected: all green (at least the new `toolbar_component_spec.rb` plus any existing specs in that folder).

- [ ] **Step 2: Run any request specs in the affected area if present**

```bash
bundle exec rspec spec/requests/admin/maintenance/platform/code_generators_spec.rb 2>/dev/null
```

Expected: green or empty.

- [ ] **Step 3: Final manual smoke test**

1. `rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000`
2. Open `/81721200/admin/maintenance/code_generators` in a browser
3. Click any generator → show page renders with edge-to-edge layout, single toolbar header
4. Compare visually with `/81721200/admin/maintenance/pages/<id>/edit` — the toolbar height, back-arrow, divider style, and overall shell should match

- [ ] **Step 4: Stop the server**

Hit Ctrl+C in the terminal running rails.
