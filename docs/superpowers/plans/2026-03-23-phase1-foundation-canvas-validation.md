# Phase 1: Foundation (Canvas + Validation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add zoom/pan, dynamic canvas, copy/paste, alignment tools, flowchart validation, and undo persistence to bring the Anysys to industry-standard canvas interaction quality.

**Architecture:** The canvas is a custom SVG-based editor (`FlowchartCanvas` class) with functionality split across 4 mixins (ElementRenderer, ConnectionManager, SelectionManager, DragHandler). Zoom/pan is the most architecturally impactful change — it introduces viewBox-based coordinate transformation that all other mouse interactions depend on. Tasks are ordered so zoom/pan lands first, then features that build on it.

**Tech Stack:** StimulusJS controllers, vanilla SVG manipulation, RSpec for server-side tests, manual verification for client-side (no JS test framework exists in project).

**Spec Reference:** `docs/superpowers/specs/2026-03-23-anysys-industry-standard-audit-design.md` — Items #1, #3, #5, #10, #28, #30

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `app/javascript/flowchart/zoom_pan_manager.js` | Zoom/pan state, viewBox manipulation, coordinate transforms |
| `app/javascript/flowchart/clipboard_manager.js` | Copy/paste/duplicate element serialization |
| `app/javascript/flowchart/alignment_manager.js` | Alignment and distribution commands |
| `app/javascript/flowchart/validation_service.js` | Client-side flowchart structural/completeness validation |
| `app/javascript/controllers/flowchart_canvas/validation_panel_controller.js` | Stimulus controller for validation problems panel UI |
| `spec/services/flowchart_validator_spec.rb` | RSpec tests for server-side validation |

### Modified Files
| File | Changes |
|------|---------|
| `app/javascript/flowchart/canvas.js` | Integrate ZoomPanManager, update `_createSvg` for viewBox, update `_getSVGPoint` for coordinate transforms, add keyboard shortcuts for copy/paste/align, remove fixed canvas dimensions, update `getConfiguration()` metadata, add `onZoomChange` callback |
| `app/javascript/flowchart/constants/canvas.js` | Add zoom constants (MIN_ZOOM, MAX_ZOOM, ZOOM_STEP), remove CANVAS_WIDTH/CANVAS_HEIGHT |
| `app/javascript/flowchart/drag_handler.js` | Replace CANVAS_WIDTH/CANVAS_HEIGHT usage in alignment guides with large constant values |
| `app/javascript/controllers/flowchart_canvas_controller.js` | Wire up zoom controls, clipboard, alignment, validation, beforeunload handler |
| `app/javascript/controllers/flowchart_canvas/undo_redo_manager.js` | Add sessionStorage persistence, dirty state tracking |
| `app/views/flowcharts/_editor.html.erb` | Add zoom controls to toolbar, alignment toolbar, validate button, unsaved indicator, validation panel, remove hardcoded dimensions |
| `app/services/activity_generator.rb` | Add validation guard before code generation |

---

## Task 1: Zoom and Pan — ViewBox Foundation

**Files:**
- Create: `app/javascript/flowchart/zoom_pan_manager.js`
- Modify: `app/javascript/flowchart/canvas.js:104-113` (`_createSvg`), `:1301-1304` (`_getSVGPoint`)
- Modify: `app/javascript/flowchart/constants/canvas.js`

This is the most critical task — it changes the coordinate system that every mouse interaction depends on.

- [ ] **Step 1: Add zoom constants**

In `app/javascript/flowchart/constants/canvas.js`, add zoom configuration constants:

```javascript
/** Minimum zoom level (25%) */
export const MIN_ZOOM = 0.25

/** Maximum zoom level (200%) */
export const MAX_ZOOM = 2.0

/** Zoom increment per scroll step */
export const ZOOM_STEP = 0.1

/** Default zoom level (100%) */
export const DEFAULT_ZOOM = 1.0
```

- [ ] **Step 2: Create ZoomPanManager**

Create `app/javascript/flowchart/zoom_pan_manager.js`:

```javascript
import { MIN_ZOOM, MAX_ZOOM, ZOOM_STEP, DEFAULT_ZOOM } from "flowchart/constants"
import { clamp } from "utils"

export class ZoomPanManager {
  constructor(svg) {
    this.svg = svg
    this.zoom = DEFAULT_ZOOM
    this.panX = 0
    this.panY = 0
    this.isPanning = false
    this.isSpaceHeld = false
    this.panStart = null
    this._updateViewBox()
  }

  /** Get current viewBox dimensions based on zoom */
  get viewWidth() {
    return this.svg.clientWidth / this.zoom
  }

  get viewHeight() {
    return this.svg.clientHeight / this.zoom
  }

  /** Convert client (screen) coordinates to SVG coordinates */
  clientToSVG(clientX, clientY) {
    const rect = this.svg.getBoundingClientRect()
    const relX = clientX - rect.left
    const relY = clientY - rect.top
    return {
      x: this.panX + (relX / rect.width) * this.viewWidth,
      y: this.panY + (relY / rect.height) * this.viewHeight
    }
  }

  /** Zoom to a specific level, centering on a point */
  zoomTo(newZoom, centerClientX, centerClientY) {
    const clamped = clamp(newZoom, MIN_ZOOM, MAX_ZOOM)
    if (clamped === this.zoom) return

    // Get SVG point under cursor before zoom
    const rect = this.svg.getBoundingClientRect()
    const relX = centerClientX - rect.left
    const relY = centerClientY - rect.top
    const svgX = this.panX + (relX / rect.width) * this.viewWidth
    const svgY = this.panY + (relY / rect.height) * this.viewHeight

    this.zoom = clamped

    // Adjust pan so the same SVG point stays under cursor
    this.panX = svgX - (relX / rect.width) * this.viewWidth
    this.panY = svgY - (relY / rect.height) * this.viewHeight

    this._updateViewBox()
  }

  /** Zoom in by one step, centered on SVG center */
  zoomIn() {
    const rect = this.svg.getBoundingClientRect()
    this.zoomTo(this.zoom + ZOOM_STEP, rect.left + rect.width / 2, rect.top + rect.height / 2)
  }

  /** Zoom out by one step, centered on SVG center */
  zoomOut() {
    const rect = this.svg.getBoundingClientRect()
    this.zoomTo(this.zoom - ZOOM_STEP, rect.left + rect.width / 2, rect.top + rect.height / 2)
  }

  /** Fit all content in view with padding */
  fitToContent(elements, padding = 80) {
    if (!elements || elements.length === 0) return

    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
    for (const el of elements) {
      const hw = el.width / 2, hh = el.height / 2
      minX = Math.min(minX, el.x - hw)
      minY = Math.min(minY, el.y - hh)
      maxX = Math.max(maxX, el.x + hw)
      maxY = Math.max(maxY, el.y + hh)
    }

    const contentW = maxX - minX + padding * 2
    const contentH = maxY - minY + padding * 2
    const rect = this.svg.getBoundingClientRect()
    const scaleX = rect.width / contentW
    const scaleY = rect.height / contentH
    this.zoom = clamp(Math.min(scaleX, scaleY), MIN_ZOOM, MAX_ZOOM)
    this.panX = minX - padding
    this.panY = minY - padding
    this._updateViewBox()
  }

  /** Reset to default zoom and pan */
  resetZoom() {
    this.zoom = DEFAULT_ZOOM
    this.panX = 0
    this.panY = 0
    this._updateViewBox()
  }

  /** Pan by pixel delta (in screen space) */
  panBy(deltaScreenX, deltaScreenY) {
    this.panX -= deltaScreenX / this.zoom
    this.panY -= deltaScreenY / this.zoom
    this._updateViewBox()
  }

  /** Start panning from a screen position */
  startPan(clientX, clientY) {
    this.isPanning = true
    this.panStart = { x: clientX, y: clientY }
    this.svg.style.cursor = "grabbing"
  }

  /** Update pan during drag */
  updatePan(clientX, clientY) {
    if (!this.isPanning || !this.panStart) return
    const dx = clientX - this.panStart.x
    const dy = clientY - this.panStart.y
    this.panBy(dx, dy)
    this.panStart = { x: clientX, y: clientY }
  }

  /** End panning */
  endPan() {
    this.isPanning = false
    this.panStart = null
    this.svg.style.cursor = this.isSpaceHeld ? "grab" : "default"
  }

  /** Get zoom percentage for display */
  get zoomPercent() {
    return Math.round(this.zoom * 100)
  }

  _updateViewBox() {
    this.svg.setAttribute("viewBox", `${this.panX} ${this.panY} ${this.viewWidth} ${this.viewHeight}`)
  }
}
```

- [ ] **Step 3: Integrate ZoomPanManager into FlowchartCanvas**

Modify `app/javascript/flowchart/canvas.js`:

**3a.** Add import at top:
```javascript
import { ZoomPanManager } from "flowchart/zoom_pan_manager"
```

**3b.** Update `_createSvg()` (line 104) — replace fixed width/height with viewBox, make SVG fill container:
```javascript
_createSvg() {
  this.svg = createSvgElement("svg", {
    class: "flowchart-svg",
    style: "width: 100%; height: 100%;"
  })
  this.svg.style.cursor = "default"
  this.containerElement.parentNode.replaceChild(this.svg, this.containerElement)
  this.zoomPanManager = new ZoomPanManager(this.svg)
}
```

**3c.** Add `onZoomChange` to constructor callback declarations (line 49, after `this.onredo = null`):
```javascript
this.onZoomChange = null
```

**3d.** Update `_getSVGPoint(e)` (line 1301) — use ZoomPanManager for coordinate conversion:
```javascript
_getSVGPoint(e) {
  return this.zoomPanManager.clientToSVG(e.clientX, e.clientY)
}
```

- [ ] **Step 4: Add scroll-to-zoom handler**

In `_bindEvents()` (canvas.js line 148), add wheel event:
```javascript
this.svg.addEventListener("wheel", e => this._handleWheel(e), { passive: false })
```

Add new method after `_handleKeyDown`:
```javascript
_handleWheel(e) {
  if (!e.ctrlKey && !e.metaKey) return
  e.preventDefault()
  const delta = e.deltaY > 0 ? -ZOOM_STEP : ZOOM_STEP
  this.zoomPanManager.zoomTo(this.zoomPanManager.zoom + delta, e.clientX, e.clientY)
  this.onZoomChange?.(this.zoomPanManager.zoomPercent)
}
```

Add `ZOOM_STEP` to the imports from `"flowchart/constants"`.

- [ ] **Step 5: Add Space+drag panning**

In `_handleKeyDown` (canvas.js line 326), add Space key handling. Note: the existing guard (line 327) checks `INPUT` and `TEXTAREA` tags. Extend it to also skip `SELECT` and `contenteditable` elements:

Update the guard at line 327:
```javascript
if (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA" || e.target.tagName === "SELECT" || e.target.isContentEditable) return
```

Then add Space key handling:
```javascript
// Space: enable pan mode
if (e.key === " " && !e.repeat) {
  e.preventDefault()
  this.zoomPanManager.isSpaceHeld = true
  this.svg.style.cursor = "grab"
  return
}
```

Add `_handleKeyUp` method and bind it in `_bindEvents`. Store a reference for cleanup:
```javascript
// In _bindEvents:
this._keyUpHandler = e => this._handleKeyUp(e)
document.addEventListener("keyup", this._keyUpHandler)

// New method:
_handleKeyUp(e) {
  if (e.key === " ") {
    this.zoomPanManager.isSpaceHeld = false
    if (this.zoomPanManager.isPanning) {
      this.zoomPanManager.endPan()
    }
    this.svg.style.cursor = "default"
  }
}
```

Modify `_handleMouseDown` (canvas.js line 172) — if Space is held, start panning instead of normal interaction:
```javascript
_handleMouseDown(e) {
  if (this.zoomPanManager.isSpaceHeld) {
    this.zoomPanManager.startPan(e.clientX, e.clientY)
    return
  }
  // ... existing code
}
```

Modify `_handleMouseMove` (canvas.js line 228) — if panning, update pan:
```javascript
_handleMouseMove(e) {
  if (this.zoomPanManager.isPanning) {
    this.zoomPanManager.updatePan(e.clientX, e.clientY)
    return
  }
  // ... existing code
}
```

Modify `_handleMouseUp` (canvas.js line 276) — end panning:
```javascript
_handleMouseUp(e) {
  if (this.zoomPanManager.isPanning) {
    this.zoomPanManager.endPan()
    return
  }
  // ... existing code
}
```

- [ ] **Step 6: Add zoom controls to toolbar UI**

Modify `app/views/flowcharts/_editor.html.erb`. After the Redo button (line 55) and before the Clear button (line 57), add a zoom controls group:

```erb
<!-- Zoom controls separator -->
<div class="h-6 w-px bg-gray-300 mx-1"></div>

<!-- Zoom controls -->
<button data-action="click->toolbar#zoomOut"
        title="Zoom Out (Ctrl+-)"
        class="inline-flex items-center p-2 border border-gray-300 shadow-sm text-sm rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 transition-colors">
  <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0zM13 10H7" />
  </svg>
</button>

<span data-toolbar-target="zoomLevel" class="text-sm text-gray-600 font-mono w-12 text-center select-none">100%</span>

<button data-action="click->toolbar#zoomIn"
        title="Zoom In (Ctrl++)"
        class="inline-flex items-center p-2 border border-gray-300 shadow-sm text-sm rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 transition-colors">
  <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0zM10 7v3m0 0v3m0-3h3m-3 0H7" />
  </svg>
</button>

<button data-action="click->toolbar#fitToContent"
        title="Fit to Content"
        class="inline-flex items-center p-2 border border-gray-300 shadow-sm text-sm rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 transition-colors">
  <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 8V4m0 0h4M4 4l5 5m11-1V4m0 0h-4m4 0l-5 5M4 16v4m0 0h4m-4 0l5-5m11 5l-5-5m5 5v-4m0 4h-4" />
  </svg>
</button>
```

- [ ] **Step 7: Wire zoom controls in toolbar controller**

In `app/javascript/controllers/toolbar_controller.js`, add zoom methods following the existing pattern (uses `_getCanvasController()` for direct calls, same as undo/redo/clear):

```javascript
zoomIn(event) {
  event.preventDefault()
  const canvasController = this._getCanvasController()
  if (canvasController) canvasController.zoomIn()
}

zoomOut(event) {
  event.preventDefault()
  const canvasController = this._getCanvasController()
  if (canvasController) canvasController.zoomOut()
}

fitToContent(event) {
  event.preventDefault()
  const canvasController = this._getCanvasController()
  if (canvasController) canvasController.fitToContent()
}
```

In `flowchart_canvas_controller.js`, add the public zoom methods:
```javascript
zoomIn() {
  this.canvas.zoomPanManager.zoomIn()
  this._updateZoomDisplay()
}

zoomOut() {
  this.canvas.zoomPanManager.zoomOut()
  this._updateZoomDisplay()
}

fitToContent() {
  this.canvas.zoomPanManager.fitToContent(this.canvas.elements)
  this._updateZoomDisplay()
}

_updateZoomDisplay() {
  const label = document.querySelector("[data-toolbar-target='zoomLevel']")
  if (label) label.textContent = `${this.canvas.zoomPanManager.zoomPercent}%`
}
```

Wire `onZoomChange` callback in `_setupCanvasCallbacks` to update toolbar display:
```javascript
this.canvas.onZoomChange = (percent) => this._updateZoomDisplay()
```

- [ ] **Step 8: Add Ctrl+Plus/Minus keyboard zoom**

In `_handleKeyDown` (canvas.js), add keyboard zoom shortcuts:
```javascript
// Zoom In: Ctrl+= or Ctrl++
if (isMod && (e.key === "=" || e.key === "+")) {
  e.preventDefault()
  this.zoomPanManager.zoomIn()
  this.onZoomChange?.(this.zoomPanManager.zoomPercent)
  return
}

// Zoom Out: Ctrl+-
if (isMod && e.key === "-") {
  e.preventDefault()
  this.zoomPanManager.zoomOut()
  this.onZoomChange?.(this.zoomPanManager.zoomPercent)
  return
}

// Fit to Content: Ctrl+0
if (isMod && e.key === "0") {
  e.preventDefault()
  this.zoomPanManager.fitToContent(this.elements)
  this.onZoomChange?.(this.zoomPanManager.zoomPercent)
  return
}
```

- [ ] **Step 9: Verify zoom/pan works end-to-end**

Manual verification:
1. Load a flowchart with several elements
2. Ctrl+scroll should zoom in/out centered on cursor
3. Space+drag should pan the canvas
4. Zoom toolbar buttons (+/-/fit) should work
5. Ctrl+Plus/Minus should zoom from keyboard
6. Zoom percentage display should update
7. Elements should still be clickable, draggable, and connectable at all zoom levels
8. Double-click to edit properties should work at zoomed levels
9. Drag from palette should place elements at correct SVG coordinates

- [ ] **Step 10: Commit**

```bash
git add app/javascript/flowchart/zoom_pan_manager.js app/javascript/flowchart/canvas.js app/javascript/flowchart/constants/canvas.js app/views/flowcharts/_editor.html.erb app/javascript/controllers/flowchart_canvas_controller.js app/javascript/controllers/toolbar_controller.js
git commit -m "feat: add zoom/pan with viewBox-based coordinate system

Adds ZoomPanManager for SVG viewBox manipulation. Supports Ctrl+scroll
zoom, Space+drag pan, keyboard shortcuts (Ctrl+/-/0), and toolbar
controls with zoom percentage display."
```

---

## Task 2: Dynamic Canvas Size

**Files:**
- Modify: `app/javascript/flowchart/canvas.js:104-113,124-146` (`_createSvg`, `_drawGrid`)
- Modify: `app/javascript/flowchart/zoom_pan_manager.js`
- Modify: `app/views/flowcharts/_editor.html.erb:130-141` (remove hardcoded dimensions)
- Modify: `app/javascript/flowchart/constants/canvas.js` (remove CANVAS_WIDTH/CANVAS_HEIGHT)

- [ ] **Step 1: Remove hardcoded canvas dimensions from HTML**

In `app/views/flowcharts/_editor.html.erb`, change line 130-131:

From:
```erb
<div class="flex-1 min-w-0 bg-gray-50 overflow-auto" data-flowchart-canvas-target="canvasContainer">
  <div class="relative w-[2000px] h-[1500px]" data-flowchart-canvas-target="canvasWrapper">
```

To:
```erb
<div class="flex-1 min-w-0 bg-gray-50 overflow-hidden relative" data-flowchart-canvas-target="canvasContainer">
  <div class="absolute inset-0" data-flowchart-canvas-target="canvasWrapper">
```

Also change line 134:
From: `class="flowchart-canvas-container w-[2000px] h-[1500px]"`
To: `class="flowchart-canvas-container w-full h-full"`

- [ ] **Step 2: Remove CANVAS_WIDTH/CANVAS_HEIGHT from constants and update all usages**

In `app/javascript/flowchart/constants/canvas.js`:
- Remove `export const CANVAS_WIDTH = 2000` and `export const CANVAS_HEIGHT = 1500`
- Add `export const CANVAS_PADDING = 200` (padding around content before canvas edge triggers extension)
- Add `export const GUIDE_EXTENT = 10000` (extent for alignment guide lines in infinite canvas)

Update all imports throughout the codebase:

**`app/javascript/flowchart/canvas.js`** — already handled in Task 1 (`_createSvg` no longer uses them). Also update `getConfiguration()` (line 1384-1391) — remove CANVAS_WIDTH/CANVAS_HEIGHT from metadata:
```javascript
return {
  elements,
  connections,
  metadata: {
    created_at: new Date().toISOString()
  }
}
```

**`app/javascript/flowchart/drag_handler.js`** (lines 12-13) — remove `CANVAS_WIDTH, CANVAS_HEIGHT` from imports, add `GUIDE_EXTENT`. Update alignment guide lines (lines 628, 633):
```javascript
// Line 628: was CANVAS_HEIGHT
this._addGuideLine(el.x, 0, el.x, GUIDE_EXTENT)

// Line 633: was CANVAS_WIDTH
this._addGuideLine(0, el.y, GUIDE_EXTENT, el.y)
```

- [ ] **Step 3: Update grid to use viewBox-aware rendering**

The grid pattern uses `patternUnits="userSpaceOnUse"` which already works correctly with viewBox — the grid repeats in SVG coordinate space regardless of zoom. The grid rect uses `width="100%"` and `height="100%"` which fills the SVG viewport.

However, we need the grid to extend across the infinite canvas. Change the grid rect in `_drawGrid()`:
```javascript
_drawGrid() {
  const defs = createSvgElement("defs")
  const pattern = createSvgElement("pattern", {
    id: "grid-pattern",
    width: GRID_SIZE,
    height: GRID_SIZE,
    patternUnits: "userSpaceOnUse"
  })

  pattern.appendChild(createSvgElement("path", {
    d: `M ${GRID_SIZE} 0 L 0 0 0 ${GRID_SIZE}`,
    fill: "none",
    stroke: "#f0f0f0",
    "stroke-width": "0.5"
  }))

  defs.appendChild(pattern)
  this.svg.insertBefore(defs, this.svg.firstChild)

  // Use a very large rect to cover any pan position
  this.gridRect = createRect(-10000, -10000, 20000, 20000, {
    fill: "url(#grid-pattern)"
  })
  this.gridLayer.appendChild(this.gridRect)
}
```

- [ ] **Step 4: Update _scrollToElement to use zoom/pan instead of DOM scroll**

Replace `_scrollToElement` (canvas.js line 1319):
```javascript
_scrollToElement(element) {
  this.zoomPanManager.fitToContent([element], 200)
  this.onZoomChange?.(this.zoomPanManager.zoomPercent)
}
```

- [ ] **Step 5: Verify dynamic canvas**

Manual verification:
1. Canvas should fill its container (no scrollbars)
2. Grid should be visible everywhere when panning
3. Elements placed far apart should all be reachable via pan
4. Fit-to-content should show all elements regardless of position
5. No visual glitches at canvas edges

- [ ] **Step 6: Commit**

```bash
git add app/javascript/flowchart/canvas.js app/javascript/flowchart/constants/canvas.js app/views/flowcharts/_editor.html.erb app/javascript/flowchart/zoom_pan_manager.js
git commit -m "feat: dynamic infinite canvas, remove fixed 2000x1500 boundary

Canvas now fills container and extends infinitely via viewBox panning.
Grid covers all pan positions. Removed hardcoded CANVAS_WIDTH/HEIGHT."
```

---

## Task 3: Copy/Paste

**Files:**
- Create: `app/javascript/flowchart/clipboard_manager.js`
- Modify: `app/javascript/flowchart/canvas.js:326-349` (`_handleKeyDown`)

- [ ] **Step 1: Create ClipboardManager**

Create `app/javascript/flowchart/clipboard_manager.js`:

```javascript
import { generateId, snapToGrid } from "utils"
import { GRID_SIZE } from "flowchart/constants"

export class ClipboardManager {
  constructor(canvas) {
    this.canvas = canvas
    this.clipboard = null // { elements: [], connections: [] }
  }

  /** Copy selected elements and their internal connections */
  copy() {
    const selected = this.canvas.selectedElements
    if (selected.length === 0) return false

    const selectedIds = new Set(selected.map(el => el.id))

    // Deep clone elements
    const elements = selected.map(el => JSON.parse(JSON.stringify(el)))

    // Copy only connections between selected elements
    const connections = this.canvas.connections
      .filter(c => selectedIds.has(c.from) && selectedIds.has(c.to))
      .map(c => JSON.parse(JSON.stringify(c)))

    this.clipboard = { elements, connections }
    return true
  }

  /** Paste clipboard contents at offset from original positions */
  paste() {
    if (!this.clipboard) return []

    const idMap = new Map()
    const offset = 30 // pixels offset from original

    // Generate new IDs and offset positions
    const newElements = this.clipboard.elements.map(el => {
      const newId = generateId("el")
      idMap.set(el.id, newId)
      return {
        ...el,
        id: newId,
        x: snapToGrid(el.x + offset, GRID_SIZE),
        y: snapToGrid(el.y + offset, GRID_SIZE),
        label: el.label
      }
    })

    // Remap connection IDs
    const newConnections = this.clipboard.connections.map(c => ({
      ...c,
      id: generateId("conn"),
      from: idMap.get(c.from),
      to: idMap.get(c.to)
    }))

    return { elements: newElements, connections: newConnections }
  }

  /** Copy and paste in one action (duplicate) */
  duplicate() {
    if (this.copy()) {
      return this.paste()
    }
    return null
  }

  get hasContent() {
    return this.clipboard !== null && this.clipboard.elements.length > 0
  }
}
```

- [ ] **Step 2: Integrate ClipboardManager into FlowchartCanvas**

In `canvas.js`, add import:
```javascript
import { ClipboardManager } from "flowchart/clipboard_manager"
```

In the constructor (after `this.zoomPanManager` init):
```javascript
this.clipboardManager = new ClipboardManager(this)
```

Add a method to handle paste results:
```javascript
_pasteElements(pasteResult) {
  if (!pasteResult) return

  this.onBeforeChange?.()
  this._clearSelection()

  // Add elements to canvas
  for (const el of pasteResult.elements) {
    this.elements.push(el)
    this.renderElement(el)
    this._addToSelection(el)
  }

  // Add connections
  for (const conn of pasteResult.connections) {
    this.connections.push(conn)
  }

  this.updateConnections()
  this.onchange?.()
  this.onElementSelected?.(pasteResult.elements[pasteResult.elements.length - 1])
}
```

Note: calling `onElementSelected` at the end ensures the alignment toolbar updates when multiple elements are pasted and selected.

- [ ] **Step 3: Add keyboard shortcuts for copy/paste/duplicate**

In `_handleKeyDown` (canvas.js), add before the Delete handler:

```javascript
// Copy: Ctrl+C
if (isMod && e.key === "c") {
  if (this.selectedElements.length > 0) {
    e.preventDefault()
    this.clipboardManager.copy()
  }
  return
}

// Paste: Ctrl+V
if (isMod && e.key === "v") {
  if (this.clipboardManager.hasContent) {
    e.preventDefault()
    this._pasteElements(this.clipboardManager.paste())
  }
  return
}

// Duplicate: Ctrl+D
if (isMod && e.key === "d") {
  if (this.selectedElements.length > 0) {
    e.preventDefault()
    this._pasteElements(this.clipboardManager.duplicate())
  }
  return
}
```

- [ ] **Step 4: Verify copy/paste**

Manual verification:
1. Select single element, Ctrl+C, Ctrl+V — new element appears offset by 30px
2. Select multiple elements with Ctrl+drag rectangle, Ctrl+C, Ctrl+V — group appears with internal connections preserved
3. Ctrl+D duplicates in place
4. Pasted elements are selected (original deselected)
5. Connections to non-copied elements are NOT included
6. Undo after paste removes all pasted elements

- [ ] **Step 5: Commit**

```bash
git add app/javascript/flowchart/clipboard_manager.js app/javascript/flowchart/canvas.js
git commit -m "feat: add copy/paste/duplicate for flowchart elements

Ctrl+C/V copies and pastes selected elements with internal connections.
Ctrl+D duplicates in place. New IDs generated, positions offset by 30px."
```

---

## Task 4: Alignment Tools

**Files:**
- Create: `app/javascript/flowchart/alignment_manager.js`
- Modify: `app/javascript/flowchart/canvas.js` (integrate alignment manager)
- Modify: `app/views/flowcharts/_editor.html.erb` (add alignment toolbar)

- [ ] **Step 1: Create AlignmentManager**

Create `app/javascript/flowchart/alignment_manager.js`:

```javascript
import { snapToGrid } from "utils"
import { GRID_SIZE } from "flowchart/constants"

export class AlignmentManager {
  constructor(canvas) {
    this.canvas = canvas
  }

  /** Align selected elements to leftmost element's left edge */
  alignLeft() {
    const elements = this.canvas.selectedElements
    if (elements.length < 2) return
    const minX = Math.min(...elements.map(el => el.x - el.width / 2))
    this._applyAlignment(elements, el => {
      el.x = snapToGrid(minX + el.width / 2, GRID_SIZE)
    })
  }

  /** Align selected elements to horizontal center */
  alignCenterH() {
    const elements = this.canvas.selectedElements
    if (elements.length < 2) return
    const avgX = elements.reduce((sum, el) => sum + el.x, 0) / elements.length
    this._applyAlignment(elements, el => {
      el.x = snapToGrid(avgX, GRID_SIZE)
    })
  }

  /** Align selected elements to rightmost element's right edge */
  alignRight() {
    const elements = this.canvas.selectedElements
    if (elements.length < 2) return
    const maxX = Math.max(...elements.map(el => el.x + el.width / 2))
    this._applyAlignment(elements, el => {
      el.x = snapToGrid(maxX - el.width / 2, GRID_SIZE)
    })
  }

  /** Align selected elements to topmost element's top edge */
  alignTop() {
    const elements = this.canvas.selectedElements
    if (elements.length < 2) return
    const minY = Math.min(...elements.map(el => el.y - el.height / 2))
    this._applyAlignment(elements, el => {
      el.y = snapToGrid(minY + el.height / 2, GRID_SIZE)
    })
  }

  /** Align selected elements to vertical center */
  alignCenterV() {
    const elements = this.canvas.selectedElements
    if (elements.length < 2) return
    const avgY = elements.reduce((sum, el) => sum + el.y, 0) / elements.length
    this._applyAlignment(elements, el => {
      el.y = snapToGrid(avgY, GRID_SIZE)
    })
  }

  /** Align selected elements to bottommost element's bottom edge */
  alignBottom() {
    const elements = this.canvas.selectedElements
    if (elements.length < 2) return
    const maxY = Math.max(...elements.map(el => el.y + el.height / 2))
    this._applyAlignment(elements, el => {
      el.y = snapToGrid(maxY - el.height / 2, GRID_SIZE)
    })
  }

  /** Distribute selected elements evenly horizontally */
  distributeH() {
    const elements = this.canvas.selectedElements
    if (elements.length < 3) return
    const sorted = [...elements].sort((a, b) => a.x - b.x)
    const first = sorted[0].x
    const last = sorted[sorted.length - 1].x
    const step = (last - first) / (sorted.length - 1)
    this._applyAlignment(sorted, (el, i) => {
      el.x = snapToGrid(first + step * i, GRID_SIZE)
    })
  }

  /** Distribute selected elements evenly vertically */
  distributeV() {
    const elements = this.canvas.selectedElements
    if (elements.length < 3) return
    const sorted = [...elements].sort((a, b) => a.y - b.y)
    const first = sorted[0].y
    const last = sorted[sorted.length - 1].y
    const step = (last - first) / (sorted.length - 1)
    this._applyAlignment(sorted, (el, i) => {
      el.y = snapToGrid(first + step * i, GRID_SIZE)
    })
  }

  _applyAlignment(elements, transform) {
    this.canvas.onBeforeChange?.()
    elements.forEach((el, i) => {
      transform(el, i)
      this.canvas.updateElementPosition(el)
    })
    this.canvas.updateConnections()
    this.canvas.onchange?.()
  }
}
```

- [ ] **Step 2: Integrate AlignmentManager into FlowchartCanvas**

In `canvas.js`, add import:
```javascript
import { AlignmentManager } from "flowchart/alignment_manager"
```

In constructor:
```javascript
this.alignmentManager = new AlignmentManager(this)
```

- [ ] **Step 3: Add alignment toolbar to editor UI**

In `app/views/flowcharts/_editor.html.erb`, add a floating alignment toolbar that appears when 2+ elements are selected. Add this inside the canvas container div (after the overlay div, line 140):

```erb
<!-- Alignment Toolbar (shown when 2+ elements selected) -->
<div data-flowchart-canvas-target="alignmentToolbar"
     class="absolute top-2 left-1/2 -translate-x-1/2 bg-white border border-gray-200 rounded-lg shadow-lg px-2 py-1 flex items-center space-x-1 z-20 hidden">
  <button data-action="click->flowchart-canvas#alignLeft" title="Align Left"
          class="p-1.5 rounded hover:bg-gray-100 text-gray-600 hover:text-gray-900">
    <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-width="2" d="M4 4v16M8 8h10M8 16h6"/></svg>
  </button>
  <button data-action="click->flowchart-canvas#alignCenterH" title="Align Center Horizontal"
          class="p-1.5 rounded hover:bg-gray-100 text-gray-600 hover:text-gray-900">
    <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-width="2" d="M12 4v16M7 8h10M9 16h6"/></svg>
  </button>
  <button data-action="click->flowchart-canvas#alignRight" title="Align Right"
          class="p-1.5 rounded hover:bg-gray-100 text-gray-600 hover:text-gray-900">
    <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-width="2" d="M20 4v16M6 8h10M10 16h6"/></svg>
  </button>
  <div class="w-px h-5 bg-gray-300"></div>
  <button data-action="click->flowchart-canvas#alignTop" title="Align Top"
          class="p-1.5 rounded hover:bg-gray-100 text-gray-600 hover:text-gray-900">
    <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-width="2" d="M4 4h16M8 8v10M16 8v6"/></svg>
  </button>
  <button data-action="click->flowchart-canvas#alignCenterV" title="Align Center Vertical"
          class="p-1.5 rounded hover:bg-gray-100 text-gray-600 hover:text-gray-900">
    <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-width="2" d="M4 12h16M8 7v10M16 9v6"/></svg>
  </button>
  <button data-action="click->flowchart-canvas#alignBottom" title="Align Bottom"
          class="p-1.5 rounded hover:bg-gray-100 text-gray-600 hover:text-gray-900">
    <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-width="2" d="M4 20h16M8 6v10M16 10v6"/></svg>
  </button>
  <div class="w-px h-5 bg-gray-300" data-flowchart-canvas-target="distributesSeparator" style="display:none"></div>
  <button data-action="click->flowchart-canvas#distributeH" title="Distribute Horizontally"
          data-flowchart-canvas-target="distributeHBtn" style="display:none"
          class="p-1.5 rounded hover:bg-gray-100 text-gray-600 hover:text-gray-900">
    <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-width="2" d="M4 4v16M20 4v16M9 12h6"/></svg>
  </button>
  <button data-action="click->flowchart-canvas#distributeV" title="Distribute Vertically"
          data-flowchart-canvas-target="distributeVBtn" style="display:none"
          class="p-1.5 rounded hover:bg-gray-100 text-gray-600 hover:text-gray-900">
    <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-width="2" d="M4 4h16M4 20h16M12 9v6"/></svg>
  </button>
</div>
```

- [ ] **Step 4: Wire alignment toolbar show/hide logic**

In `flowchart_canvas_controller.js`, add Stimulus targets:
```javascript
static targets = [...existing, "alignmentToolbar", "distributesSeparator", "distributeHBtn", "distributeVBtn"]
```

Add alignment action methods:
```javascript
alignLeft() { this.canvas.alignmentManager.alignLeft() }
alignCenterH() { this.canvas.alignmentManager.alignCenterH() }
alignRight() { this.canvas.alignmentManager.alignRight() }
alignTop() { this.canvas.alignmentManager.alignTop() }
alignCenterV() { this.canvas.alignmentManager.alignCenterV() }
alignBottom() { this.canvas.alignmentManager.alignBottom() }
distributeH() { this.canvas.alignmentManager.distributeH() }
distributeV() { this.canvas.alignmentManager.distributeV() }
```

Add selection change handler to show/hide the toolbar. In `_setupCanvasCallbacks`:
```javascript
this.canvas.onElementSelected = (element) => {
  this._handleElementSelected({ detail: { element } })
  this._updateAlignmentToolbar()
}

// Also call _updateAlignmentToolbar after selection rect ends and after deselection
```

Add the update method:
```javascript
_updateAlignmentToolbar() {
  if (!this.hasAlignmentToolbarTarget) return
  const count = this.canvas.selectedElements.length
  if (count >= 2) {
    this.alignmentToolbarTarget.classList.remove("hidden")
    const show3 = count >= 3
    if (this.hasDistributesSeparatorTarget) this.distributesSeparatorTarget.style.display = show3 ? "" : "none"
    if (this.hasDistributeHBtnTarget) this.distributeHBtnTarget.style.display = show3 ? "" : "none"
    if (this.hasDistributeVBtnTarget) this.distributeVBtnTarget.style.display = show3 ? "" : "none"
  } else {
    this.alignmentToolbarTarget.classList.add("hidden")
  }
}
```

Also call `_updateAlignmentToolbar()` in `_handleCanvasClick` (when deselecting).

- [ ] **Step 5: Verify alignment tools**

Manual verification:
1. Select 2 elements with Ctrl+drag → alignment toolbar appears
2. Click "Align Left" → both elements align to the leftmost element's left edge
3. Select 3+ elements → distribute buttons appear
4. "Distribute Vertically" → elements evenly spaced
5. Deselect → toolbar hides
6. Each alignment operation is undoable with Ctrl+Z

- [ ] **Step 6: Commit**

```bash
git add app/javascript/flowchart/alignment_manager.js app/javascript/flowchart/canvas.js app/javascript/controllers/flowchart_canvas_controller.js app/views/flowcharts/_editor.html.erb
git commit -m "feat: add alignment and distribution tools for multi-selected elements

Floating toolbar appears when 2+ elements selected with align left/center/
right/top/middle/bottom. Distribute H/V appears for 3+ elements."
```

---

## Task 5: Flowchart Validation

**Files:**
- Create: `app/javascript/flowchart/validation_service.js`
- Modify: `app/views/flowcharts/_editor.html.erb` (add validate button + problems panel)
- Modify: `app/javascript/controllers/flowchart_canvas_controller.js` (wire validation)
- Modify: `app/services/activity_generator.rb` (add server-side validation guard)
- Create: `spec/services/flowchart_validator_spec.rb`

- [ ] **Step 1: Create client-side ValidationService**

Create `app/javascript/flowchart/validation_service.js`:

```javascript
/**
 * Validates flowchart structural integrity and completeness.
 * Returns { errors: [], warnings: [] } where each item is
 * { elementId: string|null, type: string, message: string }
 */
export class ValidationService {
  constructor(elements, connections) {
    this.elements = elements
    this.connections = connections
    this.errors = []
    this.warnings = []
  }

  validate() {
    this.errors = []
    this.warnings = []

    this._validateStructure()
    this._validateCompleteness()
    this._validateConnections()
    this._detectCycles()

    return { errors: this.errors, warnings: this.warnings }
  }

  get isValid() {
    return this.errors.length === 0
  }

  // --- Structural validation ---

  _validateStructure() {
    const startElements = this.elements.filter(el => el.type === "start")
    const endElements = this.elements.filter(el => el.type === "end")

    if (startElements.length === 0) {
      this.errors.push({ elementId: null, type: "missing_start", message: "Flowchart must have a Start element" })
    } else if (startElements.length > 1) {
      startElements.slice(1).forEach(el => {
        this.errors.push({ elementId: el.id, type: "duplicate_start", message: "Only one Start element is allowed" })
      })
    }

    if (endElements.length === 0) {
      this.warnings.push({ elementId: null, type: "missing_end", message: "Flowchart should have at least one End element" })
    }

    // Check for orphan elements (no connections)
    for (const el of this.elements) {
      const hasIncoming = this.connections.some(c => c.to === el.id)
      const hasOutgoing = this.connections.some(c => c.from === el.id)

      if (el.type === "start" && !hasOutgoing) {
        this.errors.push({ elementId: el.id, type: "orphan_start", message: `Start element "${el.label}" has no outgoing connections` })
      } else if (el.type === "end" && !hasIncoming) {
        this.warnings.push({ elementId: el.id, type: "orphan_end", message: `End element "${el.label}" has no incoming connections` })
      } else if (el.type !== "start" && el.type !== "end" && !hasIncoming && !hasOutgoing) {
        this.errors.push({ elementId: el.id, type: "orphan_element", message: `"${el.label}" is not connected to any other element` })
      }
    }

    // Check reachability from start
    if (startElements.length === 1) {
      const reachable = this._getReachableElements(startElements[0].id)
      for (const el of this.elements) {
        if (el.type !== "start" && !reachable.has(el.id)) {
          this.errors.push({ elementId: el.id, type: "unreachable", message: `"${el.label}" is not reachable from Start` })
        }
      }
    }
  }

  // --- Completeness validation ---

  _validateCompleteness() {
    for (const el of this.elements) {
      if (el.type === "process") {
        const steps = el.properties?.steps || []
        if (steps.length === 0) {
          this.warnings.push({ elementId: el.id, type: "empty_process", message: `Process "${el.label}" has no steps defined` })
        }
      }

      if (el.type === "decision") {
        const outgoing = this.connections.filter(c => c.from === el.id)
        if (outgoing.length < 2) {
          this.errors.push({ elementId: el.id, type: "decision_branches", message: `Decision "${el.label}" needs at least 2 outgoing connections (branches)` })
        }
        const condition = el.properties?.condition
        if (!condition || (!condition.leftOperand && !condition.expression)) {
          this.warnings.push({ elementId: el.id, type: "empty_condition", message: `Decision "${el.label}" has no condition defined` })
        }
      }

      if (el.type === "loop") {
        const condition = el.properties?.condition
        if (!condition || (!condition.leftOperand && !condition.expression)) {
          this.warnings.push({ elementId: el.id, type: "empty_loop_condition", message: `Loop "${el.label}" has no condition defined` })
        }
      }
    }
  }

  // --- Connection validation ---

  _validateConnections() {
    const elementIds = new Set(this.elements.map(el => el.id))
    const seen = new Set()

    for (const conn of this.connections) {
      // Check endpoints reference existing elements
      if (!elementIds.has(conn.from)) {
        this.errors.push({ elementId: null, type: "dangling_connection", message: `Connection references missing element (from: ${conn.from})` })
      }
      if (!elementIds.has(conn.to)) {
        this.errors.push({ elementId: null, type: "dangling_connection", message: `Connection references missing element (to: ${conn.to})` })
      }

      // Self-connections
      if (conn.from === conn.to) {
        this.errors.push({ elementId: conn.from, type: "self_connection", message: "Element cannot connect to itself" })
      }

      // Duplicate connections
      const key = `${conn.from}->${conn.to}`
      if (seen.has(key)) {
        this.warnings.push({ elementId: null, type: "duplicate_connection", message: `Duplicate connection between elements` })
      }
      seen.add(key)
    }
  }

  // --- Cycle detection ---

  _detectCycles() {
    const loopIds = new Set(this.elements.filter(el => el.type === "loop").map(el => el.id))
    const adjacency = new Map()
    for (const el of this.elements) {
      adjacency.set(el.id, [])
    }
    for (const conn of this.connections) {
      if (adjacency.has(conn.from)) {
        adjacency.get(conn.from).push(conn.to)
      }
    }

    const visited = new Set()
    const inStack = new Set()

    const dfs = (nodeId) => {
      visited.add(nodeId)
      inStack.add(nodeId)
      for (const neighbor of (adjacency.get(nodeId) || [])) {
        if (inStack.has(neighbor) && !loopIds.has(neighbor)) {
          this.warnings.push({ elementId: neighbor, type: "cycle", message: `Potential infinite loop: cycle detected not involving a Loop element` })
        }
        if (!visited.has(neighbor)) {
          dfs(neighbor)
        }
      }
      inStack.delete(nodeId)
    }

    for (const el of this.elements) {
      if (!visited.has(el.id)) {
        dfs(el.id)
      }
    }
  }

  // --- Helpers ---

  _getReachableElements(startId) {
    const reachable = new Set()
    const queue = [startId]
    while (queue.length > 0) {
      const current = queue.shift()
      if (reachable.has(current)) continue
      reachable.add(current)
      for (const conn of this.connections) {
        if (conn.from === current && !reachable.has(conn.to)) {
          queue.push(conn.to)
        }
      }
    }
    return reachable
  }
}
```

- [ ] **Step 2: Write the failing RSpec test for server-side validation**

Create `spec/services/flowchart_validator_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe ActivityGenerator do
  describe "validation guard" do
    let(:entity) { create(:entity) }

    context "with a flowchart missing start element" do
      let(:flowchart) do
        create(:flowchart, entity: entity, configuration: {
          elements: [
            { id: "el_1", type: "process", x: 400, y: 200, width: 100, height: 45, label: "Process", properties: {} }
          ],
          connections: [],
          metadata: {}
        }.to_json)
      end

      it "returns nil due to validation failure" do
        generator = described_class.new(flowchart)
        expect(generator.generate).to be_nil
      end
    end

    context "with multiple start elements" do
      let(:flowchart) do
        create(:flowchart, entity: entity, configuration: {
          elements: [
            { id: "el_1", type: "start", x: 100, y: 100, width: 100, height: 45, label: "Start 1", properties: {} },
            { id: "el_2", type: "start", x: 300, y: 100, width: 100, height: 45, label: "Start 2", properties: {} },
            { id: "el_3", type: "end", x: 200, y: 300, width: 100, height: 45, label: "End", properties: {} }
          ],
          connections: [
            { id: "c1", from: "el_1", to: "el_3" }
          ],
          metadata: {}
        }.to_json)
      end

      it "returns nil due to multiple start elements" do
        generator = described_class.new(flowchart)
        expect(generator.generate).to be_nil
      end
    end

    context "with a valid flowchart" do
      # Default factory has Start -> Process -> End with connections
      let(:flowchart) { create(:flowchart, entity: entity) }

      it "generates code successfully" do
        generator = described_class.new(flowchart)
        expect(generator.generate).to be_present
      end
    end
  end
end
```

- [ ] **Step 3: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/flowchart_validator_spec.rb -v`
Expected: The "missing start element" test may already pass since `generate` returns nil for empty flowcharts. Adjust test expectations based on actual behavior — the goal is to verify the validation guard catches structural issues.

- [ ] **Step 4: Add server-side validation guard to ActivityGenerator**

In `app/services/activity_generator.rb`, enhance the `generate` method (around line 63):

```ruby
def generate
  return nil if flowchart.name.blank? || elements.empty?

  # Structural validation
  validation_errors = validate_structure
  if validation_errors.any?
    Rails.logger.warn("Flowchart validation failed for #{flowchart.id}: #{validation_errors.join(', ')}")
    return nil
  end

  steps = dfs_collect_steps
  class_def = class_definition_with_steps(steps)
  [header(steps), class_def].compact.join("\n")
end

private

def validate_structure
  errors = []
  start_elements = elements.select { |el| el["type"] == "start" }
  end_elements = elements.select { |el| el["type"] == "end" }
  conns = flowchart.connections || []

  errors << "Missing Start element" if start_elements.empty?
  errors << "Multiple Start elements" if start_elements.length > 1
  errors << "Missing End element" if end_elements.empty?

  # Check for non-start elements with no incoming connections
  elements.each do |el|
    next if el["type"] == "start"
    has_incoming = conns.any? { |c| c["to"] == el["id"] }
    errors << "Element '#{el['label']}' has no incoming connections" unless has_incoming
  end

  errors
end
```

- [ ] **Step 5: Run specs to verify they pass**

Run: `bundle exec rspec spec/services/flowchart_validator_spec.rb spec/services/activity_generator_spec.rb -v`
Expected: All tests pass. Existing tests should not break since valid flowcharts pass validation.

- [ ] **Step 6: Add validation UI — toolbar button and problems panel**

In `app/views/flowcharts/_editor.html.erb`, add a Validate button in the toolbar's left section (after Save button, line 27):

```erb
<button data-action="click->flowchart-canvas#validate"
        class="inline-flex items-center px-3 py-2 border border-gray-300 shadow-sm text-sm leading-4 font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 transition-colors">
  <svg class="-ml-0.5 mr-2 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
  </svg>
  Validate
  <span data-flowchart-canvas-target="validationBadge"
        class="ml-2 inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800 hidden">
    0
  </span>
</button>
```

Add a problems panel at the bottom of the canvas container (after the alignment toolbar):

```erb
<!-- Validation Problems Panel -->
<div data-flowchart-canvas-target="validationPanel"
     class="absolute bottom-0 left-0 right-0 bg-white border-t border-gray-200 shadow-lg z-20 hidden max-h-48 overflow-y-auto">
  <div class="flex items-center justify-between px-4 py-2 border-b border-gray-100 bg-gray-50">
    <h4 class="text-sm font-medium text-gray-700">Problems</h4>
    <button data-action="click->flowchart-canvas#closeValidationPanel"
            class="text-gray-400 hover:text-gray-600 p-1">
      <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
      </svg>
    </button>
  </div>
  <div data-flowchart-canvas-target="validationList" class="divide-y divide-gray-100">
    <!-- Validation issues rendered here -->
  </div>
</div>
```

- [ ] **Step 7: Wire validation in flowchart canvas controller**

In `flowchart_canvas_controller.js`, add targets:
```javascript
static targets = [...existing, "validationBadge", "validationPanel", "validationList"]
```

Add import:
```javascript
import { ValidationService } from "flowchart/validation_service"
```

Add validation methods:
```javascript
validate() {
  const validator = new ValidationService(this.canvas.elements, this.canvas.connections)
  const { errors, warnings } = validator.validate()
  this._showValidationResults(errors, warnings)
  return validator.isValid
}

_showValidationResults(errors, warnings) {
  const total = errors.length + warnings.length

  // Update badge
  if (this.hasValidationBadgeTarget) {
    if (total > 0) {
      this.validationBadgeTarget.textContent = total
      this.validationBadgeTarget.classList.remove("hidden")
      this.validationBadgeTarget.classList.toggle("bg-red-100", errors.length > 0)
      this.validationBadgeTarget.classList.toggle("text-red-800", errors.length > 0)
      this.validationBadgeTarget.classList.toggle("bg-yellow-100", errors.length === 0)
      this.validationBadgeTarget.classList.toggle("text-yellow-800", errors.length === 0)
    } else {
      this.validationBadgeTarget.classList.add("hidden")
    }
  }

  // Update problems panel
  if (this.hasValidationListTarget) {
    const items = [...errors.map(e => ({ ...e, severity: "error" })), ...warnings.map(w => ({ ...w, severity: "warning" }))]
    this.validationListTarget.innerHTML = items.length === 0
      ? '<div class="px-4 py-3 text-sm text-green-600">No problems found</div>'
      : items.map(item => `
        <button class="w-full text-left px-4 py-2 hover:bg-gray-50 flex items-center space-x-2 text-sm"
                data-action="click->flowchart-canvas#focusValidationIssue"
                data-element-id="${item.elementId || ""}">
          <span class="flex-shrink-0 w-2 h-2 rounded-full ${item.severity === "error" ? "bg-red-500" : "bg-yellow-500"}"></span>
          <span class="${item.severity === "error" ? "text-red-700" : "text-yellow-700"}">${item.message}</span>
        </button>
      `).join("")
  }

  // Show panel
  if (this.hasValidationPanelTarget) {
    this.validationPanelTarget.classList.remove("hidden")
  }
}

closeValidationPanel() {
  if (this.hasValidationPanelTarget) {
    this.validationPanelTarget.classList.add("hidden")
  }
}

focusValidationIssue(event) {
  const elementId = event.currentTarget.dataset.elementId
  if (!elementId) return
  const element = this.canvas.elements.find(el => el.id === elementId)
  if (element) {
    // Use the public selection API (selectElement exposed via SelectionManager)
    this.canvas.selectedElements.forEach(el => this.canvas._setElementSelected(el, false))
    this.canvas.selectedElements = []
    this.canvas.selectedElements.push(element)
    this.canvas._setElementSelected(element, true)
    this.canvas.showConnectionHandles([element])
    // Zoom to element
    this.canvas.zoomPanManager.fitToContent([element], 300)
    this._updateZoomDisplay()
    this._updateAlignmentToolbar()
  }
}
```

- [ ] **Step 8: Verify validation end-to-end**

Manual verification:
1. Click "Validate" on a valid flowchart → "No problems found" panel
2. Delete the End element, validate → error shown for missing End
3. Create an orphan Process (no connections) → error for orphan element
4. Click on an error in the panel → canvas zooms to the problem element
5. Decision with < 2 outgoing connections → error shown
6. Badge shows error count with red/yellow coloring

- [ ] **Step 9: Commit**

```bash
git add app/javascript/flowchart/validation_service.js app/javascript/controllers/flowchart_canvas_controller.js app/views/flowcharts/_editor.html.erb app/services/activity_generator.rb spec/services/flowchart_validator_spec.rb
git commit -m "feat: add flowchart validation with problems panel

Client-side ValidationService checks structural integrity (start/end
presence, orphans, reachability, cycles) and completeness (steps,
conditions, branches). Server-side guard in ActivityGenerator blocks
code generation for invalid flowcharts. Clickable problems panel
zooms to issue elements."
```

---

## Task 6: Undo/Redo Persistence & Navigation Warning

**Files:**
- Modify: `app/javascript/controllers/flowchart_canvas/undo_redo_manager.js`
- Modify: `app/javascript/controllers/flowchart_canvas_controller.js`
- Modify: `app/views/flowcharts/_editor.html.erb` (unsaved changes indicator)

- [ ] **Step 1: Add beforeunload warning for unsaved changes**

In `flowchart_canvas_controller.js`, add in `connect()` (after canvas initialization):

```javascript
this._beforeUnload = (e) => {
  if (this.hasUnsavedChanges) {
    e.preventDefault()
    e.returnValue = ""
  }
}
window.addEventListener("beforeunload", this._beforeUnload)
```

In `disconnect()`:
```javascript
window.removeEventListener("beforeunload", this._beforeUnload)
```

- [ ] **Step 2: Add unsaved changes visual indicator**

In `app/views/flowcharts/_editor.html.erb`, modify the save status text (line 25-27):

```erb
<div class="flex items-center space-x-2">
  <div data-flowchart-canvas-target="unsavedIndicator"
       class="flex items-center text-sm text-amber-600 hidden">
    <span class="w-2 h-2 rounded-full bg-amber-500 mr-1.5 animate-pulse"></span>
    Unsaved changes
  </div>
  <div class="text-sm text-gray-500" data-toolbar-target="saveStatus">
    Ready
  </div>
</div>
```

Add `unsavedIndicator` to the `flowchart_canvas_controller.js` targets:
```javascript
static targets = [...existing, "unsavedIndicator"]
```

In the `onchange` callback:
```javascript
this.canvas.onchange = () => {
  if (!this.isCanvasReady) return
  this.hasUnsavedChanges = true
  this.undoRedoManager.commitPendingState()
  this._dispatchConfigurationChange()
  this._updateUnsavedIndicator()
}
```

After successful save in `_saveToServer`:
```javascript
this.hasUnsavedChanges = false
this._updateUnsavedIndicator()
```

Add the helper:
```javascript
_updateUnsavedIndicator() {
  if (this.hasUnsavedIndicatorTarget) {
    this.unsavedIndicatorTarget.classList.toggle("hidden", !this.hasUnsavedChanges)
  }
}
```

- [ ] **Step 3: Persist undo stack to sessionStorage**

Modify `app/javascript/controllers/flowchart_canvas/undo_redo_manager.js`:

Add a storage key property in constructor:
```javascript
constructor(controller) {
  this.controller = controller
  this.maxUndoStates = 50
  this.isUndoRedoOperation = false
  this.pendingUndoState = null
  this._storageKey = `flowchart_undo_${controller.idValue}`
  this._restoreFromStorage()
}
```

Add storage methods:
```javascript
_restoreFromStorage() {
  try {
    const stored = sessionStorage.getItem(this._storageKey)
    if (stored) {
      const { undoStack, redoStack } = JSON.parse(stored)
      this.undoStack = undoStack || []
      this.redoStack = redoStack || []
      return
    }
  } catch (e) {
    // sessionStorage unavailable or corrupt — fall back to empty stacks
  }
  this.undoStack = []
  this.redoStack = []
}

_persistToStorage() {
  try {
    // Only persist last 10 states to limit sessionStorage size.
    // In-memory stack holds 50 states; after refresh, user gets 10 undo levels.
    // This is an intentional trade-off: sessionStorage has ~5MB limit and
    // flowchart configurations can be large.
    sessionStorage.setItem(this._storageKey, JSON.stringify({
      undoStack: this.undoStack.slice(-10),
      redoStack: this.redoStack.slice(-10)
    }))
  } catch (e) {
    // sessionStorage full or unavailable — silently fail
  }
}
```

Call `_persistToStorage()` at the end of `commitPendingState()`, `undo()`, and `redo()`.

Modify `saveInitialState()` — skip if undo stack already has content (restored from storage):
```javascript
saveInitialState() {
  if (this.undoStack.length > 0) return // Already restored from sessionStorage
  const state = this.captureCurrentState()
  if (state) {
    this.undoStack.push(state)
    this._persistToStorage()
  }
}
```

- [ ] **Step 4: Clean up sessionStorage on page unload for completed saves**

In `flowchart_canvas_controller.js`, after a successful save, optionally clear redo stack since saved state is now the baseline:

```javascript
// In _saveToServer, after success:
this.undoRedoManager.redoStack = []
this.undoRedoManager._persistToStorage()
```

- [ ] **Step 5: Verify undo persistence and navigation warning**

Manual verification:
1. Make changes to a flowchart → "Unsaved changes" indicator appears
2. Save → indicator disappears
3. Make changes, try to close tab → browser warns about unsaved changes
4. Make changes, Ctrl+Z to undo, then refresh the page → undo history is restored from sessionStorage
5. Ctrl+Z after refresh → reverts to previous state
6. Save and close tab → no unsaved warning shown

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/flowchart_canvas/undo_redo_manager.js app/javascript/controllers/flowchart_canvas_controller.js app/views/flowcharts/_editor.html.erb
git commit -m "feat: add undo persistence, unsaved changes warning, and indicator

Undo/redo stack persisted to sessionStorage (survives page refresh).
beforeunload handler warns when leaving with unsaved changes. Visual
amber indicator with pulse animation shows unsaved state."
```

---

## Verification Checklist

After all tasks are complete, perform a full integration test:

- [ ] **Zoom/Pan:** Ctrl+scroll zooms, Space+drag pans, toolbar controls work, coordinates are correct at all zoom levels
- [ ] **Dynamic Canvas:** No fixed boundary, grid everywhere, fit-to-content works
- [ ] **Copy/Paste:** Ctrl+C/V/D works for single and multi-select, connections preserved
- [ ] **Alignment:** Floating toolbar for 2+ selected, all align/distribute commands work
- [ ] **Validation:** Catches structural and completeness issues, problems panel with click-to-focus
- [ ] **Undo Persistence:** Undo stack survives refresh, beforeunload warning works, unsaved indicator shows
- [ ] **No Regressions:** Existing features (drag, connect, property editor, save, subflows) all work correctly
