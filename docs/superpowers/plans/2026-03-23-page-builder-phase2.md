# Page Builder Phase 2: Canvas Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the canvas with high-fidelity theme-aware field previews, drag-to-resize handles with snap-to-grid, per-breakpoint responsive width editing, and a field group system for treating multiple fields as a unit.

**Architecture:** Phase 2 builds on the Phase 1 manager architecture. Three new managers (`resize_manager.js` for drag-resize, plus group management in field_manager) extend the existing system. The width system expands from 4 to 6 named widths. Field configs gain a `responsive_widths` object for per-breakpoint overrides. A new `field_group` node type sits alongside regular fields in the page's `fields` array.

**Tech Stack:** Rails 8, StimulusJS, TailwindCSS, ViewComponent, RSpec

**Spec:** `docs/superpowers/specs/2026-03-23-page-builder-improvements-design.md` (Phase 2 sections 2.1-2.4)

**Depends on:** Phase 1 complete (tabbed property panel, inline editing, copy/paste, drag-and-drop, multi-select, dependency badges)

---

## File Map

### New Files

| File | Purpose |
|------|---------|
| `app/javascript/controllers/page_builder/resize_manager.js` | Drag-to-resize handle, snap-to-grid, tooltip |
| `app/components/page_builder/resize_handle_component.rb` | ViewComponent: resize handle overlay |
| `app/components/page_builder/resize_handle_component.html.erb` | Template for resize handle |
| `app/components/page_builder/field_group_component.rb` | ViewComponent: field group container |
| `app/components/page_builder/field_group_component.html.erb` | Template for field group |
| `spec/components/page_builder/resize_handle_component_spec.rb` | Spec for resize handle |
| `spec/components/page_builder/field_group_component_spec.rb` | Spec for field group |

### Modified Files

| File | Changes |
|------|---------|
| `app/javascript/controllers/page_builder/field_manager.js` | Expand WIDTH_COLS/WIDTH_CLASSES to 6 widths, theme-aware preview rendering, field group CRUD, responsive width in `_effectiveWidth()` |
| `app/javascript/controllers/page_builder/field_manager/field_previews.js` | Replace simplified previews with high-fidelity theme-aware form element rendering |
| `app/javascript/controllers/page_builder/property_manager.js` | Add breakpoint tabs in Layout tab, responsive width controls, field group property panel |
| `app/javascript/controllers/page_builder/viewport_manager.js` | Wire viewport changes to update field widths on canvas |
| `app/javascript/controllers/page_builder/selection_manager.js` | Update `groupIntoSection()` → `groupFields()` for field group creation |
| `app/javascript/controllers/page_builder/drag_drop_manager.js` | Respect field group nesting constraints |
| `app/javascript/controllers/page_builder_controller.js` | Import resize_manager, add targets/delegations |
| `app/services/page_content_generator.rb` | Expand WIDTH_COLS/COL_SPAN_CLASSES, generate responsive Tailwind classes from `responsive_widths` |
| `app/views/pages/_property_panel.html.erb` | Add breakpoint selector UI in Layout tab |

---

## Task 1: Expand Width System to 6 Named Widths

**Files:**
- Modify: `app/javascript/controllers/page_builder/field_manager.js` (lines 5-6)
- Modify: `app/services/page_content_generator.rb` (lines 72-73)

This is the foundation task — all other Phase 2 features depend on the expanded width system.

- [ ] **Step 1: Update WIDTH_COLS and WIDTH_CLASSES in field_manager.js**

Replace lines 5-6:

```javascript
const WIDTH_COLS = { full: 12, three_quarters: 9, two_thirds: 8, half: 6, third: 4, quarter: 3 }
const WIDTH_CLASSES = { full: "col-span-12", three_quarters: "col-span-9", two_thirds: "col-span-8", half: "col-span-6", third: "col-span-4", quarter: "col-span-3" }
```

- [ ] **Step 2: Update PageContentGenerator width mappings**

In `app/services/page_content_generator.rb`, update the two constants (lines 72-73):

```ruby
WIDTH_COLS = { "full" => 12, "three_quarters" => 9, "two_thirds" => 8, "half" => 6, "third" => 4, "quarter" => 3 }.freeze
COL_SPAN_CLASSES = { "full" => "col-span-12", "three_quarters" => "col-span-9", "two_thirds" => "col-span-8", "half" => "col-span-6", "third" => "col-span-4", "quarter" => "col-span-3" }.freeze
```

- [ ] **Step 3: Update width buttons in property panel Layout tab**

In `app/views/pages/_property_panel.html.erb`, find the width buttons in the Layout tab. Add "3/4" and "1/4" buttons:

The width buttons should be: Full | 3/4 | 2/3 | Half | 1/3 | 1/4
Each with `data-width="<name>"` and `data-action="click->page-builder#setFieldWidth"`.

- [ ] **Step 4: Update floating action bar width buttons**

In `app/components/page_builder/floating_action_bar_component.rb`, update `WIDTH_OPTIONS`:

```ruby
WIDTH_OPTIONS = [
  { key: "full", label: "Full" },
  { key: "three_quarters", label: "3/4" },
  { key: "two_thirds", label: "2/3" },
  { key: "half", label: "Half" },
  { key: "third", label: "1/3" },
  { key: "quarter", label: "1/4" }
].freeze
```

- [ ] **Step 5: Verify assets compile and specs pass**

```bash
RAILS_ENV=development bundle exec rails assets:precompile
bundle exec rspec spec/components/page_builder/ -v
```

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/page_builder/field_manager.js app/services/page_content_generator.rb app/views/pages/_property_panel.html.erb app/components/page_builder/floating_action_bar_component.rb
git commit -m "feat(page-builder): expand width system to 6 named widths (add quarter, three_quarters)"
```

---

## Task 2: High-Fidelity Theme-Aware Field Previews

**Files:**
- Modify: `app/javascript/controllers/page_builder/field_manager/field_previews.js`
- Modify: `app/javascript/controllers/page_builder/field_manager.js` (pass theme to preview)

Replace the current simplified card previews with near-actual form element rendering that respects the active theme.

- [ ] **Step 1: Read the current field_previews.js**

Read the entire file to understand all 27 preview types and the `_previewInput()` helper.

- [ ] **Step 2: Add theme context to preview rendering**

In `field_manager.js`, modify `createDataFieldCardHtml()` to pass theme settings to preview methods. The theme is at `this.c.configuration.theme`:

```javascript
const theme = this.c.configuration.theme || {}
```

Add a method to FieldPreviewsMixin that maps theme values to Tailwind classes:

```javascript
_themeClasses(theme) {
  const radiusMap = { none: "rounded-none", sm: "rounded-sm", md: "rounded-md", lg: "rounded-lg", full: "rounded-full" }
  const sizeMap = { sm: "py-1 px-2 text-xs", md: "py-1.5 px-3 text-sm", lg: "py-2 px-4 text-base" }
  const styleMap = {
    outline: "border border-gray-300 bg-white",
    filled: "border border-transparent bg-gray-100",
    underline: "border-b border-gray-300 bg-transparent rounded-none"
  }

  return {
    radius: radiusMap[theme.border_radius] || "rounded-lg",
    size: sizeMap[theme.input_size] || "py-1.5 px-3 text-sm",
    style: styleMap[theme.input_style] || "border border-gray-300 bg-white",
    primaryColor: theme.primary_color || "indigo"
  }
}
```

- [ ] **Step 3: Upgrade text input previews**

Replace `_previewInput()` with a theme-aware version that renders an actual-looking input:

```javascript
_previewInput(field, theme, placeholder, leadingIcon) {
  const t = this._themeClasses(theme)
  const ph = placeholder || field.placeholder || ""
  const iconHtml = leadingIcon ? `<div class="flex-shrink-0 text-gray-400 mr-2">${leadingIcon}</div>` : ""

  return `<div class="flex items-center ${t.style} ${t.radius} ${t.size} text-gray-400 w-full">
    ${iconHtml}
    <span class="truncate">${ph}</span>
  </div>`
}
```

- [ ] **Step 4: Upgrade selection previews (select, radio, checkbox, switch)**

For select — render a proper dropdown with chevron:
```javascript
_previewSelect(field, theme) {
  const t = this._themeClasses(theme)
  const label = field.options?.[0]?.label || field.placeholder || "Select..."
  return `<div class="flex items-center justify-between ${t.style} ${t.radius} ${t.size} text-gray-500 w-full">
    <span class="truncate">${label}</span>
    <svg class="w-4 h-4 text-gray-400 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"/></svg>
  </div>`
}
```

For radio/checkbox — render actual option labels from field.options:
```javascript
_previewRadioCheckbox(field, theme, isRadio) {
  const options = field.options?.slice(0, 3) || [{ label: "Option 1" }, { label: "Option 2" }]
  const isInline = field.inline_layout === true || field.inline_layout === "true"
  const containerClass = isInline ? "flex items-center gap-4 flex-wrap" : "space-y-1.5"
  const inputType = isRadio ? "rounded-full" : "rounded"

  const items = options.map((opt, i) => {
    const checked = i === 0
    return `<label class="flex items-center gap-1.5 text-xs text-gray-600">
      <span class="w-3.5 h-3.5 ${inputType} border ${checked ? `bg-${theme.primary_color || "indigo"}-500 border-${theme.primary_color || "indigo"}-500` : "border-gray-300 bg-white"} flex-shrink-0"></span>
      ${opt.label}
    </label>`
  }).join("")

  return `<div class="${containerClass}">${items}</div>`
}
```

- [ ] **Step 5: Upgrade numeric previews (number, currency, range, rating)**

These already look decent. Add theme radius/style to the container wrapping.

- [ ] **Step 6: Upgrade file/media previews**

Add theme-aware borders:
```javascript
_previewFile(field, theme) {
  const t = this._themeClasses(theme)
  return `<div class="border-2 border-dashed border-gray-300 ${t.radius} p-3 text-center">
    <svg class="w-6 h-6 text-gray-400 mx-auto mb-1" ...></svg>
    <p class="text-xs text-gray-500">${field.accept_types || "Drop file or click to upload"}</p>
  </div>`
}
```

- [ ] **Step 7: Wire getFieldPreviewHtml to accept theme parameter**

Update the method signature: `getFieldPreviewHtml(field, theme)`. Update all callers in `field_manager.js` to pass the theme object.

- [ ] **Step 8: Add selection overlay to distinguish builder cards from live form**

In `createFieldCard()`, after the preview HTML, add a subtle overlay on hover that signals "this is editable":

```javascript
// After the preview HTML, add:
const selectionOverlay = `<div class="absolute inset-0 rounded-lg opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none border-2 border-transparent group-hover:border-indigo-200/50"></div>`
```

- [ ] **Step 9: Ensure theme changes trigger re-render**

In `property_manager.js`, find `updateTheme()` and `applyThemePreset()`. Ensure they call `this.c.fieldManager.renderFields()` so previews update immediately when the theme changes.

- [ ] **Step 10: Manually test in browser**

Load the page builder. Verify:
- Field cards show actual styled inputs, not just icons + text
- Changing theme (Modern → Minimalist → Bold) updates all previews immediately
- Different input styles (outline/filled/underline) apply correctly
- Radio/checkbox show actual option labels from field config

- [ ] **Step 11: Commit**

```bash
git add app/javascript/controllers/page_builder/field_manager/field_previews.js app/javascript/controllers/page_builder/field_manager.js app/javascript/controllers/page_builder/property_manager.js
git commit -m "feat(page-builder): high-fidelity theme-aware field previews on canvas"
```

---

## Task 3: Resize Handle Manager

**Files:**
- Create: `app/javascript/controllers/page_builder/resize_manager.js`
- Create: `app/components/page_builder/resize_handle_component.rb`
- Create: `app/components/page_builder/resize_handle_component.html.erb`
- Create: `spec/components/page_builder/resize_handle_component_spec.rb`
- Modify: `app/javascript/controllers/page_builder_controller.js`
- Modify: `app/javascript/controllers/page_builder/field_manager.js`

- [ ] **Step 1: Write the ViewComponent spec**

```ruby
# spec/components/page_builder/resize_handle_component_spec.rb
require "rails_helper"

RSpec.describe PageBuilder::ResizeHandleComponent, type: :component do
  it "renders a vertical drag handle" do
    render_inline(described_class.new)
    expect(page).to have_css(".resize-handle")
    expect(page).to have_css("[data-action*='mousedown->page-builder#startResize']")
  end

  it "uses col-resize cursor" do
    render_inline(described_class.new)
    expect(page).to have_css(".cursor-col-resize")
  end
end
```

- [ ] **Step 2: Write the component**

```ruby
# app/components/page_builder/resize_handle_component.rb
class PageBuilder::ResizeHandleComponent < ApplicationComponent
end
```

```erb
<%# app/components/page_builder/resize_handle_component.html.erb %>
<div class="resize-handle absolute right-0 top-1/2 -translate-y-1/2 translate-x-1/2 w-1.5 h-8 bg-gray-300 rounded-full cursor-col-resize opacity-0 group-hover:opacity-100 hover:bg-indigo-400 transition-all z-20"
     data-action="mousedown->page-builder#startResize"
     title="Drag to resize">
</div>
```

- [ ] **Step 3: Run spec to verify passes**

```bash
bundle exec rspec spec/components/page_builder/resize_handle_component_spec.rb -v
```

- [ ] **Step 4: Create resize_manager.js**

```javascript
// app/javascript/controllers/page_builder/resize_manager.js
import { BaseManager } from "controllers/page_builder/base_manager"

const WIDTH_SNAP_POINTS = [
  { cols: 3,  name: "quarter",        label: "1/4" },
  { cols: 4,  name: "third",          label: "1/3" },
  { cols: 6,  name: "half",           label: "Half" },
  { cols: 8,  name: "two_thirds",     label: "2/3" },
  { cols: 9,  name: "three_quarters", label: "3/4" },
  { cols: 12, name: "full",           label: "Full" }
]

export class ResizeManager extends BaseManager {
  constructor(controller) {
    super(controller)
    this.isResizing = false
    this.resizingFieldId = null
    this.startX = 0
    this.containerWidth = 0
    this.tooltip = null
  }

  startResize(event) {
    event.preventDefault()
    event.stopPropagation()

    const card = event.currentTarget.closest("[data-field-id]")
    if (!card) return

    this.isResizing = true
    this.resizingFieldId = card.dataset.fieldId
    this.startX = event.clientX

    const container = this.c.fieldsContainerTarget
    this.containerWidth = container.getBoundingClientRect().width
    this.colWidth = this.containerWidth / 12

    // Save state before resize begins
    this.c.saveState()

    // Show grid lines
    this._showGridLines()
    this._createTooltip()

    this._onMouseMove = (e) => this._handleMouseMove(e)
    this._onMouseUp = (e) => this._handleMouseUp(e)
    document.addEventListener("mousemove", this._onMouseMove)
    document.addEventListener("mouseup", this._onMouseUp)
  }

  _handleMouseMove(event) {
    if (!this.isResizing) return

    const card = this.c.fieldsContainerTarget.querySelector(`[data-field-id="${this.resizingFieldId}"]`)
    if (!card) return

    const cardLeft = card.getBoundingClientRect().left
    const newWidth = event.clientX - cardLeft
    const cols = Math.round(newWidth / this.colWidth)

    // Find nearest snap point
    const snap = WIDTH_SNAP_POINTS.reduce((closest, point) =>
      Math.abs(point.cols - cols) < Math.abs(closest.cols - cols) ? point : closest
    )

    // Update tooltip
    this._updateTooltip(event.clientX, event.clientY, `${snap.cols}/12 (${snap.label})`)

    // Preview the width change visually
    const field = this.c.currentPageFields.find(f => f.id === this.resizingFieldId)
    if (field && field.width !== snap.name) {
      field.width = snap.name
      this.c.fieldManager.renderFields()
    }
  }

  _handleMouseUp(event) {
    if (!this.isResizing) return

    this.isResizing = false
    this._removeGridLines()
    this._removeTooltip()

    document.removeEventListener("mousemove", this._onMouseMove)
    document.removeEventListener("mouseup", this._onMouseUp)

    // Sync property panel
    const field = this.c.currentPageFields.find(f => f.id === this.resizingFieldId)
    if (field) {
      this.c.propertyManager.syncToolbarWidth(field)
    }
    this.c.saveManager.markDirty()
    this.resizingFieldId = null
  }

  _showGridLines() {
    const container = this.c.fieldsContainerTarget
    const overlay = document.createElement("div")
    overlay.className = "resize-grid-overlay absolute inset-0 pointer-events-none z-10"
    overlay.style.display = "grid"
    overlay.style.gridTemplateColumns = "repeat(12, 1fr)"
    overlay.style.gap = "0"

    for (let i = 0; i < 12; i++) {
      const line = document.createElement("div")
      line.className = i < 11 ? "border-r border-dashed border-indigo-200/40" : ""
      overlay.appendChild(line)
    }

    container.style.position = "relative"
    container.appendChild(overlay)
  }

  _removeGridLines() {
    this.c.fieldsContainerTarget.querySelector(".resize-grid-overlay")?.remove()
  }

  _createTooltip() {
    this.tooltip = document.createElement("div")
    this.tooltip.className = "fixed z-50 bg-gray-900 text-white text-xs px-2 py-1 rounded shadow-lg pointer-events-none"
    document.body.appendChild(this.tooltip)
  }

  _updateTooltip(x, y, text) {
    if (!this.tooltip) return
    this.tooltip.textContent = text
    this.tooltip.style.left = `${x + 12}px`
    this.tooltip.style.top = `${y - 28}px`
  }

  _removeTooltip() {
    this.tooltip?.remove()
    this.tooltip = null
  }
}
```

- [ ] **Step 5: Register resize_manager in controller**

In `page_builder_controller.js`:
1. Import: `import { ResizeManager } from "controllers/page_builder/resize_manager"`
2. In `connect()`: `this.resizeManager = new ResizeManager(this)`
3. Add delegation: `startResize(event) { this.resizeManager.startResize(event) }`

- [ ] **Step 6: Add resize handle to selected field cards**

In `field_manager.js`, in `createFieldCard()`, when a field is single-selected and NOT a layout element, add the resize handle HTML to the card:

```javascript
// After creating the card div, if selected:
if (isSelected && !isLayout) {
  const handle = document.createElement("div")
  handle.className = "resize-handle absolute right-0 top-1/2 -translate-y-1/2 translate-x-1/2 w-1.5 h-8 bg-gray-300 rounded-full cursor-col-resize hover:bg-indigo-400 transition-all z-20"
  handle.dataset.action = "mousedown->page-builder#startResize"
  div.style.position = "relative"
  div.appendChild(handle)
}
```

- [ ] **Step 7: Verify and test**

```bash
RAILS_ENV=development bundle exec rails assets:precompile
bundle exec rspec spec/components/page_builder/resize_handle_component_spec.rb -v
```

Test in browser: Select a data field → resize handle appears on right edge → drag to resize → tooltip shows "6/12 (Half)" → grid lines appear → field snaps to new width.

- [ ] **Step 8: Commit**

```bash
git add app/javascript/controllers/page_builder/resize_manager.js app/components/page_builder/resize_handle_component* spec/components/page_builder/resize_handle_component_spec.rb app/javascript/controllers/page_builder_controller.js app/javascript/controllers/page_builder/field_manager.js
git commit -m "feat(page-builder): add drag-to-resize handles with snap-to-grid and tooltip"
```

---

## Task 4: Responsive Breakpoint Editing

**Files:**
- Modify: `app/javascript/controllers/page_builder/field_manager.js` — viewport-aware `_effectiveWidth()`
- Modify: `app/javascript/controllers/page_builder/property_manager.js` — breakpoint tabs in Layout tab
- Modify: `app/javascript/controllers/page_builder/viewport_manager.js` — trigger re-render on viewport change
- Modify: `app/javascript/controllers/page_builder/resize_manager.js` — write to responsive_widths when not on desktop
- Modify: `app/views/pages/_property_panel.html.erb` — breakpoint selector UI
- Modify: `app/services/page_content_generator.rb` — generate responsive Tailwind classes

- [ ] **Step 1: Update _effectiveWidth to be viewport-aware**

In `field_manager.js`, modify `_effectiveWidth(field)`:

```javascript
_effectiveWidth(field) {
  if (field.property_type === "layout") return field.width || "full"

  const viewport = this.c.viewportValue || "desktop"

  // Check responsive overrides for non-desktop viewports
  if (viewport !== "desktop" && field.responsive_widths) {
    const override = field.responsive_widths[viewport]
    if (override) return override
    // Mobile inherits from tablet, tablet inherits from desktop
    if (viewport === "mobile" && field.responsive_widths.tablet) {
      return field.responsive_widths.tablet
    }
  }

  // Desktop: check layout template, then field width
  const layout = this.c.layoutTemplateValue
  if (!layout || Object.keys(layout).length === 0) return field.width || "full"
  return layout.field_width_rules?.[field.html_type] || layout.default_width || field.width || "full"
}
```

- [ ] **Step 2: Update viewport_manager to trigger re-render**

In `viewport_manager.js`, add `this.c.fieldManager.renderFields()` at the end of `setViewport()`:

```javascript
setViewport(event) {
  const viewport = event.currentTarget.dataset.viewport
  this.c.viewportValue = viewport
  this.updateViewportUI()
  this.c.fieldManager.renderFields()
}
```

- [ ] **Step 3: Add breakpoint selector to property panel Layout tab**

In `_property_panel.html.erb`, in the Layout tab content (`data-property-tab-content="layout"`), add breakpoint icons below the width buttons:

```erb
<%# Breakpoint selector %>
<div class="flex items-center gap-1 mt-2" data-page-builder-target="breakpointSelector">
  <span class="text-[10px] text-gray-400 mr-1">Breakpoint:</span>
  <button type="button" data-breakpoint="desktop" data-action="click->page-builder#switchBreakpoint"
          class="px-2 py-0.5 text-xs rounded border border-indigo-300 bg-indigo-50 text-indigo-600">
    <svg class="w-3.5 h-3.5 inline-block" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"/></svg>
  </button>
  <button type="button" data-breakpoint="tablet" data-action="click->page-builder#switchBreakpoint"
          class="px-2 py-0.5 text-xs rounded border border-gray-200 text-gray-500 hover:border-indigo-300">
    <svg class="w-3.5 h-3.5 inline-block" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 18h.01M7 21h10a2 2 0 002-2V5a2 2 0 00-2-2H7a2 2 0 00-2 2v14a2 2 0 002 2z"/></svg>
  </button>
  <button type="button" data-breakpoint="mobile" data-action="click->page-builder#switchBreakpoint"
          class="px-2 py-0.5 text-xs rounded border border-gray-200 text-gray-500 hover:border-indigo-300">
    <svg class="w-3.5 h-3.5 inline-block" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 18h.01M8 21h8a2 2 0 002-2V5a2 2 0 00-2-2H8a2 2 0 00-2 2v14a2 2 0 002 2z"/></svg>
  </button>
  <a href="#" class="text-[10px] text-indigo-500 hover:text-indigo-700 ml-2 hidden" data-page-builder-target="resetBreakpoint"
     data-action="click->page-builder#resetBreakpointWidth">Reset to inherit</a>
</div>
```

- [ ] **Step 4: Add breakpoint switching logic to property_manager**

```javascript
switchBreakpoint(event) {
  const bp = event.currentTarget.dataset.breakpoint
  this._activeBreakpoint = bp

  // Update button styling
  const selector = this.c.floatingPanelTarget.querySelector("[data-page-builder-target='breakpointSelector']")
  if (selector) {
    selector.querySelectorAll("[data-breakpoint]").forEach(btn => {
      const active = btn.dataset.breakpoint === bp
      btn.classList.toggle("border-indigo-300", active)
      btn.classList.toggle("bg-indigo-50", active)
      btn.classList.toggle("text-indigo-600", active)
      btn.classList.toggle("border-gray-200", !active)
      btn.classList.toggle("text-gray-500", !active)
    })
  }

  // Update width buttons to show this breakpoint's width
  const field = this.c.currentPageFields.find(f => f.id === this.c.selectedFieldId)
  if (field) {
    const width = bp === "desktop"
      ? (field.width || "full")
      : (field.responsive_widths?.[bp] || null)
    this._syncWidthButtonsForBreakpoint(field, width)

    // Show/hide "Reset to inherit" link
    const resetLink = this.c.floatingPanelTarget.querySelector("[data-page-builder-target='resetBreakpoint']")
    if (resetLink) {
      resetLink.classList.toggle("hidden", bp === "desktop" || !field.responsive_widths?.[bp])
    }
  }
}
```

- [ ] **Step 5: Update setFieldWidth to write to responsive_widths**

Modify `setFieldWidth()` in property_manager.js:

```javascript
setFieldWidth(event) {
  const width = event.currentTarget.dataset.width
  const fieldId = this.c.selectedFieldValue || this.c.selectedFieldId
  if (!fieldId || !width) return

  const field = this.c.currentPageFields.find(f => f.id === fieldId)
  if (!field) return

  this.c.undoRedoManager.saveState()

  const bp = this._activeBreakpoint || "desktop"
  if (bp === "desktop") {
    field.width = width
  } else {
    if (!field.responsive_widths) field.responsive_widths = {}
    field.responsive_widths[bp] = width
  }

  this.c.fieldManager.renderFields()
  this.syncToolbarWidth(field)
  this.c.saveManager.markDirty()
}
```

- [ ] **Step 6: Add resetBreakpointWidth delegation + method**

```javascript
resetBreakpointWidth(event) {
  event.preventDefault()
  const field = this.c.currentPageFields.find(f => f.id === this.c.selectedFieldId)
  if (!field || !field.responsive_widths) return

  const bp = this._activeBreakpoint
  if (bp === "desktop") return

  this.c.undoRedoManager.saveState()
  delete field.responsive_widths[bp]
  if (Object.keys(field.responsive_widths).length === 0) delete field.responsive_widths
  this.c.fieldManager.renderFields()
  this.c.saveManager.markDirty()
}
```

Add to controller: `switchBreakpoint(event) { this.propertyManager.switchBreakpoint(event) }` and `resetBreakpointWidth(event) { this.propertyManager.resetBreakpointWidth(event) }`.

Add target: `"breakpointSelector", "resetBreakpoint"`.

- [ ] **Step 7: Update resize_manager to write responsive_widths**

In `resize_manager.js`, modify `_handleMouseMove` to check the current viewport:

```javascript
const viewport = this.c.viewportValue || "desktop"
if (viewport === "desktop") {
  field.width = snap.name
} else {
  if (!field.responsive_widths) field.responsive_widths = {}
  field.responsive_widths[viewport] = snap.name
}
```

- [ ] **Step 8: Update PageContentGenerator for responsive classes**

In `page_content_generator.rb`, modify `render_field_row` to generate responsive Tailwind classes:

```ruby
BREAKPOINT_PREFIX = { "mobile" => "", "tablet" => "md:", "desktop" => "lg:" }.freeze

def responsive_col_span(field)
  desktop_width = field["width"] || "full"
  responsive = field["responsive_widths"] || {}

  mobile_width = responsive["mobile"] || responsive["tablet"] || desktop_width
  tablet_width = responsive["tablet"] || desktop_width

  classes = []
  classes << COL_SPAN_CLASSES[mobile_width] || "col-span-12"
  classes << "md:#{COL_SPAN_CLASSES[tablet_width]}" if tablet_width != mobile_width
  classes << "lg:#{COL_SPAN_CLASSES[desktop_width]}" if desktop_width != tablet_width

  classes.join(" ")
end
```

Replace `COL_SPAN_CLASSES[field["width"]]` calls with `responsive_col_span(field)` in `render_field_row`.

- [ ] **Step 9: Add breakpoint badge to field cards**

In `field_manager.js`, in `createFieldCard()`, add a small "T" or "M" badge when the field has responsive overrides:

```javascript
_getBreakpointBadge(field) {
  if (!field.responsive_widths) return ""
  const badges = []
  if (field.responsive_widths.tablet) badges.push("T")
  if (field.responsive_widths.mobile) badges.push("M")
  if (badges.length === 0) return ""
  return `<span class="text-[9px] font-bold text-indigo-500 bg-indigo-50 rounded px-0.5">${badges.join("")}</span>`
}
```

Insert this in the card header near the width/label area.

- [ ] **Step 10: Test in browser**

- Switch to tablet viewport → canvas resizes → field widths may change
- Select a field → Layout tab shows breakpoint buttons
- Click tablet breakpoint → change width → "T" badge appears on card
- Click "Reset to inherit" → override removed, inherits from desktop
- Save and preview → verify responsive classes in generated HTML

- [ ] **Step 11: Commit**

```bash
git add app/javascript/controllers/page_builder/field_manager.js app/javascript/controllers/page_builder/property_manager.js app/javascript/controllers/page_builder/viewport_manager.js app/javascript/controllers/page_builder/resize_manager.js app/views/pages/_property_panel.html.erb app/services/page_content_generator.rb app/javascript/controllers/page_builder_controller.js
git commit -m "feat(page-builder): responsive breakpoint editing with per-viewport widths

Fields can have different widths per breakpoint (desktop/tablet/mobile).
Inherit chain: mobile inherits tablet inherits desktop.
PageContentGenerator outputs responsive Tailwind classes."
```

---

## Task 5: Field Groups

**Files:**
- Create: `app/components/page_builder/field_group_component.rb`
- Create: `app/components/page_builder/field_group_component.html.erb`
- Create: `spec/components/page_builder/field_group_component_spec.rb`
- Modify: `app/javascript/controllers/page_builder/field_manager.js` — render field groups, group CRUD
- Modify: `app/javascript/controllers/page_builder/selection_manager.js` — update groupFields()
- Modify: `app/javascript/controllers/page_builder/property_manager.js` — group property panel
- Modify: `app/javascript/controllers/page_builder/drag_drop_manager.js` — nesting constraints
- Modify: `app/javascript/controllers/page_builder_controller.js` — delegations

- [ ] **Step 1: Write the ViewComponent spec**

```ruby
# spec/components/page_builder/field_group_component_spec.rb
require "rails_helper"

RSpec.describe PageBuilder::FieldGroupComponent, type: :component do
  it "renders a group container with label" do
    render_inline(described_class.new(label: "Address", group_id: "group_123"))
    expect(page).to have_css("[data-group-id='group_123']")
    expect(page).to have_text("Address")
  end

  it "renders with dashed border by default" do
    render_inline(described_class.new(label: "Test", group_id: "group_abc"))
    expect(page).to have_css(".border-dashed")
  end

  it "includes ungroup action" do
    render_inline(described_class.new(label: "Test", group_id: "group_abc"))
    expect(page).to have_css("[data-action*='ungroupFields']")
  end
end
```

- [ ] **Step 2: Write the component**

```ruby
class PageBuilder::FieldGroupComponent < ApplicationComponent
  def initialize(label:, group_id:, border: "dashed", background: "none")
    @label = label
    @group_id = group_id
    @border = border
    @background = background
  end
  attr_reader :label, :group_id, :border, :background

  def border_class
    case @border
    when "dashed" then "border-dashed border-gray-300"
    when "solid" then "border-solid border-gray-300"
    when "subtle" then "border-solid border-gray-200"
    else "border-transparent"
    end
  end

  def bg_class
    case @background
    when "light_gray" then "bg-gray-50"
    when "light_blue" then "bg-blue-50/30"
    else "bg-transparent"
    end
  end
end
```

```erb
<%# app/components/page_builder/field_group_component.html.erb %>
<div class="field-group border-2 <%= border_class %> <%= bg_class %> rounded-lg p-2 space-y-1"
     data-group-id="<%= group_id %>"
     data-field-id="<%= group_id %>">
  <div class="flex items-center justify-between mb-1">
    <span class="text-xs font-semibold text-gray-600 truncate"
          data-action="dblclick->page-builder#startInlineEdit"
          data-inline-edit-property="label"><%= label %></span>
    <div class="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
      <button type="button" class="text-[10px] text-gray-400 hover:text-indigo-500 px-1"
              data-action="click->page-builder#ungroupFields" data-group-id="<%= group_id %>">Ungroup</button>
      <button type="button" class="text-[10px] text-gray-400 hover:text-gray-600 px-1 disabled:opacity-30"
              disabled title="Available in a future update">Save as Template</button>
    </div>
  </div>
  <div class="grid grid-cols-12 gap-1" data-group-fields-container="<%= group_id %>">
    <%# Child field cards rendered by JS %>
  </div>
</div>
```

- [ ] **Step 3: Run spec**

```bash
bundle exec rspec spec/components/page_builder/field_group_component_spec.rb -v
```

- [ ] **Step 4: Add field_group as a recognized type in field_manager.js**

Update `renderFields()` to detect `field_group` type entries in the fields array and render them as group containers with nested fields:

```javascript
// In renderFields(), when iterating fields:
if (field.type === "field_group") {
  this._renderFieldGroup(field)
  continue
}
```

Add `_renderFieldGroup(group)`:

```javascript
_renderFieldGroup(group) {
  const container = this.c.fieldsContainerTarget
  const colSpanClass = WIDTH_CLASSES[group.width || "full"] || "col-span-12"

  const groupDiv = document.createElement("div")
  groupDiv.className = `field-group group border-2 border-dashed border-gray-300 rounded-lg p-2 space-y-1 ${colSpanClass}`
  groupDiv.dataset.groupId = group.id
  groupDiv.dataset.fieldId = group.id

  // Group header
  groupDiv.innerHTML = `
    <div class="flex items-center justify-between mb-1">
      <span class="text-xs font-semibold text-gray-600 truncate"
            data-action="dblclick->page-builder#startInlineEdit"
            data-inline-edit-property="label">${group.label || "Field Group"}</span>
      <div class="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
        <button type="button" class="text-[10px] text-gray-400 hover:text-indigo-500 px-1"
                data-action="click->page-builder#ungroupFields" data-group-id="${group.id}">Ungroup</button>
        <button type="button" class="text-[10px] text-gray-400 hover:text-gray-600 px-1 disabled:opacity-30"
                disabled title="Available in a future update">Save as Template</button>
      </div>
    </div>
  `

  // Nested fields grid
  const nestedGrid = document.createElement("div")
  nestedGrid.className = "grid grid-cols-12 gap-1"
  nestedGrid.dataset.groupFieldsContainer = group.id

  ;(group.fields || []).forEach(field => {
    const card = this.createFieldCard(field)
    nestedGrid.appendChild(card)
  })

  groupDiv.appendChild(nestedGrid)
  container.appendChild(groupDiv)
}
```

- [ ] **Step 5: Update groupIntoSection → groupFields in selection_manager.js**

Replace the existing `groupIntoSection()` method (from Phase 1) with `groupFields()`:

```javascript
groupFields() {
  const selected = this.getSelectedFields()
  if (selected.length < 2) return

  this.c.saveState()

  const fields = this.c.currentPageFields
  const selectedIds = new Set(selected.map(f => f.id))
  const firstIdx = fields.findIndex(f => selectedIds.has(f.id))

  // Remove selected fields from the array
  const groupedFields = fields.filter(f => selectedIds.has(f.id))
  this.c.currentPage.fields = fields.filter(f => !selectedIds.has(f.id))

  // Create group node
  const group = {
    id: `group_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`,
    type: "field_group",
    label: "Field Group",
    width: "full",
    style: { border: "dashed", padding: "normal", background: "none" },
    fields: groupedFields
  }

  // Insert at original position
  const adjustedIdx = Math.min(firstIdx, this.c.currentPage.fields.length)
  this.c.currentPage.fields.splice(adjustedIdx, 0, group)

  this.deselectAll()
  this.c.fieldManager.renderFields()
  this.c.saveManager.markDirty()
}
```

Update the controller delegation:
```javascript
groupIntoSection() { this.selectionManager.groupFields() }
```

- [ ] **Step 6: Add ungroupFields method**

In `field_manager.js`:

```javascript
ungroupFields(event) {
  event.stopPropagation()
  const groupId = event.currentTarget.dataset.groupId
  const fields = this.c.currentPageFields
  const groupIdx = fields.findIndex(f => f.id === groupId && f.type === "field_group")
  if (groupIdx === -1) return

  this.c.saveState()

  const group = fields[groupIdx]
  const ungroupedFields = group.fields || []

  // Replace group with its children
  fields.splice(groupIdx, 1, ...ungroupedFields)

  this.renderFields()
  this.c.saveManager.markDirty()
}
```

Add delegation: `ungroupFields(event) { this.fieldManager.ungroupFields(event) }`

- [ ] **Step 7: Add group property panel support**

When a field group is selected, the property panel should show Content and Layout tabs (like layout elements). In `property_manager.js`, detect `field.type === "field_group"`:

```javascript
// In populatePropertyPanel:
const isGroup = field.type === "field_group"
const category = isGroup ? "layout" : (isColumns ? "columns" : (isLayout ? "layout" : "data"))
```

The Content tab shows: Group label, description.
The Style tab shows: Width, border style (dashed/solid/subtle/none), background tint (none/light_gray/light_blue), padding.

- [ ] **Step 8: Add nesting constraints to drag_drop_manager**

In `drag_drop_manager.js`, when handling drops, enforce:
- Field groups can be placed inside columns
- Columns CANNOT be placed inside field groups
- Field groups CANNOT be nested inside other field groups

```javascript
// In the drop handler, check if target is inside a group:
const targetGroup = event.target.closest("[data-group-id]")
if (targetGroup && draggedData.type === "columns") {
  return // Columns can't go in groups
}
if (targetGroup && draggedData.type === "field_group") {
  return // Groups can't nest in groups
}
```

- [ ] **Step 9: Update allFields getter for groups**

In `page_builder_controller.js`, update the `allFields` getter to flatten group fields:

```javascript
get allFields() {
  const fields = this.configuration.pages?.flatMap(p => p.fields || []) || []
  return fields.flatMap(f => {
    if (f.field_type === "columns") return [f, ...f.columns.flatMap(c => c.fields || [])]
    if (f.type === "field_group") return [f, ...(f.fields || [])]
    return [f]
  })
}
```

- [ ] **Step 10: Test in browser**

- Multi-select 2+ fields → "Group into Section" button in floating bar
- Click → fields wrapped in a dashed-border group container
- Click group header → selects group, property panel shows group settings
- "Ungroup" button → dissolves group, fields remain in place
- Drag a field into/out of a group → works
- Try dragging a column into a group → blocked
- "Save as Template" button → disabled with tooltip

- [ ] **Step 11: Commit**

```bash
git add app/components/page_builder/field_group_component* spec/components/page_builder/field_group_component_spec.rb app/javascript/controllers/page_builder/field_manager.js app/javascript/controllers/page_builder/selection_manager.js app/javascript/controllers/page_builder/property_manager.js app/javascript/controllers/page_builder/drag_drop_manager.js app/javascript/controllers/page_builder_controller.js
git commit -m "feat(page-builder): add field groups with nesting constraints

Fields can be grouped into lightweight containers with label, border,
and background options. Drag-and-drop enforces nesting rules.
Save as Template disabled until Phase 3."
```

---

## Task 6: Final Precompile and Integration Test

**Files:** All modified JS and Ruby files

- [ ] **Step 1: Run all component specs**

```bash
bundle exec rspec spec/components/page_builder/ -v
```
Expected: All specs pass

- [ ] **Step 2: Precompile assets**

```bash
RAILS_ENV=development bundle exec rails assets:precompile
```

- [ ] **Step 3: Restart server and test**

```bash
pkill -f puma; sleep 1; RAILS_ENV=development bin/rails server -b 0.0.0.0 -p 3000 &
```

Full integration test at `/96546124/pages/32/edit`:

1. **Width system**: Verify 6 width options (Full, 3/4, 2/3, Half, 1/3, 1/4) in property panel and floating action bar
2. **High-fidelity previews**: Field cards show actual styled inputs matching theme. Change theme → previews update.
3. **Resize handles**: Select a data field → drag right edge → snaps to grid → tooltip shows width → grid lines appear
4. **Responsive editing**: Switch to tablet → canvas resizes → select field → Layout tab shows breakpoint buttons → set tablet width → "T" badge appears → switch to mobile → set mobile width → save → preview shows responsive layout
5. **Field groups**: Multi-select 3 fields → "Group into Section" → fields wrapped in group → ungroup → fields restored. Drag field into group → works. Drag column into group → blocked.
6. **Undo/redo**: After each operation, Ctrl+Z undoes, Ctrl+Shift+Z redoes
7. **Save**: Ctrl+S saves without errors

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(page-builder): Phase 2 complete - canvas overhaul

- High-fidelity theme-aware field previews
- Drag-to-resize handles with snap-to-grid
- Responsive breakpoint editing (desktop/tablet/mobile)
- Field groups with nesting constraints
- Width system expanded to 6 named widths"
```
