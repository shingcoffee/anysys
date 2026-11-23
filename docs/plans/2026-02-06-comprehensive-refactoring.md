# Comprehensive Application Refactoring Plan

> **For Copilot:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactor the Anysys application to improve readability, maintainability, and code organization following Rails conventions and best practices.

**Architecture:** Extract large monolithic JavaScript files into smaller, focused modules. Consolidate duplicate code patterns across managers into base classes. Clean up CSS and remove unused styles. Follow TailwindCSS and StimulusJS conventions throughout.

**Tech Stack:** Ruby on Rails 8.1.2, StimulusJS, TailwindCSS, ViewComponent

---

## Summary of Changes

The refactoring addresses these key areas identified in the codebase analysis:

1. **JavaScript Refactoring** - Extract large files into smaller modules
2. **CSS Cleanup** - Remove unused styles, organize following TailwindCSS conventions
3. **Code Consolidation** - Create base classes to eliminate duplication
4. **Remove Unused Code** - Clean up variables/functions not in use
5. **Professional Naming** - Ensure consistent naming conventions

---

## Task 1: Create BaseManager Class for Property Editor Managers

**Files:**
- Create: `app/javascript/controllers/property_editor/base_manager.js`
- Modify: `app/javascript/controllers/property_editor/step_manager.js`
- Modify: `app/javascript/controllers/property_editor/branch_manager.js`
- Modify: `app/javascript/controllers/property_editor/io_manager.js`
- Modify: `app/javascript/controllers/property_editor/index.js`

**Step 1: Create BaseManager class with shared functionality**

Extract common patterns from StepManager, BranchManager, and IOManager:
- Index management (reset, get, set, increment)
- Event dispatching
- Controller reference

```javascript
// app/javascript/controllers/property_editor/base_manager.js
/**
 * BaseManager - Abstract base class for Property Editor managers.
 * Provides common functionality for StepManager, BranchManager, and IOManager.
 */
export class BaseManager {
  constructor(controller, indexName = 'index') {
    this.controller = controller
    this._indexName = indexName
    this[indexName] = 0
  }

  // Index management
  reset() {
    this[this._indexName] = 0
  }

  getIndex() {
    return this[this._indexName]
  }

  setIndex(value) {
    this[this._indexName] = value
  }

  incrementIndex() {
    this[this._indexName]++
  }

  // Event dispatching
  _dispatchEvent(eventName) {
    const form = this.controller.formTarget
    if (form) {
      form.dispatchEvent(new CustomEvent(eventName, { bubbles: true }))
    }
  }

  // Convenience getters
  get canvas() {
    return this.controller.canvas
  }

  get currentElement() {
    return this.controller.currentElement
  }

  get formFieldsTarget() {
    return this.controller.formFieldsTarget
  }
}

export default BaseManager
```

**Step 2: Update StepManager to extend BaseManager**

```javascript
// In step_manager.js, update class declaration and remove duplicated methods
import { BaseManager } from "controllers/property_editor/base_manager"

export class StepManager extends BaseManager {
  constructor(controller) {
    super(controller, 'stepIndex')
    this._selectedOptions = []
    this._stepActionOptions = []
    this._draggedStepItem = null
  }

  // Remove these methods (now inherited):
  // - reset() - use inherited
  // - setStepIndex() -> setIndex()
  // - getStepIndex() -> getIndex()
  // - incrementStepIndex() -> incrementIndex()
  // - _dispatchStepEvent() -> _dispatchEvent()
  // ...rest of implementation
}
```

**Step 3: Update BranchManager to extend BaseManager**

```javascript
// In branch_manager.js
import { BaseManager } from "controllers/property_editor/base_manager"

export class BranchManager extends BaseManager {
  constructor(controller) {
    super(controller, 'branchIndex')
    this._parentOutputOptions = []
  }
  // ...rest of implementation
}
```

**Step 4: Update IOManager to extend BaseManager**

```javascript
// In io_manager.js
import { BaseManager } from "controllers/property_editor/base_manager"

export class IOManager extends BaseManager {
  constructor(controller) {
    super(controller, 'inputIndex')
    this.outputIndex = 0
  }
  // ...rest of implementation
}
```

**Step 5: Update index.js exports**

```javascript
// app/javascript/controllers/property_editor/index.js
export { BaseManager } from "./base_manager"
export { StepManager } from "./step_manager"
export { BranchManager } from "./branch_manager"
export { IOManager } from "./io_manager"
export { FormBuilder } from "./form_builder"
```

**Step 6: Verify no tests break**

Run: `bundle exec rspec`
Expected: All tests pass

---

## Task 2: Refactor constants.js - Split by Domain

**Files:**
- Modify: `app/javascript/flowchart/constants.js`
- Create: `app/javascript/flowchart/constants/canvas.js`
- Create: `app/javascript/flowchart/constants/elements.js`
- Create: `app/javascript/flowchart/constants/schemas.js`
- Create: `app/javascript/flowchart/constants/index.js`

**Step 1: Create canvas constants module**

```javascript
// app/javascript/flowchart/constants/canvas.js
/**
 * Canvas configuration constants.
 */

/** Grid snap size in pixels */
export const GRID_SIZE = 15

/** Default canvas dimensions */
export const CANVAS_WIDTH = 2000
export const CANVAS_HEIGHT = 1500

/** Threshold for alignment guides to appear */
export const ALIGNMENT_THRESHOLD = 25

/** Radius of connection handle circles */
export const CONNECTION_HANDLE_RADIUS = 6

/** Threshold distance for connection snapping */
export const CONNECTION_THRESHOLD = 30

/** Default animation duration in milliseconds */
export const ANIMATION_DURATION = 300
```

**Step 2: Create elements constants module**

```javascript
// app/javascript/flowchart/constants/elements.js
/**
 * Element configuration constants.
 */

/** Default element dimensions */
export const DEFAULT_ELEMENT_WIDTH = 100
export const DEFAULT_ELEMENT_HEIGHT = 45

/** Spacing between elements when auto-positioning */
export const DEFAULT_ELEMENT_SPACING = 50

/** Vertical spacing below elements when creating subflows */
export const VERTICAL_SPACING = 120

/** Minimum gap between branch elements */
export const MINIMUM_GAP = 40

/** Center-to-center spacing for branch elements */
export const BRANCH_SPACING = 140

/** Element color schemes */
export const ELEMENT_COLORS = {
  start: { fill: "#f0fdf4", stroke: "#10b981" },
  end: { fill: "#fef2f2", stroke: "#ef4444" },
  process: { fill: "#f8fafc", stroke: "#3b82f6" },
  decision: { fill: "#fefce8", stroke: "#f59e0b" },
  loop: { fill: "#faf5ff", stroke: "#a855f7" },
  subflow: { fill: "#ecfeff", stroke: "#06b6d4" }
}

/** Default labels for element types */
export const DEFAULT_LABELS = {
  start: "Start",
  end: "End",
  process: "Process",
  decision: "Decision",
  loop: "Loop"
}
```

**Step 3: Create schemas constants module**

```javascript
// app/javascript/flowchart/constants/schemas.js
/**
 * Property schema definitions for the property editor.
 */

// Import step actions and branch operators from their respective locations
// to keep schema definitions separate from action definitions

/** Common property definitions used across element types */
const COMMON_PROPERTIES = {
  inputs: {
    type: "inputs",
    label: "Inputs",
    dynamicOptions: "input"
  },
  outputs: {
    type: "outputs",
    label: "Outputs",
    dynamicOptions: "output"
  },
  description: {
    type: "textarea",
    label: "Description",
    placeholder: "Describe what this element does..."
  }
}

// ... rest of STEP_ACTIONS, BRANCH_OPERATORS, BRANCH_CONDITIONS, ELEMENT_SCHEMAS
// (Keep in schemas.js as they define the schema structure)
```

**Step 4: Create index.js to re-export all constants**

```javascript
// app/javascript/flowchart/constants/index.js
/**
 * Central export point for all flowchart constants.
 */
export * from "./canvas"
export * from "./elements"
export * from "./schemas"
```

**Step 5: Update main constants.js to re-export from submodules**

```javascript
// app/javascript/flowchart/constants.js
/**
 * Constants and configuration for the flowchart canvas.
 * Re-exports from organized submodules for backwards compatibility.
 */
export * from "./constants/index"
```

**Step 6: Verify imports work throughout application**

Run: `bin/rails assets:precompile`
Expected: No errors

---

## Task 3: Clean Up CSS - Remove Unused Styles and Organize

**Files:**
- Modify: `app/assets/stylesheets/application.css`

**Step 1: Audit CSS usage**

Search codebase for CSS class usage to identify unused styles.

**Step 2: Remove unused CSS variables if any**

Review `:root` variables and remove any not referenced in the codebase.

**Step 3: Consolidate duplicate scrollbar styles**

The scrollbar styles are duplicated. Create a single `.custom-scrollbar` class:

```css
/* Custom Scrollbar - Apply to any scrollable container */
.custom-scrollbar::-webkit-scrollbar,
[data-property-editor-target="formFields"]::-webkit-scrollbar {
  width: 6px;
  height: 6px;
}

.custom-scrollbar::-webkit-scrollbar-track,
[data-property-editor-target="formFields"]::-webkit-scrollbar-track {
  background: #f1f5f9;
  border-radius: 3px;
}

.custom-scrollbar::-webkit-scrollbar-thumb,
[data-property-editor-target="formFields"]::-webkit-scrollbar-thumb {
  background: #cbd5e1;
  border-radius: 3px;
}

.custom-scrollbar::-webkit-scrollbar-thumb:hover,
[data-property-editor-target="formFields"]::-webkit-scrollbar-thumb:hover {
  background: #94a3b8;
}
```

**Step 4: Add section comments for better organization**

Organize CSS into clear sections:
1. CSS Custom Properties
2. Utility Classes
3. Component Styles (Flow Item, Attribute Item)
4. Flowchart Editor Styles
5. SVG Canvas Styles
6. Modal Styles

**Step 5: Verify application styling is intact**

Run: `bin/rails server` and visually verify the flowchart editor works correctly.

---

## Task 4: Refactor SubflowManager - Extract Position Calculator

**Files:**
- Create: `app/javascript/controllers/flowchart_canvas/position_calculator.js`
- Modify: `app/javascript/controllers/flowchart_canvas/subflow_manager.js`

**Step 1: Create PositionCalculator utility class**

Extract positioning logic from SubflowManager:

```javascript
// app/javascript/controllers/flowchart_canvas/position_calculator.js
/**
 * PositionCalculator - Handles element positioning calculations.
 */
export class PositionCalculator {
  /**
   * Calculate position offset for expanding subflow elements.
   * @param {Object} subflowElement - The subflow element being expanded
   * @param {Array} subflowElements - Elements from the subflow configuration
   * @returns {Object} { offsetX, offsetY }
   */
  static calculateExpansionOffset(subflowElement, subflowElements) {
    const minX = Math.min(...subflowElements.map(el => el.x || 0))
    const minY = Math.min(...subflowElements.map(el => el.y || 0))
    return {
      offsetX: subflowElement.x - minX,
      offsetY: subflowElement.y - minY
    }
  }

  /**
   * Calculate child element position adjustment after expansion.
   * @param {Object} endElement - The end element of expanded subflow
   * @param {Object} childElement - The child element to adjust
   * @param {Object} conn - The connection object
   * @returns {Object} { shiftX, shiftY }
   */
  static calculateChildShift(endElement, childElement, conn) {
    const fromPos = "bottom"
    const toPos = conn.toPosition || "top"
    const isVertical = (fromPos === "bottom" || fromPos === "top") &&
                       (toPos === "top" || toPos === "bottom")

    let shiftY = 0
    const spacing = 50
    const endBottom = endElement.y + (endElement.height || 45) / 2
    const childTop = childElement.y - (childElement.height || 45) / 2
    const requiredChildTop = endBottom + spacing

    if (childTop < requiredChildTop) {
      shiftY = requiredChildTop - childTop
    }

    let shiftX = 0
    if (isVertical) {
      shiftX = endElement.x - childElement.x
    }

    return { shiftX, shiftY }
  }
}

export default PositionCalculator
```

**Step 2: Update SubflowManager to use PositionCalculator**

```javascript
// In subflow_manager.js
import { PositionCalculator } from "./position_calculator"

// Replace inline calculations with:
const { offsetX, offsetY } = PositionCalculator.calculateExpansionOffset(
  subflowElement,
  subflowElements
)

// And:
const { shiftX, shiftY } = PositionCalculator.calculateChildShift(
  endElement,
  childElement,
  conn
)
```

**Step 3: Verify subflow expansion/folding still works**

Test manually in browser:
1. Create a subflow element
2. Expand it
3. Fold it back
4. Verify positions are correct

---

## Task 5: Refactor connection_manager.js - Extract ConnectionRenderer

**Files:**
- Create: `app/javascript/flowchart/connection_renderer.js`
- Modify: `app/javascript/flowchart/connection_manager.js`

**Step 1: Create ConnectionRenderer class**

Extract rendering logic:

```javascript
// app/javascript/flowchart/connection_renderer.js
/**
 * ConnectionRenderer - Handles connection path and arrow rendering.
 */
import { createGroup, createPath, createPolygon, createCircle, createText, createRect } from "utils"

const CONNECTION_STYLE = {
  defaultColor: "#666666",
  selectedColor: "#2563eb",
  hoverColor: "#3b82f6",
  strokeWidth: 2,
  selectedStrokeWidth: 3,
  arrowSize: 5
}

export class ConnectionRenderer {
  /**
   * Calculate path between two points.
   */
  static calculatePath(from, to, fromPos, toPos) {
    const isVertical = (fromPos === "bottom" && toPos === "top") ||
                       (fromPos === "top" && toPos === "bottom")

    if (isVertical) {
      return [{ ...from }, { ...to }]
    }

    // Orthogonal path logic...
    // (Extract from connection_manager.js _calculatePath method)
  }

  /**
   * Convert points array to SVG path string.
   */
  static pointsToPath(points) {
    if (points.length < 2) return ""
    return points.map((p, i) => `${i === 0 ? "M" : "L"} ${p.x} ${p.y}`).join(" ")
  }

  /**
   * Calculate arrow angle from path points.
   */
  static calculateArrowAngle(points) {
    const last = points[points.length - 1]
    const prev = points[points.length - 2]
    const angle = Math.atan2(last.y - prev.y, last.x - prev.x)
    return (angle * 180 / Math.PI) + 90
  }

  /**
   * Get arrow polygon points string.
   */
  static getArrowPoints() {
    const s = CONNECTION_STYLE.arrowSize
    return `0,${-s} ${s},${s} ${-s},${s}`
  }

  /**
   * Create the SVG group for a connection.
   */
  static createConnectionGroup(connectionId, pathData, endPoint, pathPoints, label = null) {
    // Extract from connection_manager.js _createConnectionGroup method
  }

  /**
   * Create a label element for a connection.
   */
  static createConnectionLabel(pathPoints, label) {
    // Extract from connection_manager.js _createConnectionLabel method
  }
}

export { CONNECTION_STYLE }
export default ConnectionRenderer
```

**Step 2: Update ConnectionManagerMixin to use ConnectionRenderer**

```javascript
// In connection_manager.js
import { ConnectionRenderer, CONNECTION_STYLE } from "flowchart/connection_renderer"

// Replace direct method calls with:
// this._calculatePath -> ConnectionRenderer.calculatePath
// this._pointsToPath -> ConnectionRenderer.pointsToPath
// etc.
```

**Step 3: Verify connections render correctly**

Test in browser:
1. Create elements and connect them
2. Verify line paths are correct
3. Verify arrows point in correct direction
4. Verify labels display properly

---

## Task 6: Remove Unused Variables and Functions

**Files:**
- Multiple files across the codebase

**Step 1: Search for unused exports in JavaScript**

```bash
# Search for exported but potentially unused functions
grep -r "export function" app/javascript/ --include="*.js"
grep -r "export const" app/javascript/ --include="*.js"
```

**Step 2: Check for unused CSS classes**

```bash
# Search for CSS classes not used in templates
grep -r "class=" app/views/ app/components/ --include="*.erb" --include="*.html.erb"
```

**Step 3: Remove identified unused code**

Based on analysis:
- Remove `buildCloseIconSVG`, `buildPlusIconSVG`, `buildDragHandleSVG` from templates.js if not used (they appear to be utility functions not currently called)

**Step 4: Verify application still works**

Run: `bundle exec rspec`
Expected: All tests pass

---

## Task 7: Improve Variable and Function Naming

**Files:**
- `app/javascript/controllers/property_editor/step_manager.js`
- `app/javascript/controllers/property_editor/branch_manager.js`

**Step 1: Rename ambiguous private variables**

In StepManager:
- `_selectedOptions` -> `_stepSelectionPath` (clearer purpose)
- `_stepActionOptions` -> `_availableActions`
- `_draggedStepItem` -> `_draggedItem`

In BranchManager:
- `_parentOutputOptions` -> `_availableOutputOptions`

**Step 2: Update all references to renamed variables**

Search and replace within each file.

**Step 3: Verify functionality**

Test step and branch modals in browser.

---

## Task 8: Add JSDoc Comments to Key Functions

**Files:**
- `app/javascript/flowchart/canvas.js`
- `app/javascript/controllers/property_editor_controller.js`

**Step 1: Add JSDoc to public API methods in canvas.js**

```javascript
/**
 * Add a new element to the canvas.
 * @param {Object} elementData - Element data including type, properties
 * @param {string} elementData.type - Element type (start, end, process, decision, loop, subflow)
 * @param {string} [elementData.label] - Display label
 * @param {Object} [elementData.properties] - Element-specific properties
 * @returns {Object} The created element
 */
addElement(elementData) {
  // ...
}
```

**Step 2: Add JSDoc to property_editor_controller.js public methods**

```javascript
/**
 * Open the property editor for an element.
 * @param {Object} element - The element to edit
 * @param {Object} canvas - The FlowchartCanvas instance
 */
openEditor(element, canvas) {
  // ...
}
```

---

## Task 9: Consolidate Duplicate Modal Logic

**Files:**
- Modify: `app/javascript/controllers/property_editor/modal_mixin.js`
- Modify: `app/javascript/controllers/property_editor/step_manager.js`
- Modify: `app/javascript/controllers/property_editor/branch_manager.js`

**Step 1: Review modal_mixin.js for completeness**

Ensure all common modal operations are in the mixin:
- Show/hide modal
- Focus management
- Keyboard handling (Escape to close)

**Step 2: Ensure StepManager and BranchManager use mixin methods consistently**

Verify both managers apply the mixin and use its methods.

---

## Task 10: Final Verification and Testing

**Step 1: Run all tests**

```bash
bundle exec rspec
```

Expected: All tests pass

**Step 2: Manual testing checklist**

- [ ] Create new flowchart
- [ ] Add elements (all types)
- [ ] Connect elements
- [ ] Edit element properties
- [ ] Add/remove steps in Process elements
- [ ] Add/remove branches in Decision elements
- [ ] Expand/fold subflows
- [ ] Delete elements and connections
- [ ] Undo/redo operations
- [ ] Save flowchart
- [ ] Generate activity code

**Step 3: Verify no console errors**

Open browser DevTools and check for JavaScript errors.

**Step 4: Verify CSS styling is intact**

Visual review of all UI components.

---

## Notes

- **Do NOT commit changes** - User will review manually
- Each task can be executed independently
- Run tests after each task to ensure no regressions
- Focus on maintaining existing functionality while improving code organization
