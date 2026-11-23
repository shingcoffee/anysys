# Property Panel Refactoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the flowchart property editor from a 320px fixed-width single-scroll panel to a 500px default, resizable, tabbed panel with inline quick-add for steps and branches.

**Architecture:** The property editor stays as a right-side overlay panel. We add a tab bar (General/Steps/I/O/Advanced), widen the panel to 500px with drag-to-resize (400-700px), and add inline quick-add rows for steps and branches. The existing modal system stays unchanged.

**Tech Stack:** StimulusJS, TailwindCSS, vanilla JavaScript modules

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `app/javascript/flowchart/constants/schemas.js` | Modify | Add `tab` property to all field definitions |
| `app/views/flowcharts/_editor.html.erb` | Modify | Update panel HTML: width, tab bar, tab panes |
| `app/javascript/controllers/property_editor/tab_manager.js` | Create | Tab state, visibility, badge updates |
| `app/javascript/controllers/panel_resize_controller.js` | Create | Drag-to-resize with localStorage persistence |
| `app/javascript/controllers/property_editor/form_builder.js` | Modify | Group fields by tab when building form |
| `app/javascript/controllers/property_editor_controller.js` | Modify | Integrate tab_manager, reset tabs on open |
| `app/javascript/controllers/property_editor/step_manager.js` | Modify | Add inline quick-add row |
| `app/javascript/controllers/property_editor/branch_manager.js` | Modify | Add inline quick-add row |

---

### Task 1: Add `tab` property to schemas

**Files:**
- Modify: `app/javascript/flowchart/constants/schemas.js`

- [ ] **Step 1: Add `tab` to COMMON_PROPERTIES**

In `app/javascript/flowchart/constants/schemas.js`, update the `COMMON_PROPERTIES` object to include tab assignments:

```javascript
const COMMON_PROPERTIES = {
  label: {
    type: "text",
    label: "Label",
    placeholder: "Element name...",
    tab: "general"
  },
  inputs: {
    type: "inputs",
    label: "Inputs",
    dynamicOptions: "input",
    tab: "io"
  },
  outputs: {
    type: "outputs",
    label: "Outputs",
    dynamicOptions: "output",
    tab: "io"
  },
  description: {
    type: "textarea",
    label: "Description",
    placeholder: "Describe what this element does...",
    tab: "general"
  },
  comments: {
    type: "textarea",
    label: "Notes",
    placeholder: "Add notes or comments about this element...",
    tab: "general"
  }
}
```

- [ ] **Step 2: Add `tab` to element-specific fields in ELEMENT_SCHEMAS**

For each element type in `ELEMENT_SCHEMAS`, add `tab` to fields that don't inherit it from COMMON_PROPERTIES:

**start:**
```javascript
start: {
  label: COMMON_PROPERTIES.label,
  triggerType: {
    type: "select",
    label: "Trigger Type",
    options: [
      { value: "manual", label: "Manual" },
      { value: "http", label: "HTTP" },
      { value: "event", label: "Event" },
      { value: "schedule", label: "Schedule" }
    ],
    default: "manual",
    tab: "advanced"
  },
  httpMethod: {
    type: "select",
    label: "HTTP Method",
    options: [
      { value: "GET", label: "GET" },
      { value: "POST", label: "POST" },
      { value: "PUT", label: "PUT" },
      { value: "PATCH", label: "PATCH" },
      { value: "DELETE", label: "DELETE" }
    ],
    visibleWhen: { field: "triggerType", value: "http" },
    tab: "advanced"
  },
  httpPath: {
    type: "text",
    label: "HTTP Path",
    placeholder: "/api/resource",
    visibleWhen: { field: "triggerType", value: "http" },
    tab: "advanced"
  },
  eventName: {
    type: "text",
    label: "Event Name",
    placeholder: "user.created",
    visibleWhen: { field: "triggerType", value: "event" },
    tab: "advanced"
  },
  cronExpression: {
    type: "text",
    label: "Cron Expression",
    placeholder: "0 0 * * *",
    visibleWhen: { field: "triggerType", value: "schedule" },
    tab: "advanced"
  },
  inputs: COMMON_PROPERTIES.inputs,
  outputs: COMMON_PROPERTIES.outputs,
  description: {
    ...COMMON_PROPERTIES.description,
    placeholder: "Describe the starting point..."
  }
}
```

**end:**
```javascript
end: {
  label: COMMON_PROPERTIES.label,
  inputs: COMMON_PROPERTIES.inputs,
  responseType: {
    type: "select",
    label: "Response Type",
    options: [
      { value: "none", label: "None" },
      { value: "value", label: "Value" },
      { value: "http_response", label: "HTTP Response" }
    ],
    default: "none",
    tab: "advanced"
  },
  returnValue: {
    type: "text",
    label: "Return Value",
    placeholder: "ctx.result",
    visibleWhen: { field: "responseType", value: "value" },
    tab: "advanced"
  },
  httpStatus: {
    type: "number",
    label: "HTTP Status Code",
    placeholder: "200",
    min: 100,
    max: 599,
    visibleWhen: { field: "responseType", value: "http_response" },
    tab: "advanced"
  },
  responseBody: {
    type: "textarea",
    label: "Response Body",
    placeholder: "{ success: true, data: ctx.result }",
    visibleWhen: { field: "responseType", value: "http_response" },
    tab: "advanced"
  },
  outputs: COMMON_PROPERTIES.outputs,
  description: {
    ...COMMON_PROPERTIES.description,
    placeholder: "Describe the end result..."
  }
}
```

**process:**
```javascript
process: {
  label: COMMON_PROPERTIES.label,
  inputs: COMMON_PROPERTIES.inputs,
  steps: {
    type: "steps",
    label: "Steps",
    actionOptions: STEP_ACTIONS,
    tab: "steps"
  },
  outputs: COMMON_PROPERTIES.outputs,
  description: {
    ...COMMON_PROPERTIES.description,
    placeholder: "Describe what this process does..."
  },
  errorHandling: {
    type: "error_handling",
    label: "Error Handling",
    tab: "advanced"
  }
}
```

**decision:**
```javascript
decision: {
  label: COMMON_PROPERTIES.label,
  inputs: COMMON_PROPERTIES.inputs,
  condition: {
    type: "condition",
    label: "Condition",
    tab: "branches"
  },
  branches: {
    type: "branches",
    label: "Branches",
    conditionOptions: BRANCH_CONDITIONS,
    tab: "branches"
  },
  outputs: COMMON_PROPERTIES.outputs,
  description: {
    ...COMMON_PROPERTIES.description,
    placeholder: "Describe this decision point..."
  }
}
```

**join:**
```javascript
join: {
  label: COMMON_PROPERTIES.label,
  description: {
    ...COMMON_PROPERTIES.description,
    placeholder: "Describe this join point..."
  }
}
```
(Join has no io tab, no steps tab, no advanced tab — only general fields plus join-specific fields added in controller)

**loop:**
```javascript
loop: {
  label: COMMON_PROPERTIES.label,
  inputs: COMMON_PROPERTIES.inputs,
  loopType: {
    type: "select",
    label: "Loop Type",
    options: [
      { value: "while", label: "While" },
      { value: "do_while", label: "Do-While" },
      { value: "for_each", label: "For-Each" }
    ],
    default: "while",
    tab: "advanced"
  },
  condition: {
    type: "condition",
    label: "Loop Condition",
    visibleWhen: { field: "loopType", values: ["while", "do_while", ""] },
    tab: "advanced"
  },
  collection: {
    type: "text",
    label: "Collection",
    placeholder: "e.g. ctx.items or ctx.users",
    visibleWhen: { field: "loopType", value: "for_each" },
    tab: "advanced"
  },
  itemVariable: {
    type: "text",
    label: "Item Variable",
    placeholder: "item",
    visibleWhen: { field: "loopType", value: "for_each" },
    tab: "advanced"
  },
  indexVariable: {
    type: "text",
    label: "Index Variable",
    placeholder: "index",
    visibleWhen: { field: "loopType", value: "for_each" },
    tab: "advanced"
  },
  iterations: {
    type: "number",
    label: "Max Iterations",
    min: 1,
    placeholder: "10",
    tab: "advanced"
  },
  outputs: COMMON_PROPERTIES.outputs,
  description: {
    ...COMMON_PROPERTIES.description,
    placeholder: "Describe what this loop does..."
  }
}
```

**subflow:**
```javascript
subflow: {
  label: COMMON_PROPERTIES.label,
  inputs: COMMON_PROPERTIES.inputs,
  outputs: COMMON_PROPERTIES.outputs,
  description: {
    ...COMMON_PROPERTIES.description,
    placeholder: "Describe what this subflow does..."
  }
}
```

**error_handler:**
```javascript
error_handler: {
  label: COMMON_PROPERTIES.label,
  inputs: COMMON_PROPERTIES.inputs,
  errorTypes: {
    type: "text",
    label: "Error Types",
    placeholder: "e.g., ValidationError, NotFoundError",
    tab: "advanced"
  },
  fallbackAction: {
    type: "select",
    label: "Fallback Action",
    options: [
      { value: "log_and_continue", label: "Log and Continue" },
      { value: "retry_parent", label: "Retry Parent Step" },
      { value: "halt", label: "Halt Execution" }
    ],
    default: "log_and_continue",
    tab: "advanced"
  },
  outputs: COMMON_PROPERTIES.outputs,
  description: COMMON_PROPERTIES.description
}
```

**timer:**
```javascript
timer: {
  label: COMMON_PROPERTIES.label,
  inputs: COMMON_PROPERTIES.inputs,
  delayType: {
    type: "select",
    label: "Delay Type",
    options: [
      { value: "fixed", label: "Fixed Duration" },
      { value: "until_condition", label: "Until Condition" }
    ],
    default: "fixed",
    tab: "advanced"
  },
  duration: {
    type: "number",
    label: "Duration",
    placeholder: "e.g., 30",
    min: 0,
    visibleWhen: { field: "delayType", value: "fixed" },
    tab: "advanced"
  },
  durationUnit: {
    type: "select",
    label: "Duration Unit",
    options: [
      { value: "seconds", label: "Seconds" },
      { value: "minutes", label: "Minutes" },
      { value: "hours", label: "Hours" }
    ],
    default: "seconds",
    visibleWhen: { field: "delayType", value: "fixed" },
    tab: "advanced"
  },
  waitCondition: {
    type: "text",
    label: "Wait Condition",
    placeholder: "e.g., ctx.status == 'ready'",
    visibleWhen: { field: "delayType", value: "until_condition" },
    tab: "advanced"
  },
  outputs: COMMON_PROPERTIES.outputs,
  description: COMMON_PROPERTIES.description
}
```

- [ ] **Step 3: Verify the app still loads without errors**

Run: `bin/rails assets:precompile 2>&1 | tail -5` (or open the app in browser and check console for JS errors)
Expected: No JavaScript syntax errors from the schema changes.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/flowchart/constants/schemas.js
git commit -m "feat: add tab property to all schema field definitions"
```

---

### Task 2: Create TabManager module

**Files:**
- Create: `app/javascript/controllers/property_editor/tab_manager.js`

- [ ] **Step 1: Create the TabManager class**

Create `app/javascript/controllers/property_editor/tab_manager.js`:

```javascript
/**
 * Tab Manager Module
 * Manages tab state, visibility, and badge updates for the property editor.
 */

// Tab definitions with visibility rules per element type
const TAB_CONFIG = {
  general: {
    label: "General",
    visibleFor: ["start", "end", "process", "decision", "join", "loop", "subflow", "error_handler", "timer"]
  },
  steps: {
    labelByType: { process: "Steps", decision: "Branches" },
    visibleFor: ["process", "decision"]
  },
  io: {
    label: "I/O",
    visibleFor: ["start", "end", "process", "decision", "loop", "subflow", "error_handler", "timer"]
  },
  advanced: {
    label: "Advanced",
    visibleFor: ["start", "end", "process", "decision", "join", "loop", "subflow", "error_handler", "timer"]
  }
}

const TAB_ORDER = ["general", "steps", "io", "advanced"]

export class TabManager {
  constructor(controller) {
    this.controller = controller
    this.activeTab = "general"
    this._tabBarEl = null
    this._tabPanes = {}
  }

  /**
   * Build the tab bar HTML and insert it into the panel.
   * Called once when the panel structure is set up.
   * @param {HTMLElement} tabBarContainer - The element to insert the tab bar into
   * @param {Object} tabPanes - Map of tab key to tab pane element { general: el, steps: el, io: el, advanced: el }
   */
  init(tabBarContainer, tabPanes) {
    this._tabBarEl = tabBarContainer
    this._tabPanes = tabPanes
  }

  /**
   * Configure tabs for a specific element type.
   * Shows/hides tabs and sets correct labels.
   * @param {string} elementType - The element type (e.g., "process", "decision")
   */
  configureForElementType(elementType) {
    this.activeTab = "general"

    if (!this._tabBarEl) return

    this._tabBarEl.innerHTML = ""

    TAB_ORDER.forEach(tabKey => {
      const config = TAB_CONFIG[tabKey]
      if (!config.visibleFor.includes(elementType)) return

      const label = config.labelByType?.[elementType] || config.label
      const button = document.createElement("button")
      button.type = "button"
      button.dataset.tab = tabKey
      button.className = this._tabButtonClass(tabKey === "general")
      button.innerHTML = `<span data-tab-label>${label}</span><span data-tab-badge class="ml-1 text-[10px] text-slate-400 font-normal hidden"></span>`
      button.addEventListener("click", () => this.switchTo(tabKey))
      this._tabBarEl.appendChild(button)
    })

    this._showPane("general")
  }

  /**
   * Switch to a specific tab.
   * @param {string} tabKey - The tab to switch to
   */
  switchTo(tabKey) {
    if (tabKey === this.activeTab) return

    this.activeTab = tabKey
    this._updateTabButtons()
    this._showPane(tabKey)
  }

  /**
   * Update badge counts on tabs.
   * @param {Object} counts - { steps: number, branches: number, inputs: number, outputs: number }
   */
  updateBadges(counts) {
    if (!this._tabBarEl) return

    const stepsBtn = this._tabBarEl.querySelector('[data-tab="steps"]')
    if (stepsBtn) {
      const badge = stepsBtn.querySelector("[data-tab-badge]")
      const count = counts.steps ?? counts.branches ?? 0
      if (badge) {
        if (count > 0) {
          badge.textContent = `(${count})`
          badge.classList.remove("hidden")
        } else {
          badge.classList.add("hidden")
        }
      }
    }

    const ioBtn = this._tabBarEl.querySelector('[data-tab="io"]')
    if (ioBtn) {
      const badge = ioBtn.querySelector("[data-tab-badge]")
      const inputCount = counts.inputs ?? 0
      const outputCount = counts.outputs ?? 0
      if (badge) {
        if (inputCount > 0 || outputCount > 0) {
          badge.textContent = `(${inputCount}/${outputCount})`
          badge.classList.remove("hidden")
        } else {
          badge.classList.add("hidden")
        }
      }
    }
  }

  /**
   * Get the tab pane element for a given tab key.
   * @param {string} tabKey
   * @returns {HTMLElement|null}
   */
  getPane(tabKey) {
    return this._tabPanes[tabKey] || null
  }

  // ===================
  // Private
  // ===================

  _showPane(tabKey) {
    TAB_ORDER.forEach(key => {
      const pane = this._tabPanes[key]
      if (!pane) return
      if (key === tabKey) {
        pane.classList.remove("hidden")
      } else {
        pane.classList.add("hidden")
      }
    })
  }

  _updateTabButtons() {
    if (!this._tabBarEl) return
    const buttons = this._tabBarEl.querySelectorAll("[data-tab]")
    buttons.forEach(btn => {
      const isActive = btn.dataset.tab === this.activeTab
      btn.className = this._tabButtonClass(isActive)
    })
  }

  _tabButtonClass(isActive) {
    const base = "px-3 py-1.5 text-xs font-medium border-b-2 transition-colors whitespace-nowrap"
    if (isActive) {
      return `${base} border-indigo-500 text-indigo-600`
    }
    return `${base} border-transparent text-slate-500 hover:text-slate-700`
  }
}

export default TabManager
```

- [ ] **Step 2: Commit**

```bash
git add app/javascript/controllers/property_editor/tab_manager.js
git commit -m "feat: add TabManager module for property editor tabs"
```

---

### Task 3: Create PanelResize controller

**Files:**
- Create: `app/javascript/controllers/panel_resize_controller.js`

- [ ] **Step 1: Create the panel resize Stimulus controller**

Create `app/javascript/controllers/panel_resize_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

/**
 * Panel Resize Controller
 * Provides drag-to-resize functionality for a panel element.
 * Persists the user-chosen width in localStorage.
 */
export default class extends Controller {
  static values = {
    minWidth: { type: Number, default: 400 },
    maxWidth: { type: Number, default: 700 },
    defaultWidth: { type: Number, default: 500 },
    storageKey: { type: String, default: "flowchart_property_panel_width" }
  }

  connect() {
    this._isDragging = false
    this._boundMouseMove = this._onMouseMove.bind(this)
    this._boundMouseUp = this._onMouseUp.bind(this)

    // Restore saved width
    const savedWidth = localStorage.getItem(this.storageKeyValue)
    if (savedWidth) {
      const width = parseInt(savedWidth, 10)
      if (width >= this.minWidthValue && width <= this.maxWidthValue) {
        this.element.style.width = `${width}px`
      }
    }
  }

  disconnect() {
    document.removeEventListener("mousemove", this._boundMouseMove)
    document.removeEventListener("mouseup", this._boundMouseUp)
  }

  /**
   * Start drag resize. Triggered by mousedown on the drag handle.
   * @param {MouseEvent} event
   */
  startResize(event) {
    event.preventDefault()
    this._isDragging = true
    this._startX = event.clientX
    this._startWidth = this.element.offsetWidth

    document.addEventListener("mousemove", this._boundMouseMove)
    document.addEventListener("mouseup", this._boundMouseUp)

    // Prevent text selection during drag
    document.body.style.userSelect = "none"
    document.body.style.cursor = "col-resize"
  }

  _onMouseMove(event) {
    if (!this._isDragging) return

    // Panel is on the right, so dragging left increases width
    const delta = this._startX - event.clientX
    let newWidth = this._startWidth + delta

    // Clamp
    newWidth = Math.max(this.minWidthValue, Math.min(this.maxWidthValue, newWidth))
    this.element.style.width = `${newWidth}px`
  }

  _onMouseUp() {
    if (!this._isDragging) return

    this._isDragging = false
    document.removeEventListener("mousemove", this._boundMouseMove)
    document.removeEventListener("mouseup", this._boundMouseUp)

    document.body.style.userSelect = ""
    document.body.style.cursor = ""

    // Persist width
    const currentWidth = this.element.offsetWidth
    localStorage.setItem(this.storageKeyValue, String(currentWidth))
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/javascript/controllers/panel_resize_controller.js
git commit -m "feat: add PanelResize Stimulus controller for drag-to-resize"
```

---

### Task 4: Update panel HTML structure with tabs and wider default

**Files:**
- Modify: `app/views/flowcharts/_editor.html.erb` (lines 445-507)

- [ ] **Step 1: Replace the property sidebar HTML**

Replace lines 445-507 of `app/views/flowcharts/_editor.html.erb` (the entire `<!-- Right Sidebar - Property Editor -->` block) with:

```erb
    <!-- Right Sidebar - Property Editor (hidden by default, overlays canvas) -->
    <div class="absolute right-0 top-0 bottom-0 z-30 bg-white border-l border-slate-200 shadow-lg transform transition-transform duration-300 ease-in-out hidden"
         style="width: 500px;"
         data-controller="property-editor panel-resize"
         data-panel-resize-min-width-value="400"
         data-panel-resize-max-width-value="700"
         data-panel-resize-default-width-value="500"
         data-property-editor-target="sidebar"
         data-flowchart-canvas-target="propertySidebar">

      <!-- Drag handle for resizing (left edge) -->
      <div class="absolute left-0 top-0 bottom-0 w-1 cursor-col-resize hover:bg-indigo-400 transition-colors z-50"
           data-action="mousedown->panel-resize#startResize"></div>

      <!-- Modal Content Container (for positioning step modal) -->
      <div class="relative h-full flex flex-col" data-property-editor-target="modalContent">

        <!-- Property Editor Header -->
        <div class="px-4 py-2.5 border-b border-slate-200 flex items-center justify-between flex-shrink-0">
          <div class="flex items-center gap-2">
            <span data-property-editor-target="typeIndicator"
                  class="w-2 h-2 rounded-full flex-shrink-0"></span>
            <h3 class="text-sm font-semibold text-slate-900" data-property-editor-target="title">
              Element Properties
            </h3>
          </div>
          <button type="button"
                  data-action="click->property-editor#close"
                  class="text-slate-400 hover:text-slate-600 rounded p-0.5">
            <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <!-- Tab Bar -->
        <div class="flex border-b border-slate-200 bg-slate-50 flex-shrink-0 px-1"
             data-property-editor-target="tabBar">
          <!-- Tabs rendered dynamically by TabManager -->
        </div>

        <!-- Property Editor Form -->
        <form data-property-editor-target="form"
              data-action="submit->property-editor#save"
              class="flex-1 flex flex-col min-h-0">

          <!-- Tab Pane: General -->
          <div class="flex-1 overflow-y-auto px-4 py-3" data-property-editor-target="tabPaneGeneral">
            <div data-property-editor-target="formFieldsGeneral" class="space-y-3"></div>
          </div>

          <!-- Tab Pane: Steps/Branches -->
          <div class="flex-1 overflow-y-auto px-4 py-3 hidden" data-property-editor-target="tabPaneSteps">
            <div data-property-editor-target="formFieldsSteps" class="space-y-3"></div>
          </div>

          <!-- Tab Pane: I/O -->
          <div class="flex-1 overflow-y-auto px-4 py-3 hidden" data-property-editor-target="tabPaneIo">
            <div data-property-editor-target="formFieldsIo" class="space-y-3"></div>
          </div>

          <!-- Tab Pane: Advanced -->
          <div class="flex-1 overflow-y-auto px-4 py-3 hidden" data-property-editor-target="tabPaneAdvanced">
            <div data-property-editor-target="formFieldsAdvanced" class="space-y-3"></div>
          </div>

          <!-- Pinned Footer -->
          <div class="flex items-center justify-end gap-3 px-4 py-3 border-t border-slate-100 bg-white flex-shrink-0">
            <button type="button"
                    data-action="click->property-editor#close"
                    data-property-editor-target="cancelButton"
                    class="inline-flex items-center px-4 py-2 border border-slate-200 text-sm font-medium rounded-md text-slate-600 bg-white hover:bg-slate-50 transition-colors">
              Cancel
            </button>
            <button type="submit"
                    data-property-editor-target="saveButton"
                    class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 transition-colors">
              Save
            </button>
          </div>
        </form>

        <!-- Step Modal Container (populated dynamically, covers property editor sidebar) -->
        <div data-property-editor-target="stepModalContainer" class="absolute inset-0 z-40 pointer-events-none"></div>

        <!-- Branch Modal Container (populated dynamically, covers property editor sidebar) -->
        <div data-property-editor-target="branchModalContainer" class="absolute inset-0 z-40 pointer-events-none"></div>

      </div>
    </div>
```

- [ ] **Step 2: Verify the page renders without errors**

Open the flowchart edit page in the browser. The property panel should be hidden. Double-clicking an element may not fully work yet (form_builder changes come in next tasks), but the page should load without errors.

- [ ] **Step 3: Commit**

```bash
git add app/views/flowcharts/_editor.html.erb
git commit -m "feat: update property panel HTML with tab panes and wider layout"
```

---

### Task 5: Update property_editor_controller.js with tab support

**Files:**
- Modify: `app/javascript/controllers/property_editor_controller.js`

- [ ] **Step 1: Add new targets and import TabManager**

At the top of `property_editor_controller.js`, add the TabManager import:

```javascript
import { TabManager } from "controllers/property_editor/tab_manager"
```

Update `static targets` to include the new tab-related targets:

```javascript
static targets = [
  "sidebar",
  "title",
  "typeIndicator",
  "form",
  "formFields",
  "saveButton",
  "cancelButton",
  "modalContent",
  "stepModalContainer",
  "branchModalContainer",
  "tabBar",
  "tabPaneGeneral",
  "tabPaneSteps",
  "tabPaneIo",
  "tabPaneAdvanced",
  "formFieldsGeneral",
  "formFieldsSteps",
  "formFieldsIo",
  "formFieldsAdvanced"
]
```

- [ ] **Step 2: Initialize TabManager in connect()**

In the `connect()` method, after existing module initializations, add:

```javascript
this.tabManager = new TabManager(this)
```

- [ ] **Step 3: Initialize tab manager when targets connect**

Add a method to initialize the tab manager once all targets are available. Add after `connect()`:

```javascript
tabBarTargetConnected() {
  this.tabManager.init(this.tabBarTarget, {
    general: this.hasTabPaneGeneralTarget ? this.tabPaneGeneralTarget : null,
    steps: this.hasTabPaneStepsTarget ? this.tabPaneStepsTarget : null,
    io: this.hasTabPaneIoTarget ? this.tabPaneIoTarget : null,
    advanced: this.hasTabPaneAdvancedTarget ? this.tabPaneAdvancedTarget : null
  })
}
```

- [ ] **Step 4: Configure tabs when opening the editor**

In the `openEditor()` method, add tab configuration after `this.formBuilder.buildForm()` and before `this._setupFormChangeListeners()`:

```javascript
// Configure tabs for this element type
this.tabManager.configureForElementType(element.type)
```

Also, for join elements, the join-specific fields should go into the advanced tab pane. Update the join field insertion:

```javascript
if (element.type === "join") {
  const joinFieldsHTML = this.joinManager.buildJoinFieldHTML(element)
  const advancedPane = this.hasFormFieldsAdvancedTarget ? this.formFieldsAdvancedTarget : this.formFieldsTarget
  advancedPane.insertAdjacentHTML("beforeend", joinFieldsHTML)
}
```

- [ ] **Step 5: Add a method to get the formFields container for a given tab**

Add a helper method to the controller:

```javascript
/**
 * Get the form fields container for a specific tab.
 * Falls back to the legacy formFields target for backward compatibility.
 * @param {string} tabKey - "general", "steps", "io", "advanced"
 * @returns {HTMLElement}
 */
getFormFieldsForTab(tabKey) {
  switch (tabKey) {
    case "general": return this.hasFormFieldsGeneralTarget ? this.formFieldsGeneralTarget : this.formFieldsTarget
    case "steps": return this.hasFormFieldsStepsTarget ? this.formFieldsStepsTarget : this.formFieldsTarget
    case "io": return this.hasFormFieldsIoTarget ? this.formFieldsIoTarget : this.formFieldsTarget
    case "advanced": return this.hasFormFieldsAdvancedTarget ? this.formFieldsAdvancedTarget : this.formFieldsTarget
    default: return this.formFieldsTarget
  }
}
```

- [ ] **Step 6: Update _collectFormData to read from all tab panes**

The `_collectFormData()` method currently uses `this.formTarget` which wraps all tab panes, so `new FormData(this.formTarget)` will automatically collect fields from all panes. No change needed for data collection itself.

However, the `_collectErrorHandling()` method queries `this.formFieldsTarget`. Update it to also check the advanced pane:

```javascript
_collectErrorHandling() {
  // Check advanced pane first, then legacy formFields
  const container = this.hasFormFieldsAdvancedTarget ? this.formFieldsAdvancedTarget : this.formFieldsTarget
  if (!container) return null

  const modeSelect = container.querySelector("[data-error-handling-mode]")
  if (!modeSelect) return null

  const mode = modeSelect.value || "halt"
  const errorOutputField = container.querySelector("[data-error-output-field]")?.value || "ctx.error"

  return { mode, errorOutputField }
}
```

- [ ] **Step 7: Update conditional field visibility handlers to search all panes**

The `handleLoopTypeChange`, `handleTriggerTypeChange`, `handleResponseTypeChange`, and `handleDelayTypeChange` methods all query `this.formFieldsTarget.querySelectorAll("[data-visible-when]")`. Since these fields now live in the advanced pane, update all four methods to search the form target instead (which wraps all panes):

Replace `this.formFieldsTarget.querySelectorAll("[data-visible-when]")` with `this.formTarget.querySelectorAll("[data-visible-when]")` in all four methods.

- [ ] **Step 8: Verify the app loads and compile**

Run: `bin/rails assets:precompile 2>&1 | tail -5`
Expected: No errors.

- [ ] **Step 9: Commit**

```bash
git add app/javascript/controllers/property_editor_controller.js
git commit -m "feat: integrate TabManager into property editor controller"
```

---

### Task 6: Update FormBuilder to render fields into tab panes

**Files:**
- Modify: `app/javascript/controllers/property_editor/form_builder.js`

- [ ] **Step 1: Rewrite _buildFormFields to group by tab**

Replace the `_buildFormFields` method in `form_builder.js` with:

```javascript
_buildFormFields(schema, properties) {
  // Clear step modal container when rebuilding form
  if (this.controller.hasStepModalContainerTarget) {
    this.controller.stepModalContainerTarget.innerHTML = ""
  }

  // Clear branch modal container when rebuilding form
  if (this.controller.hasBranchModalContainerTarget) {
    this.controller.branchModalContainerTarget.innerHTML = ""
  }

  // Group fields by tab
  const tabFields = { general: "", steps: "", io: "", advanced: "" }

  Object.entries(schema).forEach(([fieldName, fieldSchema]) => {
    let currentValue
    if (fieldName === "label") {
      currentValue = this.controller.currentElement.label ?? fieldSchema.default ?? ""
    } else {
      currentValue = properties[fieldName] ?? fieldSchema.default ?? ""
    }

    let resolvedFieldSchema = fieldSchema
    if (fieldSchema.dynamicOptions) {
      resolvedFieldSchema = this.resolveDynamicOptions(fieldSchema, fieldName)
    }

    const fieldHTML = this._buildFieldHTML(fieldName, resolvedFieldSchema, currentValue)
    const tab = fieldSchema.tab || "general"
    tabFields[tab] += fieldHTML
  })

  // Render each tab's fields into its pane
  const generalContainer = this.controller.getFormFieldsForTab("general")
  const stepsContainer = this.controller.getFormFieldsForTab("steps")
  const ioContainer = this.controller.getFormFieldsForTab("io")
  const advancedContainer = this.controller.getFormFieldsForTab("advanced")

  if (generalContainer) generalContainer.innerHTML = tabFields.general
  if (stepsContainer) stepsContainer.innerHTML = tabFields.steps
  if (ioContainer) ioContainer.innerHTML = tabFields.io
  if (advancedContainer) advancedContainer.innerHTML = tabFields.advanced
}
```

- [ ] **Step 2: Remove old section separators**

In the old `_buildFormFields`, there were section separators for "DATA FLOW" and "ADVANCED". These are no longer needed since tabs serve this purpose. The replacement in Step 1 already removes them.

- [ ] **Step 3: Update _focusFirstInput to target the active tab pane**

Replace `_focusFirstInput`:

```javascript
_focusFirstInput() {
  setTimeout(() => {
    const activeTab = this.controller.tabManager?.activeTab || "general"
    const container = this.controller.getFormFieldsForTab(activeTab)
    if (container) {
      const firstInput = container.querySelector("input, textarea, select")
      if (firstInput) firstInput.focus()
    }
  }, 100)
}
```

- [ ] **Step 4: Verify by opening the property editor for different element types**

Open the flowchart edit page, double-click a Process element. Verify:
- General tab shows label, description
- Steps tab shows the steps section
- I/O tab shows inputs and outputs
- Advanced tab shows error handling

Double-click a Start element:
- General tab shows label, description
- Steps tab should be hidden
- I/O tab shows inputs and outputs
- Advanced tab shows trigger type and conditional fields

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/property_editor/form_builder.js
git commit -m "feat: update FormBuilder to render fields into tab panes"
```

---

### Task 7: Add inline quick-add for steps

**Files:**
- Modify: `app/javascript/controllers/property_editor/step_manager.js`

- [ ] **Step 1: Add inline quick-add row to buildStepsFieldHTML**

In `step_manager.js`, find the `buildStepsFieldHTML` method. Replace the "Add Step" button section (the `stepsHTML +=` after the `</div>` closing `data-steps-container`) with an inline quick-add row plus the existing modal button as fallback:

Replace this block (near line 887-902):
```javascript
    stepsHTML += `
        </div>

        <button type="button"
                data-add-step-button
                ...
        </button>
        ...
      </div>
    `
```

With:
```javascript
    stepsHTML += `
        </div>

        <!-- Inline quick-add row -->
        <div class="mt-2 flex items-center gap-2" data-step-quick-add>
          <select data-step-quick-category
                  data-action="change->property-editor#handleQuickAddCategoryChange"
                  class="flex-1 px-2 py-1.5 text-xs border border-slate-200 bg-slate-50 rounded-md focus:outline-none focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500"
                  ${disableAddButton ? 'disabled' : ''}>
            <option value="">Category...</option>
          </select>
          <select data-step-quick-action
                  class="flex-1 px-2 py-1.5 text-xs border border-slate-200 bg-slate-50 rounded-md focus:outline-none focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500"
                  ${disableAddButton ? 'disabled' : ''}
                  disabled>
            <option value="">Action...</option>
          </select>
          <button type="button"
                  data-action="click->property-editor#quickAddStep"
                  data-add-step-button
                  ${disableAddButton ? 'disabled' : ''}
                  class="px-3 py-1.5 text-xs font-medium text-white bg-indigo-600 rounded-md hover:bg-indigo-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed whitespace-nowrap">
            + Add
          </button>
        </div>

        <input type="hidden" data-action-options value='${JSON.stringify(actionOptions)}'>
      </div>
    `
```

- [ ] **Step 2: Populate category dropdown**

Add a method to populate the category dropdown when the steps field is built. Add after `buildStepsFieldHTML`:

```javascript
/**
 * Populate the inline quick-add category dropdown with action categories.
 * Called after the steps field HTML is inserted into the DOM.
 */
populateQuickAddCategories() {
  const quickAdd = this.controller.formTarget?.querySelector("[data-step-quick-category]")
  if (!quickAdd) return

  const grouped = getActionsByCategory()
  quickAdd.innerHTML = '<option value="">Category...</option>'
  grouped.forEach(g => {
    quickAdd.innerHTML += `<option value="${escapeHtml(g.category.value)}">${escapeHtml(g.category.label)}</option>`
  })
}
```

Call this method from `buildStepsFieldHTML` at the very end, after the modal is rendered. But since the HTML isn't in the DOM yet when `buildStepsFieldHTML` returns, we need to call it after the form is built. Add this to the end of `buildStepsFieldHTML`, before `return stepsHTML`:

```javascript
// Schedule category population after DOM insert
setTimeout(() => this.populateQuickAddCategories(), 0)
```

- [ ] **Step 3: Add handleQuickAddCategoryChange to populate action dropdown**

Add a new method to `StepManager`:

```javascript
/**
 * Handle category selection in inline quick-add.
 * Populates the action dropdown with actions from the selected category.
 */
handleQuickAddCategoryChange(event) {
  const categoryValue = event.target.value
  const quickAddContainer = event.target.closest("[data-step-quick-add]")
  if (!quickAddContainer) return

  const actionSelect = quickAddContainer.querySelector("[data-step-quick-action]")
  if (!actionSelect) return

  if (!categoryValue) {
    actionSelect.innerHTML = '<option value="">Action...</option>'
    actionSelect.disabled = true
    return
  }

  const grouped = getActionsByCategory()
  const category = grouped.find(g => g.category.value === categoryValue)
  if (!category) return

  const usedSingleUse = this.getUsedSingleUseActions()
  const singleUseList = getSingleUseActions()

  actionSelect.innerHTML = '<option value="">Action...</option>'
  category.actions.forEach(a => {
    const isDisabled = singleUseList.includes(a.value) && usedSingleUse.includes(a.value)
    actionSelect.innerHTML += `<option value="${escapeHtml(a.value)}" ${isDisabled ? 'disabled' : ''}>${escapeHtml(a.label)}</option>`
  })
  actionSelect.disabled = false
}
```

- [ ] **Step 4: Add quickAddStep method**

Add a method to handle the inline add button click:

```javascript
/**
 * Quick-add a step from the inline category+action dropdowns.
 * Adds the step directly without opening the modal.
 */
quickAddStep() {
  const quickAdd = this.controller.formTarget?.querySelector("[data-step-quick-add]")
  if (!quickAdd) return

  const categorySelect = quickAdd.querySelector("[data-step-quick-category]")
  const actionSelect = quickAdd.querySelector("[data-step-quick-action]")
  const actionValue = actionSelect?.value
  if (!actionValue) return

  const actionLabel = actionSelect.options[actionSelect.selectedIndex]?.textContent || actionValue
  const categoryLabel = categorySelect.options[categorySelect.selectedIndex]?.textContent || ""

  const container = this.controller.formTarget.querySelector("[data-steps-container]")
  if (!container) return

  // Limit to one step per process element
  const existingSteps = container.querySelectorAll("[data-step-item]")
  if (existingSteps.length >= 1) return

  const emptyState = container.querySelector("[data-steps-empty]")
  if (emptyState) emptyState.classList.add("hidden")

  // Build default config from configSchema
  const actionEntry = getActionConfig(actionValue)
  const defaultConfig = {}
  if (actionEntry) {
    const schema = actionEntry.configSchema || []
    schema.forEach(field => {
      if (field.default !== undefined) defaultConfig[field.key] = field.default
    })
  }

  const selectionLabels = [categoryLabel, actionLabel].filter(Boolean)

  const stepHtml = this.buildStepItemHTML(
    this.stepIndex,
    actionValue,
    "",
    null,
    true,
    "",
    { value: actionValue, label: actionLabel },
    selectionLabels,
    [],
    0, "none", 0, "",
    defaultConfig
  )
  container.insertAdjacentHTML("beforeend", stepHtml)
  this.stepIndex++

  // Disable quick-add controls
  const addButton = quickAdd.querySelector("[data-add-step-button]")
  if (addButton) addButton.disabled = true
  if (categorySelect) categorySelect.disabled = true
  if (actionSelect) actionSelect.disabled = true

  this._dispatchEvent("stepAdded")
}
```

- [ ] **Step 5: Add delegation methods in property_editor_controller.js**

Add these delegated action methods to `property_editor_controller.js`:

```javascript
handleQuickAddCategoryChange(event) {
  this.stepManager.handleQuickAddCategoryChange(event)
}

quickAddStep(event) {
  if (event) event.preventDefault()
  this.stepManager.quickAddStep()
}
```

- [ ] **Step 6: Verify inline step quick-add works**

Open a Process element, switch to Steps tab. Verify:
- Category dropdown shows all categories
- Selecting a category populates the action dropdown
- Clicking "+ Add" adds the step inline
- After adding, the quick-add controls are disabled (one step limit)

- [ ] **Step 7: Commit**

```bash
git add app/javascript/controllers/property_editor/step_manager.js
git add app/javascript/controllers/property_editor_controller.js
git commit -m "feat: add inline quick-add row for steps in property editor"
```

---

### Task 8: Add inline quick-add for branches

**Files:**
- Modify: `app/javascript/controllers/property_editor/branch_manager.js`
- Modify: `app/javascript/controllers/property_editor_controller.js`

- [ ] **Step 1: Add inline quick-add row to buildBranchesFieldHTML**

In `branch_manager.js`, find the `buildBranchesFieldHTML` method. After the existing "Add Branch" button, add an inline quick-add row. Find the section that renders the "Add Branch" button and replace it to include an inline quick-add:

Add this HTML after the branches container closing `</div>` and before the existing `Add Branch` button:

```javascript
// Inline quick-add row for branches
const branchConditions = fieldSchema.conditionOptions || []
let quickAddOptions = '<option value="">Condition type...</option>'
branchConditions.forEach(c => {
  quickAddOptions += `<option value="${escapeHtml(c.value)}">${escapeHtml(c.label)}</option>`
})
```

Then include in the output HTML:

```html
<!-- Inline quick-add row -->
<div class="mt-2 flex items-center gap-2" data-branch-quick-add>
  <select data-branch-quick-condition
          class="flex-1 px-2 py-1.5 text-xs border border-slate-200 bg-slate-50 rounded-md focus:outline-none focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500">
    ${quickAddOptions}
  </select>
  <button type="button"
          data-action="click->property-editor#quickAddBranch"
          class="px-3 py-1.5 text-xs font-medium text-white bg-indigo-600 rounded-md hover:bg-indigo-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed whitespace-nowrap">
    + Add
  </button>
</div>
```

- [ ] **Step 2: Add quickAddBranch method to BranchManager**

Add a method to handle inline branch addition:

```javascript
/**
 * Quick-add a branch from the inline condition type dropdown.
 * Adds a branch with the selected condition type, using default values.
 */
quickAddBranch() {
  const quickAdd = this.controller.formTarget?.querySelector("[data-branch-quick-add]")
  if (!quickAdd) return

  const conditionSelect = quickAdd.querySelector("[data-branch-quick-condition]")
  const conditionValue = conditionSelect?.value
  if (!conditionValue) return

  const conditionLabel = conditionSelect.options[conditionSelect.selectedIndex]?.textContent || conditionValue

  // Create branch with default values
  const branchName = conditionLabel
  const branchData = {
    name: branchName,
    label: conditionLabel,
    conditionType: conditionValue,
    description: "",
    condition: { leftOperand: "", operator: "==", rightOperand: "" }
  }

  // Use existing addBranchToList method or equivalent
  this._addBranchItem(branchData)

  // Reset dropdown
  conditionSelect.value = ""

  this._dispatchEvent("branchAdded")
}
```

Note: The exact `_addBranchItem` implementation depends on the existing branch rendering code in `branch_manager.js`. This method should insert a branch item HTML into the branches container, similar to how `addBranchFromModal` works but with default values. Adapt the call to use the existing `buildBranchItemTemplate` from templates.js.

- [ ] **Step 3: Add delegation method in property_editor_controller.js**

Add to `property_editor_controller.js`:

```javascript
quickAddBranch(event) {
  if (event) event.preventDefault()
  this.branchManager.quickAddBranch()
}
```

- [ ] **Step 4: Verify inline branch quick-add works**

Open a Decision element, switch to Branches tab. Verify:
- Condition type dropdown shows all condition types
- Clicking "+ Add" adds a branch with default values
- User can click "Edit" on the added branch to configure details via modal

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/property_editor/branch_manager.js
git add app/javascript/controllers/property_editor_controller.js
git commit -m "feat: add inline quick-add row for branches in property editor"
```

---

### Task 9: Wire up tab badge updates

**Files:**
- Modify: `app/javascript/controllers/property_editor_controller.js`

- [ ] **Step 1: Add badge update method**

Add a method to `property_editor_controller.js` that computes badge counts and updates the tab manager:

```javascript
/**
 * Update tab badge counts based on current form state.
 */
_updateTabBadges() {
  if (!this.tabManager) return

  const counts = {}

  if (this.currentElement?.type === "process") {
    const container = this.formTarget?.querySelector("[data-steps-container]")
    counts.steps = container ? container.querySelectorAll("[data-step-item]").length : 0
  }

  if (this.currentElement?.type === "decision") {
    const container = this.formTarget?.querySelector("[data-branches-container]")
    counts.branches = container ? container.querySelectorAll("[data-branch-item]").length : 0
  }

  // Count visible (non-hidden) inputs and outputs
  const inputItems = this.formTarget?.querySelectorAll("[data-input-item]") || []
  const outputItems = this.formTarget?.querySelectorAll("[data-output-item]") || []
  counts.inputs = Array.from(inputItems).filter(el => !el.querySelector("[data-hidden-input]")).length
  counts.outputs = Array.from(outputItems).filter(el => !el.querySelector("[data-hidden-output]")).length

  this.tabManager.updateBadges(counts)
}
```

- [ ] **Step 2: Call badge update after form build and after sync events**

In `openEditor()`, after `this.tabManager.configureForElementType(element.type)`, add:

```javascript
this._updateTabBadges()
```

In `_performSync()`, at the end of the method (before the closing `}`), add:

```javascript
this._updateTabBadges()
```

Also call it in the form event listeners. The simplest approach is to call `_updateTabBadges()` inside `_syncChangesToCanvas()` after the debounce fires. Since `_performSync()` is already the debounced target, the addition in Step 2 covers this.

- [ ] **Step 3: Verify badge counts**

Open a Process element that has a step — the Steps tab should show "(1)".
Open a Decision element with branches — the Branches tab should show the count.
Add/remove inputs or outputs — the I/O tab badge should update live.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/property_editor_controller.js
git commit -m "feat: add live tab badge counts for steps, branches, and I/O"
```

---

### Task 10: Handle connection editor (no tabs)

**Files:**
- Modify: `app/javascript/controllers/property_editor_controller.js`

- [ ] **Step 1: Hide tab bar and show single pane for connection editing**

In `openConnectionEditor()`, after the existing code that builds the connection form, add tab bar hiding logic. Update the method to hide the tab bar and use the general pane:

After `this._removeFormChangeListeners()` at the start of the method, add:

```javascript
// Hide tab bar for connections (no tabs needed)
if (this.hasTabBarTarget) {
  this.tabBarTarget.classList.add("hidden")
}
// Show only the general pane
if (this.hasTabPaneGeneralTarget) this.tabPaneGeneralTarget.classList.remove("hidden")
if (this.hasTabPaneStepsTarget) this.tabPaneStepsTarget.classList.add("hidden")
if (this.hasTabPaneIoTarget) this.tabPaneIoTarget.classList.add("hidden")
if (this.hasTabPaneAdvancedTarget) this.tabPaneAdvancedTarget.classList.add("hidden")
```

Update `_buildConnectionForm` to render into the general pane:

Replace `this.formFieldsTarget.innerHTML = ...` with:

```javascript
const container = this.hasFormFieldsGeneralTarget ? this.formFieldsGeneralTarget : this.formFieldsTarget
container.innerHTML = ...
```

- [ ] **Step 2: Show tab bar when opening element editor**

In `openEditor()`, before `this.tabManager.configureForElementType(element.type)`, ensure the tab bar is visible:

```javascript
if (this.hasTabBarTarget) {
  this.tabBarTarget.classList.remove("hidden")
}
```

- [ ] **Step 3: Verify**

Open a connection (single-click) — should show connection form without tabs.
Open an element (double-click) — should show tabbed form.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/property_editor_controller.js
git commit -m "feat: hide tab bar for connection editing, show for elements"
```

---

### Task 11: Handle 2-column layout for Advanced tab short fields

**Files:**
- Modify: `app/javascript/controllers/property_editor/form_builder.js`

- [ ] **Step 1: Add 2-column wrapper for short fields in advanced tab**

In `_buildFieldHTML`, detect when a field is in the "advanced" tab and is a "select" or "number" type. Wrap consecutive short fields in a 2-column grid.

A simpler approach: add a CSS grid wrapper in `_buildFormFields` for the advanced tab content. After building `tabFields.advanced`, wrap it:

In `_buildFormFields`, after the `Object.entries(schema).forEach(...)` loop, before rendering into containers, process the advanced tab fields:

```javascript
// For the advanced tab, wrap fields in a responsive grid for short fields
if (tabFields.advanced) {
  // The 2-column layout is achieved via CSS grid on the container
  // Individual fields that should span full width (textarea) will use col-span-2
}
```

Actually, the simplest approach is to add a CSS class to the advanced fields container. Update the HTML in `_editor.html.erb` for the advanced pane:

Change the `formFieldsAdvanced` div class from `class="space-y-3"` to `class="grid grid-cols-2 gap-3"`.

Then in `_buildFieldHTML`, when the field is in the "advanced" tab and is a `textarea` type, add `col-span-2` to the wrapper div:

```javascript
// In _buildFieldHTML, after building the opening div:
const tabKey = fieldSchema.tab || "general"
const colSpanClass = (tabKey === "advanced" && (fieldSchema.type === "textarea")) ? " col-span-2" : ""

let fieldHTML = `
  <div class="mb-3${hiddenClass}${colSpanClass}"${visibilityAttrs}>
```

Note: Also add `col-span-2` for `text` type fields in the advanced tab that are full-width (like `waitCondition`, `errorTypes`). A simple rule: add `col-span-2` for `textarea` and `text` types in the advanced tab.

Update the condition:
```javascript
const colSpanClass = (tabKey === "advanced" && (fieldSchema.type === "textarea" || fieldSchema.type === "text")) ? " col-span-2" : ""
```

- [ ] **Step 2: Update _editor.html.erb advanced pane**

In `_editor.html.erb`, change the advanced pane's inner div:

```html
<div data-property-editor-target="formFieldsAdvanced" class="grid grid-cols-2 gap-3"></div>
```

- [ ] **Step 3: Verify the advanced tab layout**

Open a Start element, go to Advanced tab. Verify:
- `triggerType` select and `httpMethod` select appear side by side
- `httpPath` text field spans full width
- Layout looks clean with 2-column for selects/numbers and full-width for text/textarea

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/property_editor/form_builder.js
git add app/views/flowcharts/_editor.html.erb
git commit -m "feat: add 2-column layout for short fields in advanced tab"
```

---

### Task 12: Final integration testing and cleanup

**Files:**
- All modified files

- [ ] **Step 1: Test all element types**

Manually test each element type by double-clicking on the canvas:

1. **Process**: General (label, desc), Steps (step list + quick-add), I/O (inputs/outputs), Advanced (error handling)
2. **Decision**: General, Branches (condition + branch list + quick-add), I/O, Advanced
3. **Start**: General, I/O, Advanced (trigger type + conditional fields)
4. **End**: General, I/O, Advanced (response type + conditional fields)
5. **Loop**: General, I/O, Advanced (loop type + conditional fields)
6. **Error Handler**: General, I/O, Advanced (error types, fallback)
7. **Timer**: General, I/O, Advanced (delay type + conditional fields)
8. **Subflow**: General, I/O, Advanced
9. **Join**: General, Advanced (join-specific fields)

For each, verify:
- Correct tabs visible/hidden
- Fields render in correct tab
- Tab switching preserves data
- Save works correctly
- Cancel closes without losing cached changes
- Reopening restores cached changes

- [ ] **Step 2: Test panel resize**

1. Drag the left edge of the panel to resize
2. Verify min (400px) and max (700px) constraints
3. Close and reopen the panel — verify the width is restored from localStorage
4. Clear localStorage and reopen — verify default 500px

- [ ] **Step 3: Test inline quick-add for steps**

1. Open a Process element
2. Go to Steps tab
3. Select a category from the dropdown
4. Select an action
5. Click "+ Add"
6. Verify the step appears in the list
7. Verify quick-add controls are disabled (one step limit)
8. Remove the step — verify quick-add re-enables

- [ ] **Step 4: Test inline quick-add for branches**

1. Open a Decision element
2. Go to Branches tab
3. Select a condition type from the dropdown
4. Click "+ Add"
5. Verify the branch appears in the list
6. Click "Edit" on the branch — verify the modal opens

- [ ] **Step 5: Test connection editing**

1. Click a connection
2. Verify no tab bar shown
3. Verify connection form (label, description, priority) renders in the panel
4. Save and verify persistence

- [ ] **Step 6: Test tab badges**

1. Open Process with steps — Steps tab shows count
2. Open Decision with branches — Branches tab shows count
3. Add/remove inputs/outputs — I/O badge updates live

- [ ] **Step 7: Commit all remaining changes**

```bash
git add -A
git commit -m "feat: complete property panel refactoring with tabs, resize, and inline quick-add"
```
