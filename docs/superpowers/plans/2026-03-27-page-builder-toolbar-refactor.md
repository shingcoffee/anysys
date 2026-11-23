# Page Builder Toolbar Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the page builder top toolbar into a `PageBuilder::ToolbarComponent` ViewComponent and apply a Gutenberg-style visual refresh with icon-only tabs, tighter spacing, and slate color palette.

**Architecture:** Single ViewComponent replaces the inline `<header>` block (lines 27-187) in `app/views/pages/_editor.html.erb`. No Stimulus controller changes — all `data-page-builder-target` and `data-action` attributes are preserved identically. The component receives the page model, customer ID, and optional entity.

**Tech Stack:** Ruby on Rails 8.1, ViewComponent, TailwindCSS, StimulusJS (existing, unchanged)

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `app/components/page_builder/toolbar_component.rb` | Component class with params: page, customer_id, selected_entity |
| Create | `app/components/page_builder/toolbar_component.html.erb` | Toolbar template with Gutenberg-style layout |
| Create | `spec/components/page_builder/toolbar_component_spec.rb` | Component rendering specs |
| Modify | `app/views/pages/_editor.html.erb:27-187` | Replace inline header with component render call |

---

### Task 1: Create the ToolbarComponent Ruby class

**Files:**
- Create: `app/components/page_builder/toolbar_component.rb`

- [ ] **Step 1: Create the component class**

```ruby
# frozen_string_literal: true

module PageBuilder
  class ToolbarComponent < ApplicationComponent
    def initialize(page:, customer_id:, selected_entity: nil)
      @page = page
      @customer_id = customer_id
      @selected_entity = selected_entity
    end

    private

    attr_reader :page, :customer_id, :selected_entity

    def back_path
      helpers.pages_path(customer_id)
    end

    def entity_path
      return nil unless selected_entity
      helpers.entity_path(customer_id, selected_entity)
    end

    def preview_path
      helpers.preview_page_path(customer_id, page)
    end
  end
end
```

- [ ] **Step 2: Verify the file loads without errors**

Run: `bundle exec rails runner "PageBuilder::ToolbarComponent"`
Expected: No error output

- [ ] **Step 3: Commit**

```bash
git add app/components/page_builder/toolbar_component.rb
git commit -m "feat: add PageBuilder::ToolbarComponent class"
```

---

### Task 2: Create the ToolbarComponent template with Gutenberg-style layout

**Files:**
- Create: `app/components/page_builder/toolbar_component.html.erb`

- [ ] **Step 1: Create the template file**

```erb
<header class="bg-white border-b border-slate-200 flex-shrink-0 z-30">
  <div class="flex items-center h-12 px-4">

    <%# Left Section: Navigation & Context %>
    <div class="flex items-center gap-2 min-w-0">
      <%= link_to back_path, class: "flex items-center justify-center w-8 h-8 text-slate-500 hover:text-slate-900 hover:bg-slate-100 rounded-md transition-colors", title: "Back to Pages" do %>
        <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 19.5L8.25 12l7.5-7.5" />
        </svg>
      <% end %>

      <div class="h-4 w-px bg-slate-200"></div>

      <div class="flex items-center gap-1.5 min-w-0">
        <span class="text-sm font-semibold text-slate-900 truncate"><%= page.name %></span>
        <% if selected_entity %>
          <span class="text-slate-300">/</span>
          <a href="<%= entity_path %>" target="_blank"
             class="text-xs text-slate-500 hover:text-indigo-600 truncate transition-colors"><%= selected_entity.name %></a>
        <% end %>
      </div>
    </div>

    <%# Center Section: Icon-Only Tab Navigation %>
    <div class="flex-1 flex items-center justify-center">
      <nav class="flex items-center bg-slate-100 rounded-lg p-0.5 gap-0.5" role="tablist">
        <button type="button" role="tab" aria-selected="false"
                data-action="click->page-builder#switchTab" data-tab="templates"
                data-page-builder-target="tabButton"
                class="relative p-2 rounded-md text-slate-500 hover:text-slate-700 transition-all"
                title="Templates">
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M4 5a1 1 0 011-1h4a1 1 0 011 1v7a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM14 5a1 1 0 011-1h4a1 1 0 011 1v7a1 1 0 01-1 1h-4a1 1 0 01-1-1V5zM4 16a1 1 0 011-1h4a1 1 0 011 1v3a1 1 0 01-1 1H5a1 1 0 01-1-1v-3zM14 16a1 1 0 011-1h4a1 1 0 011 1v3a1 1 0 01-1 1h-4a1 1 0 01-1-1v-3z" />
          </svg>
        </button>
        <button type="button" role="tab" aria-selected="false"
                data-action="click->page-builder#switchTab" data-tab="theme"
                data-page-builder-target="tabButton"
                class="relative p-2 rounded-md text-slate-500 hover:text-slate-700 transition-all"
                title="Theme">
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M4.098 19.902a3.75 3.75 0 005.304 0l6.401-6.402M6.75 21A3.75 3.75 0 013 17.25V4.125C3 3.504 3.504 3 4.125 3h5.25c.621 0 1.125.504 1.125 1.125V11l-3.75 3.75M6.75 21l3.75-3.75M6.75 21h7.5" />
          </svg>
        </button>
        <button type="button" role="tab" aria-selected="false"
                data-action="click->page-builder#switchTab" data-tab="rules"
                data-page-builder-target="tabButton"
                class="relative p-2 rounded-md text-slate-500 hover:text-slate-700 transition-all"
                title="Rules">
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4" />
          </svg>
        </button>
        <button type="button" role="tab" aria-selected="false"
                data-action="click->page-builder#switchTab" data-tab="calculations"
                data-page-builder-target="tabButton"
                class="relative p-2 rounded-md text-slate-500 hover:text-slate-700 transition-all"
                title="Calculations">
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M9 7h6m0 10v-3m-3 3h.01M9 17h.01M9 14h.01M12 14h.01M15 11h.01M12 11h.01M9 11h.01M7 21h10a2 2 0 002-2V5a2 2 0 00-2-2H7a2 2 0 00-2 2v14a2 2 0 002 2z" />
          </svg>
        </button>
        <button type="button" role="tab" aria-selected="false"
                data-action="click->page-builder#switchTab" data-tab="settings"
                data-page-builder-target="tabButton"
                class="relative p-2 rounded-md text-slate-500 hover:text-slate-700 transition-all"
                title="Settings">
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.324.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 011.37.49l1.296 2.247a1.125 1.125 0 01-.26 1.431l-1.003.827c-.293.24-.438.613-.431.992a6.759 6.759 0 010 .255c-.007.378.138.75.43.99l1.005.828c.424.35.534.954.26 1.43l-1.298 2.247a1.125 1.125 0 01-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.57 6.57 0 01-.22.128c-.331.183-.581.495-.644.869l-.213 1.28c-.09.543-.56.941-1.11.941h-2.594c-.55 0-1.02-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 01-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 01-1.369-.49l-1.297-2.247a1.125 1.125 0 01.26-1.431l1.004-.827c.292-.24.437-.613.43-.992a6.932 6.932 0 010-.255c.007-.378-.138-.75-.43-.99l-1.004-.828a1.125 1.125 0 01-.26-1.43l1.297-2.247a1.125 1.125 0 011.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.087.22-.128.332-.183.582-.495.644-.869l.214-1.281z" />
            <path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
          </svg>
        </button>
      </nav>
    </div>

    <%# Right Section: Actions %>
    <div class="flex items-center gap-1.5">
      <%# Viewport Toggle %>
      <div class="flex items-center bg-slate-100 rounded-md p-0.5">
        <button type="button" data-action="click->page-builder#setViewport" data-viewport="desktop"
                data-page-builder-target="viewportBtn"
                class="p-1.5 rounded text-slate-400 hover:text-slate-700 transition-colors" title="Desktop">
          <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
          </svg>
        </button>
        <button type="button" data-action="click->page-builder#setViewport" data-viewport="tablet"
                data-page-builder-target="viewportBtn"
                class="p-1.5 rounded text-slate-400 hover:text-slate-700 transition-colors" title="Tablet">
          <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 18h.01M7 21h10a2 2 0 002-2V5a2 2 0 00-2-2H7a2 2 0 00-2 2v14a2 2 0 002 2z" />
          </svg>
        </button>
        <button type="button" data-action="click->page-builder#setViewport" data-viewport="mobile"
                data-page-builder-target="viewportBtn"
                class="p-1.5 rounded text-slate-400 hover:text-slate-700 transition-colors" title="Mobile">
          <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 18h.01M8 21h8a2 2 0 002-2V5a2 2 0 00-2-2H8a2 2 0 00-2 2v14a2 2 0 002 2z" />
          </svg>
        </button>
      </div>

      <div class="h-4 w-px bg-slate-200"></div>

      <%# Undo/Redo %>
      <div class="flex items-center gap-0.5">
        <button type="button"
                data-action="click->page-builder#undo"
                data-page-builder-target="undoBtn"
                disabled
                class="p-1.5 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded-md disabled:opacity-30 disabled:cursor-not-allowed disabled:hover:bg-transparent transition-colors"
                title="Undo">
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M3 10h10a8 8 0 018 8v2M3 10l6 6m-6-6l6-6" />
          </svg>
        </button>
        <button type="button"
                data-action="click->page-builder#redo"
                data-page-builder-target="redoBtn"
                disabled
                class="p-1.5 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded-md disabled:opacity-30 disabled:cursor-not-allowed disabled:hover:bg-transparent transition-colors"
                title="Redo">
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M21 10H11a8 8 0 00-8 8v2m18-10l-6-6m6 6l-6 6" />
          </svg>
        </button>
      </div>

      <div class="h-4 w-px bg-slate-200"></div>

      <%# Preview (hidden form + icon-only button) %>
      <form method="post" action="<%= preview_path %>" target="_blank"
            data-page-builder-target="previewForm" class="hidden">
        <input type="hidden" name="authenticity_token" value="<%= helpers.form_authenticity_token %>">
        <input type="hidden" name="page[configuration]" data-page-builder-target="previewConfigInput">
      </form>

      <button type="button"
              data-action="click->page-builder#preview"
              class="p-1.5 text-slate-500 hover:text-slate-900 hover:bg-slate-100 rounded-md transition-colors"
              title="Preview">
        <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M13.5 6H5.25A2.25 2.25 0 003 8.25v10.5A2.25 2.25 0 005.25 21h10.5A2.25 2.25 0 0018 18.75V10.5m-10.5 6L21 3m0 0h-5.25M21 3v5.25" />
        </svg>
      </button>

      <%# Save %>
      <button type="button"
              data-action="click->page-builder#save"
              data-page-builder-target="saveBtn"
              class="inline-flex items-center gap-1.5 px-4 py-1.5 text-xs font-semibold text-white bg-indigo-600 hover:bg-indigo-700 active:bg-indigo-800 rounded-md transition-colors focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-1">
        <span data-page-builder-target="saveText">Save</span>
      </button>
    </div>
  </div>
</header>
```

- [ ] **Step 2: Commit**

```bash
git add app/components/page_builder/toolbar_component.html.erb
git commit -m "feat: add ToolbarComponent template with Gutenberg-style layout"
```

---

### Task 3: Write component specs

**Files:**
- Create: `spec/components/page_builder/toolbar_component_spec.rb`

- [ ] **Step 1: Write the spec file**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageBuilder::ToolbarComponent, type: :component do
  let(:customer_id) { 96546124 }
  let(:page) { create(:page, name: "Test Page") }
  let(:entity) { create(:entity, name: "Order") }

  describe "basic rendering" do
    it "renders the toolbar header" do
      render_inline(described_class.new(page: page, customer_id: customer_id))

      expect(rendered_content).to have_css("header")
    end

    it "displays the page name" do
      render_inline(described_class.new(page: page, customer_id: customer_id))

      expect(rendered_content).to have_text("Test Page")
    end

    it "renders back link to pages index" do
      render_inline(described_class.new(page: page, customer_id: customer_id))

      expect(rendered_content).to have_link(href: "/#{customer_id}/pages")
    end
  end

  describe "entity breadcrumb" do
    it "shows entity name when entity is present" do
      render_inline(described_class.new(page: page, customer_id: customer_id, selected_entity: entity))

      expect(rendered_content).to have_text("Order")
      expect(rendered_content).to have_link("Order", href: "/#{customer_id}/entities/#{entity.id}")
    end

    it "hides entity breadcrumb when no entity" do
      render_inline(described_class.new(page: page, customer_id: customer_id, selected_entity: nil))

      expect(rendered_content).not_to have_text("Order")
    end
  end

  describe "tab buttons" do
    it "renders all 5 icon-only tab buttons" do
      render_inline(described_class.new(page: page, customer_id: customer_id))

      expect(rendered_content).to have_css("[data-page-builder-target='tabButton']", count: 5)
    end

    it "renders tabs with correct data-tab attributes" do
      render_inline(described_class.new(page: page, customer_id: customer_id))

      %w[templates theme rules calculations settings].each do |tab|
        expect(rendered_content).to have_css("[data-tab='#{tab}']")
      end
    end

    it "renders tabs with title tooltips" do
      render_inline(described_class.new(page: page, customer_id: customer_id))

      %w[Templates Theme Rules Calculations Settings].each do |title|
        expect(rendered_content).to have_css("[title='#{title}']")
      end
    end

    it "does not render text labels in tab buttons" do
      render_inline(described_class.new(page: page, customer_id: customer_id))

      %w[Templates Theme Rules Calculations Settings].each do |label|
        expect(rendered_content).not_to have_css("[data-page-builder-target='tabButton']", text: label)
      end
    end
  end

  describe "viewport toggle" do
    it "renders desktop, tablet, and mobile buttons" do
      render_inline(described_class.new(page: page, customer_id: customer_id))

      %w[desktop tablet mobile].each do |viewport|
        expect(rendered_content).to have_css("[data-viewport='#{viewport}']")
      end
    end
  end

  describe "action buttons" do
    it "renders undo and redo buttons" do
      render_inline(described_class.new(page: page, customer_id: customer_id))

      expect(rendered_content).to have_css("[data-page-builder-target='undoBtn']")
      expect(rendered_content).to have_css("[data-page-builder-target='redoBtn']")
    end

    it "renders undo/redo as disabled by default" do
      render_inline(described_class.new(page: page, customer_id: customer_id))

      expect(rendered_content).to have_css("[data-page-builder-target='undoBtn'][disabled]")
      expect(rendered_content).to have_css("[data-page-builder-target='redoBtn'][disabled]")
    end

    it "renders preview button with tooltip" do
      render_inline(described_class.new(page: page, customer_id: customer_id))

      expect(rendered_content).to have_css("button[title='Preview']")
    end

    it "renders hidden preview form" do
      render_inline(described_class.new(page: page, customer_id: customer_id))

      expect(rendered_content).to have_css("form[data-page-builder-target='previewForm'].hidden")
    end

    it "renders save button" do
      render_inline(described_class.new(page: page, customer_id: customer_id))

      expect(rendered_content).to have_css("[data-page-builder-target='saveBtn']", text: "Save")
    end
  end

  describe "slate color palette" do
    it "uses slate colors instead of gray" do
      render_inline(described_class.new(page: page, customer_id: customer_id))

      expect(rendered_content).to have_css("header.border-slate-200")
      expect(rendered_content).not_to have_css(".border-gray-200", visible: :all)
    end
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec rspec spec/components/page_builder/toolbar_component_spec.rb --format documentation`
Expected: All tests pass (the component and template already exist from Tasks 1-2)

- [ ] **Step 3: Commit**

```bash
git add spec/components/page_builder/toolbar_component_spec.rb
git commit -m "test: add specs for PageBuilder::ToolbarComponent"
```

---

### Task 4: Replace inline toolbar in _editor.html.erb with component render

**Files:**
- Modify: `app/views/pages/_editor.html.erb:27-187`

- [ ] **Step 1: Replace the inline header block**

In `app/views/pages/_editor.html.erb`, replace everything from line 27 (`<%# ===== TOP TOOLBAR ===== %>`) through line 187 (`</header>`) with:

```erb
  <%# ===== TOP TOOLBAR ===== %>
  <%= render PageBuilder::ToolbarComponent.new(
    page: @page,
    customer_id: current_customer_id,
    selected_entity: selected_entity
  ) %>
```

The lines to remove start with:
```erb
  <%# ===== TOP TOOLBAR ===== %>
  <header class="bg-white border-b border-gray-200 flex-shrink-0 z-30">
```

And end with:
```erb
      </div>
    </div>
  </header>
```

- [ ] **Step 2: Run the component spec to confirm nothing broke**

Run: `bundle exec rspec spec/components/page_builder/toolbar_component_spec.rb --format documentation`
Expected: All tests pass

- [ ] **Step 3: Run the full page builder specs to confirm no regressions**

Run: `bundle exec rspec spec/components/page_builder/ --format documentation`
Expected: All tests pass

- [ ] **Step 4: Verify the page loads in the browser**

Open: `http://localhost:3000/96546124/pages/32/edit`
Verify:
- Toolbar renders with the new compact layout
- Tab buttons are icon-only with tooltips on hover
- Viewport toggle works (desktop/tablet/mobile)
- Undo/redo buttons render disabled
- Preview button opens preview in a new tab
- Save button persists changes
- Entity breadcrumb link works (if entity is present)
- Back arrow navigates to pages index
- Colors are slate-based (not gray)

- [ ] **Step 5: Commit**

```bash
git add app/views/pages/_editor.html.erb
git commit -m "refactor: extract toolbar into PageBuilder::ToolbarComponent"
```

---

### Task 5: Update tab panel overlay positioning

**Files:**
- Modify: `app/views/pages/_editor.html.erb`

The tab panel overlays (Templates, Settings, Rules, Calculations, Theme) use `fixed top-16` positioning which assumes the old toolbar height contributed `4rem` to the offset. Since the toolbar height is unchanged at `h-12` (3rem), check whether `top-16` needs to become `top-12`.

- [ ] **Step 1: Check the tab panel overlay positioning in the browser**

Open: `http://localhost:3000/96546124/pages/32/edit`
Click each tab icon and verify the overlay panel aligns flush below the toolbar without a gap or overlap.

If the panels use `top-16` (64px) but the toolbar is `h-12` (48px), the overlays sit 16px too low. In that case, update `top-16` to `top-12` in each tab panel overlay div.

If they already align correctly (because they account for the toolbar + page-tabs sticky header), no change is needed — skip to Step 3.

- [ ] **Step 2: Fix overlay top offset if needed**

In `app/views/pages/_editor.html.erb`, search for `class="tab-panel hidden fixed top-16` and replace `top-16` with `top-12` in all 5 occurrences:

- Templates tab panel
- Settings tab panel
- Rules tab panel
- Calculations tab panel
- Theme tab panel

- [ ] **Step 3: Commit if changes were made**

```bash
git add app/views/pages/_editor.html.erb
git commit -m "fix: adjust tab panel overlay positioning for toolbar height"
```
