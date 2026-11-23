# Phase 2: Properties Enrichment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enrich element properties to match workflow builder standards — compound conditions, loop types, connection properties with inline labels, and per-element color customization.

**Architecture:** The property system is schema-driven (`ELEMENT_SCHEMAS` in schemas.js) with delegated managers (StepManager, BranchManager, IOManager). FormBuilder routes field types to managers. Changes flow: schema → FormBuilder → manager → canvas → ActivityGenerator. Connection rendering is in `ConnectionManagerMixin`. Element rendering is in `ElementRendererMixin`.

**Tech Stack:** StimulusJS, vanilla SVG, TailwindCSS, RSpec. Extends the March 22 enrichment spec (structured conditions already exist).

**Spec Reference:** `docs/superpowers/specs/2026-03-23-anysys-industry-standard-audit-design.md` — Items #8, #14, #15, #17, #18

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `spec/services/activity_generator_compound_conditions_spec.rb` | Tests for compound condition code generation |

### Modified Files
| File | Changes |
|------|---------|
| `app/javascript/flowchart/constants/schemas.js` | Add `loopType` field to loop schema, add `style` field to all schemas |
| `app/javascript/controllers/property_editor/branch_manager.js` | Compound condition builder with AND/OR groups |
| `app/javascript/controllers/property_editor/form_builder.js` | Handle `loopType` field rendering, `style` field rendering |
| `app/javascript/controllers/property_editor_controller.js` | Collect compound conditions, loop types, element styles |
| `app/javascript/flowchart/connection_manager.js` | Add `properties` to connection data, support click-to-select for property editing, inline label editing |
| `app/javascript/flowchart/element_renderer.js` | Read `element.style` for custom colors, fallback to type defaults |
| `app/services/activity_generator.rb` | Compile compound conditions to Ruby, handle loop types (for-each, do-while) |
| `app/views/flowcharts/_editor.html.erb` | Connection property support in property editor |

---

## Task 1: Connection Properties and Labels (#17 + #8)

**Files:**
- Modify: `app/javascript/flowchart/connection_manager.js`
- Modify: `app/javascript/controllers/property_editor_controller.js`
- Modify: `app/javascript/controllers/property_editor/form_builder.js`
- Modify: `app/javascript/flowchart/canvas.js`

Connections currently store `{ id, from, to, fromPosition, toPosition, label }`. We extend this with a `properties` object and add inline label editing.

- [ ] **Step 1: Extend connection data structure**

In `app/javascript/flowchart/connection_manager.js`, update `createConnection()` (line 44) to initialize properties:

```javascript
// In createConnection, when building the connection object:
const connection = {
  id: generateId("conn"),
  from: fromElement.id,
  to: toElement.id,
  fromPosition,
  toPosition,
  label: options.label || null,
  properties: {
    description: "",
    priority: 0,
    ...(options.properties || {})
  }
}
```

- [ ] **Step 2: Add double-click to edit connection label inline**

In `_createConnectionGroup()` (connection_manager.js, line 96), add a double-click handler to the group:

```javascript
group.addEventListener("dblclick", (e) => {
  e.stopPropagation()
  this._startInlineLabelEdit(connectionId, e)
})
```

Add the inline label editing methods:

```javascript
_startInlineLabelEdit(connectionId, event) {
  const connection = this.connections.find(c => c.id === connectionId)
  if (!connection) return

  // Get the label position (midpoint of connection path)
  const group = this.connectionLayer.querySelector(`[data-connection-id="${connectionId}"]`)
  if (!group) return

  // Remove existing inline editor if any
  this._endInlineLabelEdit()

  // Calculate position using path midpoint
  const pathEl = group.querySelector("path.connection-line")
  if (!pathEl) return
  const pathLength = pathEl.getTotalLength()
  const midPoint = pathEl.getPointAtLength(pathLength / 2)

  // Create foreignObject for text input
  const fo = createSvgElement("foreignObject", {
    x: midPoint.x - 60,
    y: midPoint.y - 14,
    width: 120,
    height: 28,
    class: "connection-label-editor"
  })

  const input = document.createElement("input")
  input.type = "text"
  input.value = connection.label || ""
  input.placeholder = "Label..."
  input.className = "w-full h-full px-2 text-xs border border-blue-400 rounded bg-white focus:outline-none focus:ring-1 focus:ring-blue-500 text-center"
  input.style.fontSize = "10px"

  input.addEventListener("keydown", (e) => {
    if (e.key === "Enter") {
      this._commitInlineLabel(connectionId, input.value)
    } else if (e.key === "Escape") {
      this._endInlineLabelEdit()
    }
    e.stopPropagation()
  })

  input.addEventListener("blur", () => {
    this._commitInlineLabel(connectionId, input.value)
  })

  fo.appendChild(input)
  this.handleLayer.appendChild(fo)
  this._inlineLabelEditor = fo

  // Focus after append
  requestAnimationFrame(() => {
    input.focus()
    input.select()
  })
}

_commitInlineLabel(connectionId, value) {
  const connection = this.connections.find(c => c.id === connectionId)
  if (connection) {
    this.onBeforeChange?.()
    connection.label = value.trim() || null
    this.updateConnections()
    this.onchange?.()
  }
  this._endInlineLabelEdit()
}

_endInlineLabelEdit() {
  if (this._inlineLabelEditor) {
    this._inlineLabelEditor.remove()
    this._inlineLabelEditor = null
  }
}
```

Note: `createSvgElement` needs to be imported if not already.

- [ ] **Step 3: Open property editor for connections**

When a connection is clicked (already selects it), double-clicking should open inline label editing. Single-clicking should select it. We need the property editor to also support showing connection properties.

In `app/javascript/controllers/property_editor_controller.js`, add connection editing support:

```javascript
openConnectionEditor(connection, canvas) {
  this.currentElement = null
  this.currentConnection = connection
  this.canvas = canvas

  this.titleTarget.textContent = "Connection Properties"
  this.elementIdValue = connection.id
  this.elementTypeValue = "connection"

  const html = this._buildConnectionPropertiesHTML(connection)
  this.formFieldsTarget.innerHTML = html
  this._setupFormListeners()

  this.sidebarTarget?.classList.remove("hidden")
}

_buildConnectionPropertiesHTML(connection) {
  return `
    <div class="space-y-4">
      <div>
        <label class="block text-sm font-medium text-gray-700 mb-1">Label</label>
        <input type="text" name="label" value="${connection.label || ""}"
               placeholder="e.g., yes, no, error"
               class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm"
               data-action="input->property-editor#_syncChangesToCanvas">
      </div>
      <div>
        <label class="block text-sm font-medium text-gray-700 mb-1">Description</label>
        <textarea name="description" rows="2" placeholder="Optional description..."
                  class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm">${connection.properties?.description || ""}</textarea>
      </div>
      <div>
        <label class="block text-sm font-medium text-gray-700 mb-1">Priority</label>
        <input type="number" name="priority" value="${connection.properties?.priority || 0}" min="0"
               class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm">
      </div>
    </div>
  `
}
```

Update the `save` method to handle connections:

```javascript
// In save(), add a branch for connections:
if (this.currentConnection) {
  const formData = new FormData(this.formTarget)
  this.currentConnection.label = formData.get("label")?.trim() || null
  this.currentConnection.properties = {
    description: formData.get("description") || "",
    priority: parseInt(formData.get("priority") || "0", 10)
  }
  this.canvas.updateConnections()
  // Save to server
  this._saveToDatabase()
  return
}
```

In `app/javascript/controllers/flowchart_canvas_controller.js`, wire connection selection to open property editor. In `_setupCanvasCallbacks`, the canvas already has connection selection. Add:

```javascript
// After existing onElementDoubleClick setup:
this.canvas.onConnectionSelected = (connection) => {
  this._showConnectionPropertySidebar(connection)
}
```

Add the method:
```javascript
_showConnectionPropertySidebar(connection) {
  const propertyEditor = this.application.getControllerForElementAndIdentifier(
    this.propertySidebarTarget, "property-editor"
  )
  if (propertyEditor) {
    propertyEditor.openConnectionEditor(connection, this.canvas)
    this.propertySidebarTarget.classList.remove("hidden")
  }
}
```

In `canvas.js`, add the `onConnectionSelected` callback to the constructor and fire it when a connection is selected (in `selectConnection` in `connection_manager.js`).

- [ ] **Step 4: Preserve connection properties in serialization**

In `canvas.js`, update `getConfiguration()` to include connection properties:

```javascript
// In getConfiguration(), where connections are serialized:
const connections = this.connections
  .filter(c => elementIds.has(c.from) && elementIds.has(c.to))
  .map(c => ({
    ...c,
    label: c.label || null,
    properties: c.properties || {}
  }))
```

In `loadConfiguration()`, ensure connection properties are preserved when loading:

```javascript
// When creating connections from config:
connection.properties = connData.properties || { description: "", priority: 0 }
```

- [ ] **Step 5: Verify connection properties**

Manual verification:
1. Double-click a connection → inline label editor appears at midpoint
2. Type a label, press Enter → label appears on connection as yellow badge
3. Click a connection to select → property editor sidebar opens with label/description/priority
4. Edit and save → properties persist
5. Decision branch connections show auto-populated labels
6. Save and reload → connection labels and properties persist

- [ ] **Step 6: Commit**

```bash
git add app/javascript/flowchart/connection_manager.js app/javascript/controllers/property_editor_controller.js app/javascript/controllers/property_editor/form_builder.js app/javascript/controllers/flowchart_canvas_controller.js app/javascript/flowchart/canvas.js
git commit -m "feat: add connection properties (label, description, priority) with inline editing"
```

---

## Task 2: Element Color/Style Customization (#18)

**Files:**
- Modify: `app/javascript/flowchart/constants/schemas.js`
- Modify: `app/javascript/flowchart/element_renderer.js`
- Modify: `app/javascript/controllers/property_editor/form_builder.js`
- Modify: `app/javascript/controllers/property_editor_controller.js`

- [ ] **Step 1: Add style property to element data structure**

Elements already have a `properties` object. We'll add a `style` sub-object. No schema change needed for storage — just add UI to edit it and renderer to read it.

In `app/javascript/flowchart/constants/schemas.js`, add a `style` field to each element type's schema in `ELEMENT_SCHEMAS`. Add it as the last field for each type:

```javascript
style: {
  label: "Style",
  type: "style",
  hidden: false
}
```

Add to: start, end, process, decision, loop, subflow schemas.

- [ ] **Step 2: Build style picker UI in FormBuilder**

In `app/javascript/controllers/property_editor/form_builder.js`, add handling for `type: "style"` in `_buildFieldHTML()`:

```javascript
if (fieldSchema.type === "style") {
  return this._buildStyleFieldHTML(fieldName, currentValue)
}
```

Add the method:

```javascript
_buildStyleFieldHTML(fieldName, currentValue) {
  const colors = [
    { label: "Default", fill: null, stroke: null },
    { label: "Blue", fill: "#dbeafe", stroke: "#3b82f6" },
    { label: "Green", fill: "#dcfce7", stroke: "#16a34a" },
    { label: "Red", fill: "#fee2e2", stroke: "#ef4444" },
    { label: "Yellow", fill: "#fef9c3", stroke: "#ca8a04" },
    { label: "Purple", fill: "#f3e8ff", stroke: "#9333ea" },
    { label: "Pink", fill: "#fce7f3", stroke: "#db2777" },
    { label: "Cyan", fill: "#cffafe", stroke: "#0891b2" },
    { label: "Orange", fill: "#ffedd5", stroke: "#ea580c" },
    { label: "Slate", fill: "#f1f5f9", stroke: "#475569" },
    { label: "Emerald", fill: "#d1fae5", stroke: "#059669" },
    { label: "Indigo", fill: "#e0e7ff", stroke: "#4f46e5" }
  ]

  const currentFill = currentValue?.fill || null

  return `
    <div class="space-y-2">
      <label class="block text-sm font-medium text-gray-700">Style</label>
      <div class="grid grid-cols-6 gap-2">
        ${colors.map(c => {
          const isSelected = c.fill === currentFill
          const bgStyle = c.fill ? `background-color: ${c.fill}; border-color: ${c.stroke}` : "background-color: white; border-color: #d1d5db"
          return `
            <button type="button"
                    data-action="click->property-editor#selectStyle"
                    data-fill="${c.fill || ""}"
                    data-stroke="${c.stroke || ""}"
                    title="${c.label}"
                    class="w-8 h-8 rounded border-2 transition-all ${isSelected ? "ring-2 ring-offset-1 ring-indigo-500" : "hover:scale-110"}"
                    style="${bgStyle}">
            </button>
          `
        }).join("")}
      </div>
      <input type="hidden" name="style_fill" value="${currentValue?.fill || ""}">
      <input type="hidden" name="style_stroke" value="${currentValue?.stroke || ""}">
    </div>
  `
}
```

- [ ] **Step 3: Handle style selection in property editor**

In `app/javascript/controllers/property_editor_controller.js`, add the `selectStyle` action method:

```javascript
selectStyle(event) {
  const fill = event.currentTarget.dataset.fill || null
  const stroke = event.currentTarget.dataset.stroke || null

  // Update hidden inputs
  const fillInput = this.formTarget.querySelector('input[name="style_fill"]')
  const strokeInput = this.formTarget.querySelector('input[name="style_stroke"]')
  if (fillInput) fillInput.value = fill || ""
  if (strokeInput) strokeInput.value = stroke || ""

  // Update visual selection
  const buttons = event.currentTarget.parentElement.querySelectorAll("button")
  buttons.forEach(btn => {
    btn.classList.remove("ring-2", "ring-offset-1", "ring-indigo-500")
    btn.classList.add("hover:scale-110")
  })
  event.currentTarget.classList.add("ring-2", "ring-offset-1", "ring-indigo-500")
  event.currentTarget.classList.remove("hover:scale-110")

  this._syncChangesToCanvas()
}
```

In `_collectFormData()`, collect style:

```javascript
// After collecting other properties:
const styleFill = formData.get("style_fill")
const styleStroke = formData.get("style_stroke")
if (styleFill || styleStroke) {
  newProperties.style = { fill: styleFill || null, stroke: styleStroke || null }
} else {
  newProperties.style = null
}
```

- [ ] **Step 4: Render elements with custom styles**

In `app/javascript/flowchart/element_renderer.js`, update `_createShape()` (line 209) to check for custom style:

```javascript
_createShape(element, colors) {
  // Use custom style if present, otherwise type-based colors
  const effectiveColors = element.properties?.style?.fill
    ? { fill: element.properties.style.fill, stroke: element.properties.style.stroke }
    : colors

  switch (element.type) {
    case "start":
    case "end":
      return this._createOvalShape(element, effectiveColors)
    // ... other cases using effectiveColors instead of colors
  }
}
```

Also update each shape creator to accept and use the colors parameter (they likely already do).

- [ ] **Step 5: Verify element styles**

Manual verification:
1. Double-click element to open property editor → style picker visible at bottom
2. Click a color → element updates immediately on canvas
3. Click "Default" → element returns to type-based color
4. Save and reload → custom colors persist
5. All element types support custom colors

- [ ] **Step 6: Commit**

```bash
git add app/javascript/flowchart/constants/schemas.js app/javascript/flowchart/element_renderer.js app/javascript/controllers/property_editor/form_builder.js app/javascript/controllers/property_editor_controller.js
git commit -m "feat: add per-element color customization with 12-color palette"
```

---

## Task 3: Compound Conditions for Decision and Loop (#14)

**Files:**
- Modify: `app/javascript/controllers/property_editor/branch_manager.js`
- Modify: `app/javascript/controllers/property_editor_controller.js`
- Modify: `app/services/activity_generator.rb`
- Create: `spec/services/activity_generator_compound_conditions_spec.rb`

This extends the existing single condition `{ leftOperand, operator, rightOperand }` with group structure `{ type: "group", operator: "AND", conditions: [...] }`.

- [ ] **Step 1: Write failing specs for compound condition code generation**

Create `spec/services/activity_generator_compound_conditions_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe ActivityGenerator do
  let(:entity) { create(:entity) }

  describe "compound condition compilation" do
    let(:flowchart) do
      create(:flowchart, entity: entity, configuration: {
        elements: [
          { id: "el_1", type: "start", x: 100, y: 100, width: 100, height: 45, label: "Start", properties: { inputs: [], outputs: [] } },
          { id: "el_2", type: "decision", x: 100, y: 200, width: 100, height: 45, label: "Check",
            properties: {
              inputs: [], outputs: [],
              condition: {
                "type" => "group",
                "operator" => "AND",
                "conditions" => [
                  { "type" => "comparison", "leftOperand" => "ctx.model.status", "operator" => "==", "rightOperand" => "active" },
                  { "type" => "comparison", "leftOperand" => "ctx.model.role", "operator" => "!=", "rightOperand" => "guest" }
                ]
              }
            }
          },
          { id: "el_3", type: "end", x: 100, y: 300, width: 100, height: 45, label: "End", properties: {} },
          { id: "el_4", type: "end", x: 300, y: 300, width: 100, height: 45, label: "End 2", properties: {} }
        ],
        connections: [
          { id: "c1", from: "el_1", to: "el_2" },
          { id: "c2", from: "el_2", to: "el_3" },
          { id: "c3", from: "el_2", to: "el_4" }
        ],
        metadata: {}
      }.to_json)
    end

    it "generates Ruby AND condition" do
      code = described_class.new(flowchart).generate
      expect(code).to include("&&")
      expect(code).to include("ctx.dig(:model, :status)")
      expect(code).to include("ctx.dig(:model, :role)")
    end

    context "with OR operator" do
      let(:flowchart) do
        create(:flowchart, entity: entity, configuration: {
          elements: [
            { id: "el_1", type: "start", x: 100, y: 100, width: 100, height: 45, label: "Start", properties: { inputs: [], outputs: [] } },
            { id: "el_2", type: "decision", x: 100, y: 200, width: 100, height: 45, label: "Check",
              properties: {
                inputs: [], outputs: [],
                condition: {
                  "type" => "group",
                  "operator" => "OR",
                  "conditions" => [
                    { "type" => "comparison", "leftOperand" => "ctx.model.active", "operator" => "is_true" },
                    { "type" => "comparison", "leftOperand" => "ctx.model.admin", "operator" => "is_true" }
                  ]
                }
              }
            },
            { id: "el_3", type: "end", x: 100, y: 300, width: 100, height: 45, label: "End", properties: {} },
            { id: "el_4", type: "end", x: 300, y: 300, width: 100, height: 45, label: "End 2", properties: {} }
          ],
          connections: [
            { id: "c1", from: "el_1", to: "el_2" },
            { id: "c2", from: "el_2", to: "el_3" },
            { id: "c3", from: "el_2", to: "el_4" }
          ],
          metadata: {}
        }.to_json)
      end

      it "generates Ruby OR condition" do
        code = described_class.new(flowchart).generate
        expect(code).to include("||")
      end
    end

    context "with legacy single condition (backward compatibility)" do
      let(:flowchart) do
        create(:flowchart, entity: entity, configuration: {
          elements: [
            { id: "el_1", type: "start", x: 100, y: 100, width: 100, height: 45, label: "Start", properties: { inputs: [], outputs: [] } },
            { id: "el_2", type: "decision", x: 100, y: 200, width: 100, height: 45, label: "Check",
              properties: {
                inputs: [], outputs: [],
                condition: { "leftOperand" => "ctx.model.status", "operator" => "==", "rightOperand" => "active" }
              }
            },
            { id: "el_3", type: "end", x: 100, y: 300, width: 100, height: 45, label: "End", properties: {} },
            { id: "el_4", type: "end", x: 300, y: 300, width: 100, height: 45, label: "End 2", properties: {} }
          ],
          connections: [
            { id: "c1", from: "el_1", to: "el_2" },
            { id: "c2", from: "el_2", to: "el_3" },
            { id: "c3", from: "el_2", to: "el_4" }
          ],
          metadata: {}
        }.to_json)
      end

      it "still generates code for single conditions" do
        code = described_class.new(flowchart).generate
        expect(code).to include("ctx.dig(:model, :status)")
      end
    end
  end
end
```

- [ ] **Step 2: Run specs to verify they fail**

Run: `bundle exec rspec spec/services/activity_generator_compound_conditions_spec.rb -v`
Expected: Fail because `build_structured_condition` doesn't handle the group type.

- [ ] **Step 3: Update ActivityGenerator to compile compound conditions**

In `app/services/activity_generator.rb`, update `build_structured_condition` (around line 450):

```ruby
def build_structured_condition(condition)
  return "true" if condition.blank?

  # Handle compound condition groups
  if condition["type"] == "group"
    return build_condition_group(condition)
  end

  # Handle single comparison (legacy or type: "comparison")
  build_single_condition(condition)
end

def build_condition_group(group)
  conditions = group["conditions"] || []
  return "true" if conditions.empty?

  ruby_operator = group["operator"] == "OR" ? " || " : " && "
  parts = conditions.map do |cond|
    if cond["type"] == "group"
      "(#{build_condition_group(cond)})"
    else
      build_single_condition(cond)
    end
  end

  parts.length == 1 ? parts.first : "(#{parts.join(ruby_operator)})"
end

def build_single_condition(condition)
  left = condition["leftOperand"]
  operator = condition["operator"]
  right = condition["rightOperand"]

  return "true" if left.blank? && operator.blank?

  left_ruby = condition_operand_to_ruby(left)

  case operator
  when "==" then "#{left_ruby} == #{condition_operand_to_ruby(right)}"
  when "!=" then "#{left_ruby} != #{condition_operand_to_ruby(right)}"
  when ">" then "#{left_ruby} > #{condition_operand_to_ruby(right)}"
  when ">=" then "#{left_ruby} >= #{condition_operand_to_ruby(right)}"
  when "<" then "#{left_ruby} < #{condition_operand_to_ruby(right)}"
  when "<=" then "#{left_ruby} <= #{condition_operand_to_ruby(right)}"
  when "contains" then "#{left_ruby}.to_s.include?(#{condition_operand_to_ruby(right)})"
  when "starts_with" then "#{left_ruby}.to_s.start_with?(#{condition_operand_to_ruby(right)})"
  when "ends_with" then "#{left_ruby}.to_s.end_with?(#{condition_operand_to_ruby(right)})"
  when "is_empty" then "#{left_ruby}.blank?"
  when "is_not_empty" then "#{left_ruby}.present?"
  when "is_true" then "#{left_ruby} == true"
  when "is_false" then "#{left_ruby} == false"
  else "true"
  end
end
```

Note: The existing `build_structured_condition` method should be replaced/refactored into these three methods. The `build_single_condition` method extracts the existing logic.

- [ ] **Step 4: Run specs to verify they pass**

Run: `bundle exec rspec spec/services/activity_generator_compound_conditions_spec.rb spec/services/activity_generator_spec.rb -v`
Expected: All pass (new compound specs + existing specs unchanged).

- [ ] **Step 5: Build compound condition UI in BranchManager**

In `app/javascript/controllers/property_editor/branch_manager.js`, update `buildConditionFieldHTML()` (line 212) to support compound conditions:

The current condition builder renders a single row of 3 dropdowns. We need to:

1. Detect if the condition is a group (has `type: "group"`) or legacy (no type field)
2. For groups: render multiple condition rows with AND/OR toggle between them
3. For legacy: auto-wrap in a group with one condition on load

Update `buildConditionFieldHTML(fieldName, fieldSchema, currentValue)`:

```javascript
buildConditionFieldHTML(fieldName, fieldSchema, currentValue) {
  // Normalize to group format
  const group = this._normalizeConditionToGroup(currentValue)

  let html = `<div class="space-y-3" data-condition-group>`
  html += `<label class="block text-sm font-medium text-gray-700">Condition</label>`

  // Condition rows
  group.conditions.forEach((cond, index) => {
    if (index > 0) {
      // AND/OR toggle between rows
      html += `
        <div class="flex justify-center">
          <button type="button" data-action="click->property-editor#toggleConditionOperator"
                  class="px-3 py-0.5 text-xs font-semibold rounded-full border
                         ${group.operator === 'OR' ? 'bg-orange-100 text-orange-700 border-orange-300' : 'bg-blue-100 text-blue-700 border-blue-300'}">
            ${group.operator}
          </button>
        </div>
      `
    }
    html += this._buildConditionRowHTML(index, cond)
  })

  // Hidden input for group operator
  html += `<input type="hidden" name="condition_group_operator" value="${group.operator}">`

  // Add condition button
  html += `
    <button type="button" data-action="click->property-editor#addConditionRow"
            class="mt-2 inline-flex items-center px-2 py-1 text-xs font-medium text-indigo-600 hover:text-indigo-800">
      <svg class="w-3 h-3 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/>
      </svg>
      Add condition
    </button>
  `
  html += `</div>`

  return html
}

_normalizeConditionToGroup(condition) {
  if (!condition) return { type: "group", operator: "AND", conditions: [{ type: "comparison", leftOperand: "", operator: "", rightOperand: "" }] }
  if (condition.type === "group") return condition
  // Legacy single condition — wrap in group
  return {
    type: "group",
    operator: "AND",
    conditions: [{ type: "comparison", ...condition }]
  }
}

_buildConditionRowHTML(index, condition) {
  const leftOptions = this._buildContextAwareLeftOperandOptions(condition.leftOperand || "")
  const operatorOptions = this._buildOperatorOptions(condition.operator || "")
  const rightOptions = this._buildContextAwareRightOperandOptions(condition.rightOperand || "")
  const isUnary = this._operatorNeedsRightOperand ? !this._operatorNeedsRightOperand(condition.operator) : false

  return `
    <div class="flex items-center space-x-2 bg-gray-50 rounded-lg p-2" data-condition-row data-condition-index="${index}">
      <select name="condition_left_${index}" class="flex-1 text-xs rounded-md border-gray-300 focus:border-indigo-500 focus:ring-indigo-500"
              data-action="change->property-editor#handleConditionLeftOperandChange">
        ${leftOptions}
      </select>
      <select name="condition_operator_${index}" class="w-28 text-xs rounded-md border-gray-300 focus:border-indigo-500 focus:ring-indigo-500"
              data-action="change->property-editor#handleConditionOperatorChange">
        ${operatorOptions}
      </select>
      <div class="flex-1 ${isUnary ? 'hidden' : ''}" data-right-operand-container="${index}">
        <select name="condition_right_${index}" class="w-full text-xs rounded-md border-gray-300 focus:border-indigo-500 focus:ring-indigo-500"
                data-action="change->property-editor#handleConditionRightOperandChange">
          ${rightOptions}
        </select>
      </div>
      ${index > 0 ? `
        <button type="button" data-action="click->property-editor#removeConditionRow"
                data-condition-index="${index}"
                class="p-1 text-gray-400 hover:text-red-500">
          <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
          </svg>
        </button>
      ` : ""}
    </div>
  `
}

_buildOperatorOptions(selectedValue) {
  // Import BRANCH_OPERATORS from schemas
  const operators = [
    { value: "==", label: "equals" },
    { value: "!=", label: "not equals" },
    { value: ">", label: "greater than" },
    { value: ">=", label: "greater or equal" },
    { value: "<", label: "less than" },
    { value: "<=", label: "less or equal" },
    { value: "contains", label: "contains" },
    { value: "starts_with", label: "starts with" },
    { value: "ends_with", label: "ends with" },
    { value: "is_empty", label: "is empty" },
    { value: "is_not_empty", label: "is not empty" },
    { value: "is_true", label: "is true" },
    { value: "is_false", label: "is false" }
  ]
  return `<option value="">Select...</option>` + operators.map(op =>
    `<option value="${op.value}" ${op.value === selectedValue ? "selected" : ""}>${op.label}</option>`
  ).join("")
}
```

- [ ] **Step 6: Handle compound condition events in PropertyEditorController**

In `property_editor_controller.js`, add:

```javascript
toggleConditionOperator(event) {
  const btn = event.currentTarget
  const hiddenInput = this.formTarget.querySelector('input[name="condition_group_operator"]')
  const newOp = hiddenInput.value === "AND" ? "OR" : "AND"
  hiddenInput.value = newOp
  // Update all toggle buttons
  this.formTarget.querySelectorAll('[data-action*="toggleConditionOperator"]').forEach(b => {
    b.textContent = newOp
    b.classList.toggle("bg-blue-100", newOp === "AND")
    b.classList.toggle("text-blue-700", newOp === "AND")
    b.classList.toggle("border-blue-300", newOp === "AND")
    b.classList.toggle("bg-orange-100", newOp === "OR")
    b.classList.toggle("text-orange-700", newOp === "OR")
    b.classList.toggle("border-orange-300", newOp === "OR")
  })
  this._syncChangesToCanvas()
}

addConditionRow(event) {
  const container = this.formTarget.querySelector("[data-condition-group]")
  const rows = container.querySelectorAll("[data-condition-row]")
  const newIndex = rows.length
  const operator = this.formTarget.querySelector('input[name="condition_group_operator"]')?.value || "AND"

  // Insert AND/OR toggle before new row
  const toggleHTML = `
    <div class="flex justify-center">
      <button type="button" data-action="click->property-editor#toggleConditionOperator"
              class="px-3 py-0.5 text-xs font-semibold rounded-full border
                     ${operator === 'OR' ? 'bg-orange-100 text-orange-700 border-orange-300' : 'bg-blue-100 text-blue-700 border-blue-300'}">
        ${operator}
      </button>
    </div>
  `
  const rowHTML = this.branchManager._buildConditionRowHTML(newIndex, { type: "comparison", leftOperand: "", operator: "", rightOperand: "" })

  // Insert before the "Add condition" button
  const addBtn = container.querySelector('[data-action*="addConditionRow"]')
  addBtn.insertAdjacentHTML("beforebegin", toggleHTML + rowHTML)
  this._syncChangesToCanvas()
}

removeConditionRow(event) {
  const index = event.currentTarget.dataset.conditionIndex
  const row = this.formTarget.querySelector(`[data-condition-row][data-condition-index="${index}"]`)
  if (row) {
    // Also remove the AND/OR toggle before this row
    const prev = row.previousElementSibling
    if (prev && prev.querySelector('[data-action*="toggleConditionOperator"]')) {
      prev.remove()
    }
    row.remove()
  }
  this._syncChangesToCanvas()
}
```

Update `collectCondition()` in BranchManager to collect compound conditions:

```javascript
collectCondition() {
  const groupOperator = this.controller.formTarget.querySelector('input[name="condition_group_operator"]')?.value || "AND"
  const rows = this.controller.formTarget.querySelectorAll("[data-condition-row]")

  if (rows.length === 0) return null

  const conditions = Array.from(rows).map((row, i) => {
    const left = row.querySelector(`select[name="condition_left_${i}"]`)?.value || ""
    const op = row.querySelector(`select[name="condition_operator_${i}"]`)?.value || ""
    const right = row.querySelector(`select[name="condition_right_${i}"]`)?.value || ""
    return { type: "comparison", leftOperand: left, operator: op, rightOperand: right }
  }).filter(c => c.leftOperand || c.operator)

  if (conditions.length === 0) return null
  if (conditions.length === 1) {
    // Build expression for single condition
    const c = conditions[0]
    return { ...c, expression: this._buildConditionExpression(c.leftOperand, c.operator, c.rightOperand) }
  }

  // Build compound expression
  const exprParts = conditions.map(c => this._buildConditionExpression(c.leftOperand, c.operator, c.rightOperand))
  const expression = exprParts.join(` ${groupOperator} `)

  return {
    type: "group",
    operator: groupOperator,
    conditions,
    expression
  }
}
```

- [ ] **Step 7: Run all specs**

Run: `bundle exec rspec spec/services/activity_generator_compound_conditions_spec.rb spec/services/activity_generator_spec.rb -v`
Expected: All pass.

- [ ] **Step 8: Verify compound conditions**

Manual verification:
1. Open Decision element properties → condition shows as single row (backward compatible)
2. Click "Add condition" → second row appears with AND toggle between them
3. Click AND toggle → switches to OR
4. Fill in both conditions → expression preview shows both
5. Save → condition stored as group structure
6. Reopen → compound condition loads correctly with all rows
7. Remove a row → back to single condition
8. Existing single-condition flowcharts still work

- [ ] **Step 9: Commit**

```bash
git add app/javascript/controllers/property_editor/branch_manager.js app/javascript/controllers/property_editor_controller.js app/services/activity_generator.rb spec/services/activity_generator_compound_conditions_spec.rb
git commit -m "feat: compound conditions with AND/OR for Decision and Loop elements"
```

---

## Task 4: Loop Type Selection (#15)

**Files:**
- Modify: `app/javascript/flowchart/constants/schemas.js`
- Modify: `app/javascript/controllers/property_editor/form_builder.js`
- Modify: `app/javascript/controllers/property_editor_controller.js`
- Modify: `app/services/activity_generator.rb`
- Modify: `spec/services/activity_generator_spec.rb`

- [ ] **Step 1: Add loopType to schema**

In `app/javascript/flowchart/constants/schemas.js`, update the loop element schema. Add `loopType` as the first field (before inputs):

```javascript
loop: {
  loopType: {
    label: "Loop Type",
    type: "select",
    options: [
      { value: "while", label: "While (condition checked before body)" },
      { value: "do_while", label: "Do-While (execute at least once)" },
      { value: "for_each", label: "For-Each (iterate collection)" }
    ],
    default: "while"
  },
  ...COMMON_PROPERTIES,
  condition: { label: "Condition", type: "condition" },
  iterations: { label: "Max Iterations", type: "number", placeholder: "10" },
  // For-each specific fields:
  collection: { label: "Collection", type: "text", placeholder: "ctx.model.items", visibleWhen: { loopType: "for_each" } },
  itemVariable: { label: "Item Variable", type: "text", placeholder: "item", visibleWhen: { loopType: "for_each" } },
  indexVariable: { label: "Index Variable", type: "text", placeholder: "index", visibleWhen: { loopType: "for_each" } }
}
```

- [ ] **Step 2: Handle conditional field visibility in FormBuilder**

In `form_builder.js`, update `_buildFieldHTML()` to support `visibleWhen`:

```javascript
// In _buildFieldHTML, after building the HTML:
if (fieldSchema.visibleWhen) {
  const [depField, depValue] = Object.entries(fieldSchema.visibleWhen)[0]
  const currentDepValue = properties[depField] || fieldSchema.default || ""
  const isVisible = currentDepValue === depValue
  // Wrap in a conditional container
  return `<div data-visible-when="${depField}" data-visible-value="${depValue}" ${isVisible ? "" : 'class="hidden"'}>${html}</div>`
}
```

Add a handler in `property_editor_controller.js` for the loop type change:

```javascript
handleLoopTypeChange(event) {
  const newType = event.target.value
  // Show/hide conditional fields
  this.formTarget.querySelectorAll("[data-visible-when]").forEach(el => {
    const field = el.dataset.visibleWhen
    const value = el.dataset.visibleValue
    if (field === "loopType") {
      el.classList.toggle("hidden", newType !== value)
    }
  })

  // Show/hide condition field (hide for for_each)
  const conditionGroup = this.formTarget.querySelector("[data-condition-group]")?.closest(".space-y-3")
  if (conditionGroup) {
    conditionGroup.style.display = newType === "for_each" ? "none" : ""
  }

  this._syncChangesToCanvas()
}
```

Add `data-action="change->property-editor#handleLoopTypeChange"` to the loopType select in the generated HTML. This can be done in FormBuilder's `_buildInputHTML` by checking if the field name is `loopType`.

- [ ] **Step 3: Collect loop type and for-each fields**

In `_collectFormData()` (property_editor_controller.js), collect the new fields:

```javascript
// Collect loopType
const loopType = formData.get("loopType")
if (loopType) newProperties.loopType = loopType

// Collect for-each fields
if (loopType === "for_each") {
  newProperties.collection = formData.get("collection") || ""
  newProperties.itemVariable = formData.get("itemVariable") || "item"
  newProperties.indexVariable = formData.get("indexVariable") || ""
}
```

- [ ] **Step 4: Update ActivityGenerator for loop types**

In `app/services/activity_generator.rb`, update the loop code generation (around lines 429-447):

```ruby
def generate_loop_body(element, method_name)
  props = element["properties"] || {}
  loop_type = props["loopType"] || "while"
  max_iterations = (props["iterations"] || 10).to_i
  condition = props["condition"]

  case loop_type
  when "for_each"
    generate_for_each_loop(props, max_iterations)
  when "do_while"
    generate_do_while_loop(condition, max_iterations)
  else # "while"
    generate_while_loop(condition, max_iterations)
  end
end

def generate_for_each_loop(props, max_iterations)
  collection = condition_operand_to_ruby(props["collection"] || "[]")
  item_var = props["itemVariable"] || "item"
  index_var = props["indexVariable"]

  code = "# For-each loop with safety limit\n"
  code += "collection = #{collection}\n"
  code += "collection = collection.is_a?(Array) ? collection : [collection]\n"
  code += "collection.take(#{max_iterations}).#{index_var.present? ? "each_with_index" : "each"} do |#{item_var}#{index_var.present? ? ", #{index_var}" : ""}|\n"
  code += "  ctx[:#{item_var}] = #{item_var}\n"
  code += "  ctx[:#{index_var}] = #{index_var}\n" if index_var.present?
  code
end

def generate_do_while_loop(condition, max_iterations)
  condition_ruby = build_structured_condition(condition)

  code = "# Do-while loop (executes at least once)\n"
  code += "ctx[:_loop_iteration_count] = 0\n"
  code += "loop do\n"
  code += "  ctx[:_loop_iteration_count] += 1\n"
  code += "  break if ctx[:_loop_iteration_count] > #{max_iterations}\n"
  code
  # Note: the condition check and break is added after the loop body
end

def generate_while_loop(condition, max_iterations)
  condition_ruby = build_structured_condition(condition)

  code = "# While loop with safety limit\n"
  code += "ctx[:_loop_iteration_count] = (ctx[:_loop_iteration_count] || 0) + 1\n"
  code += "return false if ctx[:_loop_iteration_count] > #{max_iterations}\n"
  code += "\n#{condition_ruby}\n" if condition_ruby != "true"
  code
end
```

- [ ] **Step 5: Write and run specs for loop types**

Add to the existing loop specs in `spec/services/activity_generator_spec.rb` or the compound conditions spec file:

```ruby
describe "loop type code generation" do
  context "for-each loop" do
    let(:flowchart) do
      create(:flowchart, entity: entity, configuration: {
        elements: [
          { id: "el_1", type: "start", x: 100, y: 100, width: 100, height: 45, label: "Start", properties: { inputs: [], outputs: [] } },
          { id: "el_2", type: "loop", x: 100, y: 200, width: 100, height: 45, label: "Each Item",
            properties: {
              inputs: [], outputs: [],
              loopType: "for_each",
              collection: "ctx.model.items",
              itemVariable: "item",
              indexVariable: "index",
              iterations: 100
            }
          },
          { id: "el_3", type: "end", x: 100, y: 300, width: 100, height: 45, label: "End", properties: {} }
        ],
        connections: [
          { id: "c1", from: "el_1", to: "el_2" },
          { id: "c2", from: "el_2", to: "el_3" }
        ],
        metadata: {}
      }.to_json)
    end

    it "generates for-each loop code" do
      code = described_class.new(flowchart).generate
      expect(code).to include("each_with_index")
      expect(code).to include("ctx[:item]")
    end
  end
end
```

Run: `bundle exec rspec spec/services/ --format progress`

- [ ] **Step 6: Verify loop types**

Manual verification:
1. Open Loop element properties → Loop Type dropdown appears (defaults to "While")
2. Select "For-Each" → collection/itemVariable/indexVariable fields appear, condition hides
3. Select "Do-While" → condition shows, for-each fields hide
4. Select "While" → same as current behavior
5. Save each type → properties persist correctly
6. Generated code matches expected pattern for each type

- [ ] **Step 7: Commit**

```bash
git add app/javascript/flowchart/constants/schemas.js app/javascript/controllers/property_editor/form_builder.js app/javascript/controllers/property_editor_controller.js app/services/activity_generator.rb spec/
git commit -m "feat: loop type selection (while, do-while, for-each) with conditional fields"
```

---

## Verification Checklist

After all tasks are complete:

- [ ] **Connection Properties:** Double-click connection for inline label, click for property editor sidebar, labels persist
- [ ] **Element Styles:** Color picker in property editor, elements render with custom colors, styles persist
- [ ] **Compound Conditions:** AND/OR groups, add/remove rows, toggle operator, legacy backward compatible, code generates correctly
- [ ] **Loop Types:** While/Do-While/For-Each with conditional field visibility, code generates correctly
- [ ] **No Regressions:** All existing features work, all RSpec tests pass
