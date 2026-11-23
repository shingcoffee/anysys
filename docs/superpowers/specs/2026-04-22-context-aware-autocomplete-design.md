# Context-Aware Autocomplete for Property Editor Config Fields

## Summary

Add autocomplete functionality to step config fields in the property editor so users can easily reference available context variables from upstream elements, prior steps, and implicit runtime keys.

## Problem

When configuring flowchart steps, users must manually type context variable references (e.g., `email`, `model`, `user_id`). There's no UI assistance showing what variables are actually available at that point in the flowchart. This leads to:
- Typos in variable names causing runtime errors
- Users not knowing what upstream outputs exist
- Difficulty discovering implicit keys like `params`, `current_user`

## Solution

Implement an autocomplete dropdown that appears when typing in text/textarea config fields, showing available variables grouped by their source.

## Requirements

### Trigger Behavior
- Autocomplete activates on any typing in text/textarea config fields
- Not applied to `key_value_list` field types

### Variable Sources (in display order)
1. **Implicit keys** — Always available runtime context (`params`, `current_user`, `customer_id`, `bound_entity`, `current_customer`)
2. **Upstream element outputs** — Outputs from elements connected upstream in the flowchart, grouped by element with canvas label displayed
3. **Prior step outputs** — Outputs from earlier steps within the same Process element

### Display Format
- Variables grouped by source
- Group headers show element labels (e.g., "From 'Validate User Input'")
- For collision-renamed variables, show only the effective (renamed) key

### Selection Behavior
- Insert just the variable name (e.g., `email`, not `ctx[:email]`)
- Keyboard navigation: Arrow keys, Enter/Tab to select, Escape to close

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Property Editor                          │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Step Config Field (text input)                       │   │
│  │  data-controller="context-autocomplete"              │   │
│  │  data-context-autocomplete-element-id-value="..."    │   │
│  │  data-context-autocomplete-step-index-value="..."    │   │
│  └─────────────────────────────────────────────────────┘   │
│                          │                                  │
│                          ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ context-autocomplete Stimulus Controller             │   │
│  │  - Listens for input events                          │   │
│  │  - Queries ContextVariableProvider                   │   │
│  │  - Renders/positions dropdown                        │   │
│  │  - Handles selection & keyboard navigation           │   │
│  └─────────────────────────────────────────────────────┘   │
│                          │                                  │
│                          ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ ContextVariableProvider                              │   │
│  │  - Collects implicit keys (cached from server)       │   │
│  │  - Collects upstream element outputs                 │   │
│  │  - Collects prior step outputs within element        │   │
│  │  - Returns grouped, labeled results                  │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Component Details

### ContextVariableProvider

**Location:** `app/javascript/flowchart/context_variable_provider.js`

**API:**
```javascript
getAvailableVariables(canvas, elementId, stepIndex?)
// Returns:
{
  groups: [
    {
      label: "Always Available",
      source: "implicit",
      variables: ["params", "current_user", ...]
    },
    {
      label: "From 'Validate User Input'",
      source: "element",
      sourceId: "elem_abc123",
      variables: ["user", "email", ...]
    },
    {
      label: "From 'Find Model' (this element)",
      source: "step",
      sourceId: "step_xyz789",
      variables: ["model"]
    }
  ]
}
```

**Key Methods:**
- `getAvailableVariables(canvas, elementId, stepIndex?)` — main entry point
- `_getImplicitKeys()` — returns cached implicit keys, fetches if needed
- `_getUpstreamOutputs(canvas, elementId)` — uses ElementReachability + getElementPins
- `_getPriorStepOutputs(canvas, elementId, stepIndex)` — outputs from steps 0..stepIndex-1

**Dependencies:**
- Reuses `ElementReachability` from `controllers/property_editor/element_io/reachability.js`
- Reuses implicit keys endpoint `/flowchart_validation/implicit_keys.json`

### context-autocomplete Stimulus Controller

**Location:** `app/javascript/controllers/context_autocomplete_controller.js`

**Values:**
- `elementId` (String) — current flowchart element being edited
- `stepIndex` (Number) — index of current step (-1 for element-level fields)

**Lifecycle:**
- `connect()` — bind input/keydown/blur listeners, get canvas reference via `document.querySelector('[data-controller*="flowchart-canvas"]').flowchartCanvas`
- `disconnect()` — remove listeners, destroy dropdown if open

**Event Handling:**
- `onInput()` — query provider, filter by typed text, render dropdown
- `onKeydown()` — handle arrow navigation, Enter/Tab selection, Escape close
- `onBlur()` — close dropdown after short delay (allows click on option)
- `onSelect(variable)` — insert variable at cursor, close dropdown, dispatch input event

### Dropdown UI

**Rendering:** Appended to `document.body` to avoid overflow clipping.

**Positioning:** Fixed position below input field, flips above if near viewport bottom.

**HTML Structure:**
```html
<div class="context-autocomplete-dropdown"
     style="position: fixed; z-index: 9999;">
  <div class="context-autocomplete-group">
    <div class="context-autocomplete-group-label">Always Available</div>
    <div class="context-autocomplete-option" data-value="params">params</div>
    ...
  </div>
  ...
</div>
```

**Styling (TailwindCSS):**
- Dropdown container: `bg-white border border-slate-200 rounded-lg shadow-lg max-h-64 overflow-y-auto w-64`
- Group label: `px-2 py-1 text-[10px] font-semibold text-slate-500 uppercase tracking-wide bg-slate-50 sticky top-0`
- Option: `px-3 py-1.5 text-xs text-slate-700 cursor-pointer hover:bg-indigo-50`
- Selected option: `bg-indigo-100 text-indigo-900`

**Empty State:** "No matching variables"

## Integration

### Template Changes

**File:** `app/javascript/controllers/property_editor/templates.js`

Modify `buildConfigTextField` and `buildConfigTextareaField` to add Stimulus controller attributes:

```javascript
function buildConfigTextField(field, value, context = {}) {
  const { elementId, stepIndex } = context
  const controllerAttrs = elementId
    ? `data-controller="context-autocomplete"
       data-context-autocomplete-element-id-value="${escapeHtml(elementId)}"
       data-context-autocomplete-step-index-value="${stepIndex ?? -1}"`
    : ""
  
  return `<input type="text"
    data-config-input="${escapeHtml(field.key)}"
    ${controllerAttrs}
    value="${escapeHtml(String(value))}"
    ...>`
}
```

Update `buildStepConfigFieldsHTML` signature:
```javascript
// Current:
export function buildStepConfigFieldsHTML(configSchema, currentConfig = {})

// New:
export function buildStepConfigFieldsHTML(configSchema, currentConfig = {}, context = {})
```

### StepManager Changes

**File:** `app/javascript/controllers/property_editor/step_manager.js`

When calling `buildStepConfigFieldsHTML`, pass context:
```javascript
const configFieldsHTML = buildStepConfigFieldsHTML(
  actionOptionData.configSchema,
  step.config || {},
  {
    elementId: this.controller.currentElement.id,
    stepIndex: index,
    canvas: this.controller.canvas
  }
)
```

### Controller Registration

**File:** `app/javascript/controllers/index.js`

Add import and registration for `context-autocomplete` controller.

## File Changes Summary

**New Files:**
| File | Purpose |
|------|---------|
| `app/javascript/flowchart/context_variable_provider.js` | Collects and groups available context variables |
| `app/javascript/controllers/context_autocomplete_controller.js` | Stimulus controller for autocomplete behavior |

**Modified Files:**
| File | Changes |
|------|---------|
| `app/javascript/controllers/property_editor/templates.js` | Add controller attributes to text/textarea config fields |
| `app/javascript/controllers/property_editor/step_manager.js` | Pass context (elementId, stepIndex) to template builder |
| `app/javascript/controllers/index.js` | Register context-autocomplete controller |

## Testing

### Unit Tests

**ContextVariableProvider** (`spec/javascript/flowchart/context_variable_provider_spec.js`):
- Returns implicit keys in first group
- Returns upstream element outputs with correct labels
- Returns prior step outputs with "(this element)" suffix
- Handles renamed (collision) variables — shows effective key only
- Filters variables by search term
- Returns empty groups gracefully

### Integration Tests

Manual or system spec verification:
- Typing in config field shows dropdown
- Dropdown positioned correctly (below input, or above if near bottom)
- Arrow keys navigate options, visual highlight follows
- Enter/Tab inserts selected variable name
- Escape closes dropdown without inserting
- Click on option inserts variable
- Click outside closes dropdown
- Variables grouped correctly by source
- Filtering works as user types

## Non-Goals

- Autocomplete for `key_value_list` fields (kept as plain text)
- Autocomplete for element-level fields (future enhancement)
- Type information for variables (all treated as strings for now)
- Nested property access (e.g., `user.email`) — only top-level keys

## Future Considerations

- Could extend to element-level config fields (Start, End, Loop elements)
- Could add type hints if pin metadata includes type information
- Could support dot-notation for nested access with sub-property suggestions
