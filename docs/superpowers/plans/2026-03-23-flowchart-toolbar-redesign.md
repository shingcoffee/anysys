# Flowchart Toolbar Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize the flowchart editor toolbar from a cluttered single row into a clean two-row layout with logically grouped actions and dropdown menus.

**Architecture:** Replace the toolbar section (lines 11-197) in `_editor.html.erb` with a two-row layout. Row 1: Save/Undo/Redo + flowchart name + zoom. Row 2: View/Tools/Export dropdowns. Update `toolbar_controller.js` to use a dot indicator instead of text status. Clean up dead code.

**Tech Stack:** ERB, TailwindCSS, StimulusJS (existing `toolbar` + `dropdown` + `flowchart-canvas` controllers)

**Spec:** `docs/superpowers/specs/2026-03-23-flowchart-toolbar-redesign.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `app/views/flowcharts/_editor.html.erb` | Modify lines 11-197 | Two-row toolbar HTML |
| `app/javascript/controllers/toolbar_controller.js` | Modify | Save dot indicator, dead code cleanup |
| `spec/system/flowchart_management_spec.rb` | Modify line ~126 | Update toolbar assertions for icon-only buttons |

---

### Task 1: Update toolbar_controller.js — Save dot indicator + dead code cleanup

**Files:**
- Modify: `app/javascript/controllers/toolbar_controller.js`

- [ ] **Step 1: Remove dead code and update targets**

Replace the full `static targets` declaration and remove dead methods. The new controller should have these changes:
- Replace `saveStatus` with `saveDot` in targets
- Remove `nameInput` from targets
- Keep `undoButton`, `redoButton`, `zoomLevel`

In `app/javascript/controllers/toolbar_controller.js`, replace the targets array:

```javascript
static targets = [
  "saveDot",
  "undoButton",
  "redoButton",
  "zoomLevel"
]
```

Remove `connect()` line: `this.nameInputDebounceTimer = null`

Remove these methods entirely:
- `updateName(event)` (lines 160-171)
- `_saveNameChange(name)` (lines 202-219)
- `_clearDebounceTimer()` (lines 307-312)

Update `disconnect()` to remove the `this._clearDebounceTimer()` call.

- [ ] **Step 2: Update save status methods to use dot indicator**

Replace `_updateSaveStatus`:
```javascript
_updateSaveStatus() {
  if (!this.hasSaveDotTarget) return

  if (this.hasUnsavedChanges) {
    this.saveDotTarget.className = "absolute -top-0.5 -right-0.5 w-2 h-2 rounded-full bg-amber-500"
  } else {
    this.saveDotTarget.classList.add("hidden")
  }
}
```

Replace `_showSaving`:
```javascript
_showSaving() {
  if (!this.hasSaveDotTarget) return
  this.saveDotTarget.className = "absolute -top-0.5 -right-0.5 w-2 h-2 rounded-full bg-blue-500 animate-pulse"
}
```

Replace `_showSaveSuccess`:
```javascript
_showSaveSuccess() {
  if (this.hasSaveDotTarget) {
    this.saveDotTarget.className = "absolute -top-0.5 -right-0.5 w-2 h-2 rounded-full bg-green-500"
    setTimeout(() => this._updateSaveStatus(), 3000)
  }
  this._showNotification("Flowchart saved successfully", "success")
}
```

Replace `_showSaveError`:
```javascript
_showSaveError(errors = []) {
  if (this.hasSaveDotTarget) {
    this.saveDotTarget.className = "absolute -top-0.5 -right-0.5 w-2 h-2 rounded-full bg-red-500"
    setTimeout(() => this._updateSaveStatus(), 5000)
  }

  const errorMessage = errors.length > 0
    ? errors.join(", ")
    : "Failed to save flowchart"
  this._showNotification(errorMessage, "error")
}
```

- [ ] **Step 3: Verify JS has no syntax errors**

Run: `node -c app/javascript/controllers/toolbar_controller.js`
Expected: no errors

- [ ] **Step 4: Commit**

```
git add app/javascript/controllers/toolbar_controller.js
git commit -m "refactor: update toolbar controller for dot indicator and remove dead code"
```

---

### Task 2: Replace toolbar HTML with two-row layout

**Files:**
- Modify: `app/views/flowcharts/_editor.html.erb` (lines 11-197)

- [ ] **Step 1: Replace the toolbar section**

Replace lines 11-197 (from `<!-- Top Toolbar -->` through the closing `</div>` of the toolbar) with the following two-row toolbar. Everything below line 197 (canvas area, sidebars, panels) stays unchanged.

```erb
  <!-- Top Toolbar -->
  <div class="bg-white border-b border-gray-200 flex-shrink-0" data-controller="toolbar">

    <!-- Row 1: Primary actions + Name + Zoom -->
    <div class="px-4 py-2 flex items-center justify-between border-b border-gray-100">

      <!-- Left: Save, Undo, Redo -->
      <div class="flex items-center space-x-2">
        <button data-action="click->toolbar#save"
                title="Save"
                class="relative inline-flex items-center p-2 border border-transparent rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-600 transition-colors">
          <svg class="h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3-3m0 0l-3 3m3-3v12" />
          </svg>
          <span data-toolbar-target="saveDot"
                class="absolute -top-0.5 -right-0.5 w-2 h-2 rounded-full bg-amber-500 hidden"></span>
        </button>

        <div class="w-px h-6 bg-gray-200 mx-1"></div>

        <button data-action="click->toolbar#undo"
                data-toolbar-target="undoButton"
                title="Undo"
                class="inline-flex items-center p-2 border border-gray-300 shadow-sm rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed transition-colors">
          <svg class="h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 10h10a8 8 0 018 8v2M3 10l6 6m-6-6l6-6" />
          </svg>
        </button>

        <button data-action="click->toolbar#redo"
                data-toolbar-target="redoButton"
                title="Redo"
                class="inline-flex items-center p-2 border border-gray-300 shadow-sm rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed transition-colors">
          <svg class="h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 10H11a8 8 0 00-8 8v2m18-10l-6-6m6 6l-6 6" />
          </svg>
        </button>
      </div>

      <!-- Center: Flowchart name -->
      <div class="flex-1 max-w-md mx-8">
        <%= link_to @flowchart.name, flowchart_path(@flowchart.customer_id || current_customer_id, @flowchart),
            class: "block w-full text-lg font-medium text-gray-900 hover:text-indigo-600 text-center py-1 transition-colors",
            title: "View flowchart details" %>
      </div>

      <!-- Right: Zoom controls -->
      <div class="flex items-center space-x-1">
        <button data-action="click->toolbar#zoomOut"
                title="Zoom Out (Ctrl+-)"
                class="inline-flex items-center p-2 border border-gray-300 shadow-sm rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 transition-colors">
          <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0zM13 10H7" />
          </svg>
        </button>

        <span data-toolbar-target="zoomLevel" class="text-sm text-gray-600 font-mono w-12 text-center select-none">100%</span>

        <button data-action="click->toolbar#zoomIn"
                title="Zoom In (Ctrl++)"
                class="inline-flex items-center p-2 border border-gray-300 shadow-sm rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 transition-colors">
          <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0zM10 7v3m0 0v3m0-3h3m-3 0H7" />
          </svg>
        </button>

        <button data-action="click->toolbar#fitToContent"
                title="Fit to Content"
                class="inline-flex items-center p-2 border border-gray-300 shadow-sm rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 transition-colors">
          <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 8V4m0 0h4M4 4l5 5m11-1V4m0 0h-4m4 0l-5 5M4 16v4m0 0h4m-4 0l5-5m11 5l-5-5m5 5v-4m0 4h-4" />
          </svg>
        </button>
      </div>
    </div>

    <!-- Row 2: Dropdown menus -->
    <div class="px-4 py-1.5 flex items-center space-x-2">

      <!-- View dropdown -->
      <div class="relative" data-controller="dropdown">
        <button data-action="click->dropdown#toggle"
                class="inline-flex items-center px-2.5 py-1.5 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 transition-colors">
          <svg class="mr-1.5 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z" />
          </svg>
          View
          <svg class="ml-1.5 h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
          </svg>
        </button>
        <div data-dropdown-target="menu"
             class="hidden absolute left-0 mt-1 w-48 rounded-md shadow-lg bg-white ring-1 ring-black/5 z-10">
          <div class="py-1">
            <button data-action="click->flowchart-canvas#validate click->dropdown#close"
                    class="w-full text-left px-3 py-2 text-sm text-gray-700 hover:bg-gray-50 flex items-center">
              <svg class="mr-2 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              Validate
              <span data-flowchart-canvas-target="validationBadge"
                    class="ml-auto inline-flex items-center px-1.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800 hidden">0</span>
            </button>
            <button data-action="click->flowchart-canvas#toggleTestPanel click->dropdown#close"
                    class="w-full text-left px-3 py-2 text-sm text-gray-700 hover:bg-gray-50 flex items-center">
              <svg class="mr-2 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z" />
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              Run Test
            </button>
            <button data-action="click->flowchart-canvas#toggleVersionPanel click->dropdown#close"
                    class="w-full text-left px-3 py-2 text-sm text-gray-700 hover:bg-gray-50 flex items-center">
              <svg class="mr-2 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              History
            </button>
            <button data-action="click->flowchart-canvas#toggleElementsPanel click->dropdown#close"
                    class="w-full text-left px-3 py-2 text-sm text-gray-700 hover:bg-gray-50 flex items-center">
              <svg class="mr-2 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 10h16M4 14h16M4 18h16" />
              </svg>
              Elements
            </button>
          </div>
        </div>
      </div>

      <!-- Tools dropdown -->
      <div class="relative" data-controller="dropdown">
        <button data-action="click->dropdown#toggle"
                class="inline-flex items-center px-2.5 py-1.5 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 transition-colors">
          <svg class="mr-1.5 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.066 2.573c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.573 1.066c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.066-2.573c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
          </svg>
          Tools
          <svg class="ml-1.5 h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
          </svg>
        </button>
        <div data-dropdown-target="menu"
             class="hidden absolute left-0 mt-1 w-48 rounded-md shadow-lg bg-white ring-1 ring-black/5 z-10">
          <div class="py-1">
            <button data-action="click->toolbar#autoLayout click->dropdown#close"
                    class="w-full text-left px-3 py-2 text-sm text-gray-700 hover:bg-gray-50 flex items-center">
              <svg class="mr-2 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 5a1 1 0 011-1h4a1 1 0 011 1v7a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM14 5a1 1 0 011-1h4a1 1 0 011 1v7a1 1 0 01-1 1h-4a1 1 0 01-1-1V5zM4 16a1 1 0 011-1h4a1 1 0 011 1v3a1 1 0 01-1 1H5a1 1 0 01-1-1v-3zM14 16a1 1 0 011-1h4a1 1 0 011 1v3a1 1 0 01-1 1h-4a1 1 0 01-1-1v-3z" />
              </svg>
              Auto Layout
            </button>
            <button data-action="click->toolbar#cycleConnectionRouting click->dropdown#close"
                    class="w-full text-left px-3 py-2 text-sm text-gray-700 hover:bg-gray-50 flex items-center">
              <svg class="mr-2 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
              </svg>
              Connection Routing
            </button>
            <button data-action="click->flowchart-canvas#generateDocs click->dropdown#close"
                    class="w-full text-left px-3 py-2 text-sm text-gray-700 hover:bg-gray-50 flex items-center">
              <svg class="mr-2 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
              </svg>
              Generate Docs
            </button>
            <div class="border-t border-gray-100 my-1"></div>
            <button data-action="click->toolbar#clear click->dropdown#close"
                    class="w-full text-left px-3 py-2 text-sm text-red-600 hover:bg-red-50 flex items-center">
              <svg class="mr-2 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
              </svg>
              Clear Canvas
            </button>
          </div>
        </div>
      </div>

      <!-- Export dropdown -->
      <div class="relative" data-controller="dropdown">
        <button data-action="click->dropdown#toggle"
                class="inline-flex items-center px-2.5 py-1.5 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 transition-colors">
          <svg class="mr-1.5 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
          </svg>
          Export
          <svg class="ml-1.5 h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
          </svg>
        </button>
        <div data-dropdown-target="menu"
             class="hidden absolute left-0 mt-1 w-48 rounded-md shadow-lg bg-white ring-1 ring-black/5 z-10">
          <div class="py-1">
            <button data-action="click->toolbar#exportSVG click->dropdown#close"
                    class="w-full text-left px-3 py-2 text-sm text-gray-700 hover:bg-gray-50 flex items-center">
              <svg class="mr-2 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z" />
              </svg>
              Export as SVG
            </button>
            <button data-action="click->toolbar#exportPNG click->dropdown#close"
                    class="w-full text-left px-3 py-2 text-sm text-gray-700 hover:bg-gray-50 flex items-center">
              <svg class="mr-2 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
              </svg>
              Export as PNG
            </button>
          </div>
        </div>
      </div>

    </div>
  </div>
```

- [ ] **Step 2: Verify the ERB template has no syntax errors**

Run: `ruby -rerb -e "ERB.new(File.read('app/views/flowcharts/_editor.html.erb')).result_with_hash({})" 2>&1 | head -5`

Expected: may show runtime errors (missing variables) but should NOT show ERB syntax errors.

- [ ] **Step 3: Commit**

```
git add app/views/flowcharts/_editor.html.erb
git commit -m "feat: replace toolbar with two-row grouped layout"
```

---

### Task 3: Update system test for icon-only buttons

**Files:**
- Modify: `spec/system/flowchart_management_spec.rb` (~line 125-128)

- [ ] **Step 1: Update toolbar button assertions**

The old test checks `have_button('Save')`, `have_button('Undo')`, `have_button('Redo')` which match by text content. Since buttons are now icon-only, update to check by title attribute:

Find lines 125-132:
```ruby
      # Check toolbar
      expect(page).to have_button('Save')
      expect(page).to have_button('Undo')
      expect(page).to have_button('Redo')
      expect(page).to have_button('Clear')

      # Check flowchart name input
      expect(page).to have_field(value: 'Test Flow')
```

Replace with:
```ruby
      # Check toolbar - icon-only buttons found by title
      expect(page).to have_css('button[title="Save"]')
      expect(page).to have_css('button[title="Undo"]')
      expect(page).to have_css('button[title="Redo"]')

      # Check toolbar dropdown menus
      expect(page).to have_button('View')
      expect(page).to have_button('Tools')
      expect(page).to have_button('Export')

      # Check flowchart name link
      expect(page).to have_link('Test Flow')
```

- [ ] **Step 2: Run the system test**

Run: `bundle exec rspec spec/system/flowchart_management_spec.rb --format documentation`

Expected: tests pass (or existing failures unrelated to toolbar changes)

- [ ] **Step 3: Commit**

```
git add spec/system/flowchart_management_spec.rb
git commit -m "test: update toolbar assertions for icon-only buttons"
```

---

### Task 4: Compile assets and verify

- [ ] **Step 1: Compile JavaScript assets**

Run: `yarn build`
Expected: no errors

- [ ] **Step 2: Compile CSS assets**

Run: `yarn build:css`
Expected: no errors

- [ ] **Step 3: Manual verification**

Start the dev server and visit a flowchart edit page. Verify:
- Row 1: Save (indigo, icon-only with dot), Undo, Redo, centered flowchart name, zoom controls
- Row 2: View, Tools, Export dropdowns
- View dropdown opens and shows Validate (with badge slot), Run Test, History, Elements
- Tools dropdown shows Auto Layout, Connection Routing, Generate Docs, divider, Clear Canvas (red)
- Export dropdown shows Export as SVG, Export as PNG
- All buttons dispatch correct actions
- Save dot turns amber on changes, blue while saving, green on success, red on error
- Undo/Redo disable states work
- Zoom controls work
- Dropdowns close on outside click and Escape key
