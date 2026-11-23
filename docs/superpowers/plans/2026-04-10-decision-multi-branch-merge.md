# Decision Multi-Branch + Merge Element Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign Decision element with dynamic output ports and case/when UI, and add a new Merge element for selective branch convergence.

**Architecture:** Decision elements get dynamic output ports computed from branch configuration. A new Merge element type (pure flow-control, no business logic) allows selective branch convergence. The topology analyzer gains `merge_groups` and generates compound guards for post-merge steps.

**Tech Stack:** StimulusJS, SVG canvas, ViewComponent, Trailblazer Activity, RSpec

---

## File Structure

### New Files
- `app/components/flowchart_elements/merge_element_component.rb` — Merge element ViewComponent
- `app/components/flowchart_elements/merge_element_component.html.erb` — Merge element template
- `app/javascript/flowchart/dynamic_ports.js` — Dynamic port calculation for Decision and Merge elements
- `app/javascript/controllers/property_editor/merge_manager.js` — Merge element property editor logic
- `spec/components/flowchart_elements/merge_element_component_spec.rb` — Merge ViewComponent specs

### Modified Files
- `app/javascript/flowchart/constants/elements.js:52-79` — Add merge color and label
- `app/javascript/flowchart/element_renderer.js:271-284,379-393` — Add merge shape, integrate dynamic ports
- `app/javascript/flowchart/connection_manager.js:45-78,394-412,632-670` — Port-aware connections and handles
- `app/javascript/controllers/property_editor/branch_manager.js:24-89,187-250` — Case/when branch UI
- `app/javascript/controllers/property_editor_controller.js:35-50,373-436` — Register MergeManager, delegate actions
- `app/services/flowchart_topology_analyzer.rb:14-68,135-151` — Add merge_groups, compound guards
- `app/services/activity_generator.rb:340-381` — Compound guard generation, merge no-op
- `app/views/flowcharts/_editor.html.erb:192` — Add Merge to element palette
- `app/components/flowchart_elements/base_element_component.rb:164-182` — Add merge icon
- `spec/services/flowchart_topology_analyzer_spec.rb` — Add merge-related specs
- `spec/services/activity_generator_spec.rb` — Add compound guard specs

---

### Task 1: Add Merge Element Color, Label, and Shape Constants

**Files:**
- Modify: `app/javascript/flowchart/constants/elements.js:52-61,71-79`

- [ ] **Step 1: Add merge color and label constants**

In `app/javascript/flowchart/constants/elements.js`, add the merge entry to `ELEMENT_COLORS` and `DEFAULT_LABELS`:

```javascript
// In ELEMENT_COLORS, after the timer entry:
export const ELEMENT_COLORS = {
  start: { fill: "#f0fdf4", stroke: "#10b981" },
  end: { fill: "#fef2f2", stroke: "#ef4444" },
  process: { fill: "#f8fafc", stroke: "#3b82f6" },
  decision: { fill: "#fefce8", stroke: "#f59e0b" },
  loop: { fill: "#faf5ff", stroke: "#a855f7" },
  merge: { fill: "#ede9fe", stroke: "#8b5cf6" },
  subflow: { fill: "#ecfeff", stroke: "#06b6d4" },
  error_handler: { fill: "#fff7ed", stroke: "#ea580c" },
  timer: { fill: "#f8fafc", stroke: "#64748b" }
}

// In DEFAULT_LABELS:
export const DEFAULT_LABELS = {
  start: "Start",
  end: "End",
  process: "Process",
  decision: "Decision",
  merge: "Merge",
  loop: "Loop",
  error_handler: "Error Handler",
  timer: "Timer"
}
```

- [ ] **Step 2: Verify no import errors**

Run: `bundle exec rails assets:precompile 2>&1 | head -5`
Expected: No errors related to constants

- [ ] **Step 3: Commit**

```bash
git add app/javascript/flowchart/constants/elements.js
git commit -m "feat: add merge element color and label constants"
```

---

### Task 2: Create MergeElementComponent ViewComponent

**Files:**
- Create: `app/components/flowchart_elements/merge_element_component.rb`
- Create: `app/components/flowchart_elements/merge_element_component.html.erb`
- Modify: `app/components/flowchart_elements/base_element_component.rb:164-182`

- [ ] **Step 1: Create the MergeElementComponent class**

Create `app/components/flowchart_elements/merge_element_component.rb`:

```ruby
# frozen_string_literal: true

module FlowchartElements
  class MergeElementComponent < BaseElementComponent
    def initialize(**args)
      super(element_type: :merge, **args)
    end

    private

    def default_label
      "Merge"
    end

    def element_specific_classes
      "bg-violet-50 border-violet-400 text-violet-800 hover:border-violet-600"
    end
  end
end
```

- [ ] **Step 2: Create the template**

Create `app/components/flowchart_elements/merge_element_component.html.erb` by checking the existing pattern. First, read an existing template like `decision_element_component.html.erb` to follow the same pattern, then create the merge version.

Run: `ls app/components/flowchart_elements/*.html.erb` to find the template pattern.

The template should follow the exact same structure as the other element components.

- [ ] **Step 3: Add merge_icon to BaseElementComponent**

In `app/components/flowchart_elements/base_element_component.rb`, add the `merge_icon` method and update `render_icon`:

```ruby
# Add after decision_icon method (around line 89):
def merge_icon
  content_tag :svg, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", class: icon_classes do
    safe_join([
      content_tag(:path, "", d: "M6 4v6l6 4 6-4V4", 'stroke-width': "2", 'stroke-linecap': "round", 'stroke-linejoin': "round"),
      content_tag(:path, "", d: "M12 14v6", 'stroke-width': "2", 'stroke-linecap': "round")
    ])
  end
end
```

In `render_icon`, add the merge case:

```ruby
when 'merge' then merge_icon
```

- [ ] **Step 4: Add Merge to the editor palette**

In `app/views/flowcharts/_editor.html.erb`, around line 192 (after DecisionElementComponent), add:

```erb
<%= render FlowchartElements::MergeElementComponent.new %>
```

- [ ] **Step 5: Verify in browser**

Run: `bundle exec rails assets:precompile 2>&1 | head -5`
Navigate to the flowchart editor and verify Merge appears in the left sidebar.

- [ ] **Step 6: Commit**

```bash
git add app/components/flowchart_elements/merge_element_component.rb
git add app/components/flowchart_elements/merge_element_component.html.erb
git add app/components/flowchart_elements/base_element_component.rb
git add app/views/flowcharts/_editor.html.erb
git commit -m "feat: add MergeElementComponent and sidebar palette entry"
```

---

### Task 3: Add Merge Shape to Element Renderer

**Files:**
- Modify: `app/javascript/flowchart/element_renderer.js:271-284`

- [ ] **Step 1: Add _createMergeShape method**

In `app/javascript/flowchart/element_renderer.js`, add a new shape creator after `_createBarShape` (around line 438):

```javascript
_createMergeShape(element, colors) {
  const { width: w, height: h } = element
  const group = createGroup()

  // Rounded rectangle bar
  group.appendChild(createRect(0, 0, w, h, {
    fill: colors.fill,
    stroke: colors.stroke,
    "stroke-width": SHAPE_CONFIG.strokeWidth,
    rx: 6,
    ry: 6
  }))

  // Converging arrows icon (top-left)
  const iconGroup = createGroup({ transform: `translate(8, ${h / 2 - 5})` })
  iconGroup.appendChild(createPath("M2 2l5 4-5 4M12 2l-5 4 5 4", {
    fill: "none",
    stroke: colors.stroke,
    "stroke-width": "1.2",
    "stroke-linecap": "round",
    "stroke-linejoin": "round",
    opacity: "0.5"
  }))
  group.appendChild(iconGroup)

  return group
}
```

- [ ] **Step 2: Register merge in shapeCreators**

In `_createShape` (line 271), add merge to the shapeCreators map:

```javascript
_createShape(element, colors) {
  const shapeCreators = {
    start: this._createOvalShape,
    end: this._createOvalShape,
    decision: this._createDiamondShape,
    merge: this._createMergeShape,
    loop: this._createLoopShape,
    subflow: this._createSubflowShape,
    error_handler: this._createErrorHandlerShape,
    timer: this._createRectShape
  }

  const creator = shapeCreators[element.type] || this._createRectShape
  return creator.call(this, element, colors)
}
```

- [ ] **Step 3: Verify in browser**

Drag a Merge element onto the canvas and verify it renders as a purple rounded rectangle bar.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/flowchart/element_renderer.js
git commit -m "feat: add merge shape renderer to canvas"
```

---

### Task 4: Create Dynamic Port Calculator Module

**Files:**
- Create: `app/javascript/flowchart/dynamic_ports.js`

- [ ] **Step 1: Create the dynamic_ports.js module**

Create `app/javascript/flowchart/dynamic_ports.js`:

```javascript
/**
 * DynamicPorts - Calculates dynamic port positions for Decision and Merge elements.
 *
 * Decision: input at top, output ports distributed along lower-half diamond perimeter.
 * Merge: input ports along top edge, single output at bottom center.
 */

/**
 * Get dynamic port positions for a Decision element.
 * Ports are distributed along the lower-half diamond perimeter (left vertex → bottom → right vertex).
 *
 * @param {Object} element - The decision element { x, y, width, height, properties }
 * @returns {Object} { input: {position, x, y}, outputs: [{position, x, y, branchKey, label}] }
 */
export function getDecisionPorts(element) {
  const hw = element.width / 2
  const hh = element.height / 2
  const branches = element.properties?.branches || []

  // Input: always top vertex
  const input = { position: "top", x: element.x, y: element.y - hh }

  // If no branches configured, return just bottom as default output
  if (branches.length === 0) {
    return {
      input,
      outputs: [
        { position: "port_0", x: element.x, y: element.y + hh, branchKey: "branch_0", label: "Default" }
      ]
    }
  }

  // Distribute outputs along lower-half diamond perimeter
  // Lower-half goes: left vertex (x-hw, y) → bottom vertex (x, y+hh) → right vertex (x+hw, y)
  const n = branches.length
  const outputs = branches.map((branch, i) => {
    // Parameter t goes from 0 (left vertex) to 1 (right vertex)
    // Evenly space N ports: t = (i + 1) / (n + 1)
    const t = (i + 1) / (n + 1)
    const { x: px, y: py } = diamondLowerPerimeterPoint(element, t)

    return {
      position: `port_${i}`,
      x: px,
      y: py,
      branchKey: branch.branchKey || `branch_${i}`,
      label: branch.label || branch.name || `Branch ${i}`
    }
  })

  return { input, outputs }
}

/**
 * Get dynamic port positions for a Merge element.
 * Input ports along top edge, single output at bottom center.
 *
 * @param {Object} element - The merge element { x, y, width, height, properties }
 * @returns {Object} { inputs: [{position, x, y, branchKey, label}], output: {position, x, y} }
 */
export function getMergePorts(element) {
  const hw = element.width / 2
  const hh = element.height / 2
  const mergedBranches = element.properties?.mergedBranches || []

  // Output: always bottom center
  const output = { position: "bottom", x: element.x, y: element.y + hh }

  if (mergedBranches.length === 0) {
    return {
      inputs: [{ position: "port_0", x: element.x, y: element.y - hh, branchKey: "branch_0", label: "Branch" }],
      output
    }
  }

  // Distribute input ports evenly along the top edge
  const n = mergedBranches.length
  const inputs = mergedBranches.map((branchKey, i) => {
    const t = (i + 1) / (n + 1)
    const px = element.x - hw + (element.width * t)
    const py = element.y - hh

    return {
      position: `port_${i}`,
      x: px,
      y: py,
      branchKey: branchKey,
      label: branchKey
    }
  })

  return { inputs, output }
}

/**
 * Calculate a point on the lower-half diamond perimeter.
 * t=0 → left vertex, t=0.5 → bottom vertex, t=1 → right vertex.
 */
function diamondLowerPerimeterPoint(element, t) {
  const cx = element.x
  const cy = element.y
  const hw = element.width / 2
  const hh = element.height / 2

  if (t <= 0.5) {
    // Left vertex → bottom vertex (t: 0→0.5 maps to segment 0→1)
    const s = t / 0.5
    return {
      x: cx - hw + (hw * s),       // -hw → 0
      y: cy + (hh * s)             // 0 → +hh
    }
  } else {
    // Bottom vertex → right vertex (t: 0.5→1 maps to segment 0→1)
    const s = (t - 0.5) / 0.5
    return {
      x: cx + (hw * s),            // 0 → +hw
      y: cy + hh - (hh * s)        // +hh → 0
    }
  }
}

/**
 * Check if an element uses dynamic ports.
 */
export function hasDynamicPorts(element) {
  return element.type === "decision" || element.type === "merge"
}

/**
 * Get all port positions for an element (unified interface for connection manager).
 * Returns a map of { portKey: { x, y } } compatible with the existing handle system.
 */
export function getDynamicPortPositions(element) {
  if (element.type === "decision") {
    const ports = getDecisionPorts(element)
    const result = { top: ports.input }
    ports.outputs.forEach(p => { result[p.position] = { x: p.x, y: p.y } })
    return result
  }

  if (element.type === "merge") {
    const ports = getMergePorts(element)
    const result = { bottom: ports.output }
    ports.inputs.forEach(p => { result[p.position] = { x: p.x, y: p.y } })
    return result
  }

  return null
}
```

- [ ] **Step 2: Commit**

```bash
git add app/javascript/flowchart/dynamic_ports.js
git commit -m "feat: add dynamic port calculator for Decision and Merge elements"
```

---

### Task 5: Integrate Dynamic Ports into Connection Manager

**Files:**
- Modify: `app/javascript/flowchart/connection_manager.js:394-412,632-670`

- [ ] **Step 1: Import dynamic ports module**

At the top of `connection_manager.js`, add the import:

```javascript
import { hasDynamicPorts, getDynamicPortPositions } from "flowchart/dynamic_ports"
```

- [ ] **Step 2: Update _getHandlePositions to support dynamic ports**

Replace the `_getHandlePositions` method (lines 394-404):

```javascript
_getHandlePositions(element) {
  // Use dynamic ports for decision and merge elements
  if (hasDynamicPorts(element)) {
    const dynamicPositions = getDynamicPortPositions(element)
    if (dynamicPositions) return dynamicPositions
  }

  // Standard 4-handle system for all other elements
  const hw = element.width / 2
  const hh = element.height / 2

  return {
    top: { x: element.x, y: element.y - hh },
    bottom: { x: element.x, y: element.y + hh },
    left: { x: element.x - hw, y: element.y },
    right: { x: element.x + hw, y: element.y }
  }
},
```

- [ ] **Step 3: Update _createElementHandles for port-aware rendering**

Replace `_createElementHandles` method (lines 632-670). Dynamic port handles use green/amber colors and have branch labels:

```javascript
_createElementHandles(element) {
  const handles = this._getHandlePositions(element)
  const isDynamic = hasDynamicPorts(element)

  Object.entries(handles).forEach(([position, coords]) => {
    const group = createGroup({
      "data-handle-position": position,
      "data-parent-element-id": element.id
    })
    group.style.cursor = "crosshair"

    // Hit area
    group.appendChild(createCircle(coords.x, coords.y, 14, { fill: "transparent" }))

    // Arrow (use green for dynamic output ports, blue for standard)
    const isOutputPort = position.startsWith("port_")
    const fillColor = isDynamic && isOutputPort ? "#10b981" : "#3b82f6"
    const strokeColor = isDynamic && isOutputPort ? "#059669" : "#1d4ed8"
    const rotation = this._getPortRotation(position, element)

    const arrow = createPolygon("0,-6 6,6 -6,6", {
      fill: fillColor,
      stroke: strokeColor,
      "stroke-width": "1",
      transform: `translate(${coords.x}, ${coords.y}) rotate(${rotation})`
    })
    group.appendChild(arrow)

    // Hover effect
    group.addEventListener("mouseenter", () => {
      arrow.setAttribute("fill", isDynamic && isOutputPort ? "#059669" : "#2563eb")
      arrow.setAttribute("transform", `translate(${coords.x}, ${coords.y}) rotate(${rotation}) scale(1.3)`)
    })

    group.addEventListener("mouseleave", () => {
      if (!this.isDrawingConnection) {
        arrow.setAttribute("fill", fillColor)
        arrow.setAttribute("transform", `translate(${coords.x}, ${coords.y}) rotate(${rotation})`)
      }
    })

    this.handleLayer.appendChild(group)
  })
},

/**
 * Get rotation angle for a port handle.
 * Standard handles use HANDLE_ROTATIONS. Dynamic ports compute angle from element center.
 */
_getPortRotation(position, element) {
  if (HANDLE_ROTATIONS[position] !== undefined) {
    return HANDLE_ROTATIONS[position]
  }
  // Dynamic port: compute angle from element center to port position
  const handles = this._getHandlePositions(element)
  const port = handles[position]
  if (!port) return 180
  const dx = port.x - element.x
  const dy = port.y - element.y
  return Math.atan2(dy, dx) * (180 / Math.PI) + 90
},
```

- [ ] **Step 4: Update _renderConnection to support fromPort/toPort**

In `_renderConnection` (line 83), update to check for `fromPort`/`toPort`:

```javascript
_renderConnection(connection) {
  const fromEl = this.elements.find(el => el.id === connection.from)
  const toEl = this.elements.find(el => el.id === connection.to)
  if (!fromEl || !toEl) return

  const fromPosition = connection.fromPort || connection.fromPosition
  const toPosition = connection.toPort || connection.toPosition
  const fromPoint = this._getHandlePosition(fromEl, fromPosition)
  const toPoint = this._getHandlePosition(toEl, toPosition)

  // For path calculation, map port positions to nearest cardinal direction
  const fromCardinal = this._portToCardinal(fromPosition, fromEl)
  const toCardinal = this._portToCardinal(toPosition, toEl)
  const pathPoints = this._calculatePath(fromPoint, toPoint, fromCardinal, toCardinal)
  const pathData = ConnectionRenderer.pointsToPath(pathPoints)

  const group = this._createConnectionGroup(connection.id, pathData, toPoint, pathPoints, connection.label)
  this.connectionLayer.appendChild(group)
},

/**
 * Map a port position (e.g. "port_0") to the nearest cardinal direction for path routing.
 */
_portToCardinal(position, element) {
  if (["top", "bottom", "left", "right"].includes(position)) return position

  const handles = this._getHandlePositions(element)
  const port = handles[position]
  if (!port) return "bottom"

  const dx = port.x - element.x
  const dy = port.y - element.y

  // Determine nearest cardinal based on angle
  if (Math.abs(dy) > Math.abs(dx)) {
    return dy > 0 ? "bottom" : "top"
  }
  return dx > 0 ? "right" : "left"
},
```

- [ ] **Step 5: Update createConnection to store fromPort/toPort**

In `createConnection` (line 45), update the connection object:

```javascript
createConnection(fromElement, toElement, fromPosition, toPosition, options = {}) {
  if (fromElement.id === toElement.id) return null

  const exists = this.connections.some(c =>
    (c.from === fromElement.id && c.to === toElement.id) ||
    (c.from === toElement.id && c.to === fromElement.id)
  )
  if (exists) return null

  const connection = {
    id: generateId("conn"),
    from: fromElement.id,
    to: toElement.id,
    fromPort: fromPosition.startsWith("port_") ? fromPosition : null,
    fromPosition: fromPosition.startsWith("port_") ? null : fromPosition,
    toPort: toPosition.startsWith("port_") ? toPosition : null,
    toPosition: toPosition.startsWith("port_") ? null : toPosition,
    label: options.label || null,
    properties: options.properties || { description: "", priority: 0 }
  }

  this.connections.push(connection)
  const parentOutputs = fromElement.properties?.outputs || []
  this._updateInheritedInputs(toElement, parentOutputs)
  this._alignConnectionElements(connection)
  this._renderConnection(connection)

  return connection
},
```

- [ ] **Step 6: Verify in browser**

Drag a Decision element onto the canvas, select it, and verify dynamic port handles appear (green arrows along the lower diamond perimeter). Draw a connection from a port to another element.

- [ ] **Step 7: Commit**

```bash
git add app/javascript/flowchart/connection_manager.js
git commit -m "feat: integrate dynamic ports into connection manager"
```

---

### Task 6: Redesign Branch Manager for Case/When UI

**Files:**
- Modify: `app/javascript/controllers/property_editor/branch_manager.js:24-89,187-250`

- [ ] **Step 1: Replace branch value dropdown with free-text name field**

In `openBranchModal` (line 24), change the reset logic from yes/no dropdown to a free-text branch name:

```javascript
// In the _resetModalFields call, change:
selects: [{ selector: "[data-branch-value]", defaultValue: "yes" }]
// To:
inputs: "[data-branch-modal-label], [data-branch-name]",
textareas: "[data-branch-modal-description]"
```

- [ ] **Step 2: Fix the display label logic**

In `addBranchFromModal` (around line 207), replace the hardcoded yes/no display label:

```javascript
// Replace:
const displayLabel = label || (branchValue === "yes" ? "Yes" : "No")
// With:
const branchNameInput = modal.querySelector("[data-branch-name]")
const branchName = branchNameInput?.value?.trim() || ""
const displayLabel = label || branchName || `Branch ${this.branchIndex}`
```

- [ ] **Step 3: Update the branch modal template**

In the template file (find via `buildBranchModalTemplate` in `controllers/property_editor/templates.js`), replace the yes/no `<select>` with a branch name text input:

```html
<!-- Replace the branch value select with: -->
<div class="mb-3">
  <label class="block text-[10px] font-medium text-slate-600 mb-1">Branch Name</label>
  <input type="text"
         data-branch-name
         placeholder="e.g. Active, Pending, Rejected..."
         class="w-full px-2 py-1.5 text-xs border border-slate-200 rounded shadow-sm focus:outline-none focus:ring-1 focus:ring-amber-500 focus:border-amber-500">
</div>
```

- [ ] **Step 4: Update collectBranches to use branch name**

In `collectBranches` (line 285), update to collect branch name instead of value:

```javascript
collectBranches() {
  const container = this.controller.formFieldsTarget.querySelector("[data-branches-container]")
  if (!container) return null

  const branches = []
  const branchItems = container.querySelectorAll("[data-branch-item]")

  branchItems.forEach(item => {
    const nameInput = item.querySelector("input[name*='[name]']") || item.querySelector("input[name*='[value]']")
    const labelInput = item.querySelector("input[name*='[label]']")
    const descInput = item.querySelector("input[name*='[description]']")
    const elementIdInput = item.querySelector("input[name*='[elementId]']")

    const name = nameInput?.value || `Branch ${branches.length}`
    const label = labelInput?.value || ""
    const description = descInput?.value?.trim() || ""
    const elementId = elementIdInput?.value || item.dataset.branchElementId || null

    const branch = { name, label, description, branchKey: `branch_${branches.length}` }
    if (elementId) branch.elementId = elementId
    branches.push(branch)
  })

  return branches
}
```

- [ ] **Step 5: Verify in browser**

Open a Decision element's property editor. The branch modal should now show a free-text "Branch Name" field instead of a yes/no dropdown.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/property_editor/branch_manager.js
git add app/javascript/controllers/property_editor/templates.js
git commit -m "feat: redesign branch manager for case/when style UI"
```

---

### Task 7: Add Merge Manager for Property Editor

**Files:**
- Create: `app/javascript/controllers/property_editor/merge_manager.js`
- Modify: `app/javascript/controllers/property_editor_controller.js:35-50`

- [ ] **Step 1: Create MergeManager class**

Create `app/javascript/controllers/property_editor/merge_manager.js`:

```javascript
/**
 * Merge Manager Module
 * Handles property editing for Merge elements.
 * Auto-detects source Decision from incoming connections and shows branch checkboxes.
 */

import { BaseManager } from "controllers/property_editor/base_manager"

export class MergeManager extends BaseManager {
  constructor(controller) {
    super(controller, 'mergeIndex')
  }

  /**
   * Build the merge configuration form HTML.
   * Auto-detects the source Decision from incoming connections.
   */
  buildMergeFieldHTML(element) {
    const canvas = this.controller.canvas
    if (!canvas) return ""

    const sourceDecision = this._findSourceDecision(element, canvas)
    const branches = sourceDecision
      ? this._getDecisionBranches(sourceDecision, canvas)
      : []
    const mergedBranches = element.properties?.mergedBranches || []

    let html = `
      <div class="mb-4">
        <label class="block text-sm font-medium text-slate-700 mb-2">Source Decision</label>
        <div class="p-2 bg-amber-50 border border-amber-200 rounded text-xs">
    `

    if (sourceDecision) {
      html += `<span class="text-amber-600">&#9670;</span> ${sourceDecision.label || "Decision"}`
      html += `<input type="hidden" data-merge-source-decision-id value="${sourceDecision.id}">`
    } else {
      html += `<span class="text-slate-400 italic">Connect branch outputs to this Merge to auto-detect</span>`
    }

    html += `</div></div>`

    if (branches.length > 0) {
      html += `
        <div class="mb-4">
          <label class="block text-sm font-medium text-slate-700 mb-2">Branches to Merge</label>
          <div class="border border-slate-200 rounded overflow-hidden" data-merge-branches-container>
      `

      branches.forEach((branch, i) => {
        const branchKey = branch.branchKey || `branch_${i}`
        const isChecked = mergedBranches.includes(branchKey)
        const isDefault = !branch.condition
        const dotColor = isDefault ? "#f59e0b" : "#10b981"

        html += `
          <div class="px-3 py-2 ${i < branches.length - 1 ? 'border-b border-slate-200' : ''} flex items-center gap-2 ${isChecked ? 'bg-violet-50' : 'bg-white'}">
            <input type="checkbox"
                   data-merge-branch-checkbox
                   data-branch-key="${branchKey}"
                   ${isChecked ? 'checked' : ''}
                   class="accent-violet-500"
                   data-action="change->property-editor#syncMergeBranches">
            <span style="width:8px;height:8px;border-radius:50%;background:${dotColor};display:inline-block;"></span>
            <span class="text-xs flex-1"><strong>${branch.name || branchKey}</strong></span>
          </div>
        `
      })

      html += `</div>
          <p class="text-[10px] text-slate-400 mt-1">Checked branches converge at this merge point.</p>
        </div>
      `
    }

    return html
  }

  /**
   * Collect merged branches from checkboxes.
   */
  collectMergedBranches() {
    const container = this.controller.formFieldsTarget.querySelector("[data-merge-branches-container]")
    if (!container) return []

    const checked = container.querySelectorAll("[data-merge-branch-checkbox]:checked")
    return Array.from(checked).map(cb => cb.dataset.branchKey)
  }

  /**
   * Collect the source decision ID.
   */
  collectSourceDecisionId() {
    const input = this.controller.formFieldsTarget.querySelector("[data-merge-source-decision-id]")
    return input?.value || null
  }

  // ===================
  // Private Helpers
  // ===================

  _findSourceDecision(mergeElement, canvas) {
    // Walk incoming connections backward to find a Decision element
    const incomingConns = canvas.connections.filter(c => c.to === mergeElement.id)

    for (const conn of incomingConns) {
      const sourceEl = canvas.elements.find(el => el.id === conn.from)
      if (!sourceEl) continue

      if (sourceEl.type === "decision") return sourceEl

      // Check if the source is a process within a decision branch — walk up further
      const parentConns = canvas.connections.filter(c => c.to === sourceEl.id)
      for (const pc of parentConns) {
        const parentEl = canvas.elements.find(el => el.id === pc.from)
        if (parentEl?.type === "decision") return parentEl
      }

      // Check for merge-of-merges — source is another merge
      if (sourceEl.type === "merge" && sourceEl.properties?.sourceDecisionId) {
        const decisionEl = canvas.elements.find(el => el.id === sourceEl.properties.sourceDecisionId)
        if (decisionEl) return decisionEl
      }
    }

    return null
  }

  _getDecisionBranches(decisionElement, canvas) {
    const branches = decisionElement.properties?.branches || []
    if (branches.length > 0) return branches

    // Fallback: infer branches from outgoing connections
    const outConns = canvas.connections.filter(c => c.from === decisionElement.id)
    return outConns.map((conn, i) => ({
      name: conn.label || `Branch ${i}`,
      branchKey: `branch_${i}`,
      condition: conn.condition
    }))
  }
}
```

- [ ] **Step 2: Register MergeManager in property_editor_controller.js**

In `property_editor_controller.js`, import and initialize MergeManager:

```javascript
import { MergeManager } from "controllers/property_editor/merge_manager"
```

In the `connect()` method (around line 35), add:

```javascript
this.mergeManager = new MergeManager(this)
```

- [ ] **Step 3: Add syncMergeBranches action**

In `property_editor_controller.js`, add the action handler:

```javascript
syncMergeBranches() {
  if (!this.currentElement || this.currentElement.type !== "merge") return
  const mergedBranches = this.mergeManager.collectMergedBranches()
  const sourceDecisionId = this.mergeManager.collectSourceDecisionId()

  this.currentElement.properties = this.currentElement.properties || {}
  this.currentElement.properties.mergedBranches = mergedBranches
  this.currentElement.properties.sourceDecisionId = sourceDecisionId

  // Update the merge element subtitle on canvas
  if (this.canvas) {
    this.canvas.updateConnections()
  }
}
```

- [ ] **Step 4: Integrate merge fields into openEditor**

In the `openEditor` method, add a branch for the merge element type that calls `this.mergeManager.buildMergeFieldHTML(element)` and injects the result into the form fields.

- [ ] **Step 5: Update _collectFormData for merge elements**

In `_collectFormData` (line 656), add merge handling:

```javascript
// After existing branch collection:
if (this.currentElement.type === "merge") {
  formData.mergedBranches = this.mergeManager.collectMergedBranches()
  formData.sourceDecisionId = this.mergeManager.collectSourceDecisionId()
}
```

- [ ] **Step 6: Verify in browser**

Place a Decision element with 3+ branches, then place a Merge element and connect branch outputs to it. Open the Merge property editor — it should show the source Decision and branch checkboxes.

- [ ] **Step 7: Commit**

```bash
git add app/javascript/controllers/property_editor/merge_manager.js
git add app/javascript/controllers/property_editor_controller.js
git commit -m "feat: add MergeManager for merge element property editing"
```

---

### Task 8: Update Topology Analyzer for Merge Elements

**Files:**
- Modify: `app/services/flowchart_topology_analyzer.rb`
- Test: `spec/services/flowchart_topology_analyzer_spec.rb`

- [ ] **Step 1: Write failing test for merge_groups detection**

Add to `spec/services/flowchart_topology_analyzer_spec.rb`:

```ruby
context "with merge element (selective branch convergence)" do
  # Start → Decision → BranchA → MergeAB → PostMerge → End
  #                  → BranchB ↗
  #                  → BranchC → End
  let(:merge_elements) do
    [
      { "id" => "s1", "type" => "start" },
      { "id" => "d1", "type" => "decision", "label" => "Check Status" },
      { "id" => "a1", "type" => "process", "label" => "Active" },
      { "id" => "b1", "type" => "process", "label" => "Pending" },
      { "id" => "c1", "type" => "process", "label" => "Rejected" },
      { "id" => "mg1", "type" => "merge", "label" => "Merge AB",
        "properties" => { "sourceDecisionId" => "d1", "mergedBranches" => ["branch_0", "branch_1"] } },
      { "id" => "p1", "type" => "process", "label" => "Post Merge" },
      { "id" => "e1", "type" => "end" }
    ]
  end
  let(:merge_connections) do
    [
      { "id" => "c1", "from" => "s1", "to" => "d1" },
      { "id" => "c2", "from" => "d1", "to" => "a1", "label" => "Active",
        "condition" => { "leftOperand" => "ctx[:status]", "operator" => "==", "rightOperand" => "active" } },
      { "id" => "c3", "from" => "d1", "to" => "b1", "label" => "Pending",
        "condition" => { "leftOperand" => "ctx[:status]", "operator" => "==", "rightOperand" => "pending" } },
      { "id" => "c4", "from" => "d1", "to" => "c1", "label" => "Rejected" },
      { "id" => "c5", "from" => "a1", "to" => "mg1" },
      { "id" => "c6", "from" => "b1", "to" => "mg1" },
      { "id" => "c7", "from" => "mg1", "to" => "p1" },
      { "id" => "c8", "from" => "c1", "to" => "e1" },
      { "id" => "c9", "from" => "p1", "to" => "e1" }
    ]
  end

  subject(:result) do
    described_class.new(merge_elements, merge_connections).analyze
  end

  it "detects merge_groups" do
    expect(result.merge_groups).to have_key("mg1")
    expect(result.merge_groups["mg1"][:merged_branches]).to eq([:branch_0, :branch_1])
  end

  it "assigns compound guard to the merge element" do
    guard = result.node_guards["mg1"]
    expect(guard[:decision_id]).to eq("d1")
    expect(guard[:branches]).to contain_exactly(:branch_0, :branch_1)
  end

  it "assigns compound guard to post-merge node" do
    guard = result.node_guards["p1"]
    expect(guard[:decision_id]).to eq("d1")
    expect(guard[:branches]).to contain_exactly(:branch_0, :branch_1)
  end

  it "assigns single guard to unmerged branch" do
    guard = result.node_guards["c1"]
    expect(guard[:decision_id]).to eq("d1")
    expect(guard[:branch]).to eq(:branch_2)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/flowchart_topology_analyzer_spec.rb --format documentation`
Expected: FAIL — `merge_groups` method not found, guard structure wrong

- [ ] **Step 3: Update Result struct and add MERGE_TYPE constant**

In `flowchart_topology_analyzer.rb`, update:

```ruby
BRANCHING_TYPES = %w[decision switch].freeze
MERGE_TYPE = "merge"

Result = Struct.new(:branch_groups, :merge_groups, :node_guards, :decision_indices, keyword_init: true)
```

- [ ] **Step 4: Implement merge detection in analyze method**

Replace the `analyze` method:

```ruby
def analyze
  branch_groups    = {}
  merge_groups     = {}
  node_guards      = {}
  decision_indices = {}
  index            = 0

  branching_elements.each do |el|
    el_id     = el["id"]
    out_conns = outgoing_connections(el_id)
    next if out_conns.size < 2

    decision_indices[el_id] = index

    branches = {}
    out_conns.each_with_index do |conn, i|
      branch_key = :"branch_#{i}"
      branches[branch_key] = {
        connection_id: conn["id"],
        label:         conn["label"] || branch_key.to_s,
        condition:     conn["condition"]
      }
    end

    merge_id = find_convergence_node(el_id, out_conns.map { |c| c["to"] })

    branch_groups[el_id] = {
      branches:      branches,
      merge_node_id: merge_id,
      route_index:   index
    }

    # Label downstream nodes with their branch guard
    out_conns.each_with_index do |conn, i|
      branch_key = :"branch_#{i}"
      label_branch_nodes(conn["to"], el_id, branch_key, merge_id, node_guards)
    end

    index += 1
  end

  # Detect merge elements and assign compound guards
  detect_merge_elements(merge_groups, node_guards, decision_indices, branch_groups)

  Result.new(branch_groups:, merge_groups:, node_guards:, decision_indices:)
end
```

- [ ] **Step 5: Implement detect_merge_elements**

Add to the private section:

```ruby
def detect_merge_elements(merge_groups, node_guards, decision_indices, branch_groups)
  elements.select { |el| el["type"] == MERGE_TYPE }.each do |el|
    source_decision_id = el.dig("properties", "sourceDecisionId")
    merged_branches = (el.dig("properties", "mergedBranches") || []).map(&:to_sym)
    next if source_decision_id.nil? || merged_branches.size < 2

    route_index = decision_indices[source_decision_id] || 0

    merge_groups[el["id"]] = {
      source_decision_id: source_decision_id,
      merged_branches: merged_branches,
      route_index: route_index
    }

    # Assign compound guard to the merge element itself
    node_guards[el["id"]] = {
      decision_id: source_decision_id,
      branches: merged_branches
    }

    # Label downstream nodes with compound guard
    label_merged_downstream(el["id"], source_decision_id, merged_branches, node_guards)
  end
end

def label_merged_downstream(merge_id, decision_id, branches, node_guards)
  visited = Set.new
  queue = adjacency[merge_id].map { |conn| conn["to"] }

  while (current_id = queue.shift)
    next if visited.include?(current_id)
    next if element_map[current_id].nil?

    visited.add(current_id)
    node_guards[current_id] ||= { decision_id: decision_id, branches: branches }

    adjacency[current_id].each { |conn| queue << conn["to"] }
  end
end
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/flowchart_topology_analyzer_spec.rb --format documentation`
Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
git add app/services/flowchart_topology_analyzer.rb
git add spec/services/flowchart_topology_analyzer_spec.rb
git commit -m "feat: add merge_groups detection and compound guards to topology analyzer"
```

---

### Task 9: Update Activity Generator for Compound Guards and Merge No-Op

**Files:**
- Modify: `app/services/activity_generator.rb:340-381`
- Test: `spec/services/activity_generator_spec.rb`

- [ ] **Step 1: Write failing test for compound guard generation**

Add to `spec/services/activity_generator_spec.rb`:

```ruby
context "with merge element" do
  let(:flowchart) do
    create(:flowchart, :with_entity, configuration: {
      "elements" => [
        { "id" => "s1", "type" => "start", "label" => "Start", "x" => 100, "y" => 50, "width" => 100, "height" => 45 },
        { "id" => "d1", "type" => "decision", "label" => "Check Status", "x" => 100, "y" => 150, "width" => 100, "height" => 45 },
        { "id" => "a1", "type" => "process", "label" => "Active Process", "x" => 0, "y" => 250, "width" => 100, "height" => 45, "properties" => { "steps" => [] } },
        { "id" => "b1", "type" => "process", "label" => "Pending Process", "x" => 200, "y" => 250, "width" => 100, "height" => 45, "properties" => { "steps" => [] } },
        { "id" => "mg1", "type" => "merge", "label" => "Merge AB", "x" => 100, "y" => 350, "width" => 140, "height" => 36,
          "properties" => { "sourceDecisionId" => "d1", "mergedBranches" => ["branch_0", "branch_1"] } },
        { "id" => "p1", "type" => "process", "label" => "Post Merge Step", "x" => 100, "y" => 450, "width" => 100, "height" => 45, "properties" => { "steps" => [] } },
        { "id" => "e1", "type" => "end", "label" => "End", "x" => 100, "y" => 550, "width" => 100, "height" => 45 }
      ],
      "connections" => [
        { "id" => "c1", "from" => "s1", "to" => "d1" },
        { "id" => "c2", "from" => "d1", "to" => "a1", "label" => "Active",
          "condition" => { "leftOperand" => "ctx[:status]", "operator" => "==", "rightOperand" => "active" } },
        { "id" => "c3", "from" => "d1", "to" => "b1", "label" => "Pending",
          "condition" => { "leftOperand" => "ctx[:status]", "operator" => "==", "rightOperand" => "pending" } },
        { "id" => "c4", "from" => "a1", "to" => "mg1" },
        { "id" => "c5", "from" => "b1", "to" => "mg1" },
        { "id" => "c6", "from" => "mg1", "to" => "p1" },
        { "id" => "c7", "from" => "p1", "to" => "e1" }
      ],
      "metadata" => {}
    })
  end

  it "generates a no-op method for the merge element" do
    code = described_class.new(flowchart).generate
    expect(code).to include("def merge_ab(ctx, **)")
    expect(code).to include("true")
  end

  it "generates compound guard for post-merge step" do
    code = described_class.new(flowchart).generate
    expect(code).to include("[:branch_0, :branch_1].include?(ctx[:_route_0])")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/activity_generator_spec.rb --format documentation`
Expected: FAIL — no compound guard generated

- [ ] **Step 3: Update build_method for compound guards**

In `activity_generator.rb`, update the `build_method` (line 340). Replace the guard_code generation:

```ruby
guard_code = if guard
               idx = @topology.decision_indices[guard[:decision_id]] || 0
               if guard[:branches]
                 # Compound guard for merge elements and their downstream nodes
                 branches_list = guard[:branches].map { |b| ":#{b}" }.join(", ")
                 total_branches = @topology.branch_groups[guard[:decision_id]]&.dig(:branches)&.size || 0
                 if guard[:branches].size >= total_branches && total_branches > 0
                   # All branches merged — no guard needed
                   ""
                 else
                   "return true unless [#{branches_list}].include?(ctx[:_route_#{idx}])\n"
                 end
               else
                 "return true unless ctx[:_route_#{idx}] == :#{guard[:branch]}\n"
               end
             else
               ""
             end
```

- [ ] **Step 4: Add merge element type to method_body**

In `method_body` (line 398), add a handler for merge elements before the registry lookup:

```ruby
def method_body(element, steps, ctx)
  type = element["type"]

  # Merge elements are no-op — pure flow control
  return "true" if type == "merge"

  # Delegate to element type generator via registry
  generator_class = @registry.find_element_type(type)
  if generator_class
    generator = generator_class.new(element, ctx)
    result = generator.generate_body
    return result if result
  end

  generate_process_body(element, steps, ctx)
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/activity_generator_spec.rb --format documentation`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add app/services/activity_generator.rb
git add spec/services/activity_generator_spec.rb
git commit -m "feat: add compound guard generation and merge no-op to activity generator"
```

---

### Task 10: Add Topology Analyzer Specs for Edge Cases

**Files:**
- Test: `spec/services/flowchart_topology_analyzer_spec.rb`

- [ ] **Step 1: Add 3-branch decision test**

```ruby
context "with 3-branch decision" do
  let(:three_branch_elements) do
    [
      { "id" => "s1", "type" => "start" },
      { "id" => "d1", "type" => "decision", "label" => "Three Way" },
      { "id" => "a1", "type" => "process", "label" => "A" },
      { "id" => "b1", "type" => "process", "label" => "B" },
      { "id" => "c1", "type" => "process", "label" => "C" },
      { "id" => "e1", "type" => "end" }
    ]
  end
  let(:three_branch_connections) do
    [
      { "id" => "x1", "from" => "s1", "to" => "d1" },
      { "id" => "x2", "from" => "d1", "to" => "a1" },
      { "id" => "x3", "from" => "d1", "to" => "b1" },
      { "id" => "x4", "from" => "d1", "to" => "c1" },
      { "id" => "x5", "from" => "a1", "to" => "e1" },
      { "id" => "x6", "from" => "b1", "to" => "e1" },
      { "id" => "x7", "from" => "c1", "to" => "e1" }
    ]
  end

  subject(:result) { described_class.new(three_branch_elements, three_branch_connections).analyze }

  it "creates branch_0, branch_1, branch_2" do
    branches = result.branch_groups["d1"][:branches]
    expect(branches.keys).to eq([:branch_0, :branch_1, :branch_2])
  end

  it "guards all three branch nodes" do
    expect(result.node_guards["a1"][:branch]).to eq(:branch_0)
    expect(result.node_guards["b1"][:branch]).to eq(:branch_1)
    expect(result.node_guards["c1"][:branch]).to eq(:branch_2)
  end
end
```

- [ ] **Step 2: Add multiple merges test**

```ruby
context "with two merge elements for same decision" do
  let(:two_merge_elements) do
    [
      { "id" => "s1", "type" => "start" },
      { "id" => "d1", "type" => "decision", "label" => "4-Way" },
      { "id" => "a1", "type" => "process", "label" => "A" },
      { "id" => "b1", "type" => "process", "label" => "B" },
      { "id" => "c1", "type" => "process", "label" => "C" },
      { "id" => "d2", "type" => "process", "label" => "D" },
      { "id" => "mg1", "type" => "merge", "label" => "Merge AB",
        "properties" => { "sourceDecisionId" => "d1", "mergedBranches" => ["branch_0", "branch_1"] } },
      { "id" => "mg2", "type" => "merge", "label" => "Merge CD",
        "properties" => { "sourceDecisionId" => "d1", "mergedBranches" => ["branch_2", "branch_3"] } },
      { "id" => "p1", "type" => "process", "label" => "After AB" },
      { "id" => "p2", "type" => "process", "label" => "After CD" },
      { "id" => "e1", "type" => "end" }
    ]
  end
  let(:two_merge_connections) do
    [
      { "id" => "x1", "from" => "s1", "to" => "d1" },
      { "id" => "x2", "from" => "d1", "to" => "a1" },
      { "id" => "x3", "from" => "d1", "to" => "b1" },
      { "id" => "x4", "from" => "d1", "to" => "c1" },
      { "id" => "x5", "from" => "d1", "to" => "d2" },
      { "id" => "x6", "from" => "a1", "to" => "mg1" },
      { "id" => "x7", "from" => "b1", "to" => "mg1" },
      { "id" => "x8", "from" => "c1", "to" => "mg2" },
      { "id" => "x9", "from" => "d2", "to" => "mg2" },
      { "id" => "x10", "from" => "mg1", "to" => "p1" },
      { "id" => "x11", "from" => "mg2", "to" => "p2" },
      { "id" => "x12", "from" => "p1", "to" => "e1" },
      { "id" => "x13", "from" => "p2", "to" => "e1" }
    ]
  end

  subject(:result) { described_class.new(two_merge_elements, two_merge_connections).analyze }

  it "creates two merge groups" do
    expect(result.merge_groups.keys).to contain_exactly("mg1", "mg2")
  end

  it "assigns correct branches to each merge" do
    expect(result.merge_groups["mg1"][:merged_branches]).to eq([:branch_0, :branch_1])
    expect(result.merge_groups["mg2"][:merged_branches]).to eq([:branch_2, :branch_3])
  end

  it "assigns compound guard to post-merge nodes" do
    expect(result.node_guards["p1"][:branches]).to contain_exactly(:branch_0, :branch_1)
    expect(result.node_guards["p2"][:branches]).to contain_exactly(:branch_2, :branch_3)
  end
end
```

- [ ] **Step 3: Run all topology analyzer tests**

Run: `bundle exec rspec spec/services/flowchart_topology_analyzer_spec.rb --format documentation`
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add spec/services/flowchart_topology_analyzer_spec.rb
git commit -m "test: add 3-branch and multiple merge topology analyzer specs"
```

---

### Task 11: Port Sync — Update Dynamic Ports When Branches Change

**Files:**
- Modify: `app/javascript/controllers/property_editor/branch_manager.js`

- [ ] **Step 1: Add port sync after branch add/remove**

In `addBranchFromModal` (after the `_dispatchEvent("branchAdded")` call), add port sync:

```javascript
// Sync dynamic ports on the canvas
if (this.controller.canvas && this.controller.currentElement) {
  const element = this.controller.currentElement
  element.properties = element.properties || {}
  element.properties.branches = this.collectBranches()
  this.controller.canvas._hideConnectionHandles()
  this.controller.canvas.updateConnections()
}
```

Add the same in `removeBranch` (after `_dispatchEvent("branchRemoved")`):

```javascript
if (this.controller.canvas && this.controller.currentElement) {
  const element = this.controller.currentElement
  element.properties = element.properties || {}
  element.properties.branches = this.collectBranches()
  this.controller.canvas._hideConnectionHandles()
  this.controller.canvas.updateConnections()
}
```

- [ ] **Step 2: Verify in browser**

Add/remove branches on a Decision element and verify the dynamic ports update on the diamond shape in real time.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/property_editor/branch_manager.js
git commit -m "feat: sync dynamic ports when branches are added or removed"
```

---

### Task 12: Render Port Labels on Canvas

**Files:**
- Modify: `app/javascript/flowchart/element_renderer.js`

- [ ] **Step 1: Add port label rendering in renderElement**

In `renderElement` (after line 62 `group.appendChild(this._createLabel(element))`), add:

```javascript
// Render dynamic port labels for decision and merge elements
if (element.type === "decision" || element.type === "merge") {
  const portLabels = this._createPortLabels(element)
  if (portLabels) group.appendChild(portLabels)
}
```

- [ ] **Step 2: Implement _createPortLabels**

Add the method to `ElementRendererMixin`:

```javascript
_createPortLabels(element) {
  const { getDecisionPorts, getMergePorts } = require("flowchart/dynamic_ports")
  const group = createGroup({ class: "port-labels" })

  if (element.type === "decision") {
    const ports = getDecisionPorts(element)
    ports.outputs.forEach(port => {
      // Convert absolute port position to element-local coordinates
      const localX = port.x - (element.x - element.width / 2)
      const localY = port.y - (element.y - element.height / 2)
      // Offset label outward from diamond center
      const dx = port.x - element.x
      const dy = port.y - element.y
      const dist = Math.sqrt(dx * dx + dy * dy)
      const offsetX = dist > 0 ? (dx / dist) * 14 : 0
      const offsetY = dist > 0 ? (dy / dist) * 14 : 0

      const isDefault = port.label === "Default" || !port.label
      const color = isDefault ? "#f59e0b" : "#10b981"

      group.appendChild(createText(port.label || "", localX + offsetX, localY + offsetY, {
        "text-anchor": "middle",
        "dominant-baseline": "middle",
        fill: color,
        "font-size": "8",
        "font-family": SHAPE_CONFIG.fontFamily
      }))
    })
  }

  if (element.type === "merge") {
    const ports = getMergePorts(element)
    ports.inputs.forEach(port => {
      const localX = port.x - (element.x - element.width / 2)
      const localY = port.y - (element.y - element.height / 2) - 10

      group.appendChild(createText(port.label || "", localX, localY, {
        "text-anchor": "middle",
        "dominant-baseline": "middle",
        fill: "#8b5cf6",
        "font-size": "8",
        "font-family": SHAPE_CONFIG.fontFamily
      }))
    })
  }

  return group
},
```

Note: Use dynamic import or import at the top of the file:
```javascript
import { getDecisionPorts, getMergePorts } from "flowchart/dynamic_ports"
```

- [ ] **Step 3: Verify in browser**

Decision elements with branches should show green labels near each output port. Merge elements should show purple labels near each input port.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/flowchart/element_renderer.js
git commit -m "feat: render dynamic port labels on decision and merge elements"
```

---

### Task 13: End-to-End Verification

**Files:** None (manual testing)

- [ ] **Step 1: Test full Decision workflow**

1. Drag Decision onto canvas
2. Open property editor → Add 4 branches: "Active" (condition: == "active"), "Pending" (== "pending"), "Rejected" (== "rejected"), "Default" (no condition)
3. Verify 4 labeled output ports appear on diamond
4. Connect each port to a Process element
5. Save flowchart and verify configuration JSON has correct branch data

- [ ] **Step 2: Test Merge workflow**

1. Drag Merge element onto canvas
2. Connect "Active" and "Pending" branch outputs to Merge
3. Open Merge property editor → Verify source Decision auto-detected, checkboxes show
4. Check "Active" and "Pending" branches
5. Connect Merge output to a Post-Merge process
6. Save and verify configuration JSON

- [ ] **Step 3: Test code generation**

1. Click the "Generate" or trace button on the flowchart
2. Verify generated code contains:
   - `if/elsif/else` chain for the Decision
   - No-op `merge_*` method
   - Compound guard `[:branch_0, :branch_1].include?(ctx[:_route_0])` for post-merge step
   - Single guard `ctx[:_route_0] == :branch_2` for unmerged branch

- [ ] **Step 4: Test multiple merges**

1. Add a second Merge that joins the other 2 branches
2. Verify each Merge has independent checkboxes
3. Verify code generation produces correct compound guards for each post-merge track

- [ ] **Step 5: Commit any fixes**

```bash
git add -A
git commit -m "fix: end-to-end adjustments for decision multi-branch and merge"
```
