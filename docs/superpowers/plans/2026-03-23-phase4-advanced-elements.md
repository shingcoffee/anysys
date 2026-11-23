# Phase 4: Advanced Elements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand the flowchart element types and step capabilities — add fork/join for parallel modeling, start trigger types, end response configuration, per-step retry/timeout, and conditional step execution.

**Architecture:** Element types are defined in constants (elements.js, schemas.js), rendered by ElementRendererMixin, and represented in the palette via ViewComponents. The ActivityGenerator uses DFS traversal to collect steps and generate Trailblazer Activity code. Step configuration is managed by StepManager with templates from templates.js.

**Tech Stack:** StimulusJS, vanilla SVG, TailwindCSS, ViewComponent, Rails, RSpec.

**Spec Reference:** `docs/superpowers/specs/2026-03-23-anysys-industry-standard-audit-design.md` — Items #16, #19, #20, #21, #22

---

## Task 1: Start Element Trigger Types (#21)

**Files:**
- Modify: `app/javascript/flowchart/constants/schemas.js` — add triggerType to start schema
- Modify: `app/javascript/controllers/property_editor/form_builder.js` — conditional field visibility for trigger-specific fields
- Modify: `app/javascript/controllers/property_editor_controller.js` — collect trigger fields
- Modify: `app/services/activity_generator.rb` — generate trigger metadata comment

### Implementation:

- [ ] **Step 1: Add triggerType to start schema**

In schemas.js, update the `start` entry in ELEMENT_SCHEMAS to add trigger type and trigger-specific fields:

```javascript
start: {
  triggerType: {
    label: "Trigger Type", type: "select",
    options: [
      { value: "manual", label: "Manual Trigger" },
      { value: "http", label: "HTTP Request" },
      { value: "event", label: "Event Listener" },
      { value: "schedule", label: "Scheduled (Cron)" }
    ],
    default: "manual"
  },
  httpMethod: { label: "HTTP Method", type: "select", options: [
    { value: "GET", label: "GET" }, { value: "POST", label: "POST" },
    { value: "PUT", label: "PUT" }, { value: "PATCH", label: "PATCH" },
    { value: "DELETE", label: "DELETE" }
  ], default: "POST", visibleWhen: { triggerType: "http" } },
  httpPath: { label: "Path Pattern", type: "text", placeholder: "/api/v1/resource", visibleWhen: { triggerType: "http" } },
  eventName: { label: "Event Name", type: "text", placeholder: "user.created", visibleWhen: { triggerType: "event" } },
  cronExpression: { label: "Cron Expression", type: "text", placeholder: "0 */5 * * *", visibleWhen: { triggerType: "schedule" } },
  ...COMMON_PROPERTIES,
  style: { label: "Style", type: "style" }
}
```

- [ ] **Step 2: Add change handler for trigger type visibility**

In `property_editor_controller.js`, add `handleTriggerTypeChange(event)` that toggles `visibleWhen` fields (same pattern as loopType). The FormBuilder's existing `visibleWhen` support should handle initial rendering. Add `data-action="change->property-editor#handleTriggerTypeChange"` via the schema.

- [ ] **Step 3: Update ActivityGenerator for trigger metadata**

In `activity_generator.rb`, in the `header` method, add a comment block with trigger metadata:

```ruby
def header(steps)
  trigger = start_element&.dig("properties", "triggerType") || "manual"
  trigger_comment = case trigger
  when "http"
    method = start_element&.dig("properties", "httpMethod") || "POST"
    path = start_element&.dig("properties", "httpPath") || "/api/resource"
    "# Trigger: HTTP #{method} #{path}"
  when "event"
    "# Trigger: Event #{start_element&.dig("properties", "eventName")}"
  when "schedule"
    "# Trigger: Schedule #{start_element&.dig("properties", "cronExpression")}"
  else
    "# Trigger: Manual"
  end
  # Prepend to existing header output
end
```

- [ ] **Step 4: Verify and test**

---

## Task 2: End Element Response Configuration (#22)

**Files:**
- Modify: `app/javascript/flowchart/constants/schemas.js` — add response fields to end schema
- Modify: `app/services/activity_generator.rb` — generate response code

### Implementation:

- [ ] **Step 1: Add response fields to end schema**

In schemas.js, update the `end` entry:

```javascript
end: {
  ...COMMON_PROPERTIES,
  responseType: {
    label: "Response Type", type: "select",
    options: [
      { value: "none", label: "None (default)" },
      { value: "value", label: "Return Value" },
      { value: "http_response", label: "HTTP Response" }
    ],
    default: "none"
  },
  returnValue: { label: "Return Value", type: "text", placeholder: "ctx.model", visibleWhen: { responseType: "value" } },
  httpStatus: { label: "HTTP Status", type: "number", placeholder: "200", visibleWhen: { responseType: "http_response" } },
  responseBody: { label: "Response Body Field", type: "text", placeholder: "ctx.response", visibleWhen: { responseType: "http_response" } },
  style: { label: "Style", type: "style" }
}
```

- [ ] **Step 2: Add change handler for response type**

In `property_editor_controller.js`, add `handleResponseTypeChange(event)` using the same `visibleWhen` toggle pattern.

- [ ] **Step 3: Update ActivityGenerator for end element response**

Generate response code in the final step method when end element has response config:

```ruby
def generate_end_response(end_element)
  props = end_element["properties"] || {}
  response_type = props["responseType"] || "none"
  case response_type
  when "value"
    field = props["returnValue"] || "ctx"
    "ctx[:result] = #{condition_operand_to_ruby(field)}"
  when "http_response"
    status = props["httpStatus"] || 200
    body_field = props["responseBody"] || "ctx"
    "ctx[:http_status] = #{status}\nctx[:http_body] = #{condition_operand_to_ruby(body_field)}"
  else
    nil
  end
end
```

- [ ] **Step 4: Verify and test**

---

## Task 3: Retry/Timeout on Process Steps (#19)

**Files:**
- Modify: `app/javascript/controllers/property_editor/templates.js` — add retry/timeout fields to step modal
- Modify: `app/javascript/controllers/property_editor/step_manager.js` — collect retry/timeout data
- Modify: `app/services/activity_generator.rb` — generate retry/timeout wrapper code

### Implementation:

- [ ] **Step 1: Add retry/timeout fields to step modal template**

In `templates.js`, in `buildStepModalTemplate()`, add a collapsible "Advanced" section before the description textarea:

```javascript
<!-- Advanced Configuration (collapsible) -->
<div class="border-t border-gray-100 pt-3">
  <button type="button" data-action="click->property-editor#toggleStepAdvanced"
          class="flex items-center text-sm text-gray-500 hover:text-gray-700 mb-2">
    <svg class="w-3 h-3 mr-1 transition-transform" data-step-advanced-chevron fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/>
    </svg>
    Advanced
  </button>
  <div data-step-advanced-section class="hidden space-y-3">
    <div class="grid grid-cols-2 gap-3">
      <div>
        <label class="block text-xs font-medium text-gray-600 mb-1">Max Retries</label>
        <input type="number" data-step-modal-target="retryCount" min="0" max="5" value="0" placeholder="0"
               class="block w-full rounded-md border-gray-300 text-sm focus:border-indigo-500 focus:ring-indigo-500">
      </div>
      <div>
        <label class="block text-xs font-medium text-gray-600 mb-1">Timeout (seconds)</label>
        <input type="number" data-step-modal-target="timeout" min="0" placeholder="0"
               class="block w-full rounded-md border-gray-300 text-sm focus:border-indigo-500 focus:ring-indigo-500">
      </div>
    </div>
    <div>
      <label class="block text-xs font-medium text-gray-600 mb-1">Retry Backoff</label>
      <select data-step-modal-target="retryBackoff"
              class="block w-full rounded-md border-gray-300 text-sm focus:border-indigo-500 focus:ring-indigo-500">
        <option value="none">None</option>
        <option value="linear">Linear</option>
        <option value="exponential">Exponential</option>
      </select>
    </div>
  </div>
</div>
```

- [ ] **Step 2: Collect retry/timeout in StepManager**

In `step_manager.js`, update `addStepFromModal()` to collect:
```javascript
const retryCount = parseInt(modal.querySelector('[data-step-modal-target="retryCount"]')?.value || "0")
const timeout = parseInt(modal.querySelector('[data-step-modal-target="timeout"]')?.value || "0")
const retryBackoff = modal.querySelector('[data-step-modal-target="retryBackoff"]')?.value || "none"
```

Add to step data and hidden inputs in `buildStepItemTemplate()`.

- [ ] **Step 3: Generate retry/timeout wrapper in ActivityGenerator**

```ruby
def wrap_with_retry(code, step)
  retry_count = step.dig("retryCount")&.to_i || 0
  timeout = step.dig("timeout")&.to_i || 0

  return code if retry_count == 0 && timeout == 0

  wrapped = ""
  if timeout > 0
    wrapped += "Timeout.timeout(#{timeout}) do\n"
  end

  if retry_count > 0
    backoff = step["retryBackoff"] || "none"
    wrapped += "retries = 0\nbegin\n#{code}\nrescue => e\n  retries += 1\n"
    wrapped += "  raise if retries > #{retry_count}\n"
    case backoff
    when "linear" then wrapped += "  sleep(retries)\n"
    when "exponential" then wrapped += "  sleep(2 ** retries)\n"
    end
    wrapped += "  retry\nend\n"
  else
    wrapped += code + "\n"
  end

  wrapped += "end\n" if timeout > 0
  wrapped
end
```

- [ ] **Step 4: Add toggle handler**

In `property_editor_controller.js`, add `toggleStepAdvanced(event)` to toggle the advanced section visibility and rotate the chevron.

- [ ] **Step 5: Verify and test**

---

## Task 4: Conditional Execution Per Step (#20)

**Files:**
- Modify: `app/javascript/controllers/property_editor/templates.js` — add guard condition field
- Modify: `app/javascript/controllers/property_editor/step_manager.js` — collect guard
- Modify: `app/services/activity_generator.rb` — wrap step in guard condition

### Implementation:

- [ ] **Step 1: Add guard condition to step modal**

In the "Advanced" section of the step modal (added in Task 3), add a guard condition field:

```javascript
<div>
  <label class="block text-xs font-medium text-gray-600 mb-1">Guard Condition</label>
  <p class="text-xs text-gray-400 mb-1">Step only runs if this is true</p>
  <input type="text" data-step-modal-target="guardCondition"
         placeholder="e.g., ctx[:user_role] == 'admin'"
         class="block w-full rounded-md border-gray-300 text-sm focus:border-indigo-500 focus:ring-indigo-500">
</div>
```

- [ ] **Step 2: Collect and persist guard condition**

In `addStepFromModal()`, collect:
```javascript
const guardCondition = modal.querySelector('[data-step-modal-target="guardCondition"]')?.value?.trim() || ""
```

Add to step data. Add hidden input in `buildStepItemTemplate()`.

- [ ] **Step 3: Generate guard wrapper in ActivityGenerator**

```ruby
def wrap_with_guard(code, step)
  guard = step["guardCondition"]
  return code if guard.blank?
  "if #{guard}\n#{code}\nend"
end
```

Apply guard before retry wrapper (guard → retry → timeout → actual code).

- [ ] **Step 4: Verify and test**

---

## Task 5: Fork/Join Parallel Elements (#16)

**Files:**
- Create: `app/components/flowchart_elements/fork_element_component.rb`
- Create: `app/components/flowchart_elements/join_element_component.rb`
- Modify: `app/javascript/flowchart/constants/elements.js` — fork/join colors and labels
- Modify: `app/javascript/flowchart/constants/schemas.js` — fork/join schemas
- Modify: `app/javascript/flowchart/element_renderer.js` — fork/join shape rendering
- Modify: `app/views/flowcharts/_editor.html.erb` — add fork/join to palette
- Modify: `app/javascript/flowchart/validation_service.js` — fork/join validation rules
- Modify: `app/services/activity_generator.rb` — sequential execution of fork branches

### Implementation:

- [ ] **Step 1: Add fork/join constants**

In `elements.js`:
```javascript
// Add to ELEMENT_COLORS:
fork: { fill: "#eef2ff", stroke: "#6366f1" },  // Indigo
join: { fill: "#eef2ff", stroke: "#6366f1" }    // Indigo (same)

// Add to DEFAULT_LABELS:
fork: "Fork",
join: "Join"
```

- [ ] **Step 2: Add fork/join schemas**

In `schemas.js`:
```javascript
fork: {
  ...COMMON_PROPERTIES,
  style: { label: "Style", type: "style" }
},
join: {
  ...COMMON_PROPERTIES,
  mergeStrategy: {
    label: "Merge Strategy", type: "select",
    options: [
      { value: "wait_all", label: "Wait for All" },
      { value: "wait_any", label: "Wait for Any" }
    ],
    default: "wait_all"
  },
  style: { label: "Style", type: "style" }
}
```

Add to `getDefaultPropertiesForType()` to handle fork/join types.

- [ ] **Step 3: Add fork/join shape rendering**

In `element_renderer.js`, add shape cases for fork and join. Fork/Join use a horizontal bar shape (BPMN convention):

```javascript
case "fork":
case "join":
  return this._createBarShape(element, effectiveColors)
```

Add `_createBarShape()`:
```javascript
_createBarShape(element, colors) {
  const barHeight = Math.min(element.height * 0.3, 12)
  const y = (element.height - barHeight) / 2
  return createRect(0, y, element.width, barHeight, {
    fill: colors.stroke,  // Solid fill with stroke color
    rx: 3, ry: 3
  })
}
```

- [ ] **Step 4: Create palette components**

Create `app/components/flowchart_elements/fork_element_component.rb`:
```ruby
module FlowchartElements
  class ForkElementComponent < BaseElementComponent
    def element_type = "fork"
    def element_label = "Fork"
    def element_specific_classes
      "bg-indigo-50 border-indigo-400 text-indigo-800 hover:border-indigo-600"
    end
  end
end
```

Create similar for `JoinElementComponent`.

Add fork/join to the palette in `_editor.html.erb` (in the "Basic Elements" section).

- [ ] **Step 5: Add validation rules for fork/join**

In `validation_service.js`, add:
- Fork must have 2+ outgoing connections
- Join must have 2+ incoming connections
- No nested fork/join (max 1 level)

- [ ] **Step 6: Update ActivityGenerator for fork/join**

In `dfs_collect_steps()`, when encountering a fork element:
- Collect all outgoing branches separately
- Execute each branch sequentially (initial implementation)
- Skip fork/join elements themselves (no method generated)

```ruby
# In dfs_visit, when element type is "fork":
# Collect all children, process each branch to its join point
# Generate sequential execution of branches

# In step_declarations, skip fork/join types:
next if %w[fork join].include?(s[:element]["type"])
```

- [ ] **Step 7: Write specs and verify**

Add specs for fork/join code generation ensuring branches execute sequentially.

- [ ] **Step 8: Commit**

---

## Verification Checklist

- [ ] **Start Triggers:** Trigger type dropdown, conditional fields show/hide, metadata in generated code
- [ ] **End Response:** Response type dropdown, return value/HTTP status fields, response code generated
- [ ] **Retry/Timeout:** Step modal advanced section, retry/timeout fields collected, wrapper code generated
- [ ] **Guard Conditions:** Guard field in step modal, conditional wrapper in generated code
- [ ] **Fork/Join:** New elements in palette, bar shape rendering, validation rules, sequential branch execution
- [ ] **No Regressions:** All specs pass, existing features work
