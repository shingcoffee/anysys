# Page Builder Phase 1: Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework the property panel into a tabbed contextual editor, add inline editing, copy/paste/duplicate, improved drag-and-drop feedback, multi-select bulk operations, and field dependency visualization.

**Architecture:** Phase 1 extends the existing manager-based architecture. The main `page_builder_controller.js` remains a thin orchestrator delegating to managers. Two new managers (`inline_edit_manager.js`, `clipboard_manager.js`) are added alongside existing ones. Four new ViewComponents provide server-rendered UI shells. The property panel ERB is restructured from a flat list into tabbed sections.

**Tech Stack:** Rails 8, StimulusJS, TailwindCSS, ViewComponent, RSpec

**Spec:** `docs/superpowers/specs/2026-03-23-page-builder-improvements-design.md` (Phase 1 sections 1.1-1.6)

---

## File Map

### New Files

| File | Purpose |
|------|---------|
| `app/components/page_builder/property_panel/tabbed_panel_component.rb` | ViewComponent: tabbed property panel shell |
| `app/components/page_builder/property_panel/tabbed_panel_component.html.erb` | Template for tabbed panel |
| `app/components/page_builder/floating_action_bar_component.rb` | ViewComponent: multi-select action bar |
| `app/components/page_builder/floating_action_bar_component.html.erb` | Template for floating action bar |
| `app/components/page_builder/field_action_bar_component.rb` | ViewComponent: per-field hover action bar |
| `app/components/page_builder/field_action_bar_component.html.erb` | Template for field action bar |
| `app/components/page_builder/dependency_badge_component.rb` | ViewComponent: rule indicator badge |
| `app/components/page_builder/dependency_badge_component.html.erb` | Template for dependency badge |
| `app/javascript/controllers/page_builder/inline_edit_manager.js` | Manages contenteditable lifecycle |
| `app/javascript/controllers/page_builder/clipboard_manager.js` | Copy/cut/paste with in-memory clipboard |
| `spec/components/page_builder/property_panel/tabbed_panel_component_spec.rb` | Spec for tabbed panel |
| `spec/components/page_builder/floating_action_bar_component_spec.rb` | Spec for floating action bar |
| `spec/components/page_builder/field_action_bar_component_spec.rb` | Spec for field action bar |
| `spec/components/page_builder/dependency_badge_component_spec.rb` | Spec for dependency badge |

### Modified Files

| File | Lines | Changes |
|------|-------|---------|
| `app/views/pages/_property_panel.html.erb` | 808 lines | Restructure into tabbed layout (Content/Layout/Validation/Advanced for data fields; Content/Style for layout elements) |
| `app/javascript/controllers/page_builder/property_manager.js` | 777 lines | Rework `populatePropertyPanel()` and `toggleLayoutSections()` for tabbed structure; add tab switching |
| `app/javascript/controllers/page_builder/field_manager.js` | 1202 lines | Update `createFieldCard()` to include inline-edit data attributes and dependency badges; update card action buttons |
| `app/javascript/controllers/page_builder/field_manager/layout_cards.js` | ~388 lines | Update layout card HTML to support inline editing and action bar |
| `app/javascript/controllers/page_builder/drag_drop_manager.js` | 434 lines | Improve drop indicators, add placeholder, animations, better column zones |
| `app/javascript/controllers/page_builder/selection_manager.js` | 409 lines | Add bulk width, bulk duplicate, bulk delete with confirmation, integrate floating action bar |
| `app/javascript/controllers/page_builder/keyboard_manager.js` | 183 lines | Add Ctrl+C/V/X/D shortcuts, delegate to clipboard manager |
| `app/javascript/controllers/page_builder_controller.js` | ~410 lines | Import new managers, add delegation methods, add new targets |

---

## Task 1: Tabbed Property Panel — ViewComponent Shell

**Files:**
- Create: `app/components/page_builder/property_panel/tabbed_panel_component.rb`
- Create: `app/components/page_builder/property_panel/tabbed_panel_component.html.erb`
- Create: `spec/components/page_builder/property_panel/tabbed_panel_component_spec.rb`

This component renders the tab bar and content containers. It accepts a `field_category` parameter (`:data`, `:layout`, `:columns`) that determines which tabs to show. Uses ViewComponent slots for tab content injection.

- [ ] **Step 1: Write the component spec**

```ruby
# spec/components/page_builder/property_panel/tabbed_panel_component_spec.rb
require "rails_helper"

RSpec.describe PageBuilder::PropertyPanel::TabbedPanelComponent, type: :component do
  describe "data field tabs" do
    it "renders Content, Layout, Validation, Advanced tabs" do
      render_inline(described_class.new(field_category: :data))

      expect(page).to have_css("[data-tab='content']", text: "Content")
      expect(page).to have_css("[data-tab='layout']", text: "Layout")
      expect(page).to have_css("[data-tab='validation']", text: "Validation")
      expect(page).to have_css("[data-tab='advanced']", text: "Advanced")
    end

    it "shows content tab as active by default" do
      render_inline(described_class.new(field_category: :data))

      expect(page).to have_css("[data-tab='content'].border-indigo-500")
    end
  end

  describe "layout element tabs" do
    it "renders Content and Style tabs only" do
      render_inline(described_class.new(field_category: :layout))

      expect(page).to have_css("[data-tab='content']", text: "Content")
      expect(page).to have_css("[data-tab='style']", text: "Style")
      expect(page).not_to have_css("[data-tab='validation']")
      expect(page).not_to have_css("[data-tab='advanced']")
    end
  end

  describe "column layout tabs" do
    it "renders Structure and Style tabs" do
      render_inline(described_class.new(field_category: :columns))

      expect(page).to have_css("[data-tab='structure']", text: "Structure")
      expect(page).to have_css("[data-tab='style']", text: "Style")
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```bash
bundle exec rspec spec/components/page_builder/property_panel/tabbed_panel_component_spec.rb -v
```
Expected: FAIL — uninitialized constant `PageBuilder::PropertyPanel::TabbedPanelComponent`

- [ ] **Step 3: Write the component Ruby class**

```ruby
# app/components/page_builder/property_panel/tabbed_panel_component.rb
module PageBuilder
  module PropertyPanel
    class TabbedPanelComponent < ViewComponent::Base
      TABS = {
        data: [
          { key: "content", label: "Content" },
          { key: "layout", label: "Layout" },
          { key: "validation", label: "Validation" },
          { key: "advanced", label: "Advanced" }
        ],
        layout: [
          { key: "content", label: "Content" },
          { key: "style", label: "Style" }
        ],
        columns: [
          { key: "structure", label: "Structure" },
          { key: "style", label: "Style" }
        ]
      }.freeze

      renders_many :tab_contents, ->(tab_key:) {
        TabContentComponent.new(tab_key: tab_key)
      }

      def initialize(field_category:)
        @field_category = field_category.to_sym
        @tabs = TABS[@field_category] || TABS[:data]
      end

      attr_reader :tabs, :field_category

      # Inner component for tab content wrapper
      class TabContentComponent < ViewComponent::Base
        def initialize(tab_key:)
          @tab_key = tab_key
        end

        def call
          content_tag :div, content,
            data: { property_tab_content: @tab_key },
            class: "p-3 space-y-3"
        end
      end
    end
  end
end
```

- [ ] **Step 4: Write the component template**

```erb
<%# app/components/page_builder/property_panel/tabbed_panel_component.html.erb %>
<div class="property-tabs border-b border-gray-200" data-page-builder-target="propertyTabs">
  <nav class="flex -mb-px" role="tablist">
    <% tabs.each_with_index do |tab, idx| %>
      <button type="button"
              role="tab"
              data-tab="<%= tab[:key] %>"
              data-action="click->page-builder#switchPropertyTab"
              class="flex-1 px-2 py-2 text-xs font-medium text-center border-b-2 transition-colors
                     <%= idx == 0 ? 'border-indigo-500 text-indigo-600' : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300' %>">
        <%= tab[:label] %>
      </button>
    <% end %>
  </nav>
</div>

<% tab_contents.each_with_index do |tab_content, idx| %>
  <% if idx > 0 %>
    <script>document.currentScript.previousElementSibling.classList.add("hidden")</script>
  <% end %>
  <%= tab_content %>
<% end %>
```

Note: The tab content containers are rendered via slots. The JavaScript in `property_manager.js` handles show/hide via `data-property-tab-content` attributes. The first tab is visible by default; subsequent tabs start hidden.

- [ ] **Step 5: Run spec to verify it passes**

```bash
bundle exec rspec spec/components/page_builder/property_panel/tabbed_panel_component_spec.rb -v
```
Expected: PASS (all 4 examples)

- [ ] **Step 6: Commit**

```bash
git add app/components/page_builder/property_panel/ spec/components/page_builder/property_panel/
git commit -m "feat(page-builder): add TabbedPanelComponent for contextual property tabs"
```

---

## Task 2: Restructure Property Panel ERB into Tabs

**Files:**
- Modify: `app/views/pages/_property_panel.html.erb`
- Modify: `app/javascript/controllers/page_builder/property_manager.js`
- Modify: `app/javascript/controllers/page_builder_controller.js` (add targets + delegation)

This is the largest task — restructuring the 808-line property panel from flat sections into tabbed content areas. The existing inputs remain; they're reorganized into tab containers.

- [ ] **Step 1: Add new targets to page_builder_controller.js**

Add to the `static targets` array (line 24-96):

```javascript
// Property tab targets (add after line 42 "floatingPanel" group)
"propertyTabs", "propertyTabContent",
```

Add delegation method (after line 336):

```javascript
// Property tab switching
switchPropertyTab(event) { this.propertyManager.switchPropertyTab(event) }
```

- [ ] **Step 2: Add switchPropertyTab to property_manager.js**

Add this method to the PropertyManager class:

```javascript
switchPropertyTab(event) {
  const tabKey = event.currentTarget.dataset.tab
  if (!tabKey) return

  // Update tab button styling
  const tabBar = event.currentTarget.closest("[data-page-builder-target='propertyTabs']")
  if (tabBar) {
    tabBar.querySelectorAll("[data-tab]").forEach(btn => {
      btn.classList.remove("border-indigo-500", "text-indigo-600")
      btn.classList.add("border-transparent", "text-gray-500")
    })
    event.currentTarget.classList.remove("border-transparent", "text-gray-500")
    event.currentTarget.classList.add("border-indigo-500", "text-indigo-600")
  }

  // Show/hide tab content panels
  const panel = this.c.floatingPanelTarget
  panel.querySelectorAll("[data-property-tab-content]").forEach(el => {
    el.classList.toggle("hidden", el.dataset.propertyTabContent !== tabKey)
  })
}
```

- [ ] **Step 3: Restructure _property_panel.html.erb — Header**

Replace the existing panel header (approximately lines 8-29) with a new header that includes field type icon, editable label, type badge, and an actions dropdown menu (...) containing Duplicate, Copy, and Delete:

```erb
<%# Panel header with actions dropdown %>
<div class="flex items-center justify-between p-3 border-b border-gray-200">
  <div class="flex items-center gap-2 min-w-0 flex-1">
    <div class="w-7 h-7 rounded-lg flex items-center justify-center flex-shrink-0"
         data-page-builder-target="fieldIcon">
    </div>
    <div class="min-w-0 flex-1">
      <span class="text-sm font-semibold text-gray-900 truncate block"
            data-page-builder-target="fieldName"></span>
      <span class="text-xs text-gray-500"
            data-page-builder-target="fieldTypeLabel"></span>
    </div>
  </div>
  <div class="flex items-center gap-1">
    <%# Actions dropdown %>
    <div class="relative" data-controller="dropdown">
      <button type="button" class="p-1 text-gray-400 hover:text-gray-600 rounded"
              data-action="click->dropdown#toggle">
        <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
          <path d="M10 6a2 2 0 110-4 2 2 0 010 4zm0 6a2 2 0 110-4 2 2 0 010 4zm0 6a2 2 0 110-4 2 2 0 010 4z"/>
        </svg>
      </button>
      <div class="hidden absolute right-0 mt-1 w-36 bg-white rounded-lg shadow-lg border border-gray-200 py-1 z-50"
           data-dropdown-target="menu">
        <button type="button" class="w-full px-3 py-1.5 text-left text-xs text-gray-700 hover:bg-gray-50"
                data-action="click->page-builder#duplicateSelectedField">Duplicate</button>
        <button type="button" class="w-full px-3 py-1.5 text-left text-xs text-gray-700 hover:bg-gray-50"
                data-action="click->page-builder#copyField">Copy</button>
        <hr class="my-1 border-gray-100">
        <button type="button" class="w-full px-3 py-1.5 text-left text-xs text-red-600 hover:bg-red-50"
                data-action="click->page-builder#deleteSelectedField">Delete</button>
      </div>
    </div>
    <%# Close button %>
    <button type="button" class="p-1 text-gray-400 hover:text-gray-600 rounded"
            data-action="click->page-builder#deselectField">
      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
      </svg>
    </button>
  </div>
</div>
```

- [ ] **Step 4: Restructure _property_panel.html.erb — Tab bar and content sections**

After the header, add the tab bar and reorganize the existing inputs into tab content containers. The key restructuring:

**Data field tabs:**
- `data-property-tab-content="content"` — Contains: Label, Placeholder, Help Text, Default Value, Options Editor (for select/radio/checkbox)
- `data-property-tab-content="layout"` — Contains: Width picker, field spacing controls, alignment
- `data-property-tab-content="validation"` — Contains: Required checkbox, all type-specific constraints (moved from Type Settings section)
- `data-property-tab-content="advanced"` — Contains: Property slug, autocomplete, conditional visibility summary. The conditional visibility section shows a plain-English summary of rules affecting this field (e.g., "Show this field when [Status] equals [Active]") and an "Edit Rules" link that opens the Rules tab panel with this field pre-selected. This is populated by `_populateAdvancedTab()` which reads `this.c.configuration.rules` and filters for rules referencing the current field.

**Layout element tabs:**
- `data-property-tab-content="content"` — Contains: Content textarea, heading level, spacer height, alert variant, image URL, alt text, attribution, button URL/variant/size, alignment, video URL, list style, code language, progress value/color, column layout
- `data-property-tab-content="style"` — Contains: Width picker, spacing, alignment

The existing inputs keep their `data-page-builder-target` attributes and `data-action` bindings — they just move into different parent `<div>` containers.

- [ ] **Step 5: Update populatePropertyPanel() in property_manager.js**

Modify the `populatePropertyPanel(field)` method to:
1. Determine field category: `layout` if `field.property_type === "layout"`, `columns` if `field.field_type === "columns"`, otherwise `data`
2. Show/hide the correct tab bar and content sections based on category
3. Reset to first tab when switching between fields
4. Move existing population logic into the correct tab containers

```javascript
populatePropertyPanel(field) {
  // Determine field category
  const isLayout = field.property_type === "layout"
  const isColumns = field.field_type === "columns"
  const category = isColumns ? "columns" : (isLayout ? "layout" : "data")

  // Show correct tab set, hide others
  this._showTabsForCategory(category)

  // Reset to first tab
  this._activateFirstTab()

  // ... existing population logic stays, but targets are in new tab containers
  this._populateHeader(field)
  this._populateContentTab(field, category)
  if (category === "data") {
    this._populateValidationTab(field)
    this._populateAdvancedTab(field)
  }
  this._populateLayoutTab(field, category)
}
```

- [ ] **Step 5b: Implement _populateAdvancedTab() for conditional rules summary**

Add this method to `property_manager.js`. It reads the rules configuration, filters for rules affecting the current field, and renders a plain-English summary in the Advanced tab:

```javascript
_populateAdvancedTab(field) {
  const rulesContainer = this.c.floatingPanelTarget.querySelector("[data-advanced-rules-summary]")
  if (!rulesContainer) return

  const rules = this.c.configuration.rules || []
  const summaries = []

  rules.forEach(rule => {
    if (!rule.enabled) return

    // Check if this field is an action target (field has conditions applied)
    const isTarget = rule.actions?.some(a => a.field_id === field.id)
    if (!isTarget) return

    // Build plain-English condition description
    const conditionParts = (rule.conditions || []).flatMap(group => {
      return (group.items || []).map(item => {
        const sourceField = this.c.allFields.find(f => f.id === item.field_id)
        const fieldLabel = sourceField?.label || item.field_id
        const operator = this._operatorLabel(item.operator)
        const value = item.value || '""'
        return `[${fieldLabel}] ${operator} [${value}]`
      })
    })

    if (conditionParts.length > 0) {
      const actionType = rule.actions?.find(a => a.field_id === field.id)?.type || "show"
      const verb = actionType === "hide" ? "Hide" : "Show"
      summaries.push(`${verb} this field when ${conditionParts.join(" and ")}`)
    }
  })

  if (summaries.length === 0) {
    rulesContainer.innerHTML = '<p class="text-xs text-gray-400 italic">No conditional rules</p>'
  } else {
    rulesContainer.innerHTML = summaries.map(s =>
      `<p class="text-xs text-gray-600 mb-1">${s}</p>`
    ).join("") +
    `<button type="button"
             class="text-xs text-indigo-600 hover:text-indigo-800 font-medium mt-1"
             data-action="click->page-builder#openRulesForField"
             data-field-id="${field.id}">
       Edit Rules
     </button>`
  }
}

_operatorLabel(op) {
  const labels = {
    equals: "equals", not_equals: "does not equal",
    contains: "contains", not_contains: "does not contain",
    greater_than: ">", less_than: "<",
    is_empty: "is empty", is_not_empty: "is not empty"
  }
  return labels[op] || op
}
```

Add the `openRulesForField` delegation in `page_builder_controller.js`:

```javascript
openRulesForField(event) {
  const fieldId = event.currentTarget.dataset.fieldId
  this.tabManager.switchTab({ currentTarget: this.tabButtonTargets.find(t => t.dataset.tab === "rules") })
  // Pre-select the field's rule in the rules panel if it exists
}
```

In the Advanced tab HTML section of `_property_panel.html.erb`, add:

```erb
<%# Conditional Rules Summary %>
<div class="pt-2 border-t border-gray-100 mt-2">
  <label class="block text-xs font-medium text-gray-500 mb-1">Conditional Rules</label>
  <div data-advanced-rules-summary></div>
</div>
```

- [ ] **Step 6: Remove the Delete button from the panel footer**

The Delete action now lives in the header dropdown (Step 3). Remove the footer delete button section (approximately lines 797-806 of the original).

- [ ] **Step 7: Manually test in browser**

Load the page builder at `/96546124/pages/32/edit`. Verify:
- Click a text field — see 4 tabs (Content, Layout, Validation, Advanced)
- Click a heading layout — see 2 tabs (Content, Style)
- Click a columns element — see 2 tabs (Structure, Style)
- Tab switching shows/hides correct content
- All existing property inputs still work (label, placeholder, etc.)
- Header shows actions dropdown with Duplicate, Copy, Delete

- [ ] **Step 8: Commit**

```bash
git add app/views/pages/_property_panel.html.erb app/javascript/controllers/page_builder/property_manager.js app/javascript/controllers/page_builder_controller.js
git commit -m "feat(page-builder): restructure property panel into tabbed layout

Data fields get Content/Layout/Validation/Advanced tabs.
Layout elements get Content/Style tabs.
Column layouts get Structure/Style tabs.
Delete button moves to header dropdown menu."
```

---

## Task 3: Field Action Bar Component (Hover Actions)

**Files:**
- Create: `app/components/page_builder/field_action_bar_component.rb`
- Create: `app/components/page_builder/field_action_bar_component.html.erb`
- Create: `spec/components/page_builder/field_action_bar_component_spec.rb`
- Modify: `app/javascript/controllers/page_builder/field_manager.js` (update card action buttons)
- Modify: `app/javascript/controllers/page_builder/field_manager/layout_cards.js` (update layout card actions)

Currently, field cards show an X (delete) button and drag handle on hover. Replace with a proper action bar: Duplicate + Delete icons.

- [ ] **Step 1: Write the component spec**

```ruby
# spec/components/page_builder/field_action_bar_component_spec.rb
require "rails_helper"

RSpec.describe PageBuilder::FieldActionBarComponent, type: :component do
  it "renders duplicate and delete buttons" do
    render_inline(described_class.new(field_id: "field_123"))

    expect(page).to have_css("button[data-action*='duplicateFieldFromCard']")
    expect(page).to have_css("button[data-action*='removeFieldFromCard']")
  end

  it "includes the field ID as data attribute" do
    render_inline(described_class.new(field_id: "field_abc"))

    expect(page).to have_css("[data-field-id='field_abc']", count: 2)
  end

  it "shows on hover via group-hover classes" do
    render_inline(described_class.new(field_id: "field_123"))

    expect(page).to have_css(".opacity-0.group-hover\\:opacity-100")
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```bash
bundle exec rspec spec/components/page_builder/field_action_bar_component_spec.rb -v
```

- [ ] **Step 3: Write the component**

```ruby
# app/components/page_builder/field_action_bar_component.rb
class PageBuilder::FieldActionBarComponent < ViewComponent::Base
  def initialize(field_id:)
    @field_id = field_id
  end

  attr_reader :field_id
end
```

```erb
<%# app/components/page_builder/field_action_bar_component.html.erb %>
<div class="flex items-center gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity">
  <button type="button"
          class="p-0.5 text-gray-400 hover:text-indigo-500 transition-colors"
          title="Duplicate"
          data-action="click->page-builder#duplicateFieldFromCard"
          data-field-id="<%= field_id %>">
    <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/>
    </svg>
  </button>
  <button type="button"
          class="p-0.5 text-gray-400 hover:text-red-500 transition-colors"
          title="Delete"
          data-action="click->page-builder#removeFieldFromCard"
          data-field-id="<%= field_id %>">
    <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
    </svg>
  </button>
  <button type="button"
          class="p-0.5 text-gray-400 hover:text-gray-600 cursor-grab field-drag-handle">
    <svg class="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 20 20">
      <path d="M7 2a2 2 0 1 0 0 4 2 2 0 0 0 0-4zm6 0a2 2 0 1 0 0 4 2 2 0 0 0 0-4zM7 8a2 2 0 1 0 0 4 2 2 0 0 0 0-4zm6 0a2 2 0 1 0 0 4 2 2 0 0 0 0-4zM7 14a2 2 0 1 0 0 4 2 2 0 0 0 0-4zm6 0a2 2 0 1 0 0 4 2 2 0 0 0 0-4z"/>
    </svg>
  </button>
</div>
```

- [ ] **Step 4: Run spec to verify it passes**

```bash
bundle exec rspec spec/components/page_builder/field_action_bar_component_spec.rb -v
```

- [ ] **Step 5: Update field card action buttons in field_manager.js and layout_cards.js**

In `field_manager/layout_cards.js`, update the `cardActionButtons()` function (~line 369-386) to generate HTML matching the new action bar structure (Duplicate + Delete + Drag handle instead of just Delete + Drag handle).

Add `duplicateFieldFromCard` delegation in `page_builder_controller.js`:

```javascript
duplicateFieldFromCard(event) { this.fieldManager.duplicateFieldFromCard(event) }
```

Add `duplicateFieldFromCard(event)` to `field_manager.js`:

```javascript
duplicateFieldFromCard(event) {
  event.stopPropagation()
  const fieldId = event.currentTarget.dataset.fieldId
  const field = this.c.currentPageFields.find(f => f.id === fieldId)
  if (!field) return

  this.c.saveState()
  const clone = JSON.parse(JSON.stringify(field))
  clone.id = `field_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`
  clone.property_slug = `${field.property_slug}_copy`

  const idx = this.c.currentPageFields.indexOf(field)
  this.c.currentPage.fields.splice(idx + 1, 0, clone)
  this.renderFields()
  this.c.saveManager.markDirty()
}
```

- [ ] **Step 6: Test in browser**

Hover over field cards — verify Duplicate icon, Delete icon, and drag handle all appear. Click Duplicate — verify field clones below original.

- [ ] **Step 7: Commit**

```bash
git add app/components/page_builder/field_action_bar_component* spec/components/page_builder/field_action_bar_component_spec.rb app/javascript/controllers/page_builder/field_manager.js app/javascript/controllers/page_builder/field_manager/layout_cards.js app/javascript/controllers/page_builder_controller.js
git commit -m "feat(page-builder): add field action bar with duplicate/delete on hover"
```

---

## Task 4: Inline Edit Manager

**Files:**
- Create: `app/javascript/controllers/page_builder/inline_edit_manager.js`
- Modify: `app/javascript/controllers/page_builder_controller.js` (import, instantiate, delegate)
- Modify: `app/javascript/controllers/page_builder/field_manager.js` (add dblclick data-action to cards)
- Modify: `app/javascript/controllers/page_builder/field_manager/layout_cards.js` (add dblclick to layout cards)

- [ ] **Step 1: Create inline_edit_manager.js**

```javascript
// app/javascript/controllers/page_builder/inline_edit_manager.js
import { BaseManager } from "controllers/page_builder/base_manager"

export class InlineEditManager extends BaseManager {
  constructor(controller) {
    super(controller)
    this.isEditing = false
    this.editingFieldId = null
    this.editingProperty = null
    this.originalValue = null
  }

  // Entry point: double-click on a field's editable text
  startEdit(event) {
    event.stopPropagation()
    event.preventDefault()

    const card = event.currentTarget.closest("[data-field-id]")
    if (!card) return

    const fieldId = card.dataset.fieldId
    const property = event.currentTarget.dataset.inlineEditProperty || "label"
    const field = this.c.currentPageFields.find(f => f.id === fieldId)
    if (!field) return

    // Don't start if already editing
    if (this.isEditing) this.cancelEdit()

    this.isEditing = true
    this.editingFieldId = fieldId
    this.editingProperty = property
    this.originalValue = field[property] || ""

    const el = event.currentTarget
    el.setAttribute("contenteditable", "true")
    el.classList.add("outline-none", "ring-1", "ring-indigo-300", "rounded", "px-0.5", "bg-white")
    el.focus()

    // Select all text
    const range = document.createRange()
    range.selectNodeContents(el)
    const sel = window.getSelection()
    sel.removeAllRanges()
    sel.addRange(range)

    // Attach event listeners
    this._onKeydown = (e) => this._handleKeydown(e, el)
    this._onBlur = () => this._confirmEdit(el)
    el.addEventListener("keydown", this._onKeydown)
    el.addEventListener("blur", this._onBlur)
  }

  _handleKeydown(event, el) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      el.blur() // triggers _confirmEdit via blur handler
    } else if (event.key === "Escape") {
      event.preventDefault()
      this._cancelAndRestore(el)
    }
  }

  _confirmEdit(el) {
    if (!this.isEditing) return

    const newValue = el.textContent.trim()
    const field = this.c.currentPageFields.find(f => f.id === this.editingFieldId)

    if (field && newValue !== this.originalValue) {
      this.c.saveState()
      field[this.editingProperty] = newValue
      this.c.saveManager.markDirty()

      // Sync property panel if open
      if (this.c.selectedFieldId === this.editingFieldId) {
        this.c.propertyManager.populatePropertyPanel(field)
      }
    }

    this._cleanupEditable(el)
  }

  _cancelAndRestore(el) {
    el.textContent = this.originalValue
    el.removeEventListener("blur", this._onBlur)
    this._cleanupEditable(el)
  }

  cancelEdit() {
    if (!this.isEditing) return
    const el = document.querySelector(`[data-field-id="${this.editingFieldId}"] [contenteditable="true"]`)
    if (el) this._cancelAndRestore(el)
    else this._resetState()
  }

  _cleanupEditable(el) {
    el.removeAttribute("contenteditable")
    el.classList.remove("outline-none", "ring-1", "ring-indigo-300", "rounded", "px-0.5", "bg-white")
    el.removeEventListener("keydown", this._onKeydown)
    el.removeEventListener("blur", this._onBlur)
    this._resetState()
  }

  _resetState() {
    this.isEditing = false
    this.editingFieldId = null
    this.editingProperty = null
    this.originalValue = null
  }
}
```

- [ ] **Step 2: Register in page_builder_controller.js**

Add import (after line 14):

```javascript
import { InlineEditManager } from "controllers/page_builder/inline_edit_manager"
```

Add instantiation in `connect()` (after line 132):

```javascript
this.inlineEditManager = new InlineEditManager(this)
```

Add delegation:

```javascript
startInlineEdit(event) { this.inlineEditManager.startEdit(event) }
```

- [ ] **Step 3: Add dblclick data-action to data field cards**

In `field_manager.js`, in the `createFieldCard()` method where the label `<span>` is built (~line 694-714), add:

```javascript
// On the label span element:
data-action="dblclick->page-builder#startInlineEdit"
data-inline-edit-property="label"
```

The label span becomes:

```html
<span class="text-xs font-medium text-gray-900 truncate"
      data-action="dblclick->page-builder#startInlineEdit"
      data-inline-edit-property="label">${label}</span>
```

- [ ] **Step 4: Add dblclick to layout cards**

In `layout_cards.js`, for heading/paragraph/section/alert/button cards, add the same `dblclick` action on their editable text elements. For headings, the property is `"label"`. For paragraphs/alerts, the property is `"content"`.

- [ ] **Step 4b: Add heading level floating toolbar**

When inline-editing a heading element, show a small floating toolbar above the element with H2/H3/H4 buttons. Add to `InlineEditManager`:

```javascript
_showHeadingToolbar(el, field) {
  const toolbar = document.createElement("div")
  toolbar.className = "heading-level-toolbar absolute -top-8 left-0 bg-white rounded-lg shadow-lg border border-gray-200 px-1 py-0.5 flex items-center gap-0.5 z-50"
  toolbar.dataset.inlineToolbar = "true"

  ;["h2", "h3", "h4"].forEach(level => {
    const btn = document.createElement("button")
    btn.type = "button"
    btn.textContent = level.toUpperCase()
    btn.className = `px-2 py-0.5 text-xs rounded transition-colors ${
      field.heading_level === level
        ? "bg-indigo-100 text-indigo-700 font-semibold"
        : "text-gray-500 hover:bg-gray-100"
    }`
    btn.addEventListener("mousedown", (e) => {
      e.preventDefault() // Prevent blur on the contenteditable
      this.c.saveState()
      field.heading_level = level
      this.c.saveManager.markDirty()
      // Update button styling
      toolbar.querySelectorAll("button").forEach(b => {
        b.className = b === btn
          ? "px-2 py-0.5 text-xs rounded bg-indigo-100 text-indigo-700 font-semibold transition-colors"
          : "px-2 py-0.5 text-xs rounded text-gray-500 hover:bg-gray-100 transition-colors"
      })
    })
    toolbar.appendChild(btn)
  })

  el.closest("[data-field-id]").style.position = "relative"
  el.closest("[data-field-id]").appendChild(toolbar)
}

_removeHeadingToolbar() {
  document.querySelectorAll(".heading-level-toolbar").forEach(t => t.remove())
}
```

Modify `startEdit()` to call `_showHeadingToolbar()` when the field is a heading:

```javascript
// After setting up contenteditable in startEdit():
if (field.field_type === "heading") {
  this._showHeadingToolbar(el, field)
}
```

Modify `_cleanupEditable()` to call `_removeHeadingToolbar()`:

```javascript
_cleanupEditable(el) {
  this._removeHeadingToolbar()
  // ... existing cleanup
}
```

- [ ] **Step 5: Add hover pencil icon indicator**

In the field card HTML, add a pencil icon that appears on hover near editable text:

```html
<svg class="w-3 h-3 text-gray-300 opacity-0 group-hover:opacity-50 transition-opacity inline-block ml-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"/>
</svg>
```

- [ ] **Step 6: Test in browser**

- Double-click a field label — it becomes editable with a subtle ring
- Type new text, press Enter — label updates, property panel syncs
- Press Escape — label reverts to original
- Double-click a heading — heading text becomes editable

- [ ] **Step 7: Commit**

```bash
git add app/javascript/controllers/page_builder/inline_edit_manager.js app/javascript/controllers/page_builder_controller.js app/javascript/controllers/page_builder/field_manager.js app/javascript/controllers/page_builder/field_manager/layout_cards.js
git commit -m "feat(page-builder): add inline editing via double-click on field labels

Supports data field labels, heading text, paragraph content,
section titles, alert messages, and button labels.
Enter confirms, Escape cancels, blur confirms."
```

---

## Task 5: Clipboard Manager (Copy/Paste/Duplicate)

**Files:**
- Create: `app/javascript/controllers/page_builder/clipboard_manager.js`
- Modify: `app/javascript/controllers/page_builder_controller.js` (import, instantiate, delegate)
- Modify: `app/javascript/controllers/page_builder/keyboard_manager.js` (add Ctrl+C/V/X/D)

- [ ] **Step 1: Create clipboard_manager.js**

```javascript
// app/javascript/controllers/page_builder/clipboard_manager.js
import { BaseManager } from "controllers/page_builder/base_manager"

export class ClipboardManager extends BaseManager {
  constructor(controller) {
    super(controller)
    this.clipboard = [] // Array of serialized field configs
  }

  copy() {
    const selected = this.c.selectionManager.getSelectedFields()
    if (selected.length === 0) return

    this.clipboard = selected.map(f => JSON.parse(JSON.stringify(f)))
  }

  cut() {
    this.copy()
    if (this.clipboard.length === 0) return

    this.c.saveState()
    const ids = new Set(this.clipboard.map(f => f.id))
    this.c.currentPage.fields = this.c.currentPage.fields.filter(f => !ids.has(f.id))
    this.c.selectionManager.deselectAll()
    this.c.fieldManager.renderFields()
    this.c.saveManager.markDirty()
  }

  paste() {
    if (this.clipboard.length === 0) return

    this.c.saveState()

    // Generate new IDs for all pasted fields
    const newFields = this.clipboard.map(f => {
      const clone = JSON.parse(JSON.stringify(f))
      clone.id = `field_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`
      clone.property_slug = this._uniqueSlug(clone.property_slug)
      return clone
    })

    // Insert after last selected field, or at end
    const selectedIds = this.c.selectionManager.getSelectedFieldIds()
    let insertIdx = this.c.currentPageFields.length

    if (selectedIds.length > 0) {
      const lastSelectedId = selectedIds[selectedIds.length - 1]
      const lastIdx = this.c.currentPageFields.findIndex(f => f.id === lastSelectedId)
      if (lastIdx >= 0) insertIdx = lastIdx + 1
    }

    this.c.currentPage.fields.splice(insertIdx, 0, ...newFields)
    this.c.fieldManager.renderFields()
    this.c.saveManager.markDirty()

    // Select the pasted fields
    this.c.selectionManager.deselectAll()
    newFields.forEach(f => this.c.selectionManager.addToSelection(f.id))
    this.c.selectionManager.updateVisuals()
  }

  duplicateSelected() {
    const selected = this.c.selectionManager.getSelectedFields()
    if (selected.length === 0) return

    this.c.saveState()

    selected.forEach(field => {
      const clone = JSON.parse(JSON.stringify(field))
      clone.id = `field_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`
      clone.property_slug = this._uniqueSlug(field.property_slug)

      const idx = this.c.currentPageFields.findIndex(f => f.id === field.id)
      this.c.currentPage.fields.splice(idx + 1, 0, clone)
    })

    this.c.fieldManager.renderFields()
    this.c.saveManager.markDirty()
  }

  _uniqueSlug(baseSlug) {
    // Strip existing _copy suffixes
    const cleanSlug = baseSlug.replace(/_copy(_\d+)?$/, "")
    const allSlugs = new Set(this.c.allFields.map(f => f.property_slug))

    let slug = `${cleanSlug}_copy`
    let counter = 2
    while (allSlugs.has(slug)) {
      slug = `${cleanSlug}_copy_${counter}`
      counter++
    }
    return slug
  }
}
```

- [ ] **Step 2: Register in page_builder_controller.js**

Add import:

```javascript
import { ClipboardManager } from "controllers/page_builder/clipboard_manager"
```

Add instantiation in `connect()`:

```javascript
this.clipboardManager = new ClipboardManager(this)
```

Add delegations:

```javascript
copyField() { this.clipboardManager.copy() }
cutField() { this.clipboardManager.cut() }
pasteField() { this.clipboardManager.paste() }
duplicateField() { this.clipboardManager.duplicateSelected() }
```

- [ ] **Step 3: Update keyboard_manager.js**

In the `handleKeydown` method, add handlers for Ctrl+C, Ctrl+V, Ctrl+X, Ctrl+D. Add these before the existing Ctrl+S handler:

```javascript
// Copy
if ((event.metaKey || event.ctrlKey) && event.key === "c" && !this._isInInput(event)) {
  event.preventDefault()
  this.c.clipboardManager.copy()
  return
}

// Paste
if ((event.metaKey || event.ctrlKey) && event.key === "v" && !this._isInInput(event)) {
  event.preventDefault()
  this.c.clipboardManager.paste()
  return
}

// Cut
if ((event.metaKey || event.ctrlKey) && event.key === "x" && !this._isInInput(event)) {
  event.preventDefault()
  this.c.clipboardManager.cut()
  return
}

// Duplicate
if ((event.metaKey || event.ctrlKey) && event.key === "d" && !this._isInInput(event)) {
  event.preventDefault()
  this.c.clipboardManager.duplicateSelected()
  return
}
```

Add helper method and update the top-level input guard. The existing `handleKeydown` has `if (event.target.matches("input, textarea, select")) return` at approximately line 62. Replace that with a call to `_isInInput()` so the `contenteditable` check applies to ALL shortcuts (not just clipboard ones):

```javascript
_isInInput(event) {
  const tag = event.target.tagName
  return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || event.target.isContentEditable
}
```

At the top of `handleKeydown()`, replace the existing `event.target.matches(...)` guard with:

```javascript
if (this._isInInput(event)) return
```

This ensures Delete, Backspace, arrow keys, and all other shortcuts are suppressed during inline editing.

- [ ] **Step 4: Test in browser**

- Select a field, Ctrl+C, then Ctrl+V — field cloned below with new ID and "_copy" slug
- Select a field, Ctrl+X — field removed, then Ctrl+V — field appears at end with new ID
- Select multiple fields (Ctrl+Click), Ctrl+D — all duplicated
- Verify shortcuts don't fire when typing in property panel inputs

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/page_builder/clipboard_manager.js app/javascript/controllers/page_builder_controller.js app/javascript/controllers/page_builder/keyboard_manager.js
git commit -m "feat(page-builder): add copy/cut/paste/duplicate with Ctrl+C/X/V/D

In-memory clipboard supports single and multi-field operations.
Paste generates new IDs and unique slugs. Works across pages."
```

---

## Task 6: Drag-and-Drop Improvements

**Files:**
- Modify: `app/javascript/controllers/page_builder/drag_drop_manager.js`
- Modify: `app/javascript/controllers/page_builder/field_manager.js` (drop indicator styling)

- [ ] **Step 1: Improve drop indicator styling**

In `drag_drop_manager.js`, find the drop indicator creation/update code. Replace the current subtle indicator with a bold blue line:

```javascript
_updateDropIndicator(y) {
  let indicator = this.c.hasDropIndicatorTarget ? this.c.dropIndicatorTarget : null
  if (!indicator) {
    indicator = document.createElement("div")
    indicator.dataset.pageBuilderTarget = "dropIndicator"
    indicator.className = "drop-indicator pointer-events-none absolute left-0 right-0 z-50 flex items-center transition-all duration-150"
    indicator.innerHTML = `
      <div class="w-3 h-3 rounded-full bg-indigo-500 border-2 border-white shadow-sm flex-shrink-0 -ml-1.5"></div>
      <div class="flex-1 h-[3px] bg-indigo-500 rounded-full"></div>
    `
    this.c.fieldsContainerTarget.appendChild(indicator)
  }
  indicator.style.top = `${y}px`
  indicator.classList.remove("hidden")
}
```

- [ ] **Step 2: Add dashed placeholder for dragged field**

When a field card starts dragging on the canvas (reorder), insert a dashed placeholder at the original position:

```javascript
// In fieldDragStart or the canvas drag start handler:
_createPlaceholder(element) {
  const rect = element.getBoundingClientRect()
  const placeholder = document.createElement("div")
  placeholder.className = "drag-placeholder border-2 border-dashed border-gray-300 rounded-lg bg-gray-50"
  placeholder.style.height = `${rect.height}px`
  placeholder.dataset.placeholderFor = element.dataset.fieldId
  element.parentNode.insertBefore(placeholder, element.nextSibling)
  return placeholder
}

_removePlaceholder() {
  const placeholder = this.c.fieldsContainerTarget.querySelector(".drag-placeholder")
  if (placeholder) placeholder.remove()
}
```

- [ ] **Step 3: Add drag card visual feedback**

On drag start, add slight rotation and elevated shadow to the drag preview:

```javascript
// In the drag preview / ghost element creation:
this.c.dragPreviewTarget.classList.add("rotate-2", "shadow-xl", "scale-105")
```

On drag end:

```javascript
this.c.dragPreviewTarget.classList.remove("rotate-2", "shadow-xl", "scale-105")
```

- [ ] **Step 4: Improve column drop zone feedback**

In `columnDragEnter`, enhance the visual feedback:

```javascript
columnDragEnter(event) {
  event.preventDefault()
  const zone = event.currentTarget
  zone.classList.add("border-indigo-400", "bg-indigo-50/30")
  zone.classList.remove("border-gray-300")

  const hint = zone.querySelector("[data-zone-hint]")
  if (hint) hint.classList.remove("opacity-0")
}
```

- [ ] **Step 5: Add smooth post-drop animation**

After a field is dropped and `renderFields()` is called, add a brief highlight animation to the dropped field card:

```javascript
// After renderFields() in the drop handler:
requestAnimationFrame(() => {
  const card = this.c.fieldsContainerTarget.querySelector(`[data-field-id="${fieldId}"]`)
  if (card) {
    card.classList.add("transition-all", "duration-200")
    card.style.opacity = "0"
    card.style.transform = "translateY(-4px)"
    requestAnimationFrame(() => {
      card.style.opacity = "1"
      card.style.transform = "translateY(0)"
    })
  }
})
```

- [ ] **Step 6: Improve auto-scroll acceleration**

Update the auto-scroll logic to increase speed near edges:

```javascript
_autoScroll(event) {
  const container = this.c.canvasAreaTarget
  const rect = container.getBoundingClientRect()
  const threshold = 60
  const maxSpeed = 20

  const distFromTop = event.clientY - rect.top
  const distFromBottom = rect.bottom - event.clientY

  if (distFromTop < threshold) {
    const speed = Math.round(maxSpeed * (1 - distFromTop / threshold))
    container.scrollTop -= speed
  } else if (distFromBottom < threshold) {
    const speed = Math.round(maxSpeed * (1 - distFromBottom / threshold))
    container.scrollTop += speed
  }
}
```

- [ ] **Step 7: Add invalid drop feedback**

When dragging over non-droppable areas (outside the canvas/drop zones), set the cursor to `not-allowed`:

```javascript
// In dragOver handler, if the target is not a valid drop zone:
dragOver(event) {
  const isValidZone = event.currentTarget.matches("[data-page-builder-target='dropZone'], .row-drop-zone, [data-column-index]")
  if (isValidZone) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "copy"
  } else {
    event.dataTransfer.dropEffect = "none"
  }
}
```

- [ ] **Step 8: Test in browser**

- Drag a field on canvas — bold blue indicator line with circle endpoint appears
- Original position shows dashed placeholder
- Drop — field animates into position
- Drag over a column — column highlights with blue border
- Drag near edge of canvas — scrolls with acceleration

- [ ] **Step 9: Commit**

```bash
git add app/javascript/controllers/page_builder/drag_drop_manager.js app/javascript/controllers/page_builder/field_manager.js
git commit -m "feat(page-builder): improve drag-and-drop with bold indicators and animations

Blue drop line with circle endpoint, dashed placeholder at drag origin,
elevated drag preview, improved column zone feedback, smooth post-drop
animation, and accelerated auto-scroll near edges."
```

---

## Task 7: Floating Action Bar Component (Multi-Select)

**Files:**
- Create: `app/components/page_builder/floating_action_bar_component.rb`
- Create: `app/components/page_builder/floating_action_bar_component.html.erb`
- Create: `spec/components/page_builder/floating_action_bar_component_spec.rb`
- Modify: `app/views/pages/_editor.html.erb` (add action bar to canvas area)
- Modify: `app/javascript/controllers/page_builder/selection_manager.js` (show/hide bar, bulk ops)
- Modify: `app/javascript/controllers/page_builder_controller.js` (add target + delegations)

- [ ] **Step 1: Write the component spec**

```ruby
# spec/components/page_builder/floating_action_bar_component_spec.rb
require "rails_helper"

RSpec.describe PageBuilder::FloatingActionBarComponent, type: :component do
  it "renders selection count placeholder" do
    render_inline(described_class.new)

    expect(page).to have_css("[data-page-builder-target='selectionCount']")
  end

  it "renders width buttons" do
    render_inline(described_class.new)

    expect(page).to have_css("button[data-width='full']", text: "Full")
    expect(page).to have_css("button[data-width='half']", text: "Half")
    expect(page).to have_css("button[data-width='two_thirds']")
    expect(page).to have_css("button[data-width='third']", text: "1/3")
  end

  it "renders duplicate, delete, group, and move-to-page buttons" do
    render_inline(described_class.new)

    expect(page).to have_css("button[data-action*='bulkDuplicate']")
    expect(page).to have_css("button[data-action*='bulkDelete']")
    expect(page).to have_css("button[data-action*='openMoveToPageModal']")
    expect(page).to have_css("button[data-action*='groupIntoSection']")
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```bash
bundle exec rspec spec/components/page_builder/floating_action_bar_component_spec.rb -v
```

- [ ] **Step 3: Write the component**

```ruby
# app/components/page_builder/floating_action_bar_component.rb
class PageBuilder::FloatingActionBarComponent < ViewComponent::Base
  WIDTH_OPTIONS = [
    { key: "full", label: "Full" },
    { key: "two_thirds", label: "2/3" },
    { key: "half", label: "Half" },
    { key: "third", label: "1/3" }
  ].freeze
end
```

```erb
<%# app/components/page_builder/floating_action_bar_component.html.erb %>
<div class="hidden fixed top-2 left-1/2 -translate-x-1/2 z-50 bg-white rounded-xl shadow-xl border border-gray-200 px-4 py-2 flex items-center gap-3"
     data-page-builder-target="floatingActionBar">
  <%# Selection count %>
  <span class="text-xs font-medium text-gray-600"
        data-page-builder-target="selectionCount">0 selected</span>

  <div class="w-px h-5 bg-gray-200"></div>

  <%# Width buttons %>
  <div class="flex items-center gap-1">
    <span class="text-[10px] text-gray-400 mr-1">Width:</span>
    <% PageBuilder::FloatingActionBarComponent::WIDTH_OPTIONS.each do |opt| %>
      <button type="button"
              class="px-2 py-0.5 text-xs rounded border border-gray-200 text-gray-600 hover:bg-indigo-50 hover:border-indigo-300 hover:text-indigo-600 transition-colors"
              data-width="<%= opt[:key] %>"
              data-action="click->page-builder#bulkSetWidth">
        <%= opt[:label] %>
      </button>
    <% end %>
  </div>

  <div class="w-px h-5 bg-gray-200"></div>

  <%# Actions %>
  <button type="button"
          class="px-2 py-0.5 text-xs rounded text-gray-600 hover:bg-gray-100 transition-colors"
          data-action="click->page-builder#bulkDuplicate"
          title="Duplicate selected">
    <svg class="w-4 h-4 inline-block" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/>
    </svg>
    Duplicate
  </button>

  <button type="button"
          class="px-2 py-0.5 text-xs rounded text-gray-600 hover:bg-gray-100 transition-colors"
          data-action="click->page-builder#openMoveToPageModal"
          title="Move to another page">
    Move to Page
  </button>

  <button type="button"
          class="px-2 py-0.5 text-xs rounded text-gray-600 hover:bg-gray-100 transition-colors"
          data-action="click->page-builder#groupIntoSection"
          title="Wrap in a section">
    Group into Section
  </button>

  <button type="button"
          class="px-2 py-0.5 text-xs rounded text-red-600 hover:bg-red-50 transition-colors"
          data-action="click->page-builder#bulkDelete"
          title="Delete selected">
    <svg class="w-4 h-4 inline-block" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/>
    </svg>
    Delete
  </button>
</div>
```

- [ ] **Step 4: Run spec to verify it passes**

```bash
bundle exec rspec spec/components/page_builder/floating_action_bar_component_spec.rb -v
```

- [ ] **Step 5: Add component to _editor.html.erb**

Inside the main canvas area container, add:

```erb
<%= render PageBuilder::FloatingActionBarComponent.new %>
```

- [ ] **Step 6: Add targets and delegations to controller**

In `page_builder_controller.js`, add to `static targets`:

```javascript
"floatingActionBar", "selectionCount",
```

Add delegation methods:

```javascript
bulkSetWidth(event) { this.selectionManager.bulkSetWidth(event) }
bulkDuplicate() { this.clipboardManager.duplicateSelected() }
bulkDelete() { this.selectionManager.bulkDelete() }
groupIntoSection() { this.selectionManager.groupIntoSection() }
```

- [ ] **Step 7: Implement bulk operations in selection_manager.js**

Add methods to `SelectionManager`:

```javascript
bulkSetWidth(event) {
  const width = event.currentTarget.dataset.width
  if (!width) return

  const selected = this.getSelectedFields()
  if (selected.length === 0) return

  this.c.saveState()
  selected.forEach(f => { f.width = width })
  this.c.fieldManager.renderFields()
  this.c.saveManager.markDirty()
  this.updateVisuals()
}

bulkDelete() {
  const count = this.count
  if (count === 0) return
  if (!confirm(`Delete ${count} field${count > 1 ? "s" : ""}?`)) return

  this.c.saveState()
  const ids = new Set(this.getSelectedFieldIds())
  this.c.currentPage.fields = this.c.currentPage.fields.filter(f => !ids.has(f.id))
  this.deselectAll()
  this.c.fieldManager.renderFields()
  this.c.saveManager.markDirty()
}
```

Add public `addToSelection` method (used by ClipboardManager to select pasted fields without calling private `_toggleSelect`):

```javascript
addToSelection(fieldId) {
  if (!this._selectedIds) this._selectedIds = new Set()
  this._selectedIds.add(fieldId)
}
```

Add `groupIntoSection` to wrap selected fields in a section element:

```javascript
groupIntoSection() {
  const selected = this.getSelectedFields()
  if (selected.length === 0) return

  this.c.saveState()

  // Find the index range of selected fields
  const fields = this.c.currentPageFields
  const selectedIds = new Set(selected.map(f => f.id))
  const firstIdx = fields.findIndex(f => selectedIds.has(f.id))

  // Create a section element and insert before the first selected field
  const section = {
    id: `field_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`,
    field_type: "section",
    property_type: "layout",
    property_slug: `section_${Date.now()}`,
    label: "New Section",
    content: "",
    width: "full",
    order: firstIdx
  }

  // Insert section before the first selected field
  this.c.currentPage.fields.splice(firstIdx, 0, section)

  this.deselectAll()
  this.c.fieldManager.renderFields()
  this.c.saveManager.markDirty()
}
```

- [ ] **Step 8: Add multi-select checkbox icon to selected cards**

Update `updateVisuals()` in `SelectionManager` to add a checkbox overlay on multi-selected cards:

```javascript
updateVisuals() {
  // ... existing ring highlight logic ...

  // Add/remove checkbox icon for multi-select
  this.c.fieldsContainerTarget.querySelectorAll(".field-card").forEach(card => {
    const fieldId = card.dataset.fieldId
    const existing = card.querySelector(".multi-select-check")

    if (this.isMultiSelect && this.isSelected(fieldId)) {
      if (!existing) {
        const check = document.createElement("div")
        check.className = "multi-select-check absolute -top-1 -left-1 w-5 h-5 bg-indigo-500 rounded-full flex items-center justify-center z-10"
        check.innerHTML = '<svg class="w-3 h-3 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M5 13l4 4L19 7"/></svg>'
        card.style.position = "relative"
        card.appendChild(check)
      }
    } else if (existing) {
      existing.remove()
    }
  })
}
```

- [ ] **Step 9: Add bulk drag support**

When multiple fields are selected and one is dragged, all selected fields move together. In `field_manager.js`, modify `fieldDragStart`:

```javascript
fieldDragStart(event) {
  const fieldId = event.currentTarget.dataset.fieldId
  const selectedIds = this.c.selectionManager.getSelectedFieldIds()

  // If dragging a selected field in multi-select, drag all selected
  if (selectedIds.length > 1 && selectedIds.includes(fieldId)) {
    this.c.draggedData = {
      type: "bulk_reorder",
      fieldIds: selectedIds
    }
  } else {
    // Single field drag (existing behavior)
    this.c.draggedData = { type: "reorder", fieldId }
  }
  // ... rest of existing drag start logic
}
```

In `fieldDrop`, handle the `bulk_reorder` type:

```javascript
// In the drop handler, after determining insertIdx:
if (this.c.draggedData?.type === "bulk_reorder") {
  const fieldIds = this.c.draggedData.fieldIds
  const fieldsToMove = fieldIds.map(id => this.c.currentPageFields.find(f => f.id === id)).filter(Boolean)

  // Remove from current positions
  this.c.currentPage.fields = this.c.currentPage.fields.filter(f => !fieldIds.includes(f.id))

  // Recalculate insert index after removal
  const adjustedIdx = Math.min(insertIdx, this.c.currentPageFields.length)

  // Insert all at new position in original order
  this.c.currentPage.fields.splice(adjustedIdx, 0, ...fieldsToMove)
}
```

Update `_updatePanel()` to show/hide the floating action bar:

```javascript
_updatePanel() {
  if (this.c.hasFloatingActionBarTarget) {
    const bar = this.c.floatingActionBarTarget
    if (this.isMultiSelect) {
      bar.classList.remove("hidden")
      if (this.c.hasSelectionCountTarget) {
        this.c.selectionCountTarget.textContent = `${this.count} fields selected`
      }
      this.c.propertyManager.hideFloatingPanel()
    } else {
      bar.classList.add("hidden")
      if (this.isSingleSelect) {
        const field = this.getSelectedFields()[0]
        if (field) this.c.propertyManager.showFloatingPanel(field.id)
      }
    }
  }
}
```

- [ ] **Step 10: Test in browser**

- Ctrl+Click two fields — floating action bar appears with "2 fields selected"
- Click "Half" in width buttons — both fields change to half width
- Click "Delete" — confirmation dialog, both fields removed
- Click "Duplicate" — both fields duplicated
- Click "Move to Page" — existing modal opens
- Click "Group into Section" — section inserted before selected fields
- Drag one of multiple selected fields — all move together
- Multi-selected cards show blue checkbox icon in top-left
- Escape or deselect — action bar hides, checkboxes removed

- [ ] **Step 11: Commit**

```bash
git add app/components/page_builder/floating_action_bar_component* spec/components/page_builder/floating_action_bar_component_spec.rb app/views/pages/_editor.html.erb app/javascript/controllers/page_builder/selection_manager.js app/javascript/controllers/page_builder_controller.js app/javascript/controllers/page_builder/field_manager.js
git commit -m "feat(page-builder): add floating action bar for multi-select bulk operations

Shows field count, width buttons, duplicate, move-to-page, and delete.
Appears when 2+ fields are selected. Hides on deselect."
```

---

## Task 8: Dependency Badge Component

**Files:**
- Create: `app/components/page_builder/dependency_badge_component.rb`
- Create: `app/components/page_builder/dependency_badge_component.html.erb`
- Create: `spec/components/page_builder/dependency_badge_component_spec.rb`
- Modify: `app/javascript/controllers/page_builder/field_manager.js` (add badge to field cards)

- [ ] **Step 1: Write the component spec**

```ruby
# spec/components/page_builder/dependency_badge_component_spec.rb
require "rails_helper"

RSpec.describe PageBuilder::DependencyBadgeComponent, type: :component do
  it "renders orange badge for fields with conditions" do
    render_inline(described_class.new(type: :has_conditions, tooltip: "Shown when: Status = Active"))

    expect(page).to have_css(".text-orange-500")
    expect(page).to have_css("[title='Shown when: Status = Active']")
  end

  it "renders purple badge for referenced fields" do
    render_inline(described_class.new(type: :referenced, tooltip: "Referenced by: Email, Phone"))

    expect(page).to have_css(".text-purple-500")
  end

  it "does not render when type is nil" do
    render_inline(described_class.new(type: nil, tooltip: ""))

    expect(page).not_to have_css("svg")
  end
end
```

- [ ] **Step 2: Run spec, verify fail**

```bash
bundle exec rspec spec/components/page_builder/dependency_badge_component_spec.rb -v
```

- [ ] **Step 3: Write the component**

```ruby
# app/components/page_builder/dependency_badge_component.rb
class PageBuilder::DependencyBadgeComponent < ViewComponent::Base
  def initialize(type:, tooltip:)
    @type = type&.to_sym
    @tooltip = tooltip
  end

  def render?
    @type.present?
  end

  def color_class
    case @type
    when :has_conditions then "text-orange-500"
    when :referenced then "text-purple-500"
    else "text-gray-400"
    end
  end

  attr_reader :type, :tooltip
end
```

```erb
<%# app/components/page_builder/dependency_badge_component.html.erb %>
<span class="<%= color_class %> cursor-pointer flex-shrink-0"
      title="<%= tooltip %>"
      data-action="click->page-builder#showDependencyLines">
  <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/>
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"/>
  </svg>
</span>
```

- [ ] **Step 4: Run spec to verify it passes**

```bash
bundle exec rspec spec/components/page_builder/dependency_badge_component_spec.rb -v
```

- [ ] **Step 5: Add dependency badges to field cards in JS**

In `field_manager.js`, in the card creation code, add a function that checks if a field has rules or is referenced by rules:

```javascript
_getDependencyBadgeHtml(field) {
  const rules = this.c.configuration.rules || []

  // Check if field has conditions applied to it
  const hasConditions = rules.some(r =>
    r.actions?.some(a => a.field_id === field.id)
  )

  // Check if field is referenced in conditions
  const isReferenced = rules.some(r =>
    r.conditions?.some(cg =>
      cg.items?.some(item => item.field_id === field.id)
    )
  )

  if (!hasConditions && !isReferenced) return ""

  const color = hasConditions ? "text-orange-500" : "text-purple-500"
  const tooltip = hasConditions
    ? "Has conditional visibility rules"
    : "Referenced by other fields' rules"

  return `<span class="${color} cursor-pointer flex-shrink-0" title="${tooltip}"
                data-action="click->page-builder#showDependencyLines"
                data-field-id="${field.id}">
    <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/>
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"/>
    </svg>
  </span>`
}
```

Insert this badge HTML into the card header div, between the label and the action buttons.

- [ ] **Step 6: Add SVG overlay for dependency lines**

Add to `field_manager.js`:

```javascript
showDependencyLines(event) {
  event.stopPropagation()
  const fieldId = event.currentTarget.dataset.fieldId
  this._removeDependencyOverlay()

  const rules = this.c.configuration.rules || []
  const connections = []

  // Find connections
  rules.forEach(rule => {
    const actionFieldIds = rule.actions?.map(a => a.field_id) || []
    const conditionFieldIds = rule.conditions?.flatMap(cg =>
      cg.items?.map(item => item.field_id) || []
    ) || []

    if (actionFieldIds.includes(fieldId)) {
      conditionFieldIds.forEach(cid => connections.push({ from: cid, to: fieldId, color: "orange" }))
    }
    if (conditionFieldIds.includes(fieldId)) {
      actionFieldIds.forEach(aid => connections.push({ from: fieldId, to: aid, color: "purple" }))
    }
  })

  if (connections.length === 0) return

  // Create SVG overlay
  const container = this.c.fieldsContainerTarget
  const containerRect = container.getBoundingClientRect()

  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
  svg.setAttribute("class", "dependency-overlay absolute inset-0 pointer-events-none z-40")
  svg.setAttribute("width", container.scrollWidth)
  svg.setAttribute("height", container.scrollHeight)
  container.style.position = "relative"
  container.appendChild(svg)

  connections.forEach(({ from, to, color }) => {
    const fromEl = container.querySelector(`[data-field-id="${from}"]`)
    const toEl = container.querySelector(`[data-field-id="${to}"]`)
    if (!fromEl || !toEl) return

    const fromRect = fromEl.getBoundingClientRect()
    const toRect = toEl.getBoundingClientRect()

    const x1 = fromRect.right - containerRect.left
    const y1 = fromRect.top + fromRect.height / 2 - containerRect.top
    const x2 = toRect.left - containerRect.left
    const y2 = toRect.top + toRect.height / 2 - containerRect.top

    const path = document.createElementNS("http://www.w3.org/2000/svg", "path")
    const midX = (x1 + x2) / 2
    path.setAttribute("d", `M ${x1} ${y1} C ${midX} ${y1}, ${midX} ${y2}, ${x2} ${y2}`)
    path.setAttribute("fill", "none")
    path.setAttribute("stroke", color === "orange" ? "#f97316" : "#a855f7")
    path.setAttribute("stroke-width", "2")
    path.setAttribute("stroke-dasharray", "6 3")
    path.setAttribute("opacity", "0.6")
    svg.appendChild(path)
  })

  // Dismiss on click elsewhere or Escape
  this._dismissDependency = (e) => {
    if (!e.target.closest(".dependency-overlay") && !e.target.closest("[data-action*='showDependencyLines']")) {
      this._removeDependencyOverlay()
    }
  }
  this._dismissDependencyKey = (e) => {
    if (e.key === "Escape") this._removeDependencyOverlay()
  }
  document.addEventListener("click", this._dismissDependency)
  document.addEventListener("keydown", this._dismissDependencyKey)
}

_removeDependencyOverlay() {
  const overlay = this.c.fieldsContainerTarget.querySelector(".dependency-overlay")
  if (overlay) overlay.remove()
  document.removeEventListener("click", this._dismissDependency)
  document.removeEventListener("keydown", this._dismissDependencyKey)
}
```

Add delegation in `page_builder_controller.js`:

```javascript
showDependencyLines(event) { this.fieldManager.showDependencyLines(event) }
```

- [ ] **Step 7: Test in browser**

- Fields with rules should show an eye icon badge (orange or purple)
- Hovering the badge shows a tooltip
- Clicking the badge draws curved SVG lines to related fields
- Clicking elsewhere or pressing Escape dismisses the lines

- [ ] **Step 8: Commit**

```bash
git add app/components/page_builder/dependency_badge_component* spec/components/page_builder/dependency_badge_component_spec.rb app/javascript/controllers/page_builder/field_manager.js app/javascript/controllers/page_builder_controller.js
git commit -m "feat(page-builder): add dependency badges and SVG connector lines

Fields with conditional rules show orange eye badge. Fields referenced
by other rules show purple badge. Click badge to draw curved SVG
connection lines. Escape or click to dismiss."
```

---

## Task 9: Integrate Undo/Redo for All New Operations

**Files:**
- Modify: `app/javascript/controllers/page_builder/inline_edit_manager.js`
- Modify: `app/javascript/controllers/page_builder/clipboard_manager.js`
- Modify: `app/javascript/controllers/page_builder/selection_manager.js`

This task ensures all new state-mutating operations properly call `this.c.saveState()` before modification. Review each manager and verify.

- [ ] **Step 1: Audit inline_edit_manager.js**

Verify `_confirmEdit()` calls `this.c.saveState()` before modifying the field. (Already done in Task 4 implementation.)

- [ ] **Step 2: Audit clipboard_manager.js**

Verify:
- `cut()` calls `this.c.saveState()` before removing fields (done)
- `paste()` calls `this.c.saveState()` before inserting fields (done)
- `duplicateSelected()` calls `this.c.saveState()` before cloning (done)

- [ ] **Step 3: Audit selection_manager.js**

Verify:
- `bulkSetWidth()` calls `this.c.saveState()` (done)
- `bulkDelete()` calls `this.c.saveState()` (done)
- `confirmMoveToPage()` calls `this.c.saveState()` — the existing code in `selection_manager.js` (~line 275) delegates to `this.c.pageManager.moveFieldsToPage()` but does NOT call `saveState()` before mutation. Add `this.c.saveState()` as the first line in `confirmMoveToPage()`:

```javascript
confirmMoveToPage() {
  this.c.saveState() // Add this line
  // ... existing logic
}
```

- [ ] **Step 4: Test undo/redo flow**

- Duplicate a field, then Ctrl+Z — field disappears (undo works)
- Paste fields, then Ctrl+Z — pasted fields disappear
- Bulk delete, then Ctrl+Z — fields restored
- Inline edit a label, then Ctrl+Z — label reverts
- Ctrl+Shift+Z after undo — redoes the action

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/page_builder/inline_edit_manager.js app/javascript/controllers/page_builder/clipboard_manager.js app/javascript/controllers/page_builder/selection_manager.js
git commit -m "fix(page-builder): ensure all new operations integrate with undo/redo

Verified saveState() called before inline edit confirm, cut, paste,
duplicate, bulk width, bulk delete, and move-to-page."
```

---

## Task 10: Precompile Assets and Full Integration Test

**Files:**
- All modified JS files
- All new ViewComponent files

- [ ] **Step 1: Precompile assets**

```bash
RAILS_ENV=development bundle exec rails assets:precompile
```
Expected: No errors, clean compilation

- [ ] **Step 2: Restart server**

```bash
pkill -f puma; sleep 1; RAILS_ENV=development bin/rails server -b 0.0.0.0 -p 3000 &
```

- [ ] **Step 3: Run all component specs**

```bash
bundle exec rspec spec/components/page_builder/ -v
```
Expected: All specs pass

- [ ] **Step 4: Full manual integration test**

Test the complete Phase 1 flow at `/96546124/pages/32/edit`:

1. **Property panel tabs**: Click text field → 4 tabs. Click heading → 2 tabs. Switch tabs, verify inputs.
2. **Inline editing**: Double-click label → edit → Enter. Double-click heading → edit. Escape cancels.
3. **Field action bar**: Hover field → see Duplicate/Delete/Drag. Click Duplicate.
4. **Copy/paste**: Select field → Ctrl+C → Ctrl+V. Select field → Ctrl+X → Ctrl+V.
5. **Duplicate**: Ctrl+D on selected field.
6. **Multi-select**: Ctrl+Click two fields. Floating bar appears. Bulk set width. Bulk delete.
7. **Move to page**: Multi-select → "Move to Page" → select target.
8. **Drag-and-drop**: Drag field → bold blue indicator. Drop → smooth animation.
9. **Dependency badges**: Fields with rules show eye badges. Click → SVG lines appear.
10. **Undo/redo**: After each operation, Ctrl+Z undoes, Ctrl+Shift+Z redoes.
11. **Save**: After changes, Ctrl+S saves without errors.

- [ ] **Step 5: Commit final integration state**

```bash
git add -A
git commit -m "feat(page-builder): Phase 1 complete - foundation improvements

- Tabbed property panel (contextual tabs per field category)
- Inline editing via double-click
- Copy/cut/paste/duplicate with keyboard shortcuts
- Field action bar (hover duplicate/delete)
- Improved drag-and-drop (bold indicators, placeholders, animations)
- Multi-select floating action bar (bulk width, duplicate, delete, move)
- Dependency badges with SVG connector lines
- Full undo/redo integration for all new operations"
```
