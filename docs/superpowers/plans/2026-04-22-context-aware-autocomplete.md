# Context-Aware Autocomplete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add autocomplete to step config fields showing available context variables from upstream elements, prior steps, and implicit keys.

**Architecture:** A `ContextVariableProvider` module collects available variables grouped by source. A `context-autocomplete` Stimulus controller attaches to config text/textarea fields, shows a dropdown on typing, handles keyboard navigation, and inserts selected variables.

**Tech Stack:** StimulusJS, vanilla JavaScript, TailwindCSS

---

## File Structure

**New Files:**
| File | Responsibility |
|------|----------------|
| `app/javascript/flowchart/context_variable_provider.js` | Collects implicit keys, upstream outputs, prior step outputs; returns grouped results |
| `app/javascript/controllers/context_autocomplete_controller.js` | Stimulus controller: listens for input, renders dropdown, handles selection |

**Modified Files:**
| File | Changes |
|------|---------|
| `app/javascript/controllers/property_editor/templates.js` | Add context param to `buildConfigTextField`, `buildConfigTextareaField`, `buildStepConfigFieldsHTML`; add controller data attributes |
| `app/javascript/controllers/property_editor/step_manager.js` | Pass context object (elementId, stepIndex) when calling `buildStepConfigHTML` |

---

### Task 1: Create ContextVariableProvider with Implicit Keys

**Files:**
- Create: `app/javascript/flowchart/context_variable_provider.js`

- [ ] **Step 1: Create the provider module with implicit keys caching**

```javascript
// app/javascript/flowchart/context_variable_provider.js

/**
 * ContextVariableProvider — collects available context variables for autocomplete.
 *
 * Returns variables grouped by source:
 * - Implicit keys (always available runtime context)
 * - Upstream element outputs
 * - Prior step outputs within the same element
 */

let _implicitKeysCache = null
let _implicitKeysPromise = null

async function fetchImplicitKeys() {
  if (_implicitKeysCache) return _implicitKeysCache

  if (_implicitKeysPromise) {
    await _implicitKeysPromise
    return _implicitKeysCache
  }

  _implicitKeysPromise = (async () => {
    try {
      const response = await fetch("/flowchart_validation/implicit_keys.json")
      if (response.ok) {
        const data = await response.json()
        _implicitKeysCache = data.implicit_keys || []
      } else {
        _implicitKeysCache = []
      }
    } catch (e) {
      console.warn("[ContextVariableProvider] Failed to fetch implicit keys:", e)
      _implicitKeysCache = []
    }
  })()

  await _implicitKeysPromise
  return _implicitKeysCache
}

/**
 * Get available variables for a given element and step position.
 * @param {Object} canvas - FlowchartCanvas instance
 * @param {string} elementId - Current element ID
 * @param {number} stepIndex - Current step index (-1 for element-level)
 * @returns {Promise<{groups: Array}>}
 */
export async function getAvailableVariables(canvas, elementId, stepIndex = -1) {
  const groups = []

  // 1. Implicit keys (always first)
  const implicitKeys = await fetchImplicitKeys()
  if (implicitKeys.length > 0) {
    groups.push({
      label: "Always Available",
      source: "implicit",
      variables: [...implicitKeys]
    })
  }

  // 2. Upstream element outputs (Task 2)
  // 3. Prior step outputs (Task 3)

  return { groups }
}

/**
 * Filter variables by search term.
 * @param {{groups: Array}} result - Result from getAvailableVariables
 * @param {string} term - Search term
 * @returns {{groups: Array}}
 */
export function filterVariables(result, term) {
  if (!term || term.trim() === "") return result

  const lowerTerm = term.toLowerCase()
  const filteredGroups = []

  for (const group of result.groups) {
    const filtered = group.variables.filter(v => v.toLowerCase().includes(lowerTerm))
    if (filtered.length > 0) {
      filteredGroups.push({ ...group, variables: filtered })
    }
  }

  return { groups: filteredGroups }
}

// For testing: reset cache
export function _resetCache() {
  _implicitKeysCache = null
  _implicitKeysPromise = null
}
```

- [ ] **Step 2: Verify file was created**

Run: `cat app/javascript/flowchart/context_variable_provider.js | head -20`

Expected: First 20 lines of the provider module

- [ ] **Step 3: Commit**

```bash
git add app/javascript/flowchart/context_variable_provider.js
git commit -m "feat: add ContextVariableProvider with implicit keys support"
```

---

### Task 2: Add Upstream Element Outputs to Provider

**Files:**
- Modify: `app/javascript/flowchart/context_variable_provider.js`

- [ ] **Step 1: Import ElementReachability and add upstream outputs collection**

Add import at top of file:

```javascript
import { ElementReachability } from "controllers/property_editor/element_io/reachability"
```

- [ ] **Step 2: Add helper function to get effective outputs for an element**

Add after the `fetchImplicitKeys` function:

```javascript
/**
 * Get effective output keys for an element, honoring io_overrides renames.
 */
function getElementEffectiveOutputs(canvas, elementId) {
  const pins = canvas.getElementPins?.(elementId) || { outputs: [] }
  const outputPins = pins.outputs || []
  const element = canvas.elements.find(el => el.id === elementId)
  const overrides = element?.properties?.io_overrides?.outputs || []

  const overrideMap = new Map()
  for (const o of overrides) {
    overrideMap.set(o.pin, o.renamed_to)
  }

  const effectiveKeys = []
  for (const pin of outputPins) {
    const effective = overrideMap.get(pin.pin) || pin.pin
    effectiveKeys.push(effective)
  }

  return effectiveKeys
}
```

- [ ] **Step 3: Update getAvailableVariables to include upstream outputs**

Replace the comment `// 2. Upstream element outputs (Task 2)` with:

```javascript
  // 2. Upstream element outputs
  if (canvas && elementId) {
    const reachability = new ElementReachability(canvas)
    const predecessors = reachability.predecessors(elementId)

    // Process in reverse order (farthest first in array, we want nearest last)
    for (const predId of predecessors) {
      const predElement = canvas.elements.find(el => el.id === predId)
      if (!predElement) continue

      const outputs = getElementEffectiveOutputs(canvas, predId)
      if (outputs.length === 0) continue

      const label = predElement.label || predElement.type || predId
      groups.push({
        label: `From '${label}'`,
        source: "element",
        sourceId: predId,
        variables: outputs
      })
    }
  }
```

- [ ] **Step 4: Verify changes**

Run: `grep -n "ElementReachability\|getElementEffectiveOutputs\|From '" app/javascript/flowchart/context_variable_provider.js`

Expected: Lines showing the import, helper function, and "From '" label pattern

- [ ] **Step 5: Commit**

```bash
git add app/javascript/flowchart/context_variable_provider.js
git commit -m "feat: add upstream element outputs to ContextVariableProvider"
```

---

### Task 3: Add Prior Step Outputs to Provider

**Files:**
- Modify: `app/javascript/flowchart/context_variable_provider.js`

- [ ] **Step 1: Add helper function to get step effective outputs**

Add after the `getElementEffectiveOutputs` function:

```javascript
/**
 * Get effective output keys for a step, honoring io_overrides renames.
 */
function getStepEffectiveOutputs(canvas, stepId) {
  const pins = canvas.getStepPins?.(stepId) || { outputs: [] }
  const outputPins = pins.outputs || []
  const located = canvas.findStepById?.(stepId)
  const overrides = located?.step?.io_overrides?.outputs || []

  const overrideMap = new Map()
  for (const o of overrides) {
    overrideMap.set(o.pin, o.renamed_to)
  }

  const effectiveKeys = []
  for (const pin of outputPins) {
    const effective = overrideMap.get(pin.pin) || pin.pin
    effectiveKeys.push(effective)
  }

  return effectiveKeys
}
```

- [ ] **Step 2: Update getAvailableVariables to include prior step outputs**

Replace the comment `// 3. Prior step outputs (Task 3)` with:

```javascript
  // 3. Prior step outputs within current element
  if (canvas && elementId && stepIndex >= 0) {
    const element = canvas.elements.find(el => el.id === elementId)
    const steps = element?.properties?.steps || []

    for (let i = 0; i < stepIndex && i < steps.length; i++) {
      const step = steps[i]
      if (!step.id) continue

      const outputs = getStepEffectiveOutputs(canvas, step.id)
      if (outputs.length === 0) continue

      const stepLabel = step.selectionLabels?.join(" - ") || step.action || step.id
      groups.push({
        label: `From '${stepLabel}' (this element)`,
        source: "step",
        sourceId: step.id,
        variables: outputs
      })
    }
  }
```

- [ ] **Step 3: Verify changes**

Run: `grep -n "getStepEffectiveOutputs\|this element" app/javascript/flowchart/context_variable_provider.js`

Expected: Lines showing the helper function and "(this element)" label pattern

- [ ] **Step 4: Commit**

```bash
git add app/javascript/flowchart/context_variable_provider.js
git commit -m "feat: add prior step outputs to ContextVariableProvider"
```

---

### Task 4: Create Stimulus Controller Shell

**Files:**
- Create: `app/javascript/controllers/context_autocomplete_controller.js`

- [ ] **Step 1: Create the controller with basic structure**

```javascript
// app/javascript/controllers/context_autocomplete_controller.js

import { Controller } from "@hotwired/stimulus"
import { getAvailableVariables, filterVariables } from "flowchart/context_variable_provider"

/**
 * Context Autocomplete Controller
 *
 * Attaches to text/textarea config fields to show available context variables.
 * Shows a dropdown on typing, supports keyboard navigation, inserts selection.
 */
export default class extends Controller {
  static values = {
    elementId: String,
    stepIndex: { type: Number, default: -1 }
  }

  connect() {
    this._dropdown = null
    this._selectedIndex = 0
    this._filteredGroups = []
    this._allOptions = []
    this._canvas = null

    this._boundOnInput = this._onInput.bind(this)
    this._boundOnKeydown = this._onKeydown.bind(this)
    this._boundOnBlur = this._onBlur.bind(this)
    this._boundOnClickOutside = this._onClickOutside.bind(this)

    this.element.addEventListener("input", this._boundOnInput)
    this.element.addEventListener("keydown", this._boundOnKeydown)
    this.element.addEventListener("blur", this._boundOnBlur)

    this._resolveCanvas()
  }

  disconnect() {
    this.element.removeEventListener("input", this._boundOnInput)
    this.element.removeEventListener("keydown", this._boundOnKeydown)
    this.element.removeEventListener("blur", this._boundOnBlur)
    document.removeEventListener("mousedown", this._boundOnClickOutside)
    this._destroyDropdown()
  }

  _resolveCanvas() {
    const canvasEl = document.querySelector('[data-controller*="flowchart-canvas"]')
    this._canvas = canvasEl?.flowchartCanvas || null
  }

  async _onInput(event) {
    // Will be implemented in Task 5
  }

  _onKeydown(event) {
    // Will be implemented in Task 6
  }

  _onBlur(event) {
    // Close dropdown after short delay to allow click on option
    setTimeout(() => {
      if (!this._dropdown?.contains(document.activeElement)) {
        this._destroyDropdown()
      }
    }, 150)
  }

  _onClickOutside(event) {
    if (this._dropdown && !this._dropdown.contains(event.target) && event.target !== this.element) {
      this._destroyDropdown()
    }
  }

  _destroyDropdown() {
    if (this._dropdown) {
      this._dropdown.remove()
      this._dropdown = null
      document.removeEventListener("mousedown", this._boundOnClickOutside)
    }
    this._selectedIndex = 0
    this._filteredGroups = []
    this._allOptions = []
  }
}
```

- [ ] **Step 2: Verify file was created**

Run: `head -30 app/javascript/controllers/context_autocomplete_controller.js`

Expected: Controller import and class definition

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/context_autocomplete_controller.js
git commit -m "feat: add context-autocomplete Stimulus controller shell"
```

---

### Task 5: Implement Dropdown Rendering

**Files:**
- Modify: `app/javascript/controllers/context_autocomplete_controller.js`

- [ ] **Step 1: Implement _onInput to fetch and render variables**

Replace the `_onInput` method:

```javascript
  async _onInput(event) {
    if (!this._canvas) {
      this._resolveCanvas()
      if (!this._canvas) {
        this._destroyDropdown()
        return
      }
    }

    const term = this._getWordAtCursor()
    const result = await getAvailableVariables(this._canvas, this.elementIdValue, this.stepIndexValue)
    const filtered = filterVariables(result, term)

    this._filteredGroups = filtered.groups
    this._allOptions = this._flattenOptions(filtered.groups)
    this._selectedIndex = 0

    if (this._allOptions.length > 0) {
      this._renderDropdown()
    } else {
      this._destroyDropdown()
    }
  }
```

- [ ] **Step 2: Add helper to get word at cursor**

Add after `_resolveCanvas`:

```javascript
  _getWordAtCursor() {
    const input = this.element
    const value = input.value || ""
    const cursorPos = input.selectionStart || 0

    // Find word boundaries
    let start = cursorPos
    while (start > 0 && /\w/.test(value[start - 1])) {
      start--
    }

    let end = cursorPos
    while (end < value.length && /\w/.test(value[end])) {
      end++
    }

    return value.slice(start, end)
  }
```

- [ ] **Step 3: Add helper to flatten options for navigation**

Add after `_getWordAtCursor`:

```javascript
  _flattenOptions(groups) {
    const options = []
    for (const group of groups) {
      for (const variable of group.variables) {
        options.push({ variable, groupLabel: group.label })
      }
    }
    return options
  }
```

- [ ] **Step 4: Add dropdown rendering method**

Add after `_flattenOptions`:

```javascript
  _renderDropdown() {
    if (!this._dropdown) {
      this._dropdown = document.createElement("div")
      this._dropdown.className = "context-autocomplete-dropdown bg-white border border-slate-200 rounded-lg shadow-lg max-h-64 overflow-y-auto w-64"
      this._dropdown.style.cssText = "position: fixed; z-index: 9999;"
      document.body.appendChild(this._dropdown)
      document.addEventListener("mousedown", this._boundOnClickOutside)
    }

    this._positionDropdown()
    this._dropdown.innerHTML = this._buildDropdownHTML()
    this._updateSelection()
    this._wireOptionClicks()
  }

  _positionDropdown() {
    const rect = this.element.getBoundingClientRect()
    const spaceBelow = window.innerHeight - rect.bottom
    const dropdownHeight = 256 // max-h-64 = 16rem = 256px

    if (spaceBelow < dropdownHeight && rect.top > dropdownHeight) {
      // Position above
      this._dropdown.style.top = `${rect.top - dropdownHeight}px`
    } else {
      // Position below
      this._dropdown.style.top = `${rect.bottom + 4}px`
    }
    this._dropdown.style.left = `${rect.left}px`
  }

  _buildDropdownHTML() {
    if (this._filteredGroups.length === 0) {
      return '<div class="px-3 py-2 text-xs text-slate-500 italic">No matching variables</div>'
    }

    return this._filteredGroups.map(group => `
      <div class="context-autocomplete-group">
        <div class="px-2 py-1 text-[10px] font-semibold text-slate-500 uppercase tracking-wide bg-slate-50 sticky top-0">
          ${this._escapeHtml(group.label)}
        </div>
        ${group.variables.map(v => `
          <div class="context-autocomplete-option px-3 py-1.5 text-xs text-slate-700 cursor-pointer hover:bg-indigo-50"
               data-value="${this._escapeHtml(v)}">
            ${this._escapeHtml(v)}
          </div>
        `).join("")}
      </div>
    `).join("")
  }

  _escapeHtml(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }

  _wireOptionClicks() {
    const options = this._dropdown.querySelectorAll(".context-autocomplete-option")
    options.forEach((opt, idx) => {
      opt.addEventListener("mousedown", (e) => {
        e.preventDefault()
        this._selectOption(opt.dataset.value)
      })
    })
  }
```

- [ ] **Step 5: Verify changes**

Run: `grep -n "_renderDropdown\|_buildDropdownHTML\|_positionDropdown" app/javascript/controllers/context_autocomplete_controller.js`

Expected: Lines showing all three rendering methods

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/context_autocomplete_controller.js
git commit -m "feat: implement dropdown rendering for context autocomplete"
```

---

### Task 6: Implement Keyboard Navigation and Selection

**Files:**
- Modify: `app/javascript/controllers/context_autocomplete_controller.js`

- [ ] **Step 1: Implement _onKeydown for navigation**

Replace the `_onKeydown` method:

```javascript
  _onKeydown(event) {
    if (!this._dropdown) return

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this._selectedIndex = Math.min(this._selectedIndex + 1, this._allOptions.length - 1)
        this._updateSelection()
        break

      case "ArrowUp":
        event.preventDefault()
        this._selectedIndex = Math.max(this._selectedIndex - 1, 0)
        this._updateSelection()
        break

      case "Enter":
      case "Tab":
        if (this._allOptions.length > 0) {
          event.preventDefault()
          const selected = this._allOptions[this._selectedIndex]
          if (selected) {
            this._selectOption(selected.variable)
          }
        }
        break

      case "Escape":
        event.preventDefault()
        this._destroyDropdown()
        break
    }
  }
```

- [ ] **Step 2: Add selection highlighting method**

Add after `_wireOptionClicks`:

```javascript
  _updateSelection() {
    if (!this._dropdown) return

    const options = this._dropdown.querySelectorAll(".context-autocomplete-option")
    options.forEach((opt, idx) => {
      if (idx === this._selectedIndex) {
        opt.classList.add("bg-indigo-100", "text-indigo-900")
        opt.classList.remove("hover:bg-indigo-50")
        opt.scrollIntoView({ block: "nearest" })
      } else {
        opt.classList.remove("bg-indigo-100", "text-indigo-900")
        opt.classList.add("hover:bg-indigo-50")
      }
    })
  }
```

- [ ] **Step 3: Add option selection method**

Add after `_updateSelection`:

```javascript
  _selectOption(variable) {
    const input = this.element
    const value = input.value || ""
    const cursorPos = input.selectionStart || 0

    // Find word boundaries to replace
    let start = cursorPos
    while (start > 0 && /\w/.test(value[start - 1])) {
      start--
    }

    let end = cursorPos
    while (end < value.length && /\w/.test(value[end])) {
      end++
    }

    // Replace word with selected variable
    const before = value.slice(0, start)
    const after = value.slice(end)
    input.value = before + variable + after

    // Position cursor after inserted variable
    const newPos = start + variable.length
    input.setSelectionRange(newPos, newPos)

    // Dispatch input event to trigger form sync
    input.dispatchEvent(new Event("input", { bubbles: true }))

    this._destroyDropdown()
  }
```

- [ ] **Step 4: Verify changes**

Run: `grep -n "_onKeydown\|_updateSelection\|_selectOption" app/javascript/controllers/context_autocomplete_controller.js`

Expected: Lines showing all three methods

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/context_autocomplete_controller.js
git commit -m "feat: add keyboard navigation and selection to context autocomplete"
```

---

### Task 7: Update templates.js to Add Controller Attributes

**Files:**
- Modify: `app/javascript/controllers/property_editor/templates.js:357-373`

- [ ] **Step 1: Update buildConfigTextField to accept context parameter**

Replace the `buildConfigTextField` function (around line 357):

```javascript
function buildConfigTextField(field, value, context = {}) {
  const { elementId, stepIndex } = context
  const controllerAttrs = elementId
    ? ` data-controller="context-autocomplete" data-context-autocomplete-element-id-value="${escapeHtml(elementId)}" data-context-autocomplete-step-index-value="${stepIndex ?? -1}"`
    : ""

  return `<input type="text"
    data-config-input="${escapeHtml(field.key)}"${controllerAttrs}
    value="${escapeHtml(String(value))}"
    placeholder="${escapeHtml(field.placeholder || "")}"
    ${field.required ? "required" : ""}
    class="w-full px-2 py-1 text-xs border border-slate-200 rounded shadow-sm placeholder:text-slate-400 focus:outline-none focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500">`
}
```

- [ ] **Step 2: Update buildConfigTextareaField to accept context parameter**

Replace the `buildConfigTextareaField` function (around line 366):

```javascript
function buildConfigTextareaField(field, value, context = {}) {
  const { elementId, stepIndex } = context
  const controllerAttrs = elementId
    ? ` data-controller="context-autocomplete" data-context-autocomplete-element-id-value="${escapeHtml(elementId)}" data-context-autocomplete-step-index-value="${stepIndex ?? -1}"`
    : ""

  return `<textarea
    data-config-input="${escapeHtml(field.key)}"${controllerAttrs}
    rows="2"
    placeholder="${escapeHtml(field.placeholder || "")}"
    ${field.required ? "required" : ""}
    class="w-full px-2 py-1 text-xs border border-slate-200 rounded shadow-sm resize-none placeholder:text-slate-400 focus:outline-none focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500">${escapeHtml(String(value))}</textarea>`
}
```

- [ ] **Step 3: Verify changes**

Run: `grep -n "context-autocomplete\|context = {}" app/javascript/controllers/property_editor/templates.js | head -10`

Expected: Lines showing controller attribute and context parameter

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/property_editor/templates.js
git commit -m "feat: add context-autocomplete controller attributes to config text fields"
```

---

### Task 8: Update buildStepConfigFieldsHTML to Pass Context

**Files:**
- Modify: `app/javascript/controllers/property_editor/templates.js:449-480`

- [ ] **Step 1: Update buildStepConfigFieldsHTML signature and pass context to field builders**

Replace the `buildStepConfigFieldsHTML` function (around line 449):

```javascript
/**
 * Build HTML for action-specific config fields in expanded step item.
 * @param {Array} configSchema - Array of field schema objects from the action registry
 * @param {Object} currentConfig - Current config values (from step.config)
 * @param {Object} context - Context for autocomplete (elementId, stepIndex)
 * @returns {string} HTML string for all config fields
 */
export function buildStepConfigFieldsHTML(configSchema, currentConfig = {}, context = {}) {
  if (!configSchema || configSchema.length === 0) return ""

  return `<div data-step-config-fields class="space-y-2">${
    configSchema.map(field => {
      const value = currentConfig[field.key] ?? field.default ?? ""
      const isVisible = shouldFieldBeVisible(field, currentConfig)
      const hiddenClass = isVisible ? "" : " hidden"
      const requiredMark = field.required ? ' <span class="text-red-500">*</span>' : ""

      let inputHTML
      switch (field.type) {
        case "text":      inputHTML = buildConfigTextField(field, value, context); break
        case "textarea":  inputHTML = buildConfigTextareaField(field, value, context); break
        case "number":    inputHTML = buildConfigNumberField(field, value); break
        case "select":    inputHTML = buildConfigSelectField(field, value); break
        case "key_value_list": inputHTML = buildConfigKeyValueList(field, value); break
        default:          inputHTML = buildConfigTextField(field, value, context)
      }

      return `
        <div class="step-config-field${hiddenClass}"
             data-config-field="${escapeHtml(field.key)}"
             ${field.visibleWhen ? `data-visible-when='${escapeHtml(JSON.stringify(field.visibleWhen))}'` : ""}>
          <label class="block text-[10px] font-medium text-slate-500 mb-0.5">
            ${escapeHtml(field.label)}${requiredMark}
          </label>
          ${inputHTML}
        </div>`
    }).join("")
  }</div>`
}
```

- [ ] **Step 2: Verify changes**

Run: `grep -n "context = {}\|context)" app/javascript/controllers/property_editor/templates.js | head -10`

Expected: Lines showing context parameter in function signatures

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/property_editor/templates.js
git commit -m "feat: pass context through buildStepConfigFieldsHTML"
```

---

### Task 9: Update StepManager to Pass Context

**Files:**
- Modify: `app/javascript/controllers/property_editor/step_manager.js:1064-1078`

- [ ] **Step 1: Update buildStepConfigHTML to accept and pass context**

Replace the `buildStepConfigHTML` method (around line 1064):

```javascript
  /**
   * Build config field HTML for a specific action.
   * Reads configSchema from registry and renders fields with current values.
   * @param {string} actionValue - Action identifier
   * @param {Object} currentConfig - Current config values
   * @param {string} subOption - Sub-option path if applicable
   * @param {Object} context - Context for autocomplete (elementId, stepIndex)
   */
  buildStepConfigHTML(actionValue, currentConfig = {}, subOption = "", context = {}) {
    const actionEntry = getActionConfig(actionValue)
    if (!actionEntry) return ""

    let configSchema
    if (actionEntry.configSchemaBySubOption && subOption) {
      configSchema = actionEntry.configSchemaBySubOption[subOption] || []
    } else {
      configSchema = actionEntry.configSchema || []
    }

    if (configSchema.length === 0) return ""

    return buildStepConfigFieldsHTML(configSchema, currentConfig, context)
  }
```

- [ ] **Step 2: Update buildStepItemHTML to pass context when calling buildStepConfigHTML**

Find the line calling `buildStepConfigHTML` (around line 1032) and update it:

```javascript
    // Build config fields HTML for the expanded step item
    const context = {
      elementId: this.controller.currentElement?.id || "",
      stepIndex: index
    }
    const configFieldsHTML = this.buildStepConfigHTML(action, currentConfig, suboption, context)
```

- [ ] **Step 3: Verify changes**

Run: `grep -n "context = {\|elementId:\|stepIndex:" app/javascript/controllers/property_editor/step_manager.js | head -10`

Expected: Lines showing context object creation and passing

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/property_editor/step_manager.js
git commit -m "feat: pass context (elementId, stepIndex) to config field builders"
```

---

### Task 10: Manual Integration Test

**Files:**
- None (manual verification)

- [ ] **Step 1: Start the development server**

Run: `bin/rails server`

Expected: Server starts on port 3000

- [ ] **Step 2: Open a flowchart in the editor**

1. Navigate to a customer's flowcharts list
2. Open an existing flowchart with a Process element, or create one
3. Double-click the Process element to open the property editor
4. Add a step (e.g., "Find Model")
5. Expand the step to see config fields

- [ ] **Step 3: Test autocomplete appearance**

1. Click in the "Find Value" field
2. Start typing a letter (e.g., "p")
3. Verify dropdown appears with filtered variables

Expected: Dropdown shows variables containing "p" (e.g., "params")

- [ ] **Step 4: Test keyboard navigation**

1. Press Arrow Down to move selection
2. Press Arrow Up to move selection back
3. Verify highlight moves with key presses

Expected: Blue highlight moves between options

- [ ] **Step 5: Test selection**

1. Navigate to a variable using arrow keys
2. Press Enter (or Tab) to select

Expected: Variable name inserted at cursor, dropdown closes

- [ ] **Step 6: Test escape closes dropdown**

1. Trigger dropdown by typing
2. Press Escape

Expected: Dropdown closes without inserting anything

- [ ] **Step 7: Test upstream variables appear**

1. Create a flowchart with two Process elements connected in sequence
2. Configure first element with a step that has outputs (e.g., "Find Model" with resultVar)
3. In the second element, add a step and expand it
4. Type in a config field

Expected: Dropdown shows group "From '[First Element Label]'" with the output variable

- [ ] **Step 8: Commit verification notes**

No code changes needed - this is verification only.

---

### Task 11: Add Debouncing for Performance

**Files:**
- Modify: `app/javascript/controllers/context_autocomplete_controller.js`

- [ ] **Step 1: Add debounce timer property in connect()**

In `connect()`, add after the other property initializations:

```javascript
    this._debounceTimer = null
```

- [ ] **Step 2: Update _onInput to debounce rapid typing**

Replace the `_onInput` method:

```javascript
  async _onInput(event) {
    if (this._debounceTimer) {
      clearTimeout(this._debounceTimer)
    }

    this._debounceTimer = setTimeout(async () => {
      if (!this._canvas) {
        this._resolveCanvas()
        if (!this._canvas) {
          this._destroyDropdown()
          return
        }
      }

      const term = this._getWordAtCursor()
      const result = await getAvailableVariables(this._canvas, this.elementIdValue, this.stepIndexValue)
      const filtered = filterVariables(result, term)

      this._filteredGroups = filtered.groups
      this._allOptions = this._flattenOptions(filtered.groups)
      this._selectedIndex = 0

      if (this._allOptions.length > 0) {
        this._renderDropdown()
      } else {
        this._destroyDropdown()
      }
    }, 100)
  }
```

- [ ] **Step 3: Clean up timer in disconnect()**

In `disconnect()`, add before `this._destroyDropdown()`:

```javascript
    if (this._debounceTimer) {
      clearTimeout(this._debounceTimer)
    }
```

- [ ] **Step 4: Verify changes**

Run: `grep -n "_debounceTimer\|clearTimeout" app/javascript/controllers/context_autocomplete_controller.js`

Expected: Lines showing debounce timer handling

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/context_autocomplete_controller.js
git commit -m "perf: add debouncing to autocomplete input handler"
```

---

## Summary

After completing all tasks:
- `ContextVariableProvider` collects variables from implicit keys, upstream elements, and prior steps
- `context-autocomplete` Stimulus controller shows dropdown on typing with keyboard navigation
- Config text/textarea fields in step items have autocomplete wired via data attributes
- Variables are inserted at cursor position when selected

Total new lines of code: ~350 (provider ~120, controller ~180, template changes ~50)
