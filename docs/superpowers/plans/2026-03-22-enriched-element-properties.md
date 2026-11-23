# Enriched Element Properties — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enrich the property schemas for Process (error handling), Decision (context-aware operands), and Loop (structured condition) flowchart elements.

**Architecture:** Extend `schemas.js` with new field types, modify `BranchManager` to build context-aware operand dropdowns with optgroup separators, add error handling UI rendering in `FormBuilder`, and update `ActivityGenerator` with error handling code generation. The Loop element reuses the Decision condition builder by changing its schema type from `text` to `condition`.

**Tech Stack:** StimulusJS, TailwindCSS, Rails 8.1, Trailblazer Activity, RSpec

**Spec:** `docs/superpowers/specs/2026-03-22-flowchart-element-enrichment-design.md` (Part 1)

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `app/javascript/flowchart/constants/schemas.js` | Modify | Add `errorHandling` to process schema; change loop condition type to `condition` |
| `app/javascript/controllers/property_editor/branch_manager.js` | Modify | Expand left/right operand options with entity attributes, parent outputs, optgroup separators, custom value toggle |
| `app/javascript/controllers/property_editor/form_builder.js` | Modify | Add `error_handling` field type dispatch |
| `app/javascript/controllers/property_editor/templates.js` | Modify | Add `buildErrorHandlingFieldTemplate` function |
| `app/javascript/controllers/property_editor_controller.js` | Modify | Add error handling mode toggle, errorHandling collection, custom value delegation, legacy condition conversion |
| `app/services/activity_generator.rb` | Modify | Add error handling code generation; add loop condition code generation |
| `spec/services/activity_generator_spec.rb` | Modify | Tests for error handling and loop condition code generation |

---

### Task 1: Add Error Handling Schema and Template

**Files:**
- Modify: `app/javascript/flowchart/constants/schemas.js`
- Modify: `app/javascript/controllers/property_editor/templates.js`

- [ ] **Step 1: Add `errorHandling` to process element schema**

In `app/javascript/flowchart/constants/schemas.js`, modify the `process` entry in `ELEMENT_SCHEMAS`. Insert `errorHandling` between `steps` and `outputs`:

```javascript
// Replace the existing process schema (around line 238-250)
process: {
  inputs: COMMON_PROPERTIES.inputs,
  steps: {
    type: "steps",
    label: "Steps",
    actionOptions: STEP_ACTIONS
  },
  errorHandling: {
    type: "error_handling",
    label: "Error Handling"
  },
  outputs: COMMON_PROPERTIES.outputs,
  description: {
    ...COMMON_PROPERTIES.description,
    placeholder: "Describe what this process does..."
  }
},
```

- [ ] **Step 2: Add `buildErrorHandlingFieldTemplate` to templates.js**

Add this export function to `app/javascript/controllers/property_editor/templates.js` at the end of the file (before any closing brace):

```javascript
// ===================
// Error Handling Templates
// ===================

/**
 * Build the error handling field HTML for Process elements.
 * @param {string} fieldName - The property field name ("errorHandling")
 * @param {Object} currentValue - Current error handling config { mode, errorOutputField }
 * @returns {string} HTML string
 */
export function buildErrorHandlingFieldTemplate(fieldName, currentValue) {
  const config = currentValue || {}
  const mode = config.mode || "halt"
  const errorOutputField = config.errorOutputField || "ctx.error"
  const showErrorField = mode === "route_to_error_end" ? "" : "hidden"

  return `
    <div class="mb-4">
      <label class="block text-sm font-medium text-gray-700 mb-2">Error Handling</label>
      <div class="p-3 bg-red-50 rounded-lg border border-red-200 space-y-3">
        <div>
          <label class="block text-[10px] text-gray-500 mb-1">On Step Failure</label>
          <select data-error-handling-mode
                  name="${fieldName}[mode]"
                  data-action="change->property-editor#handleErrorHandlingModeChange"
                  class="w-full px-2 py-1.5 text-xs bg-white border border-gray-300 rounded shadow-sm focus:outline-none focus:ring-1 focus:ring-red-500 focus:border-red-500">
            <option value="halt" ${mode === "halt" ? "selected" : ""}>Halt on Failure</option>
            <option value="route_to_error_end" ${mode === "route_to_error_end" ? "selected" : ""}>Route to Error End</option>
          </select>
        </div>
        <div class="${showErrorField}" data-error-output-field-container>
          <label class="block text-[10px] text-gray-500 mb-1">Error Output Field</label>
          <input type="text"
                 data-error-output-field
                 name="${fieldName}[errorOutputField]"
                 value="${escapeHtml(errorOutputField)}"
                 placeholder="ctx.error"
                 class="w-full px-2 py-1.5 text-xs bg-white border border-gray-300 rounded shadow-sm focus:outline-none focus:ring-1 focus:ring-red-500 focus:border-red-500">
          <p class="mt-1 text-[10px] text-gray-400">The ctx field where error details will be written</p>
        </div>
      </div>
    </div>
  `
}
```

- [ ] **Step 3: Verify files saved correctly**

Run: `head -5 app/javascript/controllers/property_editor/templates.js && grep -c "buildErrorHandlingFieldTemplate" app/javascript/controllers/property_editor/templates.js`
Expected: Shows file header and count of 1+ matches

- [ ] **Step 4: Commit**

```bash
git add app/javascript/flowchart/constants/schemas.js app/javascript/controllers/property_editor/templates.js
git commit -m "feat: add error handling schema and template for Process elements"
```

---

### Task 2: Wire Error Handling into FormBuilder and PropertyEditor

**Files:**
- Modify: `app/javascript/controllers/property_editor/form_builder.js`
- Modify: `app/javascript/controllers/property_editor_controller.js`

- [ ] **Step 1: Add error_handling dispatch to FormBuilder._buildFieldHTML**

In `app/javascript/controllers/property_editor/form_builder.js`, find the `_buildFieldHTML` method (around line 125). Add a new case **after** the `outputs` handler (around line 159) and **before** the `isRequired` line:

```javascript
    // Handle error_handling field type
    if (fieldSchema.type === "error_handling") {
      const { buildErrorHandlingFieldTemplate } = await import("controllers/property_editor/templates")
      return buildErrorHandlingFieldTemplate(fieldName, currentValue)
    }
```

**Note:** Since this file doesn't use dynamic imports, use a static import instead. Add to the top of `form_builder.js` (after the existing import line):

```javascript
import { buildErrorHandlingFieldTemplate } from "controllers/property_editor/templates"
```

Then in `_buildFieldHTML`, add (after the outputs handler, before `const isRequired` line):

```javascript
    // Handle error_handling field type
    if (fieldSchema.type === "error_handling") {
      return buildErrorHandlingFieldTemplate(fieldName, currentValue)
    }
```

- [ ] **Step 2: Add handleErrorHandlingModeChange and collectErrorHandling to PropertyEditorController**

In `app/javascript/controllers/property_editor_controller.js`, find where other `handle*Change` methods are defined (e.g., `handleConditionLeftOperandChange`). Add this method:

```javascript
  handleErrorHandlingModeChange(event) {
    const mode = event.target.value
    const container = event.target.closest("[data-error-handling-mode]")?.parentElement?.parentElement
    if (!container) return

    const errorFieldContainer = container.querySelector("[data-error-output-field-container]")
    if (errorFieldContainer) {
      errorFieldContainer.classList.toggle("hidden", mode !== "route_to_error_end")
    }

    this._syncChangesToCanvas()
  }
```

Then, in `_collectFormData()` (around line 326), add `"errorHandling["` to the `skipPrefixes` array:

```javascript
    const skipPrefixes = ["steps[", "inputs[", "outputs[", "branches[", "condition[", "varMappings[", "signalWiring[", "dataMappings[", "errorHandling["]
```

And after the existing outputs collection block (around line 358), add:

```javascript
    // Collect error handling data (for Process elements)
    const errorHandling = this._collectErrorHandling()
    if (errorHandling !== null) newProperties.errorHandling = errorHandling
```

Then add this private method to the controller:

```javascript
  _collectErrorHandling() {
    if (!this.hasFormFieldsTarget) return null

    const modeSelect = this.formFieldsTarget.querySelector("[data-error-handling-mode]")
    if (!modeSelect) return null

    const mode = modeSelect.value || "halt"
    const errorOutputField = this.formFieldsTarget.querySelector("[data-error-output-field]")?.value || "ctx.error"

    return { mode, errorOutputField }
  }
```

- [ ] **Step 3: Verify no syntax errors**

Run: `node -c app/javascript/controllers/property_editor/form_builder.js && node -c app/javascript/controllers/property_editor_controller.js`
Expected: Both files pass syntax check (or use `npx acorn --ecma2020 --module` if `node -c` doesn't work with imports)

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/property_editor/form_builder.js app/javascript/controllers/property_editor_controller.js
git commit -m "feat: wire error handling field into FormBuilder and PropertyEditor"
```

---

### Task 3: Error Handling Code Generation in ActivityGenerator

**Files:**
- Modify: `app/services/activity_generator.rb`
- Modify: `spec/services/activity_generator_spec.rb`

- [ ] **Step 1: Write failing tests for error handling code generation**

Add to `spec/services/activity_generator_spec.rb`. Find the main describe block and add a new context:

```ruby
describe "error handling code generation" do
  let(:customer) { create(:customer) }
  let(:entity) { create(:entity, customer: customer) }

  context "with halt mode (default)" do
    let(:flowchart) do
      config = {
        "elements" => [
          { "id" => "el_start", "type" => "start", "x" => 400, "y" => 100, "width" => 100, "height" => 45,
            "label" => "Start", "properties" => { "inputs" => [{ "value" => "all params" }], "outputs" => [{ "value" => "ctx" }], "description" => "" } },
          { "id" => "el_process", "type" => "process", "x" => 400, "y" => 200, "width" => 100, "height" => 45,
            "label" => "Create Record", "properties" => {
              "inputs" => [], "outputs" => [{ "value" => "ctx" }], "steps" => [{ "action" => "new_model" }],
              "errorHandling" => { "mode" => "halt" }, "description" => ""
            } }
        ],
        "connections" => [{ "id" => "conn_1", "from" => "el_start", "to" => "el_process", "fromPosition" => "bottom", "toPosition" => "top" }],
        "metadata" => { "canvas" => { "width" => 2000, "height" => 1500 } }
      }
      create(:flowchart, name: "Halt Test", customer: customer, entity: entity, configuration: config.to_json)
    end

    it "generates standard code without error handler" do
      code = flowchart.activity
      expect(code).to include("def create_record")
      expect(code).not_to include("handle_error")
    end
  end

  context "with route_to_error_end mode" do
    let(:flowchart) do
      config = {
        "elements" => [
          { "id" => "el_start", "type" => "start", "x" => 400, "y" => 100, "width" => 100, "height" => 45,
            "label" => "Start", "properties" => { "inputs" => [{ "value" => "all params" }], "outputs" => [{ "value" => "ctx" }], "description" => "" } },
          { "id" => "el_process", "type" => "process", "x" => 400, "y" => 200, "width" => 100, "height" => 45,
            "label" => "Create Record", "properties" => {
              "inputs" => [], "outputs" => [{ "value" => "ctx" }], "steps" => [{ "action" => "new_model" }],
              "errorHandling" => { "mode" => "route_to_error_end", "errorOutputField" => "ctx.error_details" }, "description" => ""
            } }
        ],
        "connections" => [{ "id" => "conn_1", "from" => "el_start", "to" => "el_process", "fromPosition" => "bottom", "toPosition" => "top" }],
        "metadata" => { "canvas" => { "width" => 2000, "height" => 1500 } }
      }
      create(:flowchart, name: "Error Route Test", customer: customer, entity: entity, configuration: config.to_json)
    end

    it "generates a fail handler step" do
      code = flowchart.activity
      expect(code).to include("fail :handle_error_in_create_record")
    end

    it "writes error to the configured output field" do
      code = flowchart.activity
      expect(code).to include("ctx[:error_details]")
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/activity_generator_spec.rb -t "error handling" 2>&1 | tail -10`
Expected: FAIL — no `handle_error` method exists yet

- [ ] **Step 3: Implement error handling code generation**

In `app/services/activity_generator.rb`, make two changes:

**Change 1:** In `step_declarations` method (around line 267), modify the step_type logic to also emit a fail declaration when `route_to_error_end` is configured:

Find the line (around 274):
```ruby
step_type = s[:element]["type"] == "decision" ? "pass" : "step"
"#{step_type} :#{s[:method_name]}"
```

Replace with:
```ruby
step_type = s[:element]["type"] == "decision" ? "pass" : "step"
declaration = "#{step_type} :#{s[:method_name]}"

# Add fail handler for route_to_error_end error handling
error_handling = s[:element].dig("properties", "errorHandling")
if error_handling && error_handling["mode"] == "route_to_error_end"
  declaration += "\nfail :handle_error_in_#{s[:method_name]}"
end

declaration
```

**Change 2:** In `step_methods` method (around line 328), after `regular_steps.map { |s| build_method(s) }.join("\n\n")`, add error handler method generation:

Find:
```ruby
def step_methods(steps)
  return "" if steps.empty?

  # Filter out subprocess steps - they don't need method bodies
  regular_steps = steps.reject { |s| s[:subprocess] }
  regular_steps.map { |s| build_method(s) }.join("\n\n")
end
```

Replace with:
```ruby
def step_methods(steps)
  return "" if steps.empty?

  # Filter out subprocess steps - they don't need method bodies
  regular_steps = steps.reject { |s| s[:subprocess] }
  methods = regular_steps.map { |s| build_method(s) }

  # Add error handler methods for route_to_error_end elements
  error_handlers = regular_steps
    .select { |s| s[:element].dig("properties", "errorHandling", "mode") == "route_to_error_end" }
    .map { |s| build_error_handler_method(s) }

  (methods + error_handlers).join("\n\n")
end
```

**Change 3:** Add the `build_error_handler_method` private method (after `build_method`):

```ruby
def build_error_handler_method(step_info)
  method_name = step_info[:method_name]
  error_field = step_info[:element].dig("properties", "errorHandling", "errorOutputField") || "ctx.error"
  # Convert "ctx.error_details" -> ctx[:error_details]
  field_key = error_field.sub(/^ctx\./, "")

  <<~RUBY.chomp
    # Error handler for #{step_info[:element]['label']}
    def handle_error_in_#{method_name}(ctx, **)
      ctx[:#{field_key}] = ctx["contract.default"]&.errors&.full_messages || ["An error occurred"]
    end
  RUBY
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/activity_generator_spec.rb 2>&1 | tail -10`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/activity_generator.rb spec/services/activity_generator_spec.rb
git commit -m "feat: add error handling code generation for Process elements"
```

---

### Task 4: Context-Aware Operands for Decision Element

**Files:**
- Modify: `app/javascript/controllers/property_editor/branch_manager.js`

- [ ] **Step 1: Expand left operand options in `buildConditionFieldHTML`**

In `app/javascript/controllers/property_editor/branch_manager.js`, find the `buildConditionFieldHTML` method (around line 180). Replace the left operand options block (lines 190-194):

Find:
```javascript
    // Fixed options for Left Operand: 'signal' and 'ctx'
    const leftOperandOptions = [
      { value: "signal", label: "signal" },
      { value: "ctx", label: "ctx" }
    ]
    const leftOperandOptionsHTML = this._buildSelectOptionsWithValue(leftOperandOptions, "Select operand...", leftOperand)
```

Replace with:
```javascript
    // Context-aware options for Left Operand
    const leftOperandOptionsHTML = this._buildContextAwareLeftOperandOptions(leftOperand)
```

Then add a new private method `_buildContextAwareLeftOperandOptions` to the class:

```javascript
  /**
   * Build optgroup-separated options for left operand.
   * Sources: signals, common ctx fields, entity attributes, parent outputs.
   */
  _buildContextAwareLeftOperandOptions(selectedValue) {
    const entityAttributes = this.controller.canvas?.entityAttributes || []
    const parentOutputs = this._availableOutputOptions || []

    let html = `<option value="">Select operand...</option>`

    // Signals group
    html += `<optgroup label="Signals">`
    html += this._optionTag("signal", "signal", selectedValue)
    html += `</optgroup>`

    // Context group
    html += `<optgroup label="Context">`
    html += this._optionTag("ctx", "ctx", selectedValue)
    html += this._optionTag("ctx.model", "ctx.model", selectedValue)
    html += `</optgroup>`

    // Entity fields group (if bound entity has attributes)
    if (entityAttributes.length > 0) {
      html += `<optgroup label="Entity Fields">`
      entityAttributes.forEach(attr => {
        const slug = attr.name_slug || attr.name || attr
        const value = `ctx.model.${slug}`
        html += this._optionTag(value, value, selectedValue)
      })
      html += `</optgroup>`
    }

    // Parent outputs group
    if (parentOutputs.length > 0) {
      html += `<optgroup label="Parent Outputs">`
      parentOutputs.forEach(opt => {
        html += this._optionTag(opt.value, opt.label || opt.value, selectedValue)
      })
      html += `</optgroup>`
    }

    return html
  }

  /**
   * Build a single <option> tag.
   */
  _optionTag(value, label, selectedValue) {
    const selected = value === selectedValue ? " selected" : ""
    return `<option value="${value}"${selected}>${escapeHtml(label)}</option>`
  }
```

- [ ] **Step 2: Expand right operand with entity fields and custom value toggle**

In the same `buildConditionFieldHTML` method, find the right operand options block (lines 202-207):

Find:
```javascript
    // Right Operand options: 'TRB Activity Success' at top, then parent outputs
    const rightOperandOptions = [
      { value: "TRB Activity Success", label: "TRB Activity Success" },
      ...this._availableOutputOptions
    ]
    const rightOperandOptionsHTML = this._buildSelectOptionsWithValue(rightOperandOptions, "Select value...", rightOperand)
```

Replace with:
```javascript
    // Right Operand: check if current value is a custom (non-standard) value
    const standardRightValues = this._getStandardRightOperandValues()
    const isCustomValue = rightOperand && !standardRightValues.includes(rightOperand)
    const rightOperandOptionsHTML = this._buildContextAwareRightOperandOptions(rightOperand)
```

Then add the private helper methods:

```javascript
  /**
   * Get all standard right operand values (for detecting custom values).
   */
  _getStandardRightOperandValues() {
    const entityAttributes = this.controller.canvas?.entityAttributes || []
    const parentOutputs = this._availableOutputOptions || []
    const values = ["TRB Activity Success", "__custom__"]
    entityAttributes.forEach(attr => {
      const slug = attr.name_slug || attr.name || attr
      values.push(`ctx.model.${slug}`)
    })
    parentOutputs.forEach(opt => values.push(opt.value))
    return values
  }

  /**
   * Build optgroup-separated options for right operand with custom value option.
   */
  _buildContextAwareRightOperandOptions(selectedValue) {
    const entityAttributes = this.controller.canvas?.entityAttributes || []
    const parentOutputs = this._availableOutputOptions || []
    const standardValues = this._getStandardRightOperandValues()
    const isCustom = selectedValue && !standardValues.includes(selectedValue)

    let html = `<option value="">Select value...</option>`

    // Common values
    html += `<optgroup label="Common">`
    html += this._optionTag("TRB Activity Success", "TRB Activity Success", isCustom ? "" : selectedValue)
    html += `</optgroup>`

    // Entity fields
    if (entityAttributes.length > 0) {
      html += `<optgroup label="Entity Fields">`
      entityAttributes.forEach(attr => {
        const slug = attr.name_slug || attr.name || attr
        const value = `ctx.model.${slug}`
        html += this._optionTag(value, value, isCustom ? "" : selectedValue)
      })
      html += `</optgroup>`
    }

    // Parent outputs
    if (parentOutputs.length > 0) {
      html += `<optgroup label="Parent Outputs">`
      parentOutputs.forEach(opt => {
        html += this._optionTag(opt.value, opt.label || opt.value, isCustom ? "" : selectedValue)
      })
      html += `</optgroup>`
    }

    // Custom value option
    html += `<optgroup label="Other">`
    html += this._optionTag("__custom__", "Custom value...", isCustom ? "__custom__" : "")
    html += `</optgroup>`

    return html
  }
```

- [ ] **Step 3: Update right operand HTML to support custom value toggle**

In the condition HTML template within `buildConditionFieldHTML` (around line 245-253), replace the right operand section:

Find:
```javascript
            <!-- Right Operand -->
            <div class="${rightOperandHidden}" data-condition-right-operand-container>
              <label class="block text-[10px] text-gray-500 mb-1">Right Operand</label>
              <select data-condition-right-operand
                      name="condition[rightOperand]"
                      data-action="change->property-editor#handleConditionRightOperandChange"
                      class="w-full px-2 py-1.5 text-xs bg-white border border-gray-300 rounded shadow-sm focus:outline-none focus:ring-1 focus:ring-amber-500 focus:border-amber-500">
                ${rightOperandOptionsHTML}
              </select>
            </div>
```

Replace with:
```javascript
            <!-- Right Operand -->
            <div class="${rightOperandHidden}" data-condition-right-operand-container>
              <label class="block text-[10px] text-gray-500 mb-1">Right Operand</label>
              <select data-condition-right-operand-select
                      name="condition[rightOperand]"
                      data-action="change->property-editor#handleConditionRightOperandChange"
                      class="w-full px-2 py-1.5 text-xs bg-white border border-gray-300 rounded shadow-sm focus:outline-none focus:ring-1 focus:ring-amber-500 focus:border-amber-500 ${isCustomValue ? 'hidden' : ''}">
                ${rightOperandOptionsHTML}
              </select>
              <div class="${isCustomValue ? '' : 'hidden'}" data-condition-right-operand-custom-container>
                <div class="flex gap-1">
                  <input type="text"
                         data-condition-right-operand-custom
                         name="condition[rightOperand]"
                         value="${isCustomValue ? escapeHtml(rightOperand) : ''}"
                         placeholder="Enter custom value..."
                         class="flex-1 px-2 py-1.5 text-xs bg-white border border-gray-300 rounded shadow-sm focus:outline-none focus:ring-1 focus:ring-amber-500 focus:border-amber-500">
                  <button type="button"
                          data-action="click->property-editor#switchToSelectRightOperand"
                          class="px-2 py-1 text-[10px] text-gray-500 hover:text-gray-700 border border-gray-300 rounded hover:bg-gray-50"
                          title="Switch to dropdown">
                    &#x25BC;
                  </button>
                </div>
              </div>
            </div>
```

- [ ] **Step 4: Add custom value toggle logic to BranchManager and update collectCondition**

In `app/javascript/controllers/property_editor/branch_manager.js`, find the existing `handleConditionRightOperandChange` method (around line 588). Replace it:

```javascript
  handleConditionRightOperandChange(event) {
    const value = event.target.value
    if (value === "__custom__") {
      // Switch to custom text input
      const container = event.target.closest("[data-condition-right-operand-container]")
      if (!container) return
      const selectEl = container.querySelector("[data-condition-right-operand-select]")
      const customContainer = container.querySelector("[data-condition-right-operand-custom-container]")
      if (selectEl) selectEl.classList.add("hidden")
      if (customContainer) {
        customContainer.classList.remove("hidden")
        const input = customContainer.querySelector("input")
        if (input) { input.value = ""; input.focus() }
      }
      return
    }
    this.controller._syncChangesToCanvas()
  }

  switchToSelectRightOperand(event) {
    event.preventDefault()
    const container = event.target.closest("[data-condition-right-operand-container]")
    if (!container) return
    const selectEl = container.querySelector("[data-condition-right-operand-select]")
    const customContainer = container.querySelector("[data-condition-right-operand-custom-container]")
    if (selectEl) { selectEl.classList.remove("hidden"); selectEl.value = "" }
    if (customContainer) customContainer.classList.add("hidden")
    this.controller._syncChangesToCanvas()
  }
```

Then in `app/javascript/controllers/property_editor_controller.js`, add a delegation method for `switchToSelectRightOperand`:

```javascript
  switchToSelectRightOperand(event) {
    this.branchManager.switchToSelectRightOperand(event)
  }
```

**Also update `collectCondition()`** in `branch_manager.js` (around line 592) to handle the renamed right operand selectors. Find:

```javascript
    const rightSelect = formFields.querySelector("[data-condition-right-operand]")
```

Replace with:

```javascript
    // Check both select and custom text input for right operand
    const rightSelect = formFields.querySelector("[data-condition-right-operand-select]")
    const rightCustomInput = formFields.querySelector("[data-condition-right-operand-custom]")
```

Then find (a few lines below where `rightOperand` is assigned):

```javascript
    let rightOperand = ""
```

And update the right operand value resolution to check both:

```javascript
    let rightOperand = ""
    if (rightCustomInput && !rightCustomInput.closest("[data-condition-right-operand-custom-container]")?.classList.contains("hidden")) {
      rightOperand = rightCustomInput.value || ""
    } else if (rightSelect) {
      rightOperand = rightSelect.value || ""
    }
```

- [ ] **Step 5: Verify no syntax errors**

Run: `node -c app/javascript/controllers/property_editor/branch_manager.js 2>&1`
Expected: No syntax errors

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/property_editor/branch_manager.js app/javascript/controllers/property_editor_controller.js
git commit -m "feat: context-aware operand dropdowns for Decision condition builder"
```

---

### Task 5: Structured Condition for Loop Element

**Files:**
- Modify: `app/javascript/flowchart/constants/schemas.js`

- [ ] **Step 1: Change loop condition type from `text` to `condition`**

In `app/javascript/flowchart/constants/schemas.js`, find the `loop` entry in `ELEMENT_SCHEMAS` (around line 270-288). Replace the `condition` field:

Find:
```javascript
  loop: {
    inputs: COMMON_PROPERTIES.inputs,
    condition: {
      type: "text",
      label: "Loop Condition",
      placeholder: "e.g., while count < 10"
    },
```

Replace with:
```javascript
  loop: {
    inputs: COMMON_PROPERTIES.inputs,
    condition: {
      type: "condition",
      label: "Loop Condition"
    },
```

This single change causes the Loop element to reuse `BranchManager.buildConditionFieldHTML()` (which now has context-aware operands from Task 4), because `FormBuilder._buildFieldHTML` already dispatches `type: "condition"` to the branch manager.

- [ ] **Step 2: Handle legacy string conditions in BranchManager**

In `app/javascript/controllers/property_editor/branch_manager.js`, at the start of `buildConditionFieldHTML` (around line 180), add a legacy string check:

Find:
```javascript
  buildConditionFieldHTML(fieldName, fieldSchema, currentValue) {
    // Get parent outputs for right operand options
    this._availableOutputOptions = this._getParentOutputOptions()

    // Parse current value (can be an object with leftOperand, operator, rightOperand)
    const condition = currentValue || {}
```

Replace with:
```javascript
  buildConditionFieldHTML(fieldName, fieldSchema, currentValue) {
    // Get parent outputs for right operand options
    this._availableOutputOptions = this._getParentOutputOptions()

    // Handle legacy string conditions (from old Loop elements)
    if (typeof currentValue === "string" && currentValue.length > 0) {
      return this._buildLegacyConditionMigrationHTML(fieldName, fieldSchema, currentValue)
    }

    // Parse current value (can be an object with leftOperand, operator, rightOperand)
    const condition = currentValue || {}
```

Then add the legacy migration method:

```javascript
  /**
   * Render a migration prompt for legacy string conditions.
   */
  _buildLegacyConditionMigrationHTML(fieldName, fieldSchema, legacyValue) {
    return `
      <div class="mb-4">
        <label class="block text-sm font-medium text-gray-700 mb-2">${fieldSchema.label}</label>
        <div class="p-3 bg-amber-50 rounded-lg border border-amber-200">
          <div class="flex items-start gap-2 mb-2">
            <svg class="w-4 h-4 text-amber-500 mt-0.5 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
            </svg>
            <div>
              <p class="text-xs font-medium text-amber-800">Legacy text condition</p>
              <p class="text-[10px] text-amber-600 mt-0.5">Current value: <code class="bg-amber-100 px-1 rounded">${escapeHtml(legacyValue)}</code></p>
            </div>
          </div>
          <button type="button"
                  data-action="click->property-editor#convertLegacyCondition"
                  data-legacy-value="${escapeHtml(legacyValue)}"
                  class="w-full px-2 py-1.5 text-xs font-medium text-amber-700 bg-white border border-amber-300 rounded hover:bg-amber-50 transition-colors">
            Convert to structured condition
          </button>
          <input type="hidden" name="${fieldName}" value="${escapeHtml(legacyValue)}">
        </div>
      </div>
    `
  }
```

- [ ] **Step 3: Add convertLegacyCondition handler to PropertyEditorController**

In `app/javascript/controllers/property_editor_controller.js`, add:

```javascript
  convertLegacyCondition(event) {
    event.preventDefault()
    if (!this.currentElement) return

    // Replace string condition with empty structured condition
    this.currentElement.properties.condition = {
      leftOperand: "signal",
      operator: "",
      rightOperand: ""
    }

    // Rebuild the form to show the structured condition builder
    this.formBuilder.buildForm()
    this._syncChangesToCanvas()
  }
```

- [ ] **Step 4: Verify no syntax errors**

Run: `node -c app/javascript/flowchart/constants/schemas.js 2>&1`
Expected: No syntax errors

- [ ] **Step 5: Commit**

```bash
git add app/javascript/flowchart/constants/schemas.js app/javascript/controllers/property_editor/branch_manager.js app/javascript/controllers/property_editor_controller.js
git commit -m "feat: structured condition builder for Loop element with legacy migration"
```

---

### Task 6: Loop Condition Code Generation in ActivityGenerator

**Files:**
- Modify: `app/services/activity_generator.rb`
- Modify: `spec/services/activity_generator_spec.rb`

- [ ] **Step 1: Write failing test for loop condition code generation**

Add to `spec/services/activity_generator_spec.rb`:

```ruby
describe "loop condition code generation" do
  let(:customer) { create(:customer) }
  let(:entity) { create(:entity, customer: customer) }

  context "with structured condition" do
    let(:flowchart) do
      config = {
        "elements" => [
          { "id" => "el_start", "type" => "start", "x" => 400, "y" => 100, "width" => 100, "height" => 45,
            "label" => "Start", "properties" => { "inputs" => [{ "value" => "all params" }], "outputs" => [{ "value" => "ctx" }], "description" => "" } },
          { "id" => "el_loop", "type" => "loop", "x" => 400, "y" => 200, "width" => 100, "height" => 45,
            "label" => "Retry Loop", "properties" => {
              "inputs" => [], "outputs" => [{ "value" => "ctx" }],
              "condition" => { "leftOperand" => "ctx.retry_count", "operator" => "<", "rightOperand" => "3" },
              "iterations" => 10,
              "description" => ""
            } }
        ],
        "connections" => [{ "id" => "conn_1", "from" => "el_start", "to" => "el_loop", "fromPosition" => "bottom", "toPosition" => "top" }],
        "metadata" => { "canvas" => { "width" => 2000, "height" => 1500 } }
      }
      create(:flowchart, name: "Loop Test", customer: customer, entity: entity, configuration: config.to_json)
    end

    it "generates a loop condition check method" do
      code = flowchart.activity
      expect(code).to include("def retry_loop")
    end

    it "includes max iterations guard" do
      code = flowchart.activity
      expect(code).to include("_loop_iteration_count")
      expect(code).to include("10")
    end

    it "includes structured condition comparison" do
      code = flowchart.activity
      expect(code).to include("retry_count")
    end
  end

  context "with legacy string condition" do
    let(:flowchart) do
      config = {
        "elements" => [
          { "id" => "el_start", "type" => "start", "x" => 400, "y" => 100, "width" => 100, "height" => 45,
            "label" => "Start", "properties" => { "inputs" => [{ "value" => "all params" }], "outputs" => [{ "value" => "ctx" }], "description" => "" } },
          { "id" => "el_loop", "type" => "loop", "x" => 400, "y" => 200, "width" => 100, "height" => 45,
            "label" => "Old Loop", "properties" => {
              "inputs" => [], "outputs" => [{ "value" => "ctx" }],
              "condition" => "while count < 10",
              "iterations" => 5,
              "description" => ""
            } }
        ],
        "connections" => [{ "id" => "conn_1", "from" => "el_start", "to" => "el_loop", "fromPosition" => "bottom", "toPosition" => "top" }],
        "metadata" => { "canvas" => { "width" => 2000, "height" => 1500 } }
      }
      create(:flowchart, name: "Legacy Loop", customer: customer, entity: entity, configuration: config.to_json)
    end

    it "generates a loop with comment for legacy condition" do
      code = flowchart.activity
      expect(code).to include("def old_loop")
      expect(code).to include("while count < 10")
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/activity_generator_spec.rb -t "loop condition" 2>&1 | tail -10`
Expected: FAIL

- [ ] **Step 3: Implement loop code generation**

In `app/services/activity_generator.rb`, find the `build_method` method (around line 336). The current `method_body` only handles process steps. Add loop element handling.

Find the `method_body` method (around line 351):

```ruby
  def method_body(element, steps, ctx)
    return "# TODO: Implement #{element['label']}\ntrue" if steps.empty?
```

Replace with:

```ruby
  def method_body(element, steps, ctx)
    # Handle loop elements with structured conditions
    if element["type"] == "loop"
      return generate_loop_body(element)
    end

    return "# TODO: Implement #{element['label']}\ntrue" if steps.empty?
```

Then add the `generate_loop_body` private method:

```ruby
  def generate_loop_body(element)
    condition = element.dig("properties", "condition")
    max_iterations = element.dig("properties", "iterations") || 10

    # Iteration counter guard
    guard = <<~RUBY.chomp
      # Max iterations safety limit
      ctx[:_loop_iteration_count] = (ctx[:_loop_iteration_count] || 0) + 1
      return false if ctx[:_loop_iteration_count] > #{max_iterations}
    RUBY

    # Build condition check
    condition_check = if condition.is_a?(Hash) && condition["leftOperand"].present?
      build_structured_condition(condition)
    elsif condition.is_a?(String) && condition.present?
      "# Legacy condition: #{condition}\ntrue"
    else
      "true"
    end

    "#{guard}\n\n#{condition_check}"
  end

  def build_structured_condition(condition)
    left = condition_operand_to_ruby(condition["leftOperand"])
    operator = condition["operator"]
    right = condition_operand_to_ruby(condition["rightOperand"])

    # Unary operators (no right operand)
    case operator
    when "is_empty"     then return "#{left}.blank?"
    when "is_not_empty" then return "#{left}.present?"
    when "is_true"      then return "!!#{left}"
    when "is_false"     then return "!#{left}"
    end

    # Binary operators
    ruby_op = case operator
              when "==" then "=="
              when "!=" then "!="
              when ">"  then ">"
              when ">=" then ">="
              when "<"  then "<"
              when "<=" then "<="
              when "contains"    then return "#{left}.to_s.include?(#{right}.to_s)"
              when "starts_with" then return "#{left}.to_s.start_with?(#{right}.to_s)"
              when "ends_with"   then return "#{left}.to_s.end_with?(#{right}.to_s)"
              else "=="
              end

    "#{left} #{ruby_op} #{right}"
  end

  def condition_operand_to_ruby(operand)
    return "nil" if operand.blank?

    # Handle ctx.model.field_name -> ctx.dig(:model, :field_name)
    if operand.start_with?("ctx.")
      parts = operand.sub("ctx.", "").split(".")
      keys = parts.map { |p| ":#{p}" }.join(", ")
      "ctx.dig(#{keys})"
    elsif operand == "signal"
      "ctx[:signal]"
    elsif operand == "ctx"
      "ctx"
    elsif operand.match?(/\A\d+(\.\d+)?\z/)
      operand # numeric literal
    else
      operand.inspect # string literal
    end
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/activity_generator_spec.rb 2>&1 | tail -10`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/activity_generator.rb spec/services/activity_generator_spec.rb
git commit -m "feat: add loop condition code generation with structured condition support"
```

---

### Task 7: Final Verification

- [ ] **Step 1: Run all related tests**

Run: `bundle exec rspec spec/services/activity_generator_spec.rb -v 2>&1 | tail -20`
Expected: ALL PASS

- [ ] **Step 2: Compile assets**

Run: `bin/rails assets:precompile 2>&1 | tail -5`
Expected: Clean compilation

- [ ] **Step 3: Restart server**

Run: `kill -9 $(lsof -i :3000 -t 2>/dev/null); sleep 1; bundle exec rails server -b 0.0.0.0 -d 2>&1`
Expected: Server starts

- [ ] **Step 4: Manual smoke test**

1. Visit `/96546124/flowcharts/44/edit`
2. Double-click a Process element → verify "Error Handling" section appears with mode dropdown
3. Switch to "Route to Error End" → verify "Error Output Field" input appears
4. Double-click a Decision element → verify left operand dropdown has optgroup sections (Signals, Context, Entity Fields, Parent Outputs)
5. Verify right operand has "Custom value..." option that toggles to text input
6. Drag a Loop element → double-click → verify structured condition builder (not free-text)
7. Save flowchart → verify no errors
