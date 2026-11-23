# Editor Layout Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refine the flowchart editor layout with 5 changes: streamlined toolbar, narrower sidebars, tabbed bottom panel, and dot grid background for a Lucidchart/draw.io inspired professional feel.

**Architecture:** All changes are frontend-only. The main ERB template (`_editor.html.erb`) gets the largest rewrite touching toolbar, sidebar widths, element palette layout, and bottom panel consolidation. Two JS controllers get updated (toolbar overflow menu, panel tab logic). One JS canvas file gets a grid rendering change. One ViewComponent gets a layout tweak. No backend changes.

**Tech Stack:** TailwindCSS, StimulusJS, SVG, ViewComponent (Ruby)

**Spec:** `docs/superpowers/specs/2026-03-26-editor-layout-refinement-design.md`

---

## File Map

| File | Tasks | Purpose |
|------|-------|---------|
| `app/javascript/flowchart/canvas.js` | 1 | Replace line grid with dot grid |
| `app/views/flowcharts/_editor.html.erb` | 2, 3, 4, 5 | Sidebar widths, toolbar rewrite, tabbed bottom panel |
| `app/components/flowchart_elements/base_element_component.rb` | 3 | Update classes for horizontal row layout |
| `app/components/flowchart_elements/base_element_component.html.erb` | 3 | Change from vertical tile to horizontal row |
| `app/javascript/controllers/toolbar_controller.js` | 4 | Add overflow menu target + toggle methods |
| `app/javascript/controllers/flowchart_canvas_controller.js` | 5 | Add tabbed bottom panel logic, remove individual panel targets |

---

### Task 1: Canvas Dot Grid Background

Replace the line grid with a dot grid pattern in the SVG canvas.

**Files:**
- Modify: `app/javascript/flowchart/canvas.js:150-193`

- [ ] **Step 1: Replace `_drawGrid()` method**

In `app/javascript/flowchart/canvas.js`, replace the `_drawGrid()` method (lines 150-193). Change the pattern from a `<path>` (line grid) to a `<circle>` (dot grid). Keep the search highlight styles and the grid rect unchanged.

Replace lines 150-193:

```js
  _drawGrid() {
    const defs = createSvgElement("defs")
    const pattern = createSvgElement("pattern", {
      id: "grid-pattern",
      width: GRID_SIZE,
      height: GRID_SIZE,
      patternUnits: "userSpaceOnUse"
    })

    pattern.appendChild(createSvgElement("circle", {
      cx: GRID_SIZE / 2,
      cy: GRID_SIZE / 2,
      r: 1,
      fill: "#cbd5e1"
    }))

    defs.appendChild(pattern)

    // Add search highlight styles
    const style = createSvgElement("style")
    style.textContent = `
      .search-highlight rect,
      .search-highlight ellipse,
      .search-highlight polygon,
      .search-highlight path.shape-path {
        stroke-dasharray: 6 3;
        stroke-width: 3;
      }
      .search-current rect,
      .search-current ellipse,
      .search-current polygon,
      .search-current path.shape-path {
        stroke: #f59e0b !important;
        stroke-width: 3;
        stroke-dasharray: 6 3;
      }
    `
    defs.appendChild(style)

    this.svg.insertBefore(defs, this.svg.firstChild)

    this.gridLayer.appendChild(createRect(-10000, -10000, 20000, 20000, {
      fill: "url(#grid-pattern)"
    }))
  }
```

- [ ] **Step 2: Verify**

Open the flowchart editor. Confirm the canvas shows small gray dots instead of grid lines. Dots should be spaced 15px apart (GRID_SIZE). Pan and zoom to confirm the pattern tiles correctly.

---

### Task 2: Narrower Right Sidebar

Change the property editor sidebar from 448px to 320px.

**Files:**
- Modify: `app/views/flowcharts/_editor.html.erb:560`

- [ ] **Step 1: Change width class**

In `app/views/flowcharts/_editor.html.erb`, find line 560:

```html
    <div class="relative bg-white border-l border-gray-200 flex-shrink-0 transform transition-transform duration-300 ease-in-out w-[448px] hidden"
```

Replace `w-[448px]` with `w-[320px]`:

```html
    <div class="relative bg-white border-l border-gray-200 flex-shrink-0 transform transition-transform duration-300 ease-in-out w-[320px] hidden"
```

- [ ] **Step 2: Verify**

Open editor, double-click an element to open the property sidebar. Confirm it's narrower than before (320px). Confirm form fields render correctly at the smaller width. Confirm Save/Cancel buttons are still visible.

---

### Task 3: Compact Left Sidebar

Narrow the left sidebar from 256px to 140px, switch from 2-column grid to single-column rows, add unified search, and use uppercase section headers.

**Files:**
- Modify: `app/components/flowchart_elements/base_element_component.rb:22-24, 58-63`
- Modify: `app/components/flowchart_elements/base_element_component.html.erb`
- Modify: `app/views/flowcharts/_editor.html.erb:224-281`

- [ ] **Step 1: Update base_element_component.rb classes for horizontal row layout**

In `app/components/flowchart_elements/base_element_component.rb`, change 3 methods:

Replace `base_classes` (line 22-24):

```ruby
    def base_classes
      "flowchart-element bg-white border border-gray-200 rounded px-2 py-1.5 text-sm font-medium text-gray-700 cursor-pointer hover:border-blue-400 hover:shadow-sm transition-all duration-200 select-none"
    end
```

Replace `icon_classes` (line 58-60):

```ruby
    def icon_classes
      "w-4 h-4 flex-shrink-0"
    end
```

Replace `label_classes` (line 62-64):

```ruby
    def label_classes
      "text-xs leading-tight truncate"
    end
```

- [ ] **Step 2: Update base_element_component.html.erb to horizontal row**

Replace the entire content of `app/components/flowchart_elements/base_element_component.html.erb`:

```erb
<%= content_tag :div, html_attributes do %>
  <div class="flex items-center gap-2">
    <%= render_icon %>
    <div class="<%= label_classes %>">
      <%= label %>
    </div>
  </div>
<% end %>
```

- [ ] **Step 3: Update left sidebar in _editor.html.erb**

In `app/views/flowcharts/_editor.html.erb`, replace the left sidebar (lines 224-281) with:

```erb
    <!-- Left Sidebar - Element Palette -->
    <div class="w-[140px] bg-gray-50 border-r border-gray-200 flex flex-col flex-shrink-0 overflow-hidden"
         data-controller="element-palette"
         data-element-palette-current-flowchart-id-value="<%= @flowchart.id %>">

      <!-- Unified Search -->
      <div class="p-2">
        <div class="flex items-center rounded-lg border border-gray-200 bg-white px-2 focus-within:border-indigo-500 focus-within:ring-1 focus-within:ring-indigo-500">
          <svg class="h-3.5 w-3.5 flex-shrink-0 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
          </svg>
          <input type="text"
                 placeholder="Search..."
                 data-action="input->element-palette#searchFlowcharts"
                 data-element-palette-target="searchInput"
                 class="ml-1.5 h-7 w-full border-0 bg-transparent text-xs text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-0">
        </div>
      </div>

      <!-- Scrollable content -->
      <div class="flex-1 overflow-y-auto px-2 pb-2">

        <!-- Elements Section -->
        <div class="mb-3">
          <h3 class="text-[10px] font-medium uppercase tracking-wider text-gray-500 mb-1.5 px-1">Elements</h3>
          <div class="flex flex-col gap-1" data-element-palette-target="basicElements">
            <%= render FlowchartElements::StartElementComponent.new %>
            <%= render FlowchartElements::ProcessElementComponent.new %>
            <%= render FlowchartElements::DecisionElementComponent.new %>
            <%= render FlowchartElements::EndElementComponent.new %>
            <%= render FlowchartElements::LoopElementComponent.new %>
            <%= render FlowchartElements::ErrorHandlerElementComponent.new %>
            <%= render FlowchartElements::TimerElementComponent.new %>
          </div>
        </div>

        <!-- Flows Section -->
        <div>
          <h3 class="text-[10px] font-medium uppercase tracking-wider text-gray-500 mb-1.5 px-1">Flows</h3>
          <div class="flex flex-col gap-1" data-element-palette-target="flowchartsList">
            <div class="text-xs text-gray-400 py-1 text-center" data-element-palette-target="flowchartsPlaceholder">
              Loading...
            </div>
          </div>
        </div>

      </div>
    </div>
```

Note: The element order changed to match the spec: Start, Process, Decision, End, Loop, Error Handler, Timer.

- [ ] **Step 4: Verify**

Open the editor. Confirm:
1. Left sidebar is noticeably narrower (~140px)
2. Elements are single-column rows with icon + label side by side
3. Search bar is at the top
4. Section headers "ELEMENTS" and "FLOWS" are small, uppercase, gray
5. Canvas has more horizontal space
6. Drag-and-drop from sidebar to canvas still works
7. Double-click on sidebar element still adds to canvas

---

### Task 4: Streamlined Toolbar

Replace the dropdown-based toolbar with grouped pill buttons and an overflow menu.

**Files:**
- Modify: `app/views/flowcharts/_editor.html.erb:12-218`
- Modify: `app/javascript/controllers/toolbar_controller.js`

- [ ] **Step 1: Update toolbar_controller.js with overflow menu support**

In `app/javascript/controllers/toolbar_controller.js`, add `"overflowMenu"` to `static targets`:

```js
  static targets = [
    "saveDot",
    "undoButton",
    "redoButton",
    "zoomLevel",
    "overflowMenu"
  ]
```

Add `toggleOverflow` and `closeOverflow` methods after `cycleConnectionRouting` (after line 154):

```js
  toggleOverflow(event) {
    event.preventDefault()
    if (!this.hasOverflowMenuTarget) return
    this.overflowMenuTarget.classList.toggle("hidden")

    // Close on click outside
    if (!this.overflowMenuTarget.classList.contains("hidden")) {
      this._overflowCloseHandler = (e) => {
        if (!this.overflowMenuTarget.contains(e.target) && !event.currentTarget.contains(e.target)) {
          this.closeOverflow()
        }
      }
      setTimeout(() => document.addEventListener("click", this._overflowCloseHandler), 0)
    }
  }

  closeOverflow() {
    if (this.hasOverflowMenuTarget) {
      this.overflowMenuTarget.classList.add("hidden")
    }
    if (this._overflowCloseHandler) {
      document.removeEventListener("click", this._overflowCloseHandler)
      this._overflowCloseHandler = null
    }
  }
```

Also add cleanup in `disconnect()` (after line 39):

```js
  disconnect() {
    this._unbindCanvasEventListeners()
    this.element.closest("[data-controller~='flowchart-canvas']")?.removeEventListener("zoomChanged", this._onZoomChanged)
    if (this._overflowCloseHandler) {
      document.removeEventListener("click", this._overflowCloseHandler)
    }
  }
```

- [ ] **Step 2: Replace toolbar HTML in _editor.html.erb**

In `app/views/flowcharts/_editor.html.erb`, replace the entire toolbar section (lines 12-218) with:

```erb
  <!-- Top Toolbar -->
  <div class="bg-white border-b border-gray-200 flex-shrink-0" data-controller="toolbar">
    <div class="px-3 py-1.5 flex items-center">

      <!-- Left: Save + Undo/Redo pill group -->
      <div class="flex items-center gap-0.5 bg-gray-100 rounded-lg p-0.5">
        <button data-action="click->toolbar#save"
                title="Save"
                class="relative inline-flex items-center px-3 py-1.5 rounded-md text-white bg-indigo-600 hover:bg-indigo-700 transition-colors text-xs font-medium">
          <svg class="h-3.5 w-3.5 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3-3m0 0l-3 3m3-3v12" />
          </svg>
          Save
          <span data-toolbar-target="saveDot"
                class="absolute -top-0.5 -right-0.5 w-2 h-2 rounded-full bg-amber-500 hidden"></span>
        </button>
        <button data-action="click->toolbar#undo"
                data-toolbar-target="undoButton"
                title="Undo (Ctrl+Z)"
                class="p-1.5 rounded-md text-gray-500 hover:text-gray-900 hover:bg-white disabled:opacity-40 disabled:cursor-not-allowed transition-colors">
          <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 10h10a8 8 0 018 8v2M3 10l6 6m-6-6l6-6" />
          </svg>
        </button>
        <button data-action="click->toolbar#redo"
                data-toolbar-target="redoButton"
                title="Redo (Ctrl+Y)"
                class="p-1.5 rounded-md text-gray-500 hover:text-gray-900 hover:bg-white disabled:opacity-40 disabled:cursor-not-allowed transition-colors">
          <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 10H11a8 8 0 00-8 8v2m18-10l-6-6m6 6l-6 6" />
          </svg>
        </button>
      </div>

      <!-- Divider -->
      <div class="w-px h-5 bg-gray-200 mx-3"></div>

      <!-- Center: Flowchart name -->
      <div class="flex-1 min-w-0 text-center">
        <%= link_to @flowchart.name, flowchart_path(@flowchart.customer_id || current_customer_id, @flowchart),
            class: "text-sm font-semibold text-gray-900 hover:text-indigo-600 transition-colors truncate",
            title: "View flowchart details" %>
      </div>

      <!-- Divider -->
      <div class="w-px h-5 bg-gray-200 mx-3"></div>

      <!-- Zoom pill group -->
      <div class="flex items-center gap-0.5 bg-gray-100 rounded-lg p-0.5">
        <button data-action="click->toolbar#zoomOut"
                title="Zoom Out"
                class="p-1.5 rounded-md text-gray-500 hover:text-gray-900 hover:bg-white transition-colors">
          <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 12H4" />
          </svg>
        </button>
        <span data-toolbar-target="zoomLevel" class="text-xs text-gray-600 font-mono w-10 text-center select-none">100%</span>
        <button data-action="click->toolbar#zoomIn"
                title="Zoom In"
                class="p-1.5 rounded-md text-gray-500 hover:text-gray-900 hover:bg-white transition-colors">
          <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
          </svg>
        </button>
      </div>

      <!-- Actions pill group -->
      <div class="relative flex items-center gap-0.5 bg-gray-100 rounded-lg p-0.5 ml-2">
        <button data-action="click->flowchart-canvas#validate"
                title="Validate"
                class="relative p-1.5 rounded-md text-gray-500 hover:text-gray-900 hover:bg-white transition-colors">
          <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <span data-flowchart-canvas-target="validationBadge"
                class="absolute -top-1 -right-1 inline-flex items-center justify-center min-w-[16px] h-4 rounded-full text-[10px] font-bold bg-red-500 text-white hidden">0</span>
        </button>
        <button data-action="click->flowchart-canvas#toggleTestPanel"
                title="Test Runner"
                class="p-1.5 rounded-md text-gray-500 hover:text-gray-900 hover:bg-white transition-colors">
          <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z" />
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
        </button>
        <button data-action="click->toolbar#toggleOverflow"
                title="More actions"
                class="p-1.5 rounded-md text-gray-500 hover:text-gray-900 hover:bg-white transition-colors">
          <svg class="h-4 w-4" viewBox="0 0 24 24" fill="currentColor">
            <circle cx="12" cy="6" r="1.5"/>
            <circle cx="12" cy="12" r="1.5"/>
            <circle cx="12" cy="18" r="1.5"/>
          </svg>
        </button>

        <!-- Overflow Menu -->
        <div data-toolbar-target="overflowMenu"
             class="absolute right-0 top-full mt-1 w-48 rounded-lg shadow-lg bg-white ring-1 ring-black/5 z-50 hidden">
          <div class="py-1">
            <button data-action="click->toolbar#autoLayout click->toolbar#closeOverflow"
                    class="w-full text-left px-3 py-2 text-sm text-gray-700 hover:bg-gray-50 flex items-center">
              <svg class="mr-2 h-4 w-4 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 5a1 1 0 011-1h4a1 1 0 011 1v7a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM14 5a1 1 0 011-1h4a1 1 0 011 1v7a1 1 0 01-1 1h-4a1 1 0 01-1-1V5zM4 16a1 1 0 011-1h4a1 1 0 011 1v3a1 1 0 01-1 1H5a1 1 0 01-1-1v-3zM14 16a1 1 0 011-1h4a1 1 0 011 1v3a1 1 0 01-1 1h-4a1 1 0 01-1-1v-3z" />
              </svg>
              Auto Layout
            </button>
            <button data-action="click->toolbar#cycleConnectionRouting click->toolbar#closeOverflow"
                    class="w-full text-left px-3 py-2 text-sm text-gray-700 hover:bg-gray-50 flex items-center">
              <svg class="mr-2 h-4 w-4 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
              </svg>
              Connection Routing
            </button>
            <button data-action="click->flowchart-canvas#generateDocs click->toolbar#closeOverflow"
                    class="w-full text-left px-3 py-2 text-sm text-gray-700 hover:bg-gray-50 flex items-center">
              <svg class="mr-2 h-4 w-4 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
              </svg>
              Generate Docs
            </button>
            <div class="border-t border-gray-100 my-1"></div>
            <button data-action="click->toolbar#exportSVG click->toolbar#closeOverflow"
                    class="w-full text-left px-3 py-2 text-sm text-gray-700 hover:bg-gray-50 flex items-center">
              <svg class="mr-2 h-4 w-4 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
              </svg>
              Export as SVG
            </button>
            <button data-action="click->toolbar#exportPNG click->toolbar#closeOverflow"
                    class="w-full text-left px-3 py-2 text-sm text-gray-700 hover:bg-gray-50 flex items-center">
              <svg class="mr-2 h-4 w-4 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
              </svg>
              Export as PNG
            </button>
            <div class="border-t border-gray-100 my-1"></div>
            <button data-action="click->toolbar#clear click->toolbar#closeOverflow"
                    class="w-full text-left px-3 py-2 text-sm text-red-600 hover:bg-red-50 flex items-center">
              <svg class="mr-2 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
              </svg>
              Clear Canvas
            </button>
          </div>
        </div>
      </div>

    </div>
  </div>
```

- [ ] **Step 3: Verify**

Open the editor. Confirm:
1. Left pill group: Save (indigo) + Undo/Redo icons, all in a gray-100 rounded container
2. Center: flowchart name link
3. Right: zoom `-`/percentage/`+` pill group, then Validate/Test/`...` actions pill group
4. View, Tools, Export dropdown menus are gone
5. `...` button opens overflow menu with Auto Layout, Connection Routing, Generate Docs, separator, Export SVG/PNG, separator, Clear Canvas
6. Clicking outside the overflow menu closes it
7. Save button shows amber dot when there are unsaved changes
8. Undo/Redo buttons disable correctly
9. Validate button runs validation and shows badge count
10. Test button opens test panel

---

### Task 5: Tabbed Bottom Panel

Consolidate the 4 separate bottom panels (Validation, Test Runner, History, Elements) into a single tabbed container.

**Files:**
- Modify: `app/views/flowcharts/_editor.html.erb:428-555`
- Modify: `app/javascript/controllers/flowchart_canvas_controller.js`

- [ ] **Step 1: Replace 4 panel divs with 1 tabbed container in _editor.html.erb**

In `app/views/flowcharts/_editor.html.erb`, replace the 4 separate panel divs (lines 428-555, from `<!-- Validation Problems Panel -->` through the closing `</div>` of the elements panel) with:

```erb
        <!-- Tabbed Bottom Panel -->
        <div data-flowchart-canvas-target="bottomPanel"
             class="absolute bottom-0 left-0 right-0 bg-white border-t border-gray-200 shadow-lg z-20 hidden"
             style="max-height: 40%;">
          <div class="flex flex-col h-full">

            <!-- Tab Bar -->
            <div class="flex items-center border-b border-gray-100 bg-gray-50 flex-shrink-0">
              <button data-action="click->flowchart-canvas#switchBottomTab"
                      data-tab="problems"
                      data-flowchart-canvas-target="bottomTab"
                      class="px-3 py-2 text-xs font-medium border-b-2 border-indigo-500 text-indigo-600">
                Problems
              </button>
              <button data-action="click->flowchart-canvas#switchBottomTab"
                      data-tab="test"
                      data-flowchart-canvas-target="bottomTab"
                      class="px-3 py-2 text-xs font-medium border-b-2 border-transparent text-gray-500 hover:text-gray-700">
                Test Runner
              </button>
              <button data-action="click->flowchart-canvas#switchBottomTab"
                      data-tab="history"
                      data-flowchart-canvas-target="bottomTab"
                      class="px-3 py-2 text-xs font-medium border-b-2 border-transparent text-gray-500 hover:text-gray-700">
                History
                <span data-flowchart-canvas-target="versionCount" class="ml-1 text-gray-400 font-normal text-[10px]"></span>
              </button>
              <button data-action="click->flowchart-canvas#switchBottomTab"
                      data-tab="elements"
                      data-flowchart-canvas-target="bottomTab"
                      class="px-3 py-2 text-xs font-medium border-b-2 border-transparent text-gray-500 hover:text-gray-700">
                Elements
                <span data-flowchart-canvas-target="elementsCount" class="ml-1 text-gray-400 font-normal text-[10px]"></span>
              </button>
              <div class="flex-1"></div>
              <button data-action="click->flowchart-canvas#closeBottomPanel"
                      class="p-1.5 mr-1 text-gray-400 hover:text-gray-600 rounded hover:bg-gray-100">
                <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>

            <!-- Tab Contents -->
            <div class="flex-1 overflow-y-auto">

              <!-- Problems Tab -->
              <div data-tab-content="problems">
                <div data-flowchart-canvas-target="validationList" class="divide-y divide-gray-100"></div>
              </div>

              <!-- Test Runner Tab -->
              <div data-tab-content="test" class="hidden">
                <div class="flex items-center justify-between px-4 py-2 border-b border-gray-50">
                  <span data-flowchart-canvas-target="testStatus" class="hidden inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium"></span>
                  <div class="flex items-center gap-2 ml-auto">
                    <button data-action="click->flowchart-canvas#clearTraceOverlay"
                            class="text-xs text-gray-500 hover:text-gray-700 px-2 py-1 rounded hover:bg-gray-100">
                      Clear Overlay
                    </button>
                  </div>
                </div>
                <div class="grid grid-cols-2 gap-4 p-4">
                  <!-- Input Section -->
                  <div>
                    <div class="flex items-center justify-between mb-2">
                      <label class="text-xs font-medium text-gray-600 uppercase tracking-wider">Input (JSON)</label>
                      <button data-action="click->flowchart-canvas#runTest"
                              class="inline-flex items-center px-3 py-1.5 border border-transparent text-xs font-medium rounded-md text-white bg-green-600 hover:bg-green-700 transition-colors">
                        <svg class="-ml-0.5 mr-1.5 h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z" />
                        </svg>
                        Run
                      </button>
                    </div>
                    <textarea data-flowchart-canvas-target="testInput"
                              class="w-full h-32 text-xs font-mono border border-gray-300 rounded-md p-2 focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 resize-y"
                              placeholder='{ "key": "value" }'>{}</textarea>
                  </div>
                  <!-- Output Section -->
                  <div>
                    <label class="text-xs font-medium text-gray-600 uppercase tracking-wider mb-2 block">Output</label>
                    <div data-flowchart-canvas-target="testOutput"
                         class="w-full h-32 text-xs font-mono border border-gray-200 rounded-md p-2 bg-gray-50 overflow-auto">
                      <span class="text-gray-400">Run a test to see results here.</span>
                    </div>
                  </div>
                </div>
              </div>

              <!-- History Tab -->
              <div data-tab-content="history" class="hidden">
                <div data-flowchart-canvas-target="versionList">
                  <div class="px-4 py-3 text-sm text-gray-500 text-center">Loading versions...</div>
                </div>
              </div>

              <!-- Elements Tab -->
              <div data-tab-content="elements" class="hidden">
                <table class="w-full text-sm">
                  <thead class="bg-gray-50 sticky top-0">
                    <tr>
                      <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Type</th>
                      <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Label</th>
                      <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Connections</th>
                    </tr>
                  </thead>
                  <tbody data-flowchart-canvas-target="elementsList" class="divide-y divide-gray-100">
                  </tbody>
                </table>
              </div>

            </div>
          </div>
        </div>
```

- [ ] **Step 2: Update targets in flowchart_canvas_controller.js**

In `app/javascript/controllers/flowchart_canvas_controller.js`, update the `static targets` array (lines 26-57). Remove the 4 individual panel targets and add the new tabbed panel targets:

Remove these targets:
- `"validationPanel"`
- `"testPanel"`
- `"versionPanel"`
- `"elementsPanel"`

Add these targets:
- `"bottomPanel"`
- `"bottomTab"`

The resulting targets array should be:

```js
  static targets = [
    "canvas",
    "overlay",
    "propertySidebar",
    "canvasContainer",
    "canvasWrapper",
    "toastContainer",
    "alignmentToolbar",
    "distributeSeparator",
    "distributeHBtn",
    "distributeVBtn",
    "validationBadge",
    "validationList",
    "unsavedIndicator",
    "testInput",
    "testOutput",
    "testStatus",
    "searchBar",
    "searchInput",
    "searchCount",
    "minimapContainer",
    "versionList",
    "versionCount",
    "elementsCount",
    "elementsList",
    "shortcutPanel",
    "contextMenu",
    "contextMenuItems",
    "bottomPanel",
    "bottomTab"
  ]
```

- [ ] **Step 3: Add tabbed panel methods to flowchart_canvas_controller.js**

Add a new section after the Elements Panel section (after `focusElement` method, around line 1265). Add these methods:

```js
  // ===================
  // Tabbed Bottom Panel
  // ===================

  openBottomPanel(tabName) {
    if (!this.hasBottomPanelTarget) return

    this.bottomPanelTarget.classList.remove("hidden")
    this._activateBottomTab(tabName)

    // Tab-specific initialization
    if (tabName === "history") {
      this.loadVersions()
    } else if (tabName === "elements") {
      this._renderElementsList()
    }

    this._activeBottomTab = tabName
  }

  closeBottomPanel() {
    if (!this.hasBottomPanelTarget) return
    this.bottomPanelTarget.classList.add("hidden")
  }

  switchBottomTab(event) {
    const tabName = event.currentTarget.dataset.tab
    if (!tabName) return

    // If clicking the already-active tab while panel is open, close the panel
    if (this._activeBottomTab === tabName && this.hasBottomPanelTarget && !this.bottomPanelTarget.classList.contains("hidden")) {
      this.closeBottomPanel()
      return
    }

    this.openBottomPanel(tabName)
  }

  _activateBottomTab(tabName) {
    // Update tab button styles
    this.bottomTabTargets.forEach(tab => {
      const isActive = tab.dataset.tab === tabName
      tab.classList.toggle("border-indigo-500", isActive)
      tab.classList.toggle("text-indigo-600", isActive)
      tab.classList.toggle("border-transparent", !isActive)
      tab.classList.toggle("text-gray-500", !isActive)
    })

    // Show/hide tab content
    if (this.hasBottomPanelTarget) {
      this.bottomPanelTarget.querySelectorAll("[data-tab-content]").forEach(content => {
        const isActive = content.dataset.tabContent === tabName
        content.classList.toggle("hidden", !isActive)
      })
    }
  }
```

- [ ] **Step 4: Refactor existing panel methods**

In `flowchart_canvas_controller.js`, refactor the existing panel open/close/toggle methods to delegate to the tabbed panel. Make these changes:

**Replace `_showValidationResults` panel showing** (around line 734-736):

Find:
```js
    if (this.hasValidationPanelTarget) {
      this.validationPanelTarget.classList.remove("hidden")
    }
```

Replace with:
```js
    this.openBottomPanel("problems")
```

**Replace `closeValidationPanel`** (around line 739-743):

```js
  closeValidationPanel() {
    this.closeBottomPanel()
  }
```

**Replace `toggleTestPanel`** (around line 765-774):

```js
  toggleTestPanel() {
    if (this.hasBottomPanelTarget && !this.bottomPanelTarget.classList.contains("hidden") && this._activeBottomTab === "test") {
      this.closeBottomPanel()
    } else {
      this.openBottomPanel("test")
    }
  }
```

**Replace `openTestPanel`** (around line 776-783):

```js
  openTestPanel() {
    this.openBottomPanel("test")
  }
```

**Replace `closeTestPanel`** (around line 785-788):

```js
  closeTestPanel() {
    this.closeBottomPanel()
  }
```

**Replace `toggleVersionPanel`** (around line 1052-1061):

```js
  toggleVersionPanel() {
    if (this.hasBottomPanelTarget && !this.bottomPanelTarget.classList.contains("hidden") && this._activeBottomTab === "history") {
      this.closeBottomPanel()
    } else {
      this.openBottomPanel("history")
    }
  }
```

**Replace `openVersionPanel`** (around line 1063-1074):

```js
  openVersionPanel() {
    this.openBottomPanel("history")
  }
```

**Replace `closeVersionPanel`** (around line 1076-1079):

```js
  closeVersionPanel() {
    this.closeBottomPanel()
  }
```

**Replace `toggleElementsPanel`** (around line 1189-1198):

```js
  toggleElementsPanel() {
    if (this.hasBottomPanelTarget && !this.bottomPanelTarget.classList.contains("hidden") && this._activeBottomTab === "elements") {
      this.closeBottomPanel()
    } else {
      this.openBottomPanel("elements")
    }
  }
```

**Replace `openElementsPanel`** (around line 1200-1206):

```js
  openElementsPanel() {
    this.openBottomPanel("elements")
  }
```

**Replace `closeElementsPanel`** (around line 1208-1210):

```js
  closeElementsPanel() {
    this.closeBottomPanel()
  }
```

- [ ] **Step 5: Verify**

Open the editor. Confirm:
1. No bottom panel visible on load
2. Click the toolbar Validate icon — bottom panel opens with "Problems" tab active (indigo border + text)
3. Click "Test Runner" tab — switches content to test runner with input/output areas
4. Click "History" tab — switches to version history, loads versions
5. Click "Elements" tab — switches to elements table, shows current elements
6. Click the active tab again — panel closes
7. Click close (X) button — panel closes
8. Test toolbar Test icon — opens panel on Test Runner tab; click again closes it
9. Validate → problems tab shows validation results correctly
10. Run test in test runner → output displays correctly
11. All existing functionality (runTest, restoreVersion, focusElement, focusValidationIssue) still works

---

### Task 6: Final Verification

- [ ] **Step 1: Precompile assets**

```bash
bundle exec rails assets:precompile
```

- [ ] **Step 2: Full integration test**

Open the flowchart editor and verify all 5 changes together:

1. **Dot grid:** Canvas shows dots instead of grid lines
2. **Left sidebar:** 140px wide, single-column elements with icons, unified search, uppercase headers
3. **Right sidebar:** 320px wide when opened, form fields display correctly
4. **Toolbar:** Pill-grouped buttons, no dropdown menus, overflow `...` menu works
5. **Bottom panel:** Tabbed interface, all 4 tabs work, switching and closing work correctly
6. **Drag and drop:** Elements can still be dragged from sidebar to canvas
7. **Property editing:** Double-click element opens property sidebar
8. **Keyboard shortcuts:** `?` opens shortcut panel, other shortcuts still work
9. **Context menu:** Right-click still shows context menu
10. **Save/Undo/Redo:** All work correctly from the new toolbar
