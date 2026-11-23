# Phase 3: Productivity Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add element resize, inline testing with visual trace, export (SVG/PNG), flowchart templates, and search to make the Anysys productive for daily use.

**Architecture:** Custom SVG canvas with viewBox-based zoom/pan (Phase 1). Elements positioned by center coordinates with configurable width/height. Trace endpoint already exists (`POST /:customer_id/flowcharts/:id/trace`) returning `trace_nodes` with element labels and status. Templates are JSON configuration presets applied at creation time.

**Tech Stack:** StimulusJS, vanilla SVG, TailwindCSS, Rails, RSpec.

**Spec Reference:** `docs/superpowers/specs/2026-03-23-anysys-industry-standard-audit-design.md` — Items #4, #29, #31, #32, #34

---

## Task 1: Element Resize (#4)

**Files:**
- Create: `app/javascript/flowchart/resize_handler.js`
- Modify: `app/javascript/flowchart/canvas.js` — integrate resize handler
- Modify: `app/javascript/flowchart/element_renderer.js` — label wrapping for variable sizes
- Modify: `app/javascript/flowchart/constants/elements.js` — min/max size constants

### Implementation:

- [ ] **Step 1: Add size constants**

In `app/javascript/flowchart/constants/elements.js`, add:
```javascript
export const MIN_ELEMENT_WIDTH = 60
export const MIN_ELEMENT_HEIGHT = 30
export const MAX_ELEMENT_WIDTH = 400
export const MAX_ELEMENT_HEIGHT = 200
```

- [ ] **Step 2: Create ResizeHandler**

Create `app/javascript/flowchart/resize_handler.js` — a mixin that adds resize handles when an element is selected:

Key functionality:
- Show 4 corner resize handles when element is selected (small squares)
- Handle mousedown on resize handle → track drag → update element width/height
- Snap dimensions to grid
- Enforce min/max constraints
- Update element rendering and connections after resize
- All coordinates must go through `zoomPanManager.clientToSVG()` for correct zoom handling

- [ ] **Step 3: Integrate resize into canvas**

Apply `ResizeHandlerMixin` to FlowchartCanvas. Show resize handles alongside connection handles when element is selected. Hide on deselect.

- [ ] **Step 4: Update label rendering for variable sizes**

In `element_renderer.js`, ensure labels wrap/truncate based on actual element width rather than hardcoded max length.

- [ ] **Step 5: Verify and commit**

---

## Task 2: Inline Testing/Debugging (#29)

**Files:**
- Modify: `app/views/flowcharts/_editor.html.erb` — test panel UI
- Modify: `app/javascript/controllers/flowchart_canvas_controller.js` — test panel logic
- Modify: `app/javascript/flowchart/canvas.js` — visual trace overlay
- Modify: `app/javascript/flowchart/element_renderer.js` — trace highlighting

### Implementation:

- [ ] **Step 1: Add test panel UI**

In `_editor.html.erb`, add a slide-up panel at the bottom of the canvas container with:
- "Run" button in toolbar
- Input area: JSON textarea pre-populated from Start element inputs
- Output area: execution result
- Trace status display

- [ ] **Step 2: Add Run button to toolbar**

Next to the Validate button, add a "Run" button that opens the test panel.

- [ ] **Step 3: Implement test execution**

In `flowchart_canvas_controller.js`, add:
- `runTest()` — saves current flowchart first, then calls trace endpoint
- `_executeTrace(input)` — POST to `/:customer_id/flowcharts/:id/trace` with input data
- `_displayTraceResults(response)` — parse response, highlight elements

- [ ] **Step 4: Visual execution trace overlay**

In `canvas.js`, add methods for trace visualization:
- `showTraceOverlay(traceNodes)` — highlight executed elements green, failed red, skipped gray
- `clearTraceOverlay()` — remove all trace highlights
- Match `traceNodes[].label` to `element.label` to identify which elements were executed

The trace response format is:
```json
{
  "success": true,
  "trace_nodes": [{ "id": "...", "label": "method_name", "status": "success|failure" }],
  "context": { ... },
  "error": null
}
```

- [ ] **Step 5: Element context inspection**

When trace is active, clicking an element shows its context snapshot in the test panel output area.

- [ ] **Step 6: Verify and commit**

---

## Task 3: Export SVG/PNG (#31)

**Files:**
- Create: `app/javascript/flowchart/export_manager.js`
- Modify: `app/views/flowcharts/_editor.html.erb` — export button/dropdown
- Modify: `app/javascript/controllers/toolbar_controller.js` — export actions

### Implementation:

- [ ] **Step 1: Create ExportManager**

Create `app/javascript/flowchart/export_manager.js`:

```javascript
export class ExportManager {
  constructor(canvas) {
    this.canvas = canvas
  }

  exportSVG() {
    const svgClone = this._prepareSvgForExport()
    const svgString = new XMLSerializer().serializeToString(svgClone)
    const blob = new Blob([svgString], { type: "image/svg+xml" })
    this._downloadBlob(blob, `${this._filename()}.svg`)
  }

  exportPNG(scale = 2) {
    const svgClone = this._prepareSvgForExport()
    const svgString = new XMLSerializer().serializeToString(svgClone)

    const img = new Image()
    const svgBlob = new Blob([svgString], { type: "image/svg+xml;charset=utf-8" })
    const url = URL.createObjectURL(svgBlob)

    img.onload = () => {
      const canvas = document.createElement("canvas")
      canvas.width = img.width * scale
      canvas.height = img.height * scale
      const ctx = canvas.getContext("2d")
      ctx.scale(scale, scale)
      ctx.drawImage(img, 0, 0)
      canvas.toBlob((blob) => {
        this._downloadBlob(blob, `${this._filename()}.png`)
        URL.revokeObjectURL(url)
      }, "image/png")
    }
    img.src = url
  }

  _prepareSvgForExport() {
    // Clone SVG, set viewBox to content bounds, remove interactive elements
    const svg = this.canvas.svg.cloneNode(true)
    // Remove handle, guide, selection layers
    svg.querySelectorAll(".handle-layer, .guide-layer, .selection-layer").forEach(el => el.remove())
    // Remove connection-label-editor foreignObjects
    svg.querySelectorAll(".connection-label-editor").forEach(el => el.remove())
    // Set viewBox to fit content with padding
    const bounds = this._getContentBounds()
    const padding = 40
    svg.setAttribute("viewBox", `${bounds.x - padding} ${bounds.y - padding} ${bounds.width + padding * 2} ${bounds.height + padding * 2}`)
    svg.setAttribute("width", bounds.width + padding * 2)
    svg.setAttribute("height", bounds.height + padding * 2)
    // Inline essential styles
    svg.setAttribute("xmlns", "http://www.w3.org/2000/svg")
    return svg
  }

  _getContentBounds() {
    const elements = this.canvas.elements
    if (elements.length === 0) return { x: 0, y: 0, width: 400, height: 300 }
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
    for (const el of elements) {
      minX = Math.min(minX, el.x - el.width / 2)
      minY = Math.min(minY, el.y - el.height / 2)
      maxX = Math.max(maxX, el.x + el.width / 2)
      maxY = Math.max(maxY, el.y + el.height / 2)
    }
    return { x: minX, y: minY, width: maxX - minX, height: maxY - minY }
  }

  _filename() {
    const name = document.querySelector("[data-flowchart-canvas-id-value]")?.dataset.flowchartCanvasIdValue || "flowchart"
    const date = new Date().toISOString().slice(0, 10)
    return `flowchart_${name}_${date}`
  }

  _downloadBlob(blob, filename) {
    const link = document.createElement("a")
    link.href = URL.createObjectURL(blob)
    link.download = filename
    link.click()
    URL.revokeObjectURL(link.href)
  }
}
```

- [ ] **Step 2: Add export dropdown to toolbar**

In `_editor.html.erb`, add an export dropdown button in the toolbar:
```erb
<div class="relative" data-controller="dropdown">
  <button data-action="click->dropdown#toggle" class="...">
    Export
  </button>
  <div data-dropdown-target="menu" class="hidden absolute ...">
    <button data-action="click->toolbar#exportSVG">Export SVG</button>
    <button data-action="click->toolbar#exportPNG">Export PNG</button>
  </div>
</div>
```

- [ ] **Step 3: Wire export in controllers**

In toolbar controller, add `exportSVG()` and `exportPNG()` methods calling canvas controller. In canvas controller, initialize `ExportManager` and expose export methods.

- [ ] **Step 4: Verify and commit**

---

## Task 4: Flowchart Templates (#32)

**Files:**
- Create: `app/javascript/flowchart/templates.js` — template configuration presets
- Modify: `app/views/flowcharts/new.html.erb` — template selection UI
- Modify: `app/models/flowchart.rb` — accept template parameter
- Modify: `app/controllers/flowcharts_controller.rb` — apply template on create

### Implementation:

- [ ] **Step 1: Define template presets**

Create `app/javascript/flowchart/templates.js` (not to be confused with property_editor/templates.js):

```javascript
export const FLOWCHART_TEMPLATES = {
  blank: {
    label: "Blank",
    description: "Empty flowchart with Start and Process",
    icon: "document",
    configuration: null  // uses default_configuration
  },
  crud_create: {
    label: "CRUD Create",
    description: "New model → validate → save",
    icon: "plus-circle",
    configuration: {
      elements: [
        { id: "el_1", type: "start", x: 400, y: 80, width: 100, height: 45, label: "Start", properties: { inputs: [], outputs: [] } },
        { id: "el_2", type: "process", x: 400, y: 180, width: 100, height: 45, label: "Create", properties: { inputs: [], outputs: [], steps: [
          { action: "new_model", selectionLabels: ["New Model"] },
          { action: "build_contract", selectionLabels: ["Build Contract"] },
          { action: "validate", selectionLabels: ["Validate"] },
          { action: "save_model", selectionLabels: ["Save Model"] }
        ] } },
        { id: "el_3", type: "end", x: 400, y: 280, width: 100, height: 45, label: "End", properties: {} }
      ],
      connections: [
        { id: "c1", from: "el_1", to: "el_2", fromPosition: "bottom", toPosition: "top" },
        { id: "c2", from: "el_2", to: "el_3", fromPosition: "bottom", toPosition: "top" }
      ],
      metadata: { created_at: new Date().toISOString() }
    }
  },
  crud_read: {
    label: "CRUD Read",
    description: "Find model → check found → render or 404",
    icon: "eye",
    configuration: { /* ... Start → Process(find) → Decision(found?) → End/End */ }
  },
  crud_update: {
    label: "CRUD Update",
    description: "Find → validate → save",
    icon: "pencil",
    configuration: { /* ... */ }
  },
  crud_delete: {
    label: "CRUD Delete",
    description: "Find → destroy",
    icon: "trash",
    configuration: { /* ... */ }
  }
}
```

- [ ] **Step 2: Add template selection to new flowchart form**

In `app/views/flowcharts/new.html.erb`, add a template selection grid above the form fields. Each template is a card with icon, name, and description. Clicking selects it and populates a hidden `template` field.

- [ ] **Step 3: Apply template on server side**

In `flowchart.rb`, update `new_with_defaults` to accept template:
```ruby
def self.new_with_defaults(attributes = {})
  template_key = attributes.delete(:template)
  flowchart = new(attributes)
  flowchart.configuration_json = template_configuration(template_key) if flowchart.configuration.blank?
  flowchart
end
```

In `flowcharts_controller.rb`, permit the `template` param.

Define template configurations as class-level constants or a dedicated method.

- [ ] **Step 4: Verify and commit**

---

## Task 5: Search Within Flowchart (#34)

**Files:**
- Create: `app/javascript/flowchart/search_manager.js`
- Modify: `app/javascript/flowchart/canvas.js` — integrate search
- Modify: `app/views/flowcharts/_editor.html.erb` — search bar UI
- Modify: `app/javascript/controllers/flowchart_canvas_controller.js` — search actions

### Implementation:

- [ ] **Step 1: Create SearchManager**

```javascript
export class SearchManager {
  constructor(canvas) {
    this.canvas = canvas
    this.results = []
    this.currentIndex = -1
  }

  search(query) {
    if (!query.trim()) { this.clearSearch(); return [] }
    const q = query.toLowerCase()
    this.results = this.canvas.elements.filter(el => {
      if (el.label?.toLowerCase().includes(q)) return true
      if (el.properties?.description?.toLowerCase().includes(q)) return true
      if (el.properties?.steps?.some(s => s.selectionLabels?.join(" ").toLowerCase().includes(q))) return true
      if (el.properties?.condition?.expression?.toLowerCase().includes(q)) return true
      return false
    })
    this.currentIndex = this.results.length > 0 ? 0 : -1
    this._highlightResults()
    if (this.results.length > 0) this._focusResult(0)
    return this.results
  }

  nextResult() { /* cycle to next */ }
  prevResult() { /* cycle to prev */ }
  clearSearch() { /* remove highlights, reset */ }
  _highlightResults() { /* add visual indicator to matching elements */ }
  _focusResult(index) { /* zoom to element */ }
}
```

- [ ] **Step 2: Add search bar UI**

Ctrl+F opens a search bar at top of canvas. Shows result count and prev/next navigation. Escape closes.

- [ ] **Step 3: Wire search in controllers**

Add Ctrl+F handler in canvas keyboard handler. Wire search bar actions to SearchManager.

- [ ] **Step 4: Verify and commit**

---

## Verification Checklist

- [ ] **Resize:** Drag corner handles to resize, min/max enforced, labels adapt, connections update
- [ ] **Testing:** Run button executes trace, elements highlighted green/red, context inspectable
- [ ] **Export:** SVG and PNG export produce clean images of the flowchart
- [ ] **Templates:** Template selection on creation, pre-populated elements and connections
- [ ] **Search:** Ctrl+F opens search, matches labels/steps/conditions, navigate results
- [ ] **No Regressions:** All existing features work, all specs pass
