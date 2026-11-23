# Property Editor Refinements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move minimap to bottom-left, refine property editor sidebar to 420px with tighter "Refined Minimal" style, and fix 2 confirmed bugs.

**Architecture:** Pure CSS/Tailwind class changes for layout, JS label class updates for form styling, targeted JS fixes for debounce timeout and async race condition. No structural HTML changes.

**Tech Stack:** Rails ERB templates, TailwindCSS, StimulusJS

**Spec:** `docs/superpowers/specs/2026-04-16-property-editor-refinements-design.md`

---

### Task 1: Move Minimap to Bottom-Left

**Files:**
- Modify: `app/views/flowcharts/_editor.html.erb:244`

- [ ] **Step 1: Change minimap position class**

In `app/views/flowcharts/_editor.html.erb`, line 244, change `right-2` to `left-2`:

```erb
<!-- Before -->
<div data-flowchart-canvas-target="minimapContainer"
     class="absolute bottom-2 right-2 z-20 border border-slate-300 rounded-lg shadow-md bg-white overflow-hidden"
     style="width: 200px; height: 140px;">
</div>

<!-- After -->
<div data-flowchart-canvas-target="minimapContainer"
     class="absolute bottom-2 left-2 z-20 border border-slate-300 rounded-lg shadow-md bg-white overflow-hidden"
     style="width: 200px; height: 140px;">
</div>
```

- [ ] **Step 2: Verify in browser**

Open a flowchart with elements. Confirm minimap appears at the bottom-left of the canvas. Confirm it doesn't overlap with any toolbar or sidebar elements.

- [ ] **Step 3: Commit**

```bash
git add app/views/flowcharts/_editor.html.erb
git commit -m "Move minimap from bottom-right to bottom-left on canvas"
```

---

### Task 2: Narrow Property Editor Sidebar Width

**Files:**
- Modify: `app/views/flowcharts/_editor.html.erb:446-451`

- [ ] **Step 1: Update sidebar width and resize constraints**

In `app/views/flowcharts/_editor.html.erb`, update the sidebar container (around line 446):

```erb
<!-- Before -->
<div class="absolute right-0 top-0 bottom-0 z-30 bg-white border-l border-slate-200/80 shadow-2xl transform transition-transform duration-300 ease-in-out hidden"
     style="width: 500px;"
     data-controller="property-editor panel-resize"
     data-panel-resize-min-width-value="400"
     data-panel-resize-max-width-value="700"
     data-panel-resize-default-width-value="500"

<!-- After -->
<div class="absolute right-0 top-0 bottom-0 z-30 bg-white border-l border-slate-200/80 shadow-2xl transform transition-transform duration-300 ease-in-out hidden"
     style="width: 420px;"
     data-controller="property-editor panel-resize"
     data-panel-resize-min-width-value="360"
     data-panel-resize-max-width-value="520"
     data-panel-resize-default-width-value="420"
```

- [ ] **Step 2: Verify in browser**

Open a flowchart, double-click an element. Confirm the sidebar is noticeably narrower. Confirm resize drag handle works within the new 360-520px range.

- [ ] **Step 3: Commit**

```bash
git add app/views/flowcharts/_editor.html.erb
git commit -m "Narrow property editor sidebar to 420px (360-520px range)"
```

---

### Task 3: Refine Property Editor Spacing (Refined Minimal)

**Files:**
- Modify: `app/views/flowcharts/_editor.html.erb:466,493,509,510,514,519,524,525,529`

- [ ] **Step 1: Tighten header padding and icon size**

In `_editor.html.erb`, update the header section (around line 466):

```erb
<!-- Before -->
<div class="px-5 pt-4 pb-3 flex items-start justify-between">
  ...
  <div data-property-editor-target="typeIndicator"
       class="w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0 ring-1 ring-black/5"

<!-- After -->
<div class="px-4 pt-3 pb-2 flex items-start justify-between">
  ...
  <div data-property-editor-target="typeIndicator"
       class="w-8 h-8 rounded-xl flex items-center justify-center flex-shrink-0 ring-1 ring-black/5"
```

- [ ] **Step 2: Tighten tab bar padding**

In `_editor.html.erb`, update the tab bar wrapper (around line 493):

```erb
<!-- Before -->
<div class="px-5 pb-3" data-property-editor-target="tabBar">

<!-- After -->
<div class="px-4 pb-2" data-property-editor-target="tabBar">
```

- [ ] **Step 3: Tighten tab pane padding and field spacing**

Update all four tab panes in `_editor.html.erb`:

```erb
<!-- Before (General, around line 509-510) -->
<div class="flex-1 overflow-y-auto px-5 py-4" data-property-editor-target="tabPaneGeneral">
  <div data-property-editor-target="formFieldsGeneral" class="space-y-4"></div>

<!-- After -->
<div class="flex-1 overflow-y-auto px-4 py-3" data-property-editor-target="tabPaneGeneral">
  <div data-property-editor-target="formFieldsGeneral" class="space-y-3"></div>
```

```erb
<!-- Before (Steps, around line 514) -->
<div class="flex-1 overflow-y-auto px-5 py-4 hidden" data-property-editor-target="tabPaneSteps">
  <div data-property-editor-target="formFieldsSteps" class="space-y-4"></div>

<!-- After -->
<div class="flex-1 overflow-y-auto px-4 py-3 hidden" data-property-editor-target="tabPaneSteps">
  <div data-property-editor-target="formFieldsSteps" class="space-y-3"></div>
```

```erb
<!-- Before (I/O, around line 519) -->
<div class="flex-1 overflow-y-auto px-5 py-4 hidden" data-property-editor-target="tabPaneIo">
  <div data-property-editor-target="formFieldsIo" class="space-y-4"></div>

<!-- After -->
<div class="flex-1 overflow-y-auto px-4 py-3 hidden" data-property-editor-target="tabPaneIo">
  <div data-property-editor-target="formFieldsIo" class="space-y-3"></div>
```

```erb
<!-- Before (Advanced, around line 524-525) -->
<div class="flex-1 overflow-y-auto px-5 py-4 hidden" data-property-editor-target="tabPaneAdvanced">
  <div data-property-editor-target="formFieldsAdvanced" class="grid grid-cols-2 gap-4"></div>

<!-- After -->
<div class="flex-1 overflow-y-auto px-4 py-3 hidden" data-property-editor-target="tabPaneAdvanced">
  <div data-property-editor-target="formFieldsAdvanced" class="grid grid-cols-2 gap-3"></div>
```

- [ ] **Step 4: Tighten footer padding**

Update the footer section (around line 529):

```erb
<!-- Before -->
<div class="flex items-center justify-end gap-3 px-5 py-3.5 border-t border-slate-100 bg-slate-50/50 flex-shrink-0">

<!-- After -->
<div class="flex items-center justify-end gap-3 px-4 py-3 border-t border-slate-100 bg-slate-50/50 flex-shrink-0">
```

- [ ] **Step 5: Verify in browser**

Open property editor for different element types. Confirm spacing is tighter and consistent. Check that all tabs render properly and the footer doesn't overlap content.

- [ ] **Step 6: Commit**

```bash
git add app/views/flowcharts/_editor.html.erb
git commit -m "Tighten property editor spacing for refined minimal aesthetic"
```

---

### Task 4: Unify Form Label Styling

**Files:**
- Modify: `app/javascript/controllers/property_editor/form_builder.js:240-242`
- Modify: `app/javascript/controllers/property_editor/templates.js` (multiple label lines)

- [ ] **Step 1: Update label classes in form_builder.js**

In `form_builder.js`, lines 240-242, unify the label color. The label element at line 277 already uses `text-xs ... tracking-wide uppercase`. Update the color variable to use a single consistent color:

```javascript
// Before (lines 240-242)
    const labelClass = fieldSchema.required
      ? "font-medium text-slate-800"
      : "font-medium text-slate-500"

// After
    const labelClass = "font-medium text-slate-500"
```

This works because required fields already show a red `*` indicator — they don't need a darker label color too. The label element at line 277 already applies `text-xs tracking-wide uppercase`.

- [ ] **Step 2: Update label classes in templates.js — step modal**

In `templates.js`, update the step modal "Keyword Parameters" label (line 83):

```javascript
// Before (line 83)
                <label class="block text-sm font-medium text-slate-700 mb-1">

// After
                <label class="block text-xs font-medium text-slate-500 mb-1.5 tracking-wide uppercase">
```

Update the step modal "Description" label (line 162):

```javascript
// Before (line 162)
                <label class="block text-sm font-medium text-slate-700 mb-1">

// After
                <label class="block text-xs font-medium text-slate-500 mb-1.5 tracking-wide uppercase">
```

- [ ] **Step 3: Update label classes in templates.js — branch modal**

Update the branch modal "Branch Name" label (line 569):

```javascript
// Before (line 569)
                <label class="block text-[10px] font-medium text-slate-600 mb-1">Branch Name</label>

// After
                <label class="block text-[10px] font-medium text-slate-500 mb-1 tracking-wide uppercase">Branch Name</label>
```

Update the "Branch Description" label (line 578):

```javascript
// Before (line 578)
                <label class="block text-sm font-medium text-slate-700 mb-1">

// After
                <label class="block text-xs font-medium text-slate-500 mb-1.5 tracking-wide uppercase">
```

Update the "Condition Type" label (line 590):

```javascript
// Before (line 590)
                <label class="block text-sm font-medium text-slate-700 mb-1">

// After
                <label class="block text-xs font-medium text-slate-500 mb-1.5 tracking-wide uppercase">
```

- [ ] **Step 4: Update label classes in templates.js — error handling**

Update the "Error Handling" label (line 825):

```javascript
// Before (line 825)
      <label class="block text-sm font-medium text-slate-700 mb-2">Error Handling</label>

// After
      <label class="block text-xs font-medium text-slate-500 mb-2 tracking-wide uppercase">Error Handling</label>
```

- [ ] **Step 5: Verify in browser**

Open property editor for a Process element (has steps). Check General tab labels are uniform uppercase micro-labels. Open step modal — check labels are consistent. Open a Decision element — check branch modal labels. Check Advanced tab error handling labels.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/property_editor/form_builder.js app/javascript/controllers/property_editor/templates.js
git commit -m "Unify form labels to refined minimal uppercase micro-label style"
```

---

### Task 5: Fix Sync Timeout Not Cleared on Disconnect

**Files:**
- Modify: `app/javascript/controllers/property_editor_controller.js:80-83`

- [ ] **Step 1: Add timeout cleanup to disconnect()**

In `property_editor_controller.js`, update the `disconnect()` method (around line 80):

```javascript
// Before
  disconnect() {
    document.removeEventListener("keydown", this._boundHandleKeydown)
    this._removeFormChangeListeners()
  }

// After
  disconnect() {
    if (this._syncTimeout) clearTimeout(this._syncTimeout)
    document.removeEventListener("keydown", this._boundHandleKeydown)
    this._removeFormChangeListeners()
  }
```

- [ ] **Step 2: Commit**

```bash
git add app/javascript/controllers/property_editor_controller.js
git commit -m "Fix: clear sync debounce timeout on property editor disconnect"
```

---

### Task 6: Fix Async Race Condition in Entity Change

**Files:**
- Modify: `app/javascript/controllers/property_editor/branch_manager.js:17-19,136-166`

- [ ] **Step 1: Add fetch counter to constructor**

In `branch_manager.js`, update the constructor (around line 16-19):

```javascript
// Before
export class BranchManager extends BaseManager {
  constructor(controller) {
    super(controller, 'branchIndex')
    this._availableOutputOptions = []
  }

// After
export class BranchManager extends BaseManager {
  constructor(controller) {
    super(controller, 'branchIndex')
    this._availableOutputOptions = []
    this._entityFetchId = 0
  }
```

- [ ] **Step 2: Guard the async response**

In `branch_manager.js`, update `onQueryCountEntityChange()` (around line 136):

```javascript
// Before
  async onQueryCountEntityChange(event) {
    const entityId = event.target.value
    const modal = event.target.closest("[data-branch-modal]")
    if (!modal) return

    const whereRows = modal.querySelector("[data-branch-qc-where-rows]")
    if (!whereRows) return

    // Clear existing WHERE rows
    whereRows.innerHTML = ""

    if (!entityId) return

    // Fetch entity schema for field options
    const customerId = this.controller.canvas?.customerIdValue
    if (!customerId) return

    try {
      const response = await fetch(`/${customerId}/entities/${entityId}.json`, {
        headers: { "Accept": "application/json" }
      })
      if (!response.ok) return

      const entity = await response.json()
      this._selectedEntitySchema = entity.property_schema || []
      this._selectedEntityName = entity.name || ""

      // Add one empty WHERE row
      this._addQueryCountWhereRow(whereRows)
    } catch (e) {
      // Silently fail

// After
  async onQueryCountEntityChange(event) {
    const entityId = event.target.value
    const modal = event.target.closest("[data-branch-modal]")
    if (!modal) return

    const whereRows = modal.querySelector("[data-branch-qc-where-rows]")
    if (!whereRows) return

    // Clear existing WHERE rows
    whereRows.innerHTML = ""

    if (!entityId) return

    // Fetch entity schema for field options
    const customerId = this.controller.canvas?.customerIdValue
    if (!customerId) return

    const fetchId = ++this._entityFetchId

    try {
      const response = await fetch(`/${customerId}/entities/${entityId}.json`, {
        headers: { "Accept": "application/json" }
      })
      if (!response.ok) return
      if (fetchId !== this._entityFetchId) return

      const entity = await response.json()
      this._selectedEntitySchema = entity.property_schema || []
      this._selectedEntityName = entity.name || ""

      // Add one empty WHERE row
      this._addQueryCountWhereRow(whereRows)
    } catch (e) {
      // Silently fail
```

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/property_editor/branch_manager.js
git commit -m "Fix: prevent async race condition in query count entity change"
```

---

### Task 7: Final Verification

- [ ] **Step 1: Full verification pass**

Open a flowchart with multiple element types. Verify:
1. Minimap is at bottom-left
2. Property editor is narrower (420px default)
3. All labels use consistent uppercase micro-label style
4. Spacing is tighter throughout the sidebar
5. Resize handle works within 360-520px range
6. All tabs (General, Steps, I/O, Advanced) render correctly
7. Step modal and branch modal labels are consistent
8. Save/Cancel buttons work
9. Connection editor still works (double-click a connection line)

- [ ] **Step 2: Run existing test suite**

```bash
bundle exec rspec spec/ --format documentation 2>&1 | tail -20
```

Expect: no new failures introduced.
