# Feature Module Pages Refactor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the feature module index and show pages to follow the entity page pattern, add clickable expandable columns/associations in the Models section, and add View buttons for GET routes.

**Architecture:** Enhance `ModuleModelDiscovery` to return column and association details (not just counts). Refactor the index page to use the existing `FeatureModuleListItemComponent` rendered as table rows inside a card-wrapped `<table>` (matching the `EntityListTableComponent` pattern). On the show page, use a Stimulus `expandable-row` controller for the Models table to toggle column/association detail panels inline. Add a "View" link on GET routes that navigates to the actual URL (route params are substituted with placeholder values).

**Tech Stack:** Rails 8.1, ViewComponent, TailwindCSS, StimulusJS, RSpec

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `app/services/module_model_discovery.rb` | Modify | Return column details and association details alongside counts |
| `app/javascript/controllers/expandable_row_controller.js` | Create | Stimulus controller to toggle inline detail panels in a table |
| `app/views/feature_modules/index.html.erb` | Modify | Refactor to card-based layout using `FeatureModuleListItemComponent` |
| `app/views/feature_modules/show.html.erb` | Modify | Refactor Models section with expandable rows; add View button on GET routes |
| `app/components/feature_module_list_item_component.html.erb` | Modify | Update to include enable/disable action buttons from index page |
| `app/components/feature_module_list_item_component.rb` | Modify | Add helper methods for enable/disable state |
| `spec/services/module_model_discovery_spec.rb` | Modify | Cover new column/association detail fields |
| `spec/components/feature_module_list_item_component_spec.rb` | Modify | Cover new enable/disable actions |
| `spec/requests/feature_modules_spec.rb` | Modify | Cover Models expandable data and View button presence |

---

### Task 1: Enhance ModuleModelDiscovery to Return Column and Association Details

**Files:**
- Modify: `app/services/module_model_discovery.rb`
- Modify: `spec/services/module_model_discovery_spec.rb`

- [ ] **Step 1: Write failing tests for column details**

Add to `spec/services/module_model_discovery_spec.rb` inside the `"with authentication module"` context:

```ruby
it "includes column details for each model" do
  results = described_class.call("authentication")
  user_entry = results.find { |r| r[:name] == "Authentication::User" }
  expect(user_entry[:columns]).to be_an(Array)
  expect(user_entry[:columns].first).to include(:name, :type)
end

it "includes association details for each model" do
  results = described_class.call("authentication")
  user_entry = results.find { |r| r[:name] == "Authentication::User" }
  expect(user_entry[:associations]).to be_an(Array)
  # Authentication::User belongs_to :customer at minimum
  customer_assoc = user_entry[:associations].find { |a| a[:name] == "customer" }
  expect(customer_assoc).to be_present
  expect(customer_assoc[:macro]).to eq("belongs_to")
  expect(customer_assoc[:target_class]).to eq("Customer")
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/module_model_discovery_spec.rb -v`
Expected: FAIL — `user_entry[:columns]` and `user_entry[:associations]` are nil

- [ ] **Step 3: Implement column and association detail extraction**

**Replace the entire `discover_models` method** in `app/services/module_model_discovery.rb` (lines 21–35) and add two new methods inside the existing `private` block, after `derive_class_name`:

```ruby
def discover_models(dir)
  Dir.glob(dir.join("**", "*.rb")).filter_map do |file_path|
    class_name = derive_class_name(file_path)
    klass = class_name.safe_constantize
    next unless klass && klass < ApplicationRecord

    {
      name: klass.name,
      table_name: klass.table_name,
      columns_count: klass.columns.size,
      columns: extract_columns(klass),
      associations_count: klass.reflect_on_all_associations.size,
      associations: extract_associations(klass)
    }
  rescue StandardError
    nil
  end
end
```

Add these two methods **inside the existing `private` section**, after `derive_class_name` (do NOT add a second `private` keyword):

```ruby
def extract_columns(klass)
  klass.columns.map do |col|
    {
      name: col.name,
      type: col.type.to_s,
      nullable: col.null,
      default: col.default
    }
  end
end

def extract_associations(klass)
  klass.reflect_on_all_associations.map do |assoc|
    {
      name: assoc.name.to_s,
      macro: assoc.macro.to_s,
      target_class: assoc.class_name
    }
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/module_model_discovery_spec.rb -v`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/module_model_discovery.rb spec/services/module_model_discovery_spec.rb
git commit -m "feat: enhance ModuleModelDiscovery with column and association details"
```

---

### Task 2: Create Expandable Row Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/expandable_row_controller.js`

- [ ] **Step 1: Create the Stimulus controller**

Create `app/javascript/controllers/expandable_row_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggleButton", "detailPanel"]

  toggle(event) {
    event.preventDefault()
    const panelId = event.currentTarget.dataset.expandableRowPanel
    const panel = this.detailPanelTargets.find(
      p => p.dataset.expandableRowId === panelId
    )
    if (!panel) return

    const isHidden = panel.classList.contains("hidden")
    // Close all panels in this controller scope first
    this.detailPanelTargets.forEach(p => p.classList.add("hidden"))
    // Toggle the clicked panel
    if (isHidden) {
      panel.classList.remove("hidden")
    }
  }
}
```

- [ ] **Step 2: Verify the controller is auto-registered**

Run: `ls app/javascript/controllers/expandable_row_controller.js`
Expected: File exists. Stimulus auto-imports controllers from this directory via `pin_all_from "app/javascript/controllers"` in `config/importmap.rb`.

> **Note:** No JS unit tests are added for this controller. The expandable behavior is verified through manual smoke testing in Task 6 and by the integration specs that confirm the show page renders correctly.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/expandable_row_controller.js
git commit -m "feat: add expandable-row Stimulus controller for inline detail panels"
```

---

### Task 3: Refactor Feature Module Index Page

**Files:**
- Modify: `app/views/feature_modules/index.html.erb`
- Modify: `app/components/feature_module_list_item_component.rb`
- Modify: `app/components/feature_module_list_item_component.html.erb`
- Modify: `spec/components/feature_module_list_item_component_spec.rb`

- [ ] **Step 1: Update the component to accept and render enable/disable actions**

**Replace the entire file** `app/components/feature_module_list_item_component.rb` with this version that adds path helper methods and a `status_badge_variant` method:

```ruby
# frozen_string_literal: true

class FeatureModuleListItemComponent < ApplicationComponent
  attr_reader :feature_module, :enabled, :customer_id

  def initialize(feature_module:, enabled:, customer_id:)
    @feature_module = feature_module
    @enabled = enabled
    @customer_id = customer_id
  end

  def enabled? = @enabled
  def required? = feature_module.required?

  def status_label
    if required? && enabled?
      "Required"
    elsif enabled?
      "Enabled"
    else
      "Available"
    end
  end

  def status_badge_variant
    if required? && enabled?
      :warning
    elsif enabled?
      :success
    else
      :default
    end
  end

  def show_path
    helpers.feature_module_path(customer_id, feature_module)
  end

  def enable_path
    helpers.enable_feature_module_path(customer_id, feature_module)
  end

  def disable_path
    helpers.disable_feature_module_path(customer_id, feature_module)
  end
end
```

- [ ] **Step 2: Rewrite the component template**

Replace `app/components/feature_module_list_item_component.html.erb` with an entity-list-style row that includes enable/disable actions:

```erb
<tr class="hover:bg-gray-50 transition-colors">
  <td class="px-6 py-4">
    <div class="flex items-center gap-2.5">
      <div class="w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0 <%= enabled? ? 'bg-emerald-50 text-emerald-600' : 'bg-slate-100 text-slate-400' %>">
        <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
          <path stroke-linecap="round" stroke-linejoin="round" d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4" />
        </svg>
      </div>
      <div class="min-w-0">
        <%= link_to feature_module.name, show_path,
            class: "text-sm font-semibold text-gray-900 hover:text-indigo-600 transition-colors" %>
        <p class="mt-0.5 text-xs text-gray-500 line-clamp-1"><%= feature_module.description %></p>
      </div>
    </div>
  </td>
  <td class="px-6 py-4 whitespace-nowrap">
    <span class="font-mono text-xs text-gray-500 bg-gray-100 px-1.5 py-0.5 rounded"><%= feature_module.key %></span>
  </td>
  <td class="px-6 py-4 whitespace-nowrap">
    <%= render BadgeComponent.new(variant: status_badge_variant, size: :sm) do %><%= status_label %><% end %>
  </td>
  <td class="px-6 py-4 whitespace-nowrap text-right">
    <div class="flex items-center justify-end gap-2">
      <%= link_to show_path,
          class: "p-1.5 text-gray-500 hover:text-indigo-600 hover:bg-indigo-50 rounded-md transition-colors inline-flex",
          title: "Details" do %>
        <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
          <path stroke-linecap="round" stroke-linejoin="round" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z" />
        </svg>
      <% end %>

      <% if required? && enabled? %>
        <span class="inline-flex items-center px-3 py-1.5 text-xs font-medium text-gray-400 bg-gray-50 border border-gray-200 rounded-lg cursor-default" title="Always On">
          <svg class="w-3.5 h-3.5 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
          </svg>
          Always On
        </span>
      <% elsif enabled? %>
        <%= button_to disable_path,
              method: :post,
              data: { turbo_confirm: "Are you sure you want to disable #{feature_module.name}?" },
              class: "inline-flex items-center px-3 py-1.5 text-xs font-medium text-red-700 bg-red-50 border border-red-200 rounded-lg hover:bg-red-100 transition-colors" do %>
          Disable
        <% end %>
      <% else %>
        <%= button_to enable_path,
              method: :post,
              class: "inline-flex items-center px-3 py-1.5 text-xs font-medium text-white bg-indigo-600 border border-transparent rounded-lg hover:bg-indigo-700 transition-colors" do %>
          Enable
        <% end %>
      <% end %>
    </div>
  </td>
</tr>
```

- [ ] **Step 3: Rewrite the index page to use the component in a card-wrapped table**

Replace `app/views/feature_modules/index.html.erb`:

```erb
<div class="max-w-[1400px] mx-auto px-4 py-8">
  <nav class="mb-6">
    <%= link_to flowcharts_path(current_customer_id), class: "inline-flex items-center text-sm text-gray-500 hover:text-indigo-600 transition-colors" do %>
      <svg class="w-4 h-4 mr-1.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M10 19l-7-7m0 0l7-7m-7 7h18" />
      </svg>
      Back to Flowcharts
    <% end %>
  </nav>

  <header class="mb-8">
    <div class="flex items-center justify-between mb-4">
      <h1 class="text-2xl font-bold text-gray-900">Feature Modules</h1>
      <span class="text-sm text-gray-500">
        <%= @enabled_module_ids.size %> of <%= @available_modules.size %> enabled
      </span>
    </div>
  </header>

  <%= render AlertComponent.new(message: notice, type: :success) %>
  <%= render AlertComponent.new(message: alert, type: :error) %>

  <% if @available_modules.any? %>
    <div class="bg-white border border-gray-200 rounded-lg shadow-sm overflow-x-auto">
      <table class="min-w-full divide-y divide-gray-200">
        <thead class="bg-gray-50">
          <tr>
            <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Module</th>
            <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Key</th>
            <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
            <th scope="col" class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
          </tr>
        </thead>
        <tbody class="bg-white divide-y divide-gray-200">
          <% @available_modules.each do |feature_module| %>
            <%= render FeatureModuleListItemComponent.new(
              feature_module: feature_module,
              enabled: @enabled_module_ids.include?(feature_module.id),
              customer_id: current_customer_id
            ) %>
          <% end %>
        </tbody>
      </table>
    </div>
  <% else %>
    <%= render EmptyStateComponent.new(
      title: "No feature modules available",
      description: "Feature modules will appear here once they are registered in the system.",
      icon_path: "M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4"
    ) %>
  <% end %>
</div>
```

- [ ] **Step 4: Update component spec**

Replace `spec/components/feature_module_list_item_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModuleListItemComponent, type: :component do
  let(:feature_mod) { create(:feature_module, key: "test_mod", name: "Test Module", description: "A test module") }
  let(:customer) { create(:customer) }

  context "when enabled" do
    it "renders module name and enabled badge" do
      render_inline(described_class.new(feature_module: feature_mod, enabled: true, customer_id: customer.id))
      expect(page).to have_text("Test Module")
      expect(page).to have_text("Enabled")
    end

    it "renders disable button" do
      render_inline(described_class.new(feature_module: feature_mod, enabled: true, customer_id: customer.id))
      expect(page).to have_button("Disable")
    end
  end

  context "when not enabled" do
    it "renders available badge and enable button" do
      render_inline(described_class.new(feature_module: feature_mod, enabled: false, customer_id: customer.id))
      expect(page).to have_text("Available")
      expect(page).to have_button("Enable")
    end
  end

  context "when required and enabled" do
    let(:required_mod) { create(:feature_module, key: "req_mod", name: "Required Mod", required: true) }

    it "shows Always On instead of disable button" do
      render_inline(described_class.new(feature_module: required_mod, enabled: true, customer_id: customer.id))
      expect(page).to have_text("Required")
      expect(page).to have_text("Always On")
      expect(page).not_to have_button("Disable")
    end
  end
end
```

- [ ] **Step 5: Run all related tests**

Run: `bundle exec rspec spec/components/feature_module_list_item_component_spec.rb spec/requests/feature_modules_spec.rb -v`
Expected: ALL PASS

- [ ] **Step 6: Commit**

```bash
git add app/views/feature_modules/index.html.erb app/components/feature_module_list_item_component.rb app/components/feature_module_list_item_component.html.erb spec/components/feature_module_list_item_component_spec.rb
git commit -m "refactor: feature module index page to entity-style card layout with component"
```

---

### Task 4: Refactor Feature Module Show Page — Models Section with Expandable Rows

**Files:**
- Modify: `app/views/feature_modules/show.html.erb`

- [ ] **Step 1: Replace the Models card in the Overview tab**

In `app/views/feature_modules/show.html.erb`, replace the entire Models card (starting from the `<%# Models Card %>` comment through the closing `</div>` of that card) with the expandable version. The table now wraps in a `data-controller="expandable-row"` and makes Columns/Associations counts into clickable links that toggle detail panels:

```erb
<%# Models Card %>
<div class="bg-white border border-gray-200 rounded-lg shadow-sm">
  <div class="px-6 py-4 border-b border-gray-100">
    <div class="flex items-center justify-between">
      <h3 class="text-base font-semibold text-gray-900">Models</h3>
      <span class="text-xs text-gray-500"><%= @module_models.size %> <%= "model".pluralize(@module_models.size) %></span>
    </div>
  </div>
  <% if @module_models.any? %>
    <div class="overflow-x-auto" data-controller="expandable-row">
      <table class="min-w-full divide-y divide-gray-200">
        <thead class="bg-gray-50">
          <tr>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Class</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Table Name</th>
            <th class="px-6 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider">Columns</th>
            <th class="px-6 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider">Associations</th>
          </tr>
        </thead>
        <tbody class="bg-white divide-y divide-gray-200">
          <% @module_models.each_with_index do |model, idx| %>
            <tr class="hover:bg-gray-50 transition-colors">
              <td class="px-6 py-4 whitespace-nowrap">
                <span class="font-mono text-sm text-gray-900"><%= model[:name] %></span>
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <span class="font-mono text-xs text-gray-500 bg-gray-100 px-1.5 py-0.5 rounded"><%= model[:table_name] %></span>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-center">
                <% if model[:columns].present? %>
                  <button type="button"
                          data-action="click->expandable-row#toggle"
                          data-expandable-row-panel="columns-<%= idx %>"
                          class="text-sm text-indigo-600 hover:text-indigo-800 font-medium cursor-pointer hover:underline">
                    <%= model[:columns_count] %>
                  </button>
                <% else %>
                  <span class="text-sm text-gray-500"><%= model[:columns_count] %></span>
                <% end %>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-center">
                <% if model[:associations].present? && model[:associations].any? %>
                  <button type="button"
                          data-action="click->expandable-row#toggle"
                          data-expandable-row-panel="associations-<%= idx %>"
                          class="text-sm text-indigo-600 hover:text-indigo-800 font-medium cursor-pointer hover:underline">
                    <%= model[:associations_count] %>
                  </button>
                <% else %>
                  <span class="text-sm text-gray-500"><%= model[:associations_count] %></span>
                <% end %>
              </td>
            </tr>

            <%# Columns Detail Panel %>
            <tr class="hidden" data-expandable-row-target="detailPanel" data-expandable-row-id="columns-<%= idx %>">
              <td colspan="4" class="px-6 py-4 bg-gray-50">
                <div class="mb-2 text-xs font-semibold text-gray-500 uppercase tracking-wider">Columns</div>
                <div class="overflow-x-auto">
                  <table class="min-w-full text-xs">
                    <thead>
                      <tr class="border-b border-gray-200">
                        <th class="py-2 pr-6 text-left font-medium text-gray-500">Name</th>
                        <th class="py-2 pr-6 text-left font-medium text-gray-500">Type</th>
                        <th class="py-2 pr-6 text-left font-medium text-gray-500">Nullable</th>
                        <th class="py-2 text-left font-medium text-gray-500">Default</th>
                      </tr>
                    </thead>
                    <tbody>
                      <% (model[:columns] || []).each do |col| %>
                        <tr class="border-b border-gray-100">
                          <td class="py-1.5 pr-6 font-mono text-gray-900"><%= col[:name] %></td>
                          <td class="py-1.5 pr-6">
                            <span class="inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-blue-100 text-blue-800"><%= col[:type] %></span>
                          </td>
                          <td class="py-1.5 pr-6 text-gray-500"><%= col[:nullable] ? "Yes" : "No" %></td>
                          <td class="py-1.5 text-gray-500 font-mono"><%= col[:default].present? ? col[:default] : "-" %></td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              </td>
            </tr>

            <%# Associations Detail Panel %>
            <tr class="hidden" data-expandable-row-target="detailPanel" data-expandable-row-id="associations-<%= idx %>">
              <td colspan="4" class="px-6 py-4 bg-gray-50">
                <div class="mb-2 text-xs font-semibold text-gray-500 uppercase tracking-wider">Associations</div>
                <% if model[:associations].present? && model[:associations].any? %>
                  <div class="overflow-x-auto">
                    <table class="min-w-full text-xs">
                      <thead>
                        <tr class="border-b border-gray-200">
                          <th class="py-2 pr-6 text-left font-medium text-gray-500">Type</th>
                          <th class="py-2 pr-6 text-left font-medium text-gray-500">Name</th>
                          <th class="py-2 text-left font-medium text-gray-500">Target Class</th>
                        </tr>
                      </thead>
                      <tbody>
                        <% model[:associations].each do |assoc| %>
                          <tr class="border-b border-gray-100">
                            <td class="py-1.5 pr-6">
                              <%
                                assoc_classes = case assoc[:macro]
                                when "belongs_to" then "bg-amber-100 text-amber-800"
                                when "has_many"   then "bg-green-100 text-green-800"
                                when "has_one"    then "bg-blue-100 text-blue-800"
                                else                   "bg-gray-100 text-gray-800"
                                end
                              %>
                              <span class="inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium <%= assoc_classes %>"><%= assoc[:macro] %></span>
                            </td>
                            <td class="py-1.5 pr-6 font-mono text-gray-900"><%= assoc[:name] %></td>
                            <td class="py-1.5">
                              <% target_model = @module_models.find { |m| m[:name] == assoc[:target_class] } %>
                              <% if target_model %>
                                <span class="font-mono text-indigo-600"><%= assoc[:target_class] %></span>
                              <% else %>
                                <span class="font-mono text-gray-500"><%= assoc[:target_class] %></span>
                              <% end %>
                            </td>
                          </tr>
                        <% end %>
                      </tbody>
                    </table>
                  </div>
                <% else %>
                  <p class="text-xs text-gray-500 italic">No associations.</p>
                <% end %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  <% else %>
    <div class="p-6 text-center">
      <p class="text-sm text-gray-500 italic">No models found for this module.</p>
    </div>
  <% end %>
</div>
```

- [ ] **Step 2: Run existing feature module specs**

Run: `bundle exec rspec spec/requests/feature_modules_spec.rb -v`
Expected: ALL PASS — the show page still renders correctly.

- [ ] **Step 3: Commit**

```bash
git add app/views/feature_modules/show.html.erb
git commit -m "feat: add expandable columns and associations in feature module Models section"
```

---

### Task 5: Add View Button for GET Routes on Show Page

**Files:**
- Modify: `app/views/feature_modules/show.html.erb`

- [ ] **Step 1: Replace the entire Routes card in the Overview tab**

In `app/views/feature_modules/show.html.erb`, replace the entire Routes card (the `<%# Routes Card %>` section, from the opening `<div class="bg-white ...">` through its closing `</div>`) with this complete replacement that adds an Actions column with View buttons for GET routes:

```erb
<%# Routes Card %>
<div class="bg-white border border-gray-200 rounded-lg shadow-sm">
  <div class="px-6 py-4 border-b border-gray-100">
    <div class="flex items-center justify-between">
      <h3 class="text-base font-semibold text-gray-900">Routes</h3>
      <span class="text-xs text-gray-500"><%= @module_routes.size %> <%= "route".pluralize(@module_routes.size) %></span>
    </div>
  </div>
  <% if @module_routes.any? %>
    <div class="overflow-x-auto">
      <table class="min-w-full divide-y divide-gray-200">
        <thead class="bg-gray-50">
          <tr>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider w-24">Method</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Path</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Name</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Action</th>
            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider w-20"></th>
          </tr>
        </thead>
        <tbody class="bg-white divide-y divide-gray-200">
          <% @module_routes.each do |route| %>
            <tr class="hover:bg-gray-50 transition-colors">
              <td class="px-6 py-3 whitespace-nowrap">
                <%
                  method_classes = case route[:method]
                  when "GET"          then "bg-green-100 text-green-800"
                  when "POST"         then "bg-blue-100 text-blue-800"
                  when "PATCH", "PUT" then "bg-yellow-100 text-yellow-800"
                  when "DELETE"        then "bg-red-100 text-red-800"
                  else                      "bg-gray-100 text-gray-800"
                  end
                %>
                <span class="inline-flex items-center justify-center px-2 py-0.5 text-xs font-medium rounded-full <%= method_classes %>">
                  <%= route[:method] %>
                </span>
              </td>
              <td class="px-6 py-3">
                <span class="font-mono text-xs text-gray-700"><%= route[:path] %></span>
              </td>
              <td class="px-6 py-3 whitespace-nowrap text-sm text-gray-500"><%= route[:name].presence || "-" %></td>
              <td class="px-6 py-3">
                <span class="font-mono text-xs text-gray-500"><%= route[:controller_action] %></span>
              </td>
              <td class="px-6 py-3 whitespace-nowrap text-right">
                <% if route[:method] == "GET" %>
                  <%
                    # Build the actual URL by replacing route params with placeholder values.
                    # Note: URLs with :id params will use "1" as a placeholder — the page may
                    # show a "not found" error if no record with that ID exists.
                    view_url = route[:path]
                      .gsub(":customer_id", current_customer_id.to_s)
                      .gsub(/:id\b/, "1")
                      .gsub(/:(\w+)_id/, "1")
                  %>
                  <%= link_to view_url, target: "_blank",
                      class: "inline-flex items-center px-2.5 py-1 text-xs font-medium text-indigo-700 bg-indigo-50 border border-indigo-200 rounded-lg hover:bg-indigo-100 transition-colors" do %>
                    <svg class="w-3.5 h-3.5 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
                    </svg>
                    View
                  <% end %>
                <% else %>
                  <span class="text-xs text-gray-300">-</span>
                <% end %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  <% else %>
    <div class="p-6 text-center">
      <p class="text-sm text-gray-500 italic">No routes found for this module.</p>
    </div>
  <% end %>
</div>
```

- [ ] **Step 2: Add a request spec for the View button**

Add to `spec/requests/feature_modules_spec.rb` in the show describe block:

```ruby
it "shows View link for GET routes" do
  get feature_module_path(customer.id, auth_mod)
  # The authentication module has GET routes; check that View link appears inside a route action cell
  expect(response.body).to include('View</a>')
end

it "shows dash for non-GET routes" do
  get feature_module_path(customer.id, auth_mod)
  # POST/PATCH/DELETE routes should show a dash instead of a View link
  expect(response.body).to include('<span class="text-xs text-gray-300">-</span>')
end
```

- [ ] **Step 3: Run tests**

Run: `bundle exec rspec spec/requests/feature_modules_spec.rb -v`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add app/views/feature_modules/show.html.erb spec/requests/feature_modules_spec.rb
git commit -m "feat: add View button for GET routes on feature module show page"
```

---

### Task 6: Final Verification and Asset Compilation

- [ ] **Step 1: Run the full test suite for affected files**

Run: `bundle exec rspec spec/services/module_model_discovery_spec.rb spec/services/module_route_discovery_spec.rb spec/components/feature_module_list_item_component_spec.rb spec/requests/feature_modules_spec.rb -v`
Expected: ALL PASS

- [ ] **Step 2: Compile assets and restart server**

Run: `bin/rails assets:precompile`
Expected: Clean compilation with no errors.

- [ ] **Step 3: Manual smoke test**

1. Visit `/:customer_id/feature_modules` — verify card-based layout with list item components, enable/disable buttons work
2. Visit `/:customer_id/feature_modules/:id` — click on column count → expands column detail panel. Click again → collapses. Click associations count → expands association panel.
3. In the Routes section, verify "View" buttons appear only on GET rows. Click one → opens the actual URL in a new tab.

- [ ] **Step 4: Final commit if any fixes needed**

```bash
git add -A
git commit -m "fix: address smoke test findings for feature module page refactor"
```
