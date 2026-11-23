# Flowchart Editor Bug Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 4 bugs and 2 issues in the flowchart editor's property editor panel.

**Architecture:** All changes are in JavaScript files under `app/javascript/`. Each fix is isolated — no fix depends on another. The changes touch the property editor controller, form builder, step manager, branch manager, and element schema constants.

**Tech Stack:** StimulusJS, vanilla JavaScript, TailwindCSS

**Spec:** `docs/superpowers/specs/2026-03-26-flowchart-editor-bugfixes-design.md`

---

## File Map

| File | Changes | Bugs/Issues |
|------|---------|-------------|
| `app/javascript/controllers/property_editor_controller.js` | Add `handleDelayTypeChange`, add `stepChanged` listener, refactor `_collectFormData` for label, fix style condition | 1, 2, 4, 6 |
| `app/javascript/controllers/property_editor/form_builder.js` | Wire `delayType` action, populate label from element | 1, 4 |
| `app/javascript/controllers/property_editor/step_manager.js` | Rework `STEP_PRESETS` to single-step | 3 |
| `app/javascript/controllers/property_editor/branch_manager.js` | Guard duplicate branch creation | 5 |
| `app/javascript/flowchart/constants/schemas.js` | Add `label` field to all element schemas | 4 |

---

### Task 1: Fix Timer delayType conditional field visibility

**Bug 1:** Changing the Timer element's "Delay Type" select doesn't show/hide dependent fields (duration, durationUnit, waitCondition).

**Files:**
- Modify: `app/javascript/controllers/property_editor/form_builder.js:205-213`
- Modify: `app/javascript/controllers/property_editor_controller.js` (add handler after `handleResponseTypeChange`)

- [ ] **Step 1: Add delayType to extraAction mapping in form_builder.js**

In `app/javascript/controllers/property_editor/form_builder.js`, find the block at ~line 205:

```js
    } else if (fieldName === "responseType") {
      extraAction = ` data-action="change->property-editor#handleResponseTypeChange"`
    }
```

Add after it:

```js
    } else if (fieldName === "delayType") {
      extraAction = ` data-action="change->property-editor#handleDelayTypeChange"`
    }
```

- [ ] **Step 2: Add handleDelayTypeChange handler in property_editor_controller.js**

In `app/javascript/controllers/property_editor_controller.js`, find `handleResponseTypeChange(event)` (ends ~line 596). Add the following handler after it:

```js
  // ===================
  // Delay Type Actions
  // ===================

  /**
   * Handle delay type selection change for timer elements.
   * Shows/hides fields based on the selected delay type.
   * @param {Event} event - Change event from delayType select
   */
  handleDelayTypeChange(event) {
    const selectedValue = event.target.value
    if (!this.hasFormFieldsTarget) return

    // Find all elements with data-visible-when attribute
    const conditionalFields = this.formFieldsTarget.querySelectorAll("[data-visible-when]")
    conditionalFields.forEach(field => {
      const visibleWhen = field.dataset.visibleWhen
      if (visibleWhen !== "delayType") return

      const visibleValues = (field.dataset.visibleValues || "").split(",")
      if (visibleValues.includes(selectedValue)) {
        field.classList.remove("hidden")
      } else {
        field.classList.add("hidden")
      }
    })

    this._syncChangesToCanvas()
  }
```

- [ ] **Step 3: Verify manually**

1. Open the flowchart editor
2. Add a Timer element to the canvas
3. Double-click to open property editor
4. Confirm "Delay Type" defaults to "Fixed Duration" with duration/unit fields visible
5. Change to "Until Condition" — duration/unit fields should hide, waitCondition should appear
6. Change back to "Fixed Duration" — fields should toggle back

---

### Task 2: Add missing "stepChanged" event listener

**Bug 2:** Config field changes in expanded steps dispatch `"stepChanged"` but nobody listens for it, so canvas doesn't sync.

**Files:**
- Modify: `app/javascript/controllers/property_editor_controller.js:762-813`

- [ ] **Step 1: Add stepChanged listener in _setupFormChangeListeners**

In `app/javascript/controllers/property_editor_controller.js`, find the `_setupFormChangeListeners()` method. After line:

```js
    this.formTarget.addEventListener("stepReordered", this._boundSyncChanges)
```

Add:

```js
    this.formTarget.addEventListener("stepChanged", this._boundSyncChanges)
```

- [ ] **Step 2: Add corresponding removeEventListener in _removeFormChangeListeners**

In the same file, find `_removeFormChangeListeners()`. After line:

```js
    this.formTarget.removeEventListener("stepReordered", this._boundSyncChanges)
```

Add:

```js
    this.formTarget.removeEventListener("stepChanged", this._boundSyncChanges)
```

- [ ] **Step 3: Verify manually**

1. Open flowchart editor, add a Process element
2. Double-click to open property editor
3. Add a step (e.g., "Find Model")
4. Expand the step, change a config field (e.g., find strategy dropdown)
5. Confirm the canvas element label updates in real-time
6. Confirm the save indicator (amber dot) appears on the toolbar

---

### Task 3: Rework step presets to single-step

**Bug 3:** STEP_PRESETS define multi-step arrays, violating the 1-step-per-process design.

**Files:**
- Modify: `app/javascript/controllers/property_editor/step_manager.js:19-51`

- [ ] **Step 1: Replace STEP_PRESETS with single-step versions**

In `app/javascript/controllers/property_editor/step_manager.js`, replace the entire `STEP_PRESETS` constant (lines 19-51) with:

```js
// Step presets for common patterns (one step per process element)
const STEP_PRESETS = {
  crud_create: {
    label: "CRUD Create",
    steps: [
      { action: "save_model", selectionLabels: ["Save Model"], config: { saveStrategy: "saveAll" } }
    ]
  },
  crud_read: {
    label: "CRUD Read",
    steps: [
      { action: "find_model", selectionLabels: ["Find Model"], config: { findStrategy: "find" } }
    ]
  },
  crud_update: {
    label: "CRUD Update",
    steps: [
      { action: "save_model", selectionLabels: ["Save Model"], config: { saveStrategy: "saveAll" } }
    ]
  },
  crud_delete: {
    label: "CRUD Delete",
    steps: [
      { action: "destroy_model", selectionLabels: ["Destroy Model"], config: { destroyStrategy: "destroy" } }
    ]
  }
}
```

- [ ] **Step 2: Verify manually**

1. Open flowchart editor, add a Process element
2. Double-click to open property editor
3. Select "CRUD Create" preset — confirm only 1 step ("Save Model") appears
4. Select "CRUD Read" preset — confirm only 1 step ("Find Model") appears
5. Select "CRUD Update" preset — confirm only 1 step ("Save Model") appears
6. Select "CRUD Delete" preset — confirm only 1 step ("Destroy Model") appears
7. Confirm the "Add Step" button is disabled after each preset
8. Remove the step — confirm "Add Step" re-enables

---

### Task 4: Add Label field to all element schemas

**Bug 4:** No way to edit element labels for Start, End, Loop, Fork, Join, Error Handler, Timer from the property editor.

**Files:**
- Modify: `app/javascript/flowchart/constants/schemas.js:152-441`
- Modify: `app/javascript/controllers/property_editor/form_builder.js:18-33, 97-124`
- Modify: `app/javascript/controllers/property_editor_controller.js:645-722, 836-860`

- [ ] **Step 1: Add label field definition to COMMON_PROPERTIES in schemas.js**

In `app/javascript/flowchart/constants/schemas.js`, add a `label` entry to the `COMMON_PROPERTIES` object (after line 13, before `inputs`):

```js
const COMMON_PROPERTIES = {
  label: {
    type: "text",
    label: "Label",
    placeholder: "Element name..."
  },
  inputs: {
```

- [ ] **Step 2: Add label as the first field in every element schema**

In the same file, add `label: COMMON_PROPERTIES.label,` as the **first** property in each element schema. Make the following edits:

In `start` schema (after `start: {`):
```js
  start: {
    label: COMMON_PROPERTIES.label,
    triggerType: {
```

In `end` schema (after `end: {`):
```js
  end: {
    label: COMMON_PROPERTIES.label,
    inputs: COMMON_PROPERTIES.inputs,
```

In `process` schema (after `process: {`):
```js
  process: {
    label: COMMON_PROPERTIES.label,
    inputs: COMMON_PROPERTIES.inputs,
```

In `decision` schema (after `decision: {`):
```js
  decision: {
    label: COMMON_PROPERTIES.label,
    inputs: COMMON_PROPERTIES.inputs,
```

In `loop` schema (after `loop: {`):
```js
  loop: {
    label: COMMON_PROPERTIES.label,
    inputs: COMMON_PROPERTIES.inputs,
```

In `subflow` schema (after `subflow: {`):
```js
  subflow: {
    label: COMMON_PROPERTIES.label,
    inputs: COMMON_PROPERTIES.inputs,
```

In `fork` schema (after `fork: {`):
```js
  fork: {
    label: COMMON_PROPERTIES.label,
    inputs: COMMON_PROPERTIES.inputs,
```

In `join` schema (after `join: {`):
```js
  join: {
    label: COMMON_PROPERTIES.label,
    inputs: COMMON_PROPERTIES.inputs,
```

In `error_handler` schema (after `error_handler: {`):
```js
  error_handler: {
    label: COMMON_PROPERTIES.label,
    inputs: COMMON_PROPERTIES.inputs,
```

In `timer` schema (after `timer: {`):
```js
  timer: {
    label: COMMON_PROPERTIES.label,
    inputs: COMMON_PROPERTIES.inputs,
```

- [ ] **Step 3: Populate label field from element.label in form_builder.js**

The label lives on `element.label`, not in `element.properties`. The form builder needs to inject it before building the form.

In `app/javascript/controllers/property_editor/form_builder.js`, in the `_buildFormFields` method, after `let formHTML = ""` (line 110), add logic to set the label value from the element before iterating the schema:

Replace lines 110-124:
```js
    let formHTML = ""

    // Build fields in order defined by schema
    Object.entries(schema).forEach(([fieldName, fieldSchema]) => {
      const currentValue = properties[fieldName] ?? fieldSchema.default ?? ""
      // Handle dynamic options for select fields
      let resolvedFieldSchema = fieldSchema
      if (fieldSchema.dynamicOptions) {
        resolvedFieldSchema = this.resolveDynamicOptions(fieldSchema, fieldName)
      }
      formHTML += this._buildFieldHTML(fieldName, resolvedFieldSchema, currentValue)
    })

    this.controller.formFieldsTarget.innerHTML = formHTML
```

With:
```js
    let formHTML = ""

    // Build fields in order defined by schema
    Object.entries(schema).forEach(([fieldName, fieldSchema]) => {
      let currentValue
      if (fieldName === "label") {
        // Label lives on element itself, not in properties
        currentValue = this.controller.currentElement.label ?? fieldSchema.default ?? ""
      } else {
        currentValue = properties[fieldName] ?? fieldSchema.default ?? ""
      }
      // Handle dynamic options for select fields
      let resolvedFieldSchema = fieldSchema
      if (fieldSchema.dynamicOptions) {
        resolvedFieldSchema = this.resolveDynamicOptions(fieldSchema, fieldName)
      }
      formHTML += this._buildFieldHTML(fieldName, resolvedFieldSchema, currentValue)
    })

    this.controller.formFieldsTarget.innerHTML = formHTML
```

- [ ] **Step 4: Read label from form data in _collectFormData in property_editor_controller.js**

In `app/javascript/controllers/property_editor_controller.js`, in `_collectFormData()`, after collecting regular form fields (after line 657 `}`), add:

Find:
```js
    // Collect style data
    const styleFill = formData.get("style_fill")
```

Add before it:
```js
    // Extract label field (lives on element, not in properties)
    const formLabel = newProperties.label
    delete newProperties.label

```

Then modify the method to return both label and properties. But wait — `_collectFormData` returns properties only, and the label is used by `_deriveLabelFromProperties` and `_performSync`. The cleanest approach is to store the explicit label on a controller property.

Actually, a simpler approach: keep the label in `newProperties` during collection, then extract it in `_performSync` and `save` before passing to the canvas. Let me revise.

In `_performSync()`, find lines 844-853:
```js
    const newProperties = this._collectFormData()
    const newLabel = this._deriveLabelFromProperties(newProperties)

    // Update element properties in canvas (visual update only, no database save)
    if (this.canvas.updateElementProperties) {
      this.canvas.updateElementProperties(this.currentElement.id, newLabel, newProperties)
    } else {
      this._updateElementFallback(newProperties, newLabel)
    }
```

Replace with:
```js
    const newProperties = this._collectFormData()

    // Extract explicit label (if user typed one) before deriving
    const explicitLabel = newProperties.label
    delete newProperties.label

    const newLabel = this._deriveLabelFromProperties(newProperties, explicitLabel)

    // Update element properties in canvas (visual update only, no database save)
    if (this.canvas.updateElementProperties) {
      this.canvas.updateElementProperties(this.currentElement.id, newLabel, newProperties)
    } else {
      this._updateElementFallback(newProperties, newLabel)
    }
```

Do the same in `save()`. Find lines 200-205:
```js
    const newProperties = this._collectFormData()
    const newLabel = this._deriveLabelFromProperties(newProperties)

    // Update element properties in canvas
    if (this.canvas.updateElementProperties) {
      this.canvas.updateElementProperties(this.currentElement.id, newLabel, newProperties)
```

Replace with:
```js
    const newProperties = this._collectFormData()

    // Extract explicit label before deriving
    const explicitLabel = newProperties.label
    delete newProperties.label

    const newLabel = this._deriveLabelFromProperties(newProperties, explicitLabel)

    // Update element properties in canvas
    if (this.canvas.updateElementProperties) {
      this.canvas.updateElementProperties(this.currentElement.id, newLabel, newProperties)
```

- [ ] **Step 5: Update _deriveLabelFromProperties to respect explicit label**

In `app/javascript/controllers/property_editor_controller.js`, find `_deriveLabelFromProperties` (~line 714):

```js
  _deriveLabelFromProperties(properties) {
    if (this.currentElement?.type === "decision" && properties.condition?.expression) {
      return properties.condition.expression
    }
    if (this.currentElement?.type === "process" && properties.steps?.length > 0) {
      return this._deriveLabelFromSteps(properties.steps)
    }
    return undefined
  }
```

Replace with:
```js
  _deriveLabelFromProperties(properties, explicitLabel) {
    // If user explicitly typed a label, use it
    if (explicitLabel !== undefined && explicitLabel !== "") {
      return explicitLabel
    }

    // Auto-derive for process/decision when label is empty
    if (this.currentElement?.type === "decision" && properties.condition?.expression) {
      return properties.condition.expression
    }
    if (this.currentElement?.type === "process" && properties.steps?.length > 0) {
      return this._deriveLabelFromSteps(properties.steps)
    }
    return undefined
  }
```

- [ ] **Step 6: Verify manually**

1. Open flowchart editor
2. Add a Start element, double-click to open properties
3. Confirm "Label" field is the first field, pre-populated with "Start"
4. Change label to "Begin Here" — confirm canvas updates in real-time
5. Save and reopen — confirm "Begin Here" persists
6. Repeat for End, Loop, Fork, Join, Error Handler, Timer
7. For Process: type an explicit label — confirm it overrides the auto-derived step label
8. For Process: clear the label field — confirm it falls back to auto-derived from steps
9. For Decision: type an explicit label — confirm it overrides the condition expression
10. For Decision: clear the label — confirm it falls back to condition expression

---

### Task 5: Guard against duplicate branch element creation

**Issue 5:** Reopening a Decision element's property editor when branches haven't been persisted can create duplicate branch elements on canvas.

**Files:**
- Modify: `app/javascript/controllers/property_editor/branch_manager.js:356-369`

- [ ] **Step 1: Add guard in buildBranchesFieldHTML**

In `app/javascript/controllers/property_editor/branch_manager.js`, find the default branch creation block (lines 358-369):

```js
    // Add default 'Yes' branch if no branches exist
    if (branches.length === 0) {
      branches = [{ value: "yes", label: "", description: "" }]
      // Create the branch element on canvas for the default branch
      if (this.controller.canvas && this.controller.currentElement) {
        const branchElement = this._createBranchElement("Yes", { label: "Yes" })
        if (branchElement) {
          branches[0].elementId = branchElement.id
        }
      }
    }
```

Replace with:

```js
    // Add default 'Yes' branch if no branches exist
    if (branches.length === 0) {
      branches = [{ value: "yes", label: "", description: "" }]
      // Check if a branch element already exists on the canvas (from a previous open)
      if (this.controller.canvas && this.controller.currentElement) {
        const existingConnection = this.controller.canvas.connections.find(
          c => c.from === this.controller.currentElement.id
        )
        const existingBranchElement = existingConnection
          ? this.controller.canvas.elements.find(el => el.id === existingConnection.to)
          : null

        if (existingBranchElement) {
          // Reuse existing branch element instead of creating a duplicate
          branches[0].elementId = existingBranchElement.id
        } else {
          // Create a new branch element on canvas for the default branch
          const branchElement = this._createBranchElement("Yes", { label: "Yes" })
          if (branchElement) {
            branches[0].elementId = branchElement.id
          }
        }
      }
    }
```

- [ ] **Step 2: Verify manually**

1. Open flowchart editor
2. Add a Decision element
3. Double-click to open properties — confirm 1 "Yes" branch appears with 1 connected Process element on canvas
4. Close the property editor (without saving)
5. Double-click the Decision again — confirm NO additional branch element is created on canvas
6. Count the Process elements connected to the Decision — should still be exactly 1

---

### Task 6: Fix style saves with either fill or stroke

**Issue 6:** Style only saves when BOTH fill AND stroke are set; partial values result in `null`.

**Files:**
- Modify: `app/javascript/controllers/property_editor_controller.js:660-666`

- [ ] **Step 1: Fix the style collection condition**

In `app/javascript/controllers/property_editor_controller.js`, find the style collection block (~line 660):

```js
    // Collect style data
    const styleFill = formData.get("style_fill")
    const styleStroke = formData.get("style_stroke")
    if (styleFill && styleStroke) {
      newProperties.style = { fill: styleFill, stroke: styleStroke }
    } else {
      newProperties.style = null
    }
```

Replace with:

```js
    // Collect style data
    const styleFill = formData.get("style_fill")
    const styleStroke = formData.get("style_stroke")
    if (styleFill || styleStroke) {
      newProperties.style = { fill: styleFill || "", stroke: styleStroke || "" }
    } else {
      newProperties.style = null
    }
```

- [ ] **Step 2: Verify manually**

1. Open flowchart editor, add a Process element
2. Double-click to open properties
3. Scroll to Style section, select a color preset (e.g., Blue)
4. Save — confirm the element on canvas has the blue style applied
5. Reopen, select "Default" — confirm the style clears (element returns to default appearance)
6. Confirm no console errors during any style toggle
