# Canvas Editor Bug Fixes & UX Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 4 canvas interaction bugs and add 6 UX improvements (toast notifications, connection handle discoverability, keyboard shortcut panel, inline label editing, context menu, minimap default visible) to the flowchart editor.

**Architecture:** All changes are in JavaScript files and one ERB template. Bug fixes target drag_handler, connection_manager, element_palette_controller, and canvas. Improvements add new UI elements to the editor template and new interaction handlers to canvas.js and flowchart_canvas_controller.js. No backend changes.

**Tech Stack:** StimulusJS, vanilla JavaScript, SVG, TailwindCSS

**Spec:** `docs/superpowers/specs/2026-03-26-canvas-editor-improvements-design.md`

---

## File Map

| File | Tasks | Purpose |
|------|-------|---------|
| `app/javascript/flowchart/drag_handler.js` | 1 | Fix drag state cleanup |
| `app/javascript/controllers/element_palette_controller.js` | 1 | Fix hardcoded constants |
| `app/javascript/flowchart/connection_manager.js` | 1 | Add self-connection guard |
| `app/javascript/flowchart/canvas.js` | 1, 3, 5, 6, 7 | Bug C toast dispatch, shortcut panel toggle, inline label edit, context menu, keyboard handler |
| `app/javascript/controllers/flowchart_canvas_controller.js` | 2, 4 | Toast system, minimap default |
| `app/javascript/flowchart/selection_manager.js` | 3 | Connection handles on selection |
| `app/views/flowcharts/_editor.html.erb` | 2, 4, 5, 7 | Toast container, minimap default, shortcut panel, context menu HTML |

---

### Task 1: Fix bugs A, B, D (drag cleanup, palette constants, self-connection)

Three small, independent bug fixes.

**Files:**
- Modify: `app/javascript/flowchart/drag_handler.js:208-220`
- Modify: `app/javascript/controllers/element_palette_controller.js:1-5, 141-164`
- Modify: `app/javascript/flowchart/connection_manager.js:45-51`

- [ ] **Step 1: Fix drag state cleanup in drag_handler.js**

In `app/javascript/flowchart/drag_handler.js`, find `_cleanupDragState()` (line 208). Replace:

```js
  _cleanupDragState() {
    this._hideAlignmentGuides()

    if (this.selectedElements.length > 0) {
      this.showConnectionHandles(this.selectedElements)
    }

    this.isDragging = false
    this.draggedElement = null
    this.dragStartPosition = null
    this.draggedSubTree = null
    this.draggedElements = null
  },
```

With:

```js
  _cleanupDragState() {
    this._hideAlignmentGuides()
    this._hideDropSideIndicator()

    if (this.selectedElements.length > 0) {
      this.showConnectionHandles(this.selectedElements)
    }

    this.isDragging = false
    this.draggedElement = null
    this.dragStartPosition = null
    this.draggedSubTree = null
    this.draggedElements = null
    this.dropTargetElement = null
    this.dragOffset = { x: 0, y: 0 }
  },
```

- [ ] **Step 2: Fix hardcoded constants in element_palette_controller.js**

In `app/javascript/controllers/element_palette_controller.js`, add an import at the top of the file. Find the existing imports and add:

```js
import { DEFAULT_ELEMENT_SPACING, DEFAULT_ELEMENT_HEIGHT, GRID_SIZE } from "flowchart/constants"
```

Then replace `_calculateOptimalPosition` (lines 141-164):

```js
  _calculateOptimalPosition(flowchartCanvas, container) {
    const DEFAULT_X = 400
    const DEFAULT_Y = 80
    const ELEMENT_SPACING = 50
    const ELEMENT_HEIGHT = 45
    const GRID = 15
```

With:

```js
  _calculateOptimalPosition(flowchartCanvas, container) {
    const DEFAULT_X = 400
    const DEFAULT_Y = 80
```

And replace lines 158-159:

```js
    const rawDist = lastElement.height / 2 + ELEMENT_SPACING + ELEMENT_HEIGHT / 2
    const gridDist = Math.round(rawDist / GRID) * GRID
```

With:

```js
    const rawDist = lastElement.height / 2 + DEFAULT_ELEMENT_SPACING + DEFAULT_ELEMENT_HEIGHT / 2
    const gridDist = Math.round(rawDist / GRID_SIZE) * GRID_SIZE
```

- [ ] **Step 3: Add self-connection guard in connection_manager.js**

In `app/javascript/flowchart/connection_manager.js`, in `createConnection()` (line 45), add a self-connection check before the duplicate check. Find:

```js
  createConnection(fromElement, toElement, fromPosition, toPosition, options = {}) {
    // Check for existing connection
    const exists = this.connections.some(c =>
```

Replace with:

```js
  createConnection(fromElement, toElement, fromPosition, toPosition, options = {}) {
    // Prevent self-connections
    if (fromElement.id === toElement.id) return null

    // Check for existing connection
    const exists = this.connections.some(c =>
```

- [ ] **Step 4: Verify manually**

1. Drag an element and release — confirm no ghost drop indicator lines remain
2. Double-click a palette item — confirm element positions align with drag-dropped elements
3. Try to create a connection from an element to itself — confirm it's silently blocked

---

### Task 2: Toast notification system + Bug C fix

**Files:**
- Modify: `app/views/flowcharts/_editor.html.erb` (add toast container)
- Modify: `app/javascript/controllers/flowchart_canvas_controller.js` (add showToast method + target)
- Modify: `app/javascript/flowchart/canvas.js` (add onToast callback, use in start element rejection)

- [ ] **Step 1: Add toast container to _editor.html.erb**

In `app/views/flowcharts/_editor.html.erb`, find the canvas overlay div (around line 292):

```html
        <!-- Canvas overlay for interactions -->
        <div data-flowchart-canvas-target="overlay"
             class="absolute inset-0 pointer-events-none">
        </div>
```

Add immediately after it:

```html
        <!-- Toast notifications -->
        <div data-flowchart-canvas-target="toastContainer"
             class="absolute top-4 left-1/2 -translate-x-1/2 z-40 flex flex-col items-center gap-2 pointer-events-none">
        </div>
```

- [ ] **Step 2: Add toastContainer target and showToast method to flowchart_canvas_controller.js**

In `app/javascript/controllers/flowchart_canvas_controller.js`, add `"toastContainer"` to the `static targets` array.

Then add the `showToast` method. Find the `// UI Helpers` section or add before the private methods section:

```js
  // ===================
  // Toast Notifications
  // ===================

  showToast(message, type = "info") {
    if (!this.hasToastContainerTarget) return

    const colorMap = {
      info: "bg-blue-600 text-white",
      warning: "bg-amber-500 text-white",
      error: "bg-red-600 text-white"
    }
    const colors = colorMap[type] || colorMap.info

    const toast = document.createElement("div")
    toast.className = `pointer-events-auto px-4 py-2 rounded-lg shadow-lg text-sm font-medium ${colors} transition-all duration-300 ease-in-out opacity-0 translate-y-2`
    toast.textContent = message

    this.toastContainerTarget.appendChild(toast)

    // Animate in
    requestAnimationFrame(() => {
      toast.classList.remove("opacity-0", "translate-y-2")
      toast.classList.add("opacity-100", "translate-y-0")
    })

    // Auto-dismiss after 3 seconds
    setTimeout(() => {
      toast.classList.remove("opacity-100", "translate-y-0")
      toast.classList.add("opacity-0", "-translate-y-2")
      setTimeout(() => toast.remove(), 300)
    }, 3000)
  }
```

- [ ] **Step 3: Add onToast callback to canvas.js and use it for Bug C**

In `app/javascript/flowchart/canvas.js`, in the constructor (around line 60), add a new callback:

```js
    this.onToast = null
```

Then in `addElement()` (line 807-809), replace:

```js
    if (elementData.type === "start" && this.hasStartElement()) {
      console.warn("FlowchartCanvas: Only one Start element is allowed per flowchart")
      return null
    }
```

With:

```js
    if (elementData.type === "start" && this.hasStartElement()) {
      this.onToast?.("Only one Start element allowed per flowchart", "warning")
      return null
    }
```

In `flowchart_canvas_controller.js`, in `_setupCanvasCallbacks()`, add:

```js
    this.canvas.onToast = (message, type) => this.showToast(message, type)
```

- [ ] **Step 4: Verify manually**

1. Add a Start element to the canvas
2. Try to add a second Start element (drag, double-click, or press S)
3. Confirm a toast notification appears: "Only one Start element allowed per flowchart"
4. Confirm the toast auto-dismisses after 3 seconds

---

### Task 3: Connection handle discoverability

**Files:**
- Modify: `app/javascript/flowchart/selection_manager.js:31-49`

- [ ] **Step 1: Verify current behavior**

Read `app/javascript/flowchart/selection_manager.js`. The `_addToSelection()` method at line 37 already calls `this.showConnectionHandles(this.selectedElements)`. And `_removeFromSelection()` at line 62 calls it too when elements remain selected. Line 70 calls `this._hideConnectionHandles()` when no elements are selected.

This means connection handles ARE already shown on selected elements. The issue is that `showConnectionHandles` might only show handles temporarily (on hover). Let me verify.

Read `app/javascript/flowchart/connection_manager.js` to find `showConnectionHandles` and check if it makes handles persistent or hover-only.

- [ ] **Step 2: Ensure handles stay visible on selected elements**

If `showConnectionHandles()` already makes handles persistent for the passed elements, no code change is needed — just verify.

If handles are only shown on hover, modify `showConnectionHandles()` in `connection_manager.js` to set a `data-handles-persistent="true"` attribute on the handle group, and modify the mouseenter/mouseleave handlers to not hide handles when this attribute is present.

Find the handle mouseleave handler in connection_manager.js and update it to check:

```js
// In the mouseleave handler for connection handles:
if (handleGroup.dataset.handlesPersistent === "true") return
```

- [ ] **Step 3: Verify manually**

1. Click an element to select it
2. Confirm all 4 connection handles (top, bottom, left, right) are visible
3. Move mouse away from element — handles should stay visible
4. Click canvas to deselect — handles should disappear
5. Multi-select elements — all should show handles

---

### Task 4: Minimap visible by default

**Files:**
- Modify: `app/views/flowcharts/_editor.html.erb`
- Modify: `app/javascript/controllers/flowchart_canvas_controller.js`

- [ ] **Step 1: Remove hidden class from minimap in _editor.html.erb**

Find the minimap container (around line 297):

```html
        <!-- Minimap -->
        <div data-flowchart-canvas-target="minimapContainer"
             class="absolute bottom-2 right-2 z-20 border border-gray-300 rounded-lg shadow-md bg-white overflow-hidden hidden"
             style="width: 200px; height: 140px;">
        </div>
```

Remove the `hidden` class:

```html
        <!-- Minimap -->
        <div data-flowchart-canvas-target="minimapContainer"
             class="absolute bottom-2 right-2 z-20 border border-gray-300 rounded-lg shadow-md bg-white overflow-hidden"
             style="width: 200px; height: 140px;">
        </div>
```

- [ ] **Step 2: Verify manually**

1. Open the flowchart editor
2. Confirm the minimap is visible in the bottom-right corner immediately
3. Confirm it shows a miniature view of the canvas content

---

### Task 5: Keyboard shortcut reference panel

**Files:**
- Modify: `app/views/flowcharts/_editor.html.erb` (add panel HTML)
- Modify: `app/javascript/flowchart/canvas.js` (add `?` key handler)

- [ ] **Step 1: Add shortcut panel HTML to _editor.html.erb**

In `app/views/flowcharts/_editor.html.erb`, find the search bar div (around line 303). Add after the search bar's closing `</div>` and before the alignment toolbar:

```html
        <!-- Keyboard Shortcuts Panel -->
        <div data-flowchart-canvas-target="shortcutPanel"
             class="absolute bottom-2 left-2 z-30 bg-white/95 backdrop-blur border border-gray-200 rounded-lg shadow-lg p-4 hidden max-w-xs">
          <div class="flex items-center justify-between mb-3">
            <h4 class="text-sm font-semibold text-gray-900">Keyboard Shortcuts</h4>
            <button data-action="click->flowchart-canvas#closeShortcutPanel"
                    class="text-gray-400 hover:text-gray-600 p-0.5">
              <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
          <div class="grid grid-cols-2 gap-x-6 gap-y-1.5 text-xs">
            <div class="contents">
              <span class="text-gray-500">Add Elements</span><span></span>
              <span><kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded text-[10px] font-mono">S</kbd> Start</span>
              <span><kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded text-[10px] font-mono">E</kbd> End</span>
              <span><kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded text-[10px] font-mono">P</kbd> Process</span>
              <span><kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded text-[10px] font-mono">D</kbd> Decision</span>
              <span><kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded text-[10px] font-mono">L</kbd> Loop</span>
              <span><kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded text-[10px] font-mono">H</kbd> Error Handler</span>
              <span><kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded text-[10px] font-mono">T</kbd> Timer</span>
              <span></span>
            </div>
            <div class="contents">
              <span class="text-gray-500 mt-2">Navigation</span><span class="mt-2"></span>
              <span><kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded text-[10px] font-mono">Scroll</kbd> Pan</span>
              <span><kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded text-[10px] font-mono">Ctrl+Scroll</kbd> Zoom</span>
              <span><kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded text-[10px] font-mono">Space+Drag</kbd> Pan</span>
              <span></span>
            </div>
            <div class="contents">
              <span class="text-gray-500 mt-2">Editing</span><span class="mt-2"></span>
              <span><kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded text-[10px] font-mono">Ctrl+Z</kbd> Undo</span>
              <span><kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded text-[10px] font-mono">Ctrl+Y</kbd> Redo</span>
              <span><kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded text-[10px] font-mono">Ctrl+F</kbd> Search</span>
              <span><kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded text-[10px] font-mono">Del</kbd> Delete</span>
              <span><kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded text-[10px] font-mono">Esc</kbd> Deselect</span>
              <span><kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded text-[10px] font-mono">?</kbd> This panel</span>
            </div>
          </div>
        </div>
```

- [ ] **Step 2: Add shortcutPanel target to flowchart_canvas_controller.js**

Add `"shortcutPanel"` to the `static targets` array.

Add toggle and close methods:

```js
  toggleShortcutPanel() {
    if (!this.hasShortcutPanelTarget) return
    this.shortcutPanelTarget.classList.toggle("hidden")
  }

  closeShortcutPanel() {
    if (!this.hasShortcutPanelTarget) return
    this.shortcutPanelTarget.classList.add("hidden")
  }
```

- [ ] **Step 3: Add ? key handler in canvas.js**

In `app/javascript/flowchart/canvas.js`, in `_handleKeyDown()`, add a new callback property in the constructor (around line 60):

```js
    this.onShortcutPanelToggle = null
```

In `_handleKeyDown()`, after the quick-add elements block (after line 442, before `// Undo: Ctrl+Z`), add:

```js
    // Toggle shortcut panel: ?
    if (e.key === "?" || (e.shiftKey && e.key === "/")) {
      e.preventDefault()
      this.onShortcutPanelToggle?.()
      return
    }
```

In `flowchart_canvas_controller.js` `_setupCanvasCallbacks()`, add:

```js
    this.canvas.onShortcutPanelToggle = () => this.toggleShortcutPanel()
```

- [ ] **Step 4: Verify manually**

1. Press `?` — confirm shortcut panel appears in bottom-left
2. Press `?` again — confirm it toggles off
3. Press `Escape` while panel is showing — confirm it closes (existing Escape handling deselects, which is fine)
4. Verify all listed shortcuts work as described

---

### Task 6: Inline label editing on canvas

**Files:**
- Modify: `app/javascript/flowchart/canvas.js` (modify _handleDoubleClick, add inline edit methods)

- [ ] **Step 1: Add inline label editing state and methods to canvas.js**

In `app/javascript/flowchart/canvas.js`, in `_initState()`, add:

```js
    // Inline label editing
    this._inlineLabelInput = null
    this._inlineLabelElement = null
```

Add a new method section after `_handleWheel`:

```js
  // ===================
  // Inline Label Editing
  // ===================

  _startInlineLabelEdit(element) {
    // Remove any existing inline edit
    this._cancelInlineLabelEdit()

    this._inlineLabelElement = element
    const group = this.elementLayer.querySelector(`[data-element-id="${element.id}"]`)
    if (!group) return

    const textEl = group.querySelector("text")
    if (!textEl) return

    const textRect = textEl.getBoundingClientRect()
    const containerRect = this.containerElement.getBoundingClientRect()

    const input = document.createElement("input")
    input.type = "text"
    input.value = element.label || ""
    input.className = "absolute z-50 text-center border border-blue-400 rounded shadow-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500 text-xs px-1 py-0.5"
    input.style.left = `${textRect.left - containerRect.left - 10}px`
    input.style.top = `${textRect.top - containerRect.top - 2}px`
    input.style.width = `${Math.max(textRect.width + 20, 80)}px`
    input.style.minWidth = "80px"

    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault()
        this._commitInlineLabelEdit()
      } else if (e.key === "Escape") {
        e.preventDefault()
        this._cancelInlineLabelEdit()
      }
      e.stopPropagation()
    })

    input.addEventListener("blur", () => {
      // Small delay to allow click events to register before blur
      setTimeout(() => this._commitInlineLabelEdit(), 100)
    })

    this.containerElement.appendChild(input)
    this._inlineLabelInput = input

    // Select all text and focus
    requestAnimationFrame(() => {
      input.focus()
      input.select()
    })
  }

  _commitInlineLabelEdit() {
    if (!this._inlineLabelInput || !this._inlineLabelElement) return

    const newLabel = this._inlineLabelInput.value.trim()
    const element = this._inlineLabelElement

    if (newLabel && newLabel !== element.label) {
      this.onBeforeChange?.()
      element.label = newLabel
      this.updateElementPosition(element)
      this.onchange?.()
    }

    this._cleanupInlineLabelEdit()
  }

  _cancelInlineLabelEdit() {
    this._cleanupInlineLabelEdit()
  }

  _cleanupInlineLabelEdit() {
    if (this._inlineLabelInput) {
      this._inlineLabelInput.remove()
      this._inlineLabelInput = null
    }
    this._inlineLabelElement = null
  }
```

- [ ] **Step 2: Modify _handleDoubleClick to detect label clicks**

In `app/javascript/flowchart/canvas.js`, replace the existing `_handleDoubleClick` method:

```js
  _handleDoubleClick(e) {
    // Check for connection double-click first
    const connectionTarget = e.target.closest("[data-connection-id]")
    if (connectionTarget) {
      const connectionId = connectionTarget.dataset.connectionId
      this.selectConnection(connectionId)
      this.startInlineLabelEdit(connectionId)
      return
    }

    const target = e.target.closest("[data-element-id]")
    if (!target) return

    const element = this.elements.find(el => el.id === target.dataset.elementId)
    if (element && this.onElementDoubleClick) {
      this.onElementDoubleClick(element)
    }
  }
```

With:

```js
  _handleDoubleClick(e) {
    // Check for connection double-click first
    const connectionTarget = e.target.closest("[data-connection-id]")
    if (connectionTarget) {
      const connectionId = connectionTarget.dataset.connectionId
      this.selectConnection(connectionId)
      this.startInlineLabelEdit(connectionId)
      return
    }

    const target = e.target.closest("[data-element-id]")
    if (!target) return

    const element = this.elements.find(el => el.id === target.dataset.elementId)
    if (!element) return

    // If double-click is on the label text, start inline editing
    if (e.target.tagName === "text" || e.target.closest("text")) {
      this._startInlineLabelEdit(element)
      return
    }

    // Otherwise open property editor
    if (this.onElementDoubleClick) {
      this.onElementDoubleClick(element)
    }
  }
```

- [ ] **Step 3: Verify manually**

1. Double-click on an element's label text — confirm an input field appears over the label
2. Type a new name, press Enter — confirm label updates on canvas
3. Double-click label, press Escape — confirm edit is cancelled, original label preserved
4. Double-click on element body (not label) — confirm property sidebar opens as before
5. Click away from input (blur) — confirm label saves

---

### Task 7: Canvas right-click context menu

**Files:**
- Modify: `app/views/flowcharts/_editor.html.erb` (add context menu HTML)
- Modify: `app/javascript/flowchart/canvas.js` (add context menu handlers)
- Modify: `app/javascript/controllers/flowchart_canvas_controller.js` (add target + actions)

- [ ] **Step 1: Add context menu HTML to _editor.html.erb**

In `app/views/flowcharts/_editor.html.erb`, after the toast container div, add:

```html
        <!-- Context Menu -->
        <div data-flowchart-canvas-target="contextMenu"
             class="absolute z-50 bg-white border border-gray-200 rounded-lg shadow-xl py-1 min-w-[160px] hidden">
          <div data-flowchart-canvas-target="contextMenuItems"></div>
        </div>
```

- [ ] **Step 2: Add targets and context menu actions to flowchart_canvas_controller.js**

Add `"contextMenu"` and `"contextMenuItems"` to `static targets`.

Add methods:

```js
  // ===================
  // Context Menu
  // ===================

  showContextMenu(x, y, items) {
    if (!this.hasContextMenuTarget || !this.hasContextMenuItemsTarget) return

    const html = items.map(item => {
      if (item.separator) {
        return '<div class="border-t border-gray-100 my-1"></div>'
      }
      return `
        <button class="w-full text-left px-3 py-1.5 text-sm text-gray-700 hover:bg-gray-50 flex items-center gap-2 ${item.danger ? 'text-red-600 hover:bg-red-50' : ''}"
                data-context-action="${item.action}"
                data-context-data='${JSON.stringify(item.data || {})}'>
          ${item.label}
        </button>
      `
    }).join("")

    this.contextMenuItemsTarget.innerHTML = html

    // Position the menu
    const container = this.canvasContainerTarget.getBoundingClientRect()
    this.contextMenuTarget.style.left = `${x - container.left}px`
    this.contextMenuTarget.style.top = `${y - container.top}px`
    this.contextMenuTarget.classList.remove("hidden")

    // Bind click handlers
    this.contextMenuItemsTarget.querySelectorAll("[data-context-action]").forEach(btn => {
      btn.addEventListener("click", (e) => {
        const action = e.currentTarget.dataset.contextAction
        const data = JSON.parse(e.currentTarget.dataset.contextData || "{}")
        this._executeContextAction(action, data)
        this.hideContextMenu()
      })
    })

    // Close on click outside
    this._contextMenuCloseHandler = (e) => {
      if (!this.contextMenuTarget.contains(e.target)) {
        this.hideContextMenu()
      }
    }
    setTimeout(() => document.addEventListener("click", this._contextMenuCloseHandler), 0)
  }

  hideContextMenu() {
    if (!this.hasContextMenuTarget) return
    this.contextMenuTarget.classList.add("hidden")
    if (this._contextMenuCloseHandler) {
      document.removeEventListener("click", this._contextMenuCloseHandler)
      this._contextMenuCloseHandler = null
    }
  }

  _executeContextAction(action, data) {
    switch (action) {
      case "add_element":
        this.canvas.addElement({ type: data.type, x: data.x, y: data.y })
        break
      case "edit_properties": {
        const el = this.canvas.elements.find(e => e.id === data.elementId)
        if (el) this._handleElementSelected({ detail: { element: el } })
        break
      }
      case "duplicate": {
        const el = this.canvas.elements.find(e => e.id === data.elementId)
        if (el) {
          this.canvas._selectSingleElement(el)
          this.canvas._pasteElements(this.canvas.clipboardManager.duplicate())
        }
        break
      }
      case "delete_element":
        this.canvas.onBeforeChange?.()
        this.canvas.deleteElement(data.elementId)
        this.canvas.onchange?.()
        break
      case "delete_connection":
        this.canvas.onBeforeChange?.()
        this.canvas.deleteConnection(data.connectionId)
        this.canvas.onchange?.()
        break
      case "paste":
        this.canvas._pasteElements(this.canvas.clipboardManager.paste())
        break
    }
  }
```

- [ ] **Step 3: Add onContextMenu callback to canvas.js**

In `app/javascript/flowchart/canvas.js`, add callback in constructor:

```js
    this.onContextMenu = null
```

In `_bindEvents()`, add after the existing contextmenu listener (around line 201-203):

Replace:
```js
    this.svg.addEventListener("contextmenu", e => {
      if (e.ctrlKey) e.preventDefault()
    })
```

With:
```js
    this.svg.addEventListener("contextmenu", e => {
      e.preventDefault()
      this._handleContextMenu(e)
    })
```

Add the handler method:

```js
  _handleContextMenu(e) {
    if (!this.onContextMenu) return

    const point = this._getSVGPoint(e)

    // Check if right-click is on an element
    const elementTarget = e.target.closest("[data-element-id]")
    if (elementTarget) {
      const element = this.elements.find(el => el.id === elementTarget.dataset.elementId)
      if (element) {
        this.onContextMenu(e.clientX, e.clientY, "element", { element, point })
        return
      }
    }

    // Check if right-click is on a connection
    const connectionTarget = e.target.closest("[data-connection-id]")
    if (connectionTarget) {
      this.onContextMenu(e.clientX, e.clientY, "connection", { connectionId: connectionTarget.dataset.connectionId })
      return
    }

    // Right-click on empty canvas
    this.onContextMenu(e.clientX, e.clientY, "canvas", { point })
  }
```

- [ ] **Step 4: Wire onContextMenu in flowchart_canvas_controller.js**

In `_setupCanvasCallbacks()`, add:

```js
    this.canvas.onContextMenu = (clientX, clientY, targetType, data) => {
      let items = []

      if (targetType === "canvas") {
        items = [
          { label: "Add Process", action: "add_element", data: { type: "process", x: data.point.x, y: data.point.y } },
          { label: "Add Decision", action: "add_element", data: { type: "decision", x: data.point.x, y: data.point.y } },
          { label: "Add End", action: "add_element", data: { type: "end", x: data.point.x, y: data.point.y } },
          { separator: true },
          { label: "Paste", action: "paste", data: {} }
        ]
      } else if (targetType === "element") {
        items = [
          { label: "Edit Properties", action: "edit_properties", data: { elementId: data.element.id } },
          { label: "Duplicate", action: "duplicate", data: { elementId: data.element.id } },
          { separator: true },
          { label: "Delete", action: "delete_element", data: { elementId: data.element.id }, danger: true }
        ]
      } else if (targetType === "connection") {
        items = [
          { label: "Delete Connection", action: "delete_connection", data: { connectionId: data.connectionId }, danger: true }
        ]
      }

      this.showContextMenu(clientX, clientY, items)
    }
```

- [ ] **Step 5: Close context menu on canvas click and Escape**

In `_handleCanvasClick()` in `flowchart_canvas_controller.js`, add at the start:

```js
    this.hideContextMenu()
```

In `canvas.js` `_handleKeyDown()`, in the Escape handling section, add `this.onContextMenuClose?.()` and wire it in the controller. Or simpler: add to the existing Escape handling in `flowchart_canvas_controller.js`.

Actually, the click-outside handler in `showContextMenu` already handles most cases. For Escape, add to `_handleKeyDown()` in canvas.js before the existing Escape block:

After the `?` shortcut handler and before `// Undo: Ctrl+Z`, find the Escape handling. Look for any existing `Escape` handling or add:

In `_handleKeyDown`, find the block that handles Escape (for deselecting). It's likely in the key checks. If not present, the Escape key is handled in `flowchart_canvas_controller.js` via the property editor. Add to canvas.js in `_handleKeyDown`:

```js
    // Close context menu on Escape
    if (e.key === "Escape") {
      this.onContextMenuClose?.()
    }
```

And in the controller's `_setupCanvasCallbacks()`:

```js
    this.canvas.onContextMenuClose = () => this.hideContextMenu()
```

- [ ] **Step 6: Verify manually**

1. Right-click empty canvas — menu shows Add Process/Decision/End + Paste
2. Click "Add Process" — confirm element added at cursor position
3. Right-click an element — menu shows Edit Properties/Duplicate/Delete
4. Click "Delete" — confirm element removed
5. Right-click a connection — menu shows Delete Connection
6. Click outside menu — confirm it closes
7. Press Escape — confirm it closes

---

### Task 8: Final verification

- [ ] **Step 1: Precompile and restart**

```bash
bundle exec rails assets:precompile
# Restart the Rails server
```

- [ ] **Step 2: Full manual test pass**

Test all changes on `/96546124/flowcharts/48/edit`:

1. **Bug A**: Drag element, release — no ghost indicators
2. **Bug B**: Double-click palette item — correct position alignment
3. **Bug D**: Self-connection blocked in createConnection
4. **Bug C + Toast**: Try adding second Start — toast warning appears
5. **Connection handles**: Click element — handles stay visible; deselect — handles hide
6. **Minimap**: Visible on page load
7. **Shortcuts**: Press `?` — panel toggles on/off
8. **Inline label**: Double-click label text — inline edit; double-click body — sidebar opens
9. **Context menu**: Right-click canvas/element/connection — appropriate menus appear
10. **Scroll**: Mouse wheel pans canvas (from earlier fix — still works)
