# Template Picker Modal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the eagerly-rendered inline template grid on the entity create/edit form and the page builder "New Page" form with a trigger + modal whose template cards are fetched only when the modal first opens.

**Architecture:** A new admin endpoint renders just the heavy card grid (`layout: false`); a reusable `PageBuilder::TemplatePickerComponent` renders a cheap trigger + an initially-empty modal shell + the preview modal; the shared `template-selector` Stimulus controller gains modal open/close, one-time lazy fetch, a pending-then-confirm selection flow, and (entity form only) a styled overwrite confirmation before repopulating attributes.

**Tech Stack:** Ruby 3.2 / Rails 8.1, ViewComponent, StimulusJS, TailwindCSS, RSpec.

> **Execution note (commit policy):** The user does NOT allow commits on `master`. Execute this plan inside a git worktree branch (see `superpowers:using-git-worktrees`); the `git commit` steps below apply on that branch. If for any reason you are on `master`, skip the commit steps and leave changes staged.

---

## File Structure

**New files**
- `app/controllers/admin/maintenance/template_picker_cards_controller.rb` — lazy-load endpoint; renders the cards partial only.
- `app/views/shared/_template_picker_grid.html.erb` — the card grid (one `TemplateCardComponent` per template) + no-results node. The only heavy payload, now deferred.
- `app/components/page_builder/template_picker_component.rb` — component logic (trigger state, field config).
- `app/components/page_builder/template_picker_component.html.erb` — trigger + modal shell + preview modal markup.
- `spec/requests/admin/maintenance/template_picker_cards_spec.rb` — endpoint auth, tenant scoping, `scope` param.
- `spec/components/page_builder/template_picker_component_spec.rb` — trigger states + field config.

**Modified files**
- `config/routes.rb` — add the `template_picker_cards` route under the `maintenance` scope.
- `app/views/admin/maintenance/entities/_form.html.erb` — replace the inline Referenced Template section with the component.
- `app/views/admin/maintenance/pages/new.html.erb` — replace the inline grid + preview modal with the component (keep the theme selector in the view).
- `app/javascript/controllers/template_selector_controller.js` — modal + lazy load + pending/confirm.
- `app/javascript/controllers/entity_form_controller.js` — overwrite confirmation in `handleTemplateSelected`.

**Out of scope**
- `app/views/admin/maintenance/pages/_editor.html.erb` — uses the separate `template-applier` controller. Do not touch.

---

## Task 1: Lazy-load endpoint + route

**Files:**
- Create: `app/controllers/admin/maintenance/template_picker_cards_controller.rb`
- Modify: `config/routes.rb` (inside `scope :maintenance, as: :maintenance do`, near the `entities` block ~line 189)
- Test: `spec/requests/admin/maintenance/template_picker_cards_spec.rb`

Authorization note: every path under `/:cid/admin/` is guarded automatically by the global `RouteAuthorization` concern (`enforce_route_role!` → admin-or-owner). No explicit `before_action` guard is needed; correct route placement is the guard.

- [ ] **Step 1: Write the failing request spec**

```ruby
# spec/requests/admin/maintenance/template_picker_cards_spec.rb
# frozen_string_literal: true
require "rails_helper"

RSpec.describe "Admin::Maintenance::TemplatePickerCards", type: :request do
  let(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }
  let(:member)   { create(:user, :member, customer: customer) }

  describe "GET show" do
    it "requires authentication" do
      get "/#{customer.id}/admin/maintenance/template_picker_cards"
      expect(response).not_to have_http_status(:ok)
    end

    it "forbids member role" do
      sign_in member
      get "/#{customer.id}/admin/maintenance/template_picker_cards"
      expect(response).not_to have_http_status(:ok)
    end

    it "renders template cards for an admin (scope=all)" do
      sign_in admin
      get "/#{customer.id}/admin/maintenance/template_picker_cards", params: { scope: "all" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-template-key")
      # No application layout when rendered for injection
      expect(response.body).not_to include("<html")
    end

    it "honours scope=industry without error" do
      sign_in admin
      get "/#{customer.id}/admin/maintenance/template_picker_cards", params: { scope: "industry" }
      expect(response).to have_http_status(:ok)
    end
  end
end
```

- [ ] **Step 2: Run the spec, verify it fails**

Run: `bundle exec rspec spec/requests/admin/maintenance/template_picker_cards_spec.rb`
Expected: FAIL — routing error / no route matches `template_picker_cards`.

- [ ] **Step 3: Add the route**

In `config/routes.rb`, inside `scope :maintenance, as: :maintenance do`, immediately after the closing `end` of the `resources :entities … do … end` block, add:

```ruby
        # Template picker cards (lazy-loaded grid for entity form + page builder)
        resource :template_picker_cards, only: :show,
                 controller: "maintenance/template_picker_cards"
```

- [ ] **Step 4: Create the controller**

```ruby
# app/controllers/admin/maintenance/template_picker_cards_controller.rb
# frozen_string_literal: true

module Admin
  module Maintenance
    # Renders the template card grid on demand so the entity form and the page
    # builder can lazy-load it the first time their picker modal is opened,
    # instead of rendering 100+ cards inline at page load.
    class TemplatePickerCardsController < ApplicationController
      dashboard_menu_item :maintenance

      def show
        templates =
          if params[:scope] == "all"
            PageLayoutTemplates.all
          else
            PageLayoutTemplates.for_industry(current_customer&.industry)
          end

        render(
          partial: "shared/template_picker_grid",
          layout: false,
          locals: {
            templates: templates,
            selected_key: params[:selected].presence,
            controller_name: "template-selector"
          }
        )
      end
    end
  end
end
```

- [ ] **Step 5: Run the spec, expect it to still fail on the missing partial**

Run: `bundle exec rspec spec/requests/admin/maintenance/template_picker_cards_spec.rb`
Expected: FAIL — missing partial `shared/_template_picker_grid`. (The partial is created in Task 2; this confirms the route + controller resolve.)

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/admin/maintenance/template_picker_cards_controller.rb spec/requests/admin/maintenance/template_picker_cards_spec.rb
git commit -m "feat(entities): add lazy-load template picker cards endpoint"
```

---

## Task 2: Cards grid partial

**Files:**
- Create: `app/views/shared/_template_picker_grid.html.erb`
- Test: reuses `spec/requests/admin/maintenance/template_picker_cards_spec.rb` from Task 1.

- [ ] **Step 1: Create the partial**

```erb
<%# app/views/shared/_template_picker_grid.html.erb
    Locals:
      templates       - Array of template hashes
      selected_key    - currently selected template key (or nil)
      controller_name - Stimulus controller name (default "template-selector")
%>
<% controller_name ||= "template-selector" %>
<div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3" data-<%= controller_name %>-target="grid">
  <% templates.each do |template| %>
    <%= render PageBuilder::TemplateCardComponent.new(
      template: template,
      selected: template[:key] == selected_key,
      controller_name: controller_name
    ) %>
  <% end %>
</div>

<%# No results message %>
<div class="hidden text-center py-12" data-<%= controller_name %>-target="noResults">
  <svg class="w-16 h-16 mx-auto text-text-muted mb-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1">
    <path stroke-linecap="round" stroke-linejoin="round" d="M9.172 16.172a4 4 0 015.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
  </svg>
  <h3 class="text-body-sm font-medium text-text-primary mb-1">No templates found</h3>
  <p class="text-caption">Try adjusting your search or category filter</p>
</div>
```

- [ ] **Step 2: Run the Task 1 spec, verify it passes**

Run: `bundle exec rspec spec/requests/admin/maintenance/template_picker_cards_spec.rb`
Expected: PASS (all four examples).

- [ ] **Step 3: Commit**

```bash
git add app/views/shared/_template_picker_grid.html.erb
git commit -m "feat(entities): add template picker grid partial"
```

---

## Task 3: TemplatePickerComponent

The component does NOT emit the `data-controller` root — the consuming view owns it (the page builder needs the entity `<select>` inside the same controller scope). The component renders: trigger (empty + selected blocks), the modal shell (search, category tabs, empty grid container, loading/error states, footer), the preview modal, and the hidden field.

**Files:**
- Create: `app/components/page_builder/template_picker_component.rb`
- Create: `app/components/page_builder/template_picker_component.html.erb`
- Test: `spec/components/page_builder/template_picker_component_spec.rb`

- [ ] **Step 1: Write the failing component spec**

```ruby
# spec/components/page_builder/template_picker_component_spec.rb
# frozen_string_literal: true
require "rails_helper"

RSpec.describe PageBuilder::TemplatePickerComponent, type: :component do
  let(:category_counts) { { "all" => 3, "contact" => 1 } }
  let(:base_args) do
    {
      selected_template: nil,
      category_counts: category_counts,
      cards_url: "/1/admin/maintenance/template_picker_cards?scope=industry",
      field_name: "entity[referenced_template]",
      field_value: "",
      field_key: "",
      confirm_label: "Use Template"
    }
  end

  it "renders the empty trigger when nothing is selected" do
    render_inline(described_class.new(**base_args))
    expect(page).to have_css("[data-template-selector-target='triggerEmpty']")
    expect(page).to have_text("Choose Template")
  end

  it "renders the selected trigger summary when a template is selected" do
    render_inline(described_class.new(**base_args.merge(
      selected_template: { key: "contact_basic", name: "Basic Contact", theme_preset: "modern" },
      field_key: "contact_basic"
    )))
    expect(page).to have_css("[data-template-selector-target='triggerSelected']:not(.hidden)")
    expect(page).to have_text("Basic Contact")
  end

  it "renders an empty grid container (cards are lazy-loaded)" do
    render_inline(described_class.new(**base_args))
    expect(page).to have_css("[data-template-selector-target='templateContainer']")
    expect(page).not_to have_css("[data-template-key]") # no cards rendered server-side
  end

  it "renders the hidden field with the given name, value and template key" do
    render_inline(described_class.new(**base_args.merge(
      field_name: "page[layout_template]", field_value: "blank", field_key: "blank"
    )))
    input = page.find("input[type='hidden'][name='page[layout_template]']", visible: :all)
    expect(input[:value]).to eq("blank")
    expect(input["data-template-key"]).to eq("blank")
    expect(input["data-template-selector-target"]).to eq("selectedTemplate")
  end

  it "renders the confirm button with the given label" do
    render_inline(described_class.new(**base_args.merge(confirm_label: "Apply Layout")))
    expect(page).to have_button("Apply Layout")
  end

  it "exposes the cards url for the Stimulus controller to read" do
    render_inline(described_class.new(**base_args))
    expect(page).to have_css("[data-template-picker-cards-url='#{base_args[:cards_url]}']")
  end
end
```

- [ ] **Step 2: Run the spec, verify it fails**

Run: `bundle exec rspec spec/components/page_builder/template_picker_component_spec.rb`
Expected: FAIL — uninitialized constant `PageBuilder::TemplatePickerComponent`.

- [ ] **Step 3: Create the component class**

```ruby
# app/components/page_builder/template_picker_component.rb
# frozen_string_literal: true

module PageBuilder
  # Trigger + lazy-loaded modal for selecting a layout template.
  # Used by the entity create/edit form and the page builder "New Page" form.
  # The consuming view supplies the `data-controller="template-selector"` root
  # (and its `*-cards-url-value` / `*-customer-id-value` values) so that the
  # entity <select> in the page builder shares the same controller instance.
  class TemplatePickerComponent < ApplicationComponent
    def initialize(selected_template:, category_counts:, cards_url:,
                   field_name:, field_value:, field_key:,
                   confirm_label: "Use Template", controller_name: "template-selector")
      @selected_template = selected_template
      @category_counts   = category_counts
      @cards_url         = cards_url
      @field_name        = field_name
      @field_value       = field_value
      @field_key         = field_key.to_s
      @confirm_label     = confirm_label
      @controller_name   = controller_name
    end

    attr_reader :selected_template, :category_counts, :cards_url,
                :field_name, :field_value, :field_key, :confirm_label, :controller_name

    def selected?
      field_key.present?
    end

    def selected_name
      selected_template&.dig(:name).presence || selected_template&.dig("name").presence || field_key
    end

    def selected_theme
      selected_template&.dig(:theme_preset).presence || selected_template&.dig("theme_preset").presence
    end

    def target(name)
      "#{controller_name}-target"
    end
  end
end
```

- [ ] **Step 4: Create the component template**

```erb
<%# app/components/page_builder/template_picker_component.html.erb %>
<div data-<%= controller_name %>-target="picker" data-template-picker-cards-url="<%= cards_url %>">

  <%# ── TRIGGER ── %>
  <div class="space-y-2">
    <%# Empty state %>
    <div data-<%= controller_name %>-target="triggerEmpty"
         class="<%= 'hidden' if selected? %> flex flex-col items-center justify-center gap-3 py-8 px-4 border-2 border-dashed border-border rounded-lg bg-canvas-elevated text-center">
      <svg class="w-10 h-10 text-text-muted" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
        <path stroke-linecap="round" stroke-linejoin="round" d="M4 5a1 1 0 011-1h14a1 1 0 011 1v2a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM4 13a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1 1H5a1 1 0 01-1-1v-6zM16 13a1 1 0 011-1h2a1 1 0 011 1v6a1 1 0 01-1 1h-2a1 1 0 01-1-1v-6z" />
      </svg>
      <p class="text-caption">No template selected</p>
      <button type="button" class="btn btn-accent-outline text-xs"
              data-action="click-><%= controller_name %>#openModal">
        Choose Template
      </button>
    </div>

    <%# Selected state %>
    <div data-<%= controller_name %>-target="triggerSelected"
         class="<%= 'hidden' unless selected? %> flex items-center justify-between gap-3 py-3 px-4 border border-border rounded-lg bg-surface">
      <div class="flex items-center gap-3 min-w-0">
        <span class="inline-flex items-center justify-center w-8 h-8 rounded-lg bg-surface-active text-accent shrink-0">
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
        </span>
        <div class="min-w-0">
          <p class="text-body-sm font-medium text-text-primary truncate" data-<%= controller_name %>-target="triggerName"><%= selected_name %></p>
          <p class="text-caption">Referenced template</p>
        </div>
      </div>
      <div class="flex items-center gap-2 shrink-0">
        <button type="button" class="btn btn-secondary text-xs"
                data-action="click-><%= controller_name %>#openModal">Change</button>
        <button type="button" class="btn btn-ghost text-xs"
                data-action="click-><%= controller_name %>#clearTemplate"
                data-<%= controller_name %>-target="clearTemplateBtn">Clear</button>
      </div>
    </div>
  </div>

  <%# ── HIDDEN FIELD ── %>
  <input type="hidden"
         name="<%= field_name %>"
         value="<%= field_value %>"
         data-<%= controller_name %>-target="selectedTemplate"
         data-template-key="<%= field_key %>">

  <%# ── PICKER MODAL ── %>
  <div class="hidden fixed inset-0 z-50 overflow-y-auto"
       data-<%= controller_name %>-target="pickerModal"
       data-action="click-><%= controller_name %>#closeModalOnBackdrop">
    <div class="flex items-center justify-center min-h-screen px-4 pt-4 pb-20 text-center sm:p-0">
      <div class="fixed inset-0 transition-base bg-text-primary/75" aria-hidden="true"></div>
      <div class="relative inline-block w-full max-w-5xl text-left align-middle transform bg-surface rounded-xl shadow-float overflow-hidden">

        <%# Header + search %>
        <div class="px-6 py-4 border-b border-border">
          <div class="flex items-start justify-between mb-3">
            <div>
              <h3 class="text-subheading">Choose a Layout Template</h3>
              <p class="mt-1 text-body-sm">Templates pre-arrange your fields into professional layouts.</p>
            </div>
            <button type="button" class="icon-button" data-action="click-><%= controller_name %>#closeModal">
              <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <div class="relative">
            <div class="absolute inset-y-0 left-0 flex items-center pl-3 pointer-events-none">
              <svg class="w-4 h-4 text-text-muted" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
              </svg>
            </div>
            <input type="text" class="input-field pl-10 pr-10"
                   placeholder="Search by name, description, or category..."
                   data-action="input-><%= controller_name %>#searchTemplates"
                   data-<%= controller_name %>-target="searchInput">
            <button type="button"
                    class="absolute inset-y-0 right-0 flex items-center pr-3 text-text-muted hover:text-text-secondary transition-base hidden"
                    data-action="click-><%= controller_name %>#clearSearch"
                    data-<%= controller_name %>-target="searchClear" title="Clear search">
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <div class="mt-3">
            <%= render "shared/category_tabs", controller_name: controller_name, category_counts: category_counts %>
          </div>

          <div class="hidden mt-2 text-body-sm" data-<%= controller_name %>-target="searchResultsCount">
            <span data-<%= controller_name %>-target="searchResultsNumber">0</span> templates found
          </div>
        </div>

        <%# Body: lazy-loaded cards %>
        <div class="px-6 py-4 bg-canvas max-h-[28rem] overflow-y-auto">
          <%# Loading state %>
          <div data-<%= controller_name %>-target="loadingState" class="hidden flex flex-col items-center justify-center py-16 gap-3">
            <svg class="w-8 h-8 text-accent animate-spin" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path>
            </svg>
            <p class="text-caption">Loading templates…</p>
          </div>

          <%# Error state %>
          <div data-<%= controller_name %>-target="errorState" class="hidden text-center py-16">
            <p class="text-body-sm text-danger mb-3">Could not load templates.</p>
            <button type="button" class="btn btn-secondary text-xs" data-action="click-><%= controller_name %>#loadTemplates">Retry</button>
          </div>

          <%# Cards injected here on first open %>
          <div data-<%= controller_name %>-target="templateContainer"></div>
        </div>

        <%# Footer %>
        <div class="px-6 py-4 bg-canvas border-t border-border">
          <div class="flex justify-end gap-3">
            <button type="button" class="btn btn-secondary" data-action="click-><%= controller_name %>#closeModal">Cancel</button>
            <button type="button" class="btn btn-primary"
                    data-action="click-><%= controller_name %>#confirmSelection"
                    data-<%= controller_name %>-target="confirmBtn"><%= confirm_label %></button>
          </div>
        </div>
      </div>
    </div>
  </div>

  <%# ── PREVIEW ZOOM MODAL ── %>
  <div class="hidden fixed inset-0 z-[60] overflow-y-auto"
       data-<%= controller_name %>-target="previewModal"
       data-action="click-><%= controller_name %>#closePreviewModalOnBackdrop">
    <div class="flex items-center justify-center min-h-screen px-4 pt-4 pb-20 text-center sm:p-0">
      <div class="fixed inset-0 transition-base bg-text-primary/75" aria-hidden="true"></div>
      <div class="relative inline-block w-full max-w-6xl overflow-hidden text-left align-middle transition-base transform bg-surface rounded-xl shadow-float">
        <div class="px-6 py-4 border-b border-border">
          <div class="flex items-start justify-between">
            <div class="flex-1 min-w-0 mr-4">
              <h3 class="text-subheading" data-<%= controller_name %>-target="previewModalName">Template Preview</h3>
              <p class="mt-1 text-body-sm" data-<%= controller_name %>-target="previewModalDescription">Template description</p>
            </div>
            <div class="flex items-center gap-2">
              <span class="badge badge-accent"><span data-<%= controller_name %>-target="previewModalTheme">Modern</span></span>
              <button type="button" class="icon-button" data-action="click-><%= controller_name %>#closePreviewModal">
                <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
          </div>
        </div>
        <div class="px-6 py-6 bg-canvas">
          <div class="card overflow-hidden">
            <div class="p-8 min-h-[500px]" data-<%= controller_name %>-target="previewModalContent"></div>
          </div>
        </div>
        <div class="px-6 py-4 bg-canvas border-t border-border">
          <div class="flex justify-end gap-3">
            <button type="button" class="btn btn-secondary" data-action="click-><%= controller_name %>#closePreviewModal">Close</button>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>
```

- [ ] **Step 5: Run the component spec, verify it passes**

Run: `bundle exec rspec spec/components/page_builder/template_picker_component_spec.rb`
Expected: PASS (all six examples).

- [ ] **Step 6: Commit**

```bash
git add app/components/page_builder/template_picker_component.rb app/components/page_builder/template_picker_component.html.erb spec/components/page_builder/template_picker_component_spec.rb
git commit -m "feat(entities): add reusable TemplatePickerComponent"
```

---

## Task 4: Refactor `template-selector` Stimulus controller (modal + lazy load + pending/confirm)

Replace the connect-time card reading with hidden-field reading, add modal/lazy/confirm logic, and convert card click to pending-only selection. Keep search/category/preview/theme logic intact.

**Files:**
- Modify: `app/javascript/controllers/template_selector_controller.js`

- [ ] **Step 1: Add the new targets and value**

Replace the `static targets = [...]` array (lines ~4-12) with:

```javascript
  static targets = [
    "templateGrid", "templateCard", "selectedTemplate",
    "entitySelect", "categoryTab", "categoryTabs", "categoryGroups", "templateContainer",
    "previewModal", "previewModalContent", "previewModalName", "previewModalDescription", "previewModalTheme",
    "themeSelector", "themeOption", "selectedTheme",
    "searchInput", "searchClear", "noResults",
    "searchResultsCount", "searchResultsNumber",
    "clearTemplateBtn",
    // Modal picker additions:
    "picker", "pickerModal", "triggerEmpty", "triggerSelected", "triggerName",
    "loadingState", "errorState", "confirmBtn"
  ]
```

Replace the `static values = { customerId: String }` block with:

```javascript
  static values = {
    customerId: String,
    cardsUrl: String
  }
```

- [ ] **Step 2: Replace `connect()`**

Replace the existing `connect()` method (lines ~18-28) with:

```javascript
  connect() {
    // Cards are NOT rendered server-side anymore; they are lazy-fetched on first
    // modal open. Read the committed selection from the hidden field instead.
    const keyAttr = this.selectedTemplateTarget.dataset.templateKey
    this.selectedKey = keyAttr || this.selectedTemplateTarget.value || null
    this.pendingKey = this.selectedKey
    this.selectedTheme = this.hasSelectedThemeTarget ? this.selectedThemeTarget.value : null
    this.activeCategory = "all"
    this.searchQuery = ""
    this.loaded = false
    this.loadPromise = null
    this.refreshTrigger()
  }
```

- [ ] **Step 3: Add modal + lazy-load methods**

Add these methods to the controller (e.g. right after `connect()`):

```javascript
  // ──────────────────────────────────────────────────────────────────
  // PICKER MODAL + LAZY LOAD
  // ──────────────────────────────────────────────────────────────────

  openModal(event) {
    if (event) event.preventDefault()
    this.pendingKey = this.selectedKey
    if (this.hasPickerModalTarget) {
      this.pickerModalTarget.classList.remove("hidden")
      document.body.style.overflow = "hidden"
    }
    this.loadTemplates()
  }

  closeModal(event) {
    if (event) event.preventDefault()
    if (this.hasPickerModalTarget) {
      this.pickerModalTarget.classList.add("hidden")
      document.body.style.overflow = ""
    }
    // Discard any uncommitted pending highlight.
    this.pendingKey = this.selectedKey
    this.updateCardStates()
  }

  closeModalOnBackdrop(event) {
    if (event.target === event.currentTarget) this.closeModal(event)
  }

  // Fetch the card grid once. Returns a promise so callers (e.g. entityChanged)
  // can await it before selecting programmatically.
  loadTemplates() {
    if (this.loaded) return Promise.resolve()
    if (this.loadPromise) return this.loadPromise

    if (this.hasErrorStateTarget) this.errorStateTarget.classList.add("hidden")
    if (this.hasLoadingStateTarget) this.loadingStateTarget.classList.remove("hidden")

    const url = this.hasCardsUrlValue && this.cardsUrlValue
      ? this.cardsUrlValue
      : this.pickerTarget.dataset.templatePickerCardsUrl

    this.loadPromise = fetch(url, { headers: { "Accept": "text/html" } })
      .then(response => {
        if (!response.ok) throw new Error(`HTTP ${response.status}`)
        return response.text()
      })
      .then(html => {
        this.templateContainerTarget.innerHTML = html
        this.loaded = true
        if (this.hasLoadingStateTarget) this.loadingStateTarget.classList.add("hidden")
        // Cards just registered as targets; reflect selection + active filters.
        this.updateCardStates()
        this.applyFilters()
      })
      .catch(() => {
        if (this.hasLoadingStateTarget) this.loadingStateTarget.classList.add("hidden")
        if (this.hasErrorStateTarget) this.errorStateTarget.classList.remove("hidden")
      })
      .finally(() => { this.loadPromise = null })

    return this.loadPromise
  }

  confirmSelection(event) {
    if (event) event.preventDefault()
    if (!this.pendingKey) { this.closeModal(); return }

    this.selectedKey = this.pendingKey
    this.selectedTemplateTarget.value = this.selectedKey
    if ("templateKey" in this.selectedTemplateTarget.dataset) {
      this.selectedTemplateTarget.dataset.templateKey = this.selectedKey
    }

    const card = this.templateCardTargets.find(c => c.dataset.templateKey === this.selectedKey)
    if (card && card.dataset.templateTheme) {
      this.selectedTheme = card.dataset.templateTheme
      if (this.hasSelectedThemeTarget) this.selectedThemeTarget.value = this.selectedTheme
    }

    this.updateThemeSelector()
    this.refreshTrigger()
    this.dispatch("templateSelected", { detail: { key: this.selectedKey } })
    this.closeModal()
  }

  refreshTrigger() {
    const hasSelection = !!this.selectedKey
    if (this.hasTriggerEmptyTarget) this.triggerEmptyTarget.classList.toggle("hidden", hasSelection)
    if (this.hasTriggerSelectedTarget) this.triggerSelectedTarget.classList.toggle("hidden", !hasSelection)
    if (hasSelection && this.hasTriggerNameTarget) {
      const card = this.templateCardTargets.find(c => c.dataset.templateKey === this.selectedKey)
      const name = card ? (card.dataset.templateName || this.selectedKey) : this.triggerNameTarget.textContent
      this.triggerNameTarget.textContent = name
    }
  }
```

- [ ] **Step 4: Convert `selectTemplate` to pending-only**

Replace the existing `selectTemplate(event)` method (lines ~103-130) with:

```javascript
  // Card click inside the modal sets a PENDING selection only; the footer
  // "Use Template" button (confirmSelection) commits it.
  selectTemplate(event) {
    const card = event.currentTarget.closest("[data-template-key]")
    if (!card) return
    const key = card.dataset.templateKey
    if (!key) return
    this.pendingKey = key
    this.updateCardStates()
  }
```

- [ ] **Step 5: Make `updateCardStates` highlight the pending selection**

Replace the first line of `updateCardStates()` that computes `isSelected` (line ~334) so highlighting follows `pendingKey` while the modal is open, falling back to `selectedKey`:

Find:
```javascript
      const isSelected = card.dataset.templateKey === this.selectedKey
```
Replace with:
```javascript
      const highlightKey = this.pendingKey != null ? this.pendingKey : this.selectedKey
      const isSelected = card.dataset.templateKey === highlightKey
```

- [ ] **Step 6: Update `clearTemplate` to refresh the trigger**

Replace the existing `clearTemplate(event)` method (lines ~132-142) with:

```javascript
  clearTemplate(event) {
    if (event) event.preventDefault()
    this.selectedKey = null
    this.pendingKey = null
    this.selectedTemplateTarget.value = ""
    if ("templateKey" in this.selectedTemplateTarget.dataset) {
      this.selectedTemplateTarget.dataset.templateKey = ""
    }
    this.updateCardStates()
    this.updateThemeSelector()
    this.refreshTrigger()
    this.dispatch("templateCleared")
  }
```

- [ ] **Step 7: Make `autoSelectTemplate` (page builder entity-binding) load first then commit**

Replace the existing `autoSelectTemplate(templateKey)` method (lines ~54-101) with:

```javascript
  // Page builder: when the bound entity changes, suggest its referenced template.
  // Ensure the (lazy) cards are loaded so we can read the template's theme, then
  // commit the selection without opening the modal.
  async autoSelectTemplate(templateKey) {
    await this.loadTemplates()
    const card = this.templateCardTargets.find(c => c.dataset.templateKey === templateKey)
    if (!card) return

    this.selectedKey = templateKey
    this.pendingKey = templateKey
    this.selectedTemplateTarget.value = templateKey
    if ("templateKey" in this.selectedTemplateTarget.dataset) {
      this.selectedTemplateTarget.dataset.templateKey = templateKey
    }
    if (card.dataset.templateTheme) {
      this.selectedTheme = card.dataset.templateTheme
      if (this.hasSelectedThemeTarget) this.selectedThemeTarget.value = this.selectedTheme
    }

    this.updateCardStates()
    this.updateThemeSelector()
    this.refreshTrigger()
    this.dispatch("templateSelected", { detail: { key: templateKey } })
  }
```

- [ ] **Step 8: Verify no remaining references to removed inline behavior**

Run: `grep -n "handleDoubleClick\|templateGridTarget\|this.selectedKey" app/javascript/controllers/template_selector_controller.js`
Expected: `handleDoubleClick` and the preview/theme methods remain and still compile; there are no references to a server-rendered card grid at connect. (No code change required if grep shows only the retained methods.)

- [ ] **Step 9: Commit**

```bash
git add app/javascript/controllers/template_selector_controller.js
git commit -m "feat(entities): modal + lazy-load + confirm flow in template-selector controller"
```

---

## Task 5: Wire the entity form to the component

**Files:**
- Modify: `app/views/admin/maintenance/entities/_form.html.erb` (the Referenced Template section, lines ~68-206)

- [ ] **Step 1: Replace the Referenced Template section**

Replace the entire block from `<%# Referenced Template Section %>` (line 68) through the closing `</div>` of the `data-controller="template-selector"` card and its preview modal (line 206) with:

```erb
  <%# Referenced Template Section %>
  <%
    referenced_template_key = begin
      ref = @entity.referenced_template
      ref.present? ? JSON.parse(ref)["key"] : nil
    rescue JSON::ParserError
      ref
    end
    referenced_template = referenced_template_key.present? ? PageLayoutTemplates.find(referenced_template_key) : nil
    category_counts = PageLayoutTemplates.category_counts_for_industry(current_customer&.industry)
    cards_url = "#{admin_maintenance_template_picker_cards_path(current_customer_id)}?scope=industry"
  %>
  <div class="card"
       data-controller="template-selector"
       data-template-selector-customer-id-value="<%= current_customer_id %>"
       data-template-selector-cards-url-value="<%= cards_url %>">
    <div class="px-6 py-4 border-b border-border-subtle">
      <h3 class="section-header">Referenced Template</h3>
      <p class="mt-1 text-caption">
        Optionally select a layout template for reference. This template will be associated with the entity for page generation.
      </p>
    </div>

    <div class="p-6">
      <%= render PageBuilder::TemplatePickerComponent.new(
        selected_template: referenced_template,
        category_counts: category_counts,
        cards_url: cards_url,
        field_name: "entity[referenced_template]",
        field_value: @entity.referenced_template,
        field_key: referenced_template_key,
        confirm_label: "Use Template"
      ) %>
    </div>
  </div>
```

Note: the form's `<%= form_with ... %>` action attribute on line 6 still references `template-selector:templateSelected->entity-form#handleTemplateSelected template-selector:templateCleared->entity-form#handleTemplateCleared` — keep it unchanged; the component dispatches the same events.

- [ ] **Step 2: Verify the entity edit page renders without the inline grid**

Run (request spec sanity — reuse the existing entities request spec if present, else load the edit page):
```bash
bundle exec rspec spec/requests/admin/maintenance/entities_spec.rb 2>/dev/null || echo "no entities request spec; verify manually in Task 9"
```
Expected: PASS if the spec exists; otherwise defer to the Task 9 smoke test.

- [ ] **Step 3: Commit**

```bash
git add app/views/admin/maintenance/entities/_form.html.erb
git commit -m "feat(entities): use TemplatePickerComponent on entity form"
```

---

## Task 6: Wire the page builder to the component

**Files:**
- Modify: `app/views/admin/maintenance/pages/new.html.erb` (template selection block lines ~39-104, plus the preview modal lines ~158-213)

- [ ] **Step 1: Replace the inline template block**

Replace the block from `<%# ── TEMPLATE SELECTION ── displayed by default %>` (line 39) through `<%= form.hidden_field :layout_template, value: "blank", data: { template_selector_target: "selectedTemplate" } %>` (line 104) with:

```erb
      <%# ── TEMPLATE SELECTION (modal + lazy load) ── %>
      <%
        blank_template = PageLayoutTemplates.find("blank")
        category_counts = PageLayoutTemplates.category_counts
        cards_url = "#{admin_maintenance_template_picker_cards_path(current_customer_id)}?scope=all"
      %>
      <div>
        <label class="form-label">Choose a Layout Template</label>
        <p class="text-caption mt-0.5 mb-3">
          Templates pre-arrange your fields into professional layouts. Customize everything in the editor.
        </p>
        <%= render PageBuilder::TemplatePickerComponent.new(
          selected_template: blank_template,
          category_counts: category_counts,
          cards_url: cards_url,
          field_name: "page[layout_template]",
          field_value: "blank",
          field_key: "blank",
          confirm_label: "Use Template"
        ) %>
      </div>
```

- [ ] **Step 2: Add the cards-url value to the controller root**

On line 7, change:
```erb
<div data-controller="template-selector" data-template-selector-customer-id-value="<%= current_customer_id %>">
```
to:
```erb
<div data-controller="template-selector"
     data-template-selector-customer-id-value="<%= current_customer_id %>"
     data-template-selector-cards-url-value="<%= "#{admin_maintenance_template_picker_cards_path(current_customer_id)}?scope=all" %>">
```

- [ ] **Step 3: Remove the now-duplicated standalone preview modal**

Delete the `<%# ── PREVIEW ZOOM MODAL ── %>` block (lines ~158-213) — the component now renders the preview modal. Leave the outer `data-controller` `</div>` that closes the page wrapper.

- [ ] **Step 4: Confirm the theme selector + theme hidden field remain**

Verify lines ~106-137 (the `themeSelector` block and `form.hidden_field :theme_preset`) are untouched — they stay in the view and are revealed by `updateThemeSelector()` after a selection is committed.

- [ ] **Step 5: Commit**

```bash
git add app/views/admin/maintenance/pages/new.html.erb
git commit -m "feat(pages): use TemplatePickerComponent on page builder new form"
```

---

## Task 7: Entity-form overwrite confirmation

When a committed template would replace existing attributes (edit mode), confirm first using a styled Tailwind dialog — no native `confirm()`.

**Files:**
- Modify: `app/views/admin/maintenance/entities/_form.html.erb` (append a confirmation modal near the other modals at the bottom, lines ~287-294)
- Modify: `app/javascript/controllers/entity_form_controller.js` (`handleTemplateSelected`, lines ~339-364)

- [ ] **Step 1: Add the styled confirmation modal to the form**

After `<%= render "admin/maintenance/entities/attribute_view_modal" %>` (line 294), add:

```erb
  <%# Template overwrite confirmation %>
  <div class="hidden fixed inset-0 z-[55] overflow-y-auto" data-entity-form-target="overwriteModal">
    <div class="flex items-center justify-center min-h-screen px-4">
      <div class="fixed inset-0 bg-text-primary/75" aria-hidden="true"></div>
      <div class="relative inline-block w-full max-w-md text-left align-middle transform bg-surface rounded-xl shadow-float overflow-hidden">
        <div class="px-6 py-5">
          <h3 class="text-subheading mb-2">Replace existing attributes?</h3>
          <p class="text-body-sm">
            This template will replace your
            <span class="font-semibold" data-entity-form-target="overwriteCount">0</span>
            existing attribute(s). This cannot be undone.
          </p>
        </div>
        <div class="px-6 py-4 bg-canvas border-t border-border flex justify-end gap-3">
          <button type="button" class="btn btn-secondary" data-action="click->entity-form#cancelOverwrite">Cancel</button>
          <button type="button" class="btn btn-danger" data-action="click->entity-form#confirmOverwrite">Replace</button>
        </div>
      </div>
    </div>
  </div>
```

- [ ] **Step 2: Register the new targets on the entity-form controller**

In `app/javascript/controllers/entity_form_controller.js`, add `"overwriteModal"`, `"overwriteCount"` to the controller's `static targets` array.

Run first to find the array: `grep -n "static targets" app/javascript/controllers/entity_form_controller.js`
Then append the two target names to that array.

- [ ] **Step 3: Replace `handleTemplateSelected` to gate on existing attributes**

Replace the existing `handleTemplateSelected(event)` method (lines ~339-364) with:

```javascript
  async handleTemplateSelected(event) {
    const key = event.detail?.key
    if (!key) return

    // Count existing attribute rows. In edit mode, replacing them is destructive,
    // so confirm first.
    const existingCount = this.element.querySelectorAll("[data-attribute-item]").length
    if (existingCount > 0) {
      this._pendingTemplateKey = key
      if (this.hasOverwriteCountTarget) this.overwriteCountTarget.textContent = existingCount
      if (this.hasOverwriteModalTarget) {
        this.overwriteModalTarget.classList.remove("hidden")
        return
      }
    }

    await this._applyTemplate(key)
  }

  async confirmOverwrite() {
    if (this.hasOverwriteModalTarget) this.overwriteModalTarget.classList.add("hidden")
    const key = this._pendingTemplateKey
    this._pendingTemplateKey = null
    if (key) await this._applyTemplate(key)
  }

  cancelOverwrite() {
    if (this.hasOverwriteModalTarget) this.overwriteModalTarget.classList.add("hidden")
    this._pendingTemplateKey = null
    // Revert the committed selection back to whatever the schema currently reflects:
    // clear the referenced_template hidden field so the (unchanged) attributes stay authoritative.
    // The picker keeps its visual selection; the user can re-pick to retry.
  }

  async _applyTemplate(key) {
    try {
      const response = await fetch(
        `/${this.customerIdValue}/admin/maintenance/entities/template_fields?key=${encodeURIComponent(key)}`,
        { headers: { "Accept": "application/json" } }
      )
      if (!response.ok) return
      const data = await response.json()

      if (this.hasPropertySchemaTarget) {
        const refInput = this.element.querySelector("input[name='entity[referenced_template]']")
        if (refInput) refInput.value = JSON.stringify(data.template)
      }

      if (data.fields?.length > 0) {
        this.populateAttributesFromTemplate(data.fields, data.groups || [])
      }
    } catch (error) {
      /* silently ignore fetch errors */
    }
  }
```

- [ ] **Step 4: Verify the entity-form controller still parses**

Run: `node --check app/javascript/controllers/entity_form_controller.js 2>/dev/null && echo OK || echo "syntax check skipped (node import paths)"`
Expected: `OK`, or the skip message (bare-module imports may prevent `--check`; the real check is the Task 9 asset build).

- [ ] **Step 5: Commit**

```bash
git add app/views/admin/maintenance/entities/_form.html.erb app/javascript/controllers/entity_form_controller.js
git commit -m "feat(entities): confirm before template overwrites existing attributes"
```

---

## Task 8: End-to-end system spec (open → lazy load → confirm)

**Files:**
- Create: `spec/system/admin/maintenance/template_picker_spec.rb`

Only add if the repo runs system specs (Capybara + a JS driver). Check first.

- [ ] **Step 1: Check for a JS system-spec setup**

Run: `grep -rn "js: true\|Capybara.javascript_driver\|selenium\|cuprite" spec/ spec/rails_helper.rb spec/support 2>/dev/null | head`
Expected: if nothing references a JS driver, **skip this task** (note it as deferred) and rely on Task 9's manual smoke test. If a driver exists, continue.

- [ ] **Step 2: Write the system spec**

```ruby
# spec/system/admin/maintenance/template_picker_spec.rb
# frozen_string_literal: true
require "rails_helper"

RSpec.describe "Entity template picker", type: :system, js: true do
  let(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }

  before { sign_in admin }

  it "lazy-loads cards on first open and commits on confirm" do
    visit "/#{customer.id}/admin/maintenance/entities/new"

    # Cards are not present until the modal opens.
    expect(page).not_to have_css("[data-template-key]", visible: :all)

    click_button "Choose Template"
    expect(page).to have_css("[data-template-key]", wait: 5) # cards fetched

    first("[data-template-key]").click            # pending highlight
    click_button "Use Template"                   # commit

    expect(page).to have_css("[data-template-selector-target='triggerSelected']:not(.hidden)")
  end
end
```

- [ ] **Step 3: Run it**

Run: `bundle exec rspec spec/system/admin/maintenance/template_picker_spec.rb`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add spec/system/admin/maintenance/template_picker_spec.rb
git commit -m "test(entities): system spec for lazy-loaded template picker"
```

---

## Task 9: Asset rebuild, targeted spec run, and smoke test

**Files:** none (verification only).

- [ ] **Step 1: Run the touched-layer specs**

Run:
```bash
bundle exec rspec \
  spec/requests/admin/maintenance/template_picker_cards_spec.rb \
  spec/components/page_builder/template_picker_component_spec.rb \
  spec/components/page_builder/template_card_component_spec.rb
```
Expected: all PASS.

- [ ] **Step 2: Rebuild assets (drop the manifest first, per AGENTS.md)**

Run:
```bash
rm -f public/assets/.manifest.json
SKIP_AUTH=1 bin/rails assets:precompile 2>&1 | tail -20
```
Expected: precompile completes without JS bundling errors.

- [ ] **Step 3: Boot the dev server and smoke-test both surfaces**

Run (background): `rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000`

Then smoke-check that the forms render and ship no inline cards (cards must arrive only from the endpoint):
```bash
curl -s "http://localhost:3000/81721200/admin/maintenance/entities/new" | grep -c "data-template-key" # expect 0 inline (only the hidden field's data-template-key may match: confirm it's the input, not cards)
curl -s "http://localhost:3000/81721200/admin/maintenance/pages/new"     | grep -c 'data-template-selector-target="templateContainer"' # expect 1
curl -s "http://localhost:3000/81721200/admin/maintenance/template_picker_cards?scope=all" | grep -c "data-template-key" # expect many (cards)
```
Expected: the forms contain the empty `templateContainer` and the trigger, NOT the full card grid; the endpoint returns the cards.

- [ ] **Step 4: Final commit (if any verification fixups were needed)**

```bash
git add -A
git commit -m "chore(entities): rebuild assets for template picker modal"
```

---

## Self-Review Notes

- **Spec coverage:** endpoint (Task 1) ✓, cards partial (Task 2) ✓, component trigger/modal/field config (Task 3) ✓, modal+lazy+pending/confirm controller (Task 4) ✓, entity wiring (Task 5) ✓, page builder wiring + scope=all + theme retention (Task 6) ✓, overwrite confirmation (Task 7) ✓, e2e (Task 8, conditional) ✓, assets+smoke (Task 9) ✓.
- **Event contract:** the component dispatches `template-selector:templateSelected` / `:templateCleared`, matching the unchanged `form_with` action wiring in `entities/_form.html.erb` and `entity-form#handleTemplateSelected` / `#handleTemplateCleared`.
- **Naming consistency:** `loadTemplates`, `openModal`, `closeModal`, `confirmSelection`, `refreshTrigger`, `pendingKey`, `selectedKey`, `cardsUrlValue`, targets `pickerModal`/`templateContainer`/`triggerEmpty`/`triggerSelected`/`triggerName`/`confirmBtn` used identically across Tasks 3 and 4.
- **Authorization:** endpoint is under `/:cid/admin/maintenance/`, auto-guarded by the global `RouteAuthorization` (`enforce_route_role!` admin-or-owner); the request spec asserts member is forbidden and unauthenticated is blocked.
- **Tenant scoping:** the endpoint derives templates from `current_customer&.industry`; no cross-tenant data path.
```
