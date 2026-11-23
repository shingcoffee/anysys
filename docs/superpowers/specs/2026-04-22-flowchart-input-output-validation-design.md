# Flowchart Input/Output Validation Design

## Overview

Validate that all input items (including overridden ones) in a flowchart have corresponding output items from reachable upstream elements. This validation runs on-demand via the toolbar validate button and blocks activation of draft flowcharts that fail validation.

## Requirements

1. For every element in the flowchart, validate that each input pin (using its effective key after overrides) has a corresponding output from a reachable upstream element
2. Exclude configurable "implicit" context keys that are always available (e.g., `bound_entity`, `customer_id`, `params`)
3. Implicit keys are defined in a config file, not hardcoded
4. Validation triggers from:
   - Toolbar validate button (client-side, fast feedback)
   - Activation attempt (server-side, authoritative)
5. Failed activation redirects to edit page with Problems tab showing errors

## Architecture

### Hybrid Approach

- **Client-side validation** for toolbar button using cached element pins (fast feedback during editing)
- **Server-side validation** as authoritative check for activation (prevents invalid flowcharts from being activated regardless of client behavior)
- Both implementations share the same algorithm and read from the same config file

## Components

### 1. Configuration File

**File:** `config/flowchart_validation.yml`

```yaml
implicit_context_keys:
  - bound_entity
  - customer_id
  - params
  - current_user
  - current_customer
```

### 2. Server-Side Validation Service

**File:** `app/services/flowchart_input_output_validator.rb`

**Responsibilities:**
- Parse flowchart configuration (elements, connections)
- Build reachability graph (which elements are upstream of each element)
- Collect effective outputs per element (pin name or `renamed_to` if overridden)
- Validate each element's inputs have upstream outputs or are implicit keys
- Return list of errors

**Interface:**
```ruby
result = FlowchartInputOutputValidator.call(flowchart)
result.valid?      # => true/false
result.errors      # => [{ element_id:, element_label:, missing_input:, message: }, ...]
```

**Algorithm:**
1. Load implicit keys from config file
2. Parse elements and connections from `flowchart.configuration_json`
3. For each element, call `IoExtractor.call_element(element_type, properties)` to get pins
4. Build map of `element_id -> effective_output_keys` (applying `io_overrides.outputs[].renamed_to`)
5. Build reachability: for each element, compute set of upstream element IDs via BFS on reversed connection graph
6. For each element:
   - Get input pins from IoExtractor
   - Apply `io_overrides.inputs[].override_key` to get effective input key
   - For each effective input key:
     - Skip if override_key is empty string (tombstone - user explicitly said "no producer needed")
     - Skip if in implicit keys list
     - Check if any upstream element's effective outputs contain this key
     - If not found, add to errors

### 3. Client-Side Validation Service

**File:** `app/javascript/flowchart/input_output_validation_service.js`

**Responsibilities:**
- Fetch and cache implicit keys from server endpoint
- Use existing `ElementReachability` for upstream computation
- Use cached element pins from `canvas.getElementPins()`
- Apply same validation algorithm as server-side
- Return errors in same format as `ValidationService`

**Interface:**
```javascript
const validator = new InputOutputValidationService(canvas)
await validator.loadImplicitKeys() // one-time fetch
const errors = validator.validate()
// => [{ elementId, type: 'missing_input', message: '...' }, ...]
```

### 4. Implicit Keys Endpoint

**Route:** `GET /flowchart_validation/implicit_keys.json`

**Controller:** `FlowchartValidationController#implicit_keys`

**Response:**
```json
{
  "implicit_keys": ["bound_entity", "customer_id", "params", "current_user", "current_customer"]
}
```

### 5. Controller Changes

**File:** `app/controllers/flowcharts_controller.rb`

**Modified action: `activate`**

```ruby
def activate
  validator = FlowchartInputOutputValidator.call(@flowchart)
  
  if validator.errors.any?
    flash[:validation_errors] = validator.errors.to_json
    flash[:alert] = "Cannot activate: #{validator.errors.size} input(s) missing upstream outputs"
    redirect_to edit_flowchart_path(current_customer_id, @flowchart, show_validation: true)
    return
  end
  
  # existing activation logic...
  @flowchart.update!(status: :active)
  redirect_to flowchart_path(current_customer_id, @flowchart), notice: 'Flowchart activated successfully.'
end
```

### 6. Canvas Controller Integration

**File:** `app/javascript/controllers/flowchart_canvas_controller.js`

**Modified `validate()` method:**

```javascript
async validate() {
  // Existing structural validation
  const structuralValidator = new ValidationService(this.canvas.elements, this.canvas.connections)
  const { errors: structuralErrors, warnings } = structuralValidator.validate()
  
  // New input/output validation
  const ioValidator = new InputOutputValidationService(this.canvas)
  await ioValidator.loadImplicitKeys()
  const ioErrors = ioValidator.validate()
  
  // Merge results
  const allErrors = [...structuralErrors, ...ioErrors]
  this._showValidationResults(allErrors, warnings)
  
  return allErrors.length === 0
}
```

### 7. Edit Page Auto-Validation

**File:** `app/views/flowcharts/_editor.html.erb`

Add data attribute when `show_validation` param present:

```erb
data-flowchart-canvas-auto-validate-value="<%= params[:show_validation] == 'true' %>"
```

**File:** `app/javascript/controllers/flowchart_canvas_controller.js`

In `_onCanvasReady()`:

```javascript
if (this.autoValidateValue) {
  requestAnimationFrame(() => this.validate())
}
```

## Error Format

Errors are displayed in the Problems tab with:

| Field | Value |
|-------|-------|
| type | `missing_input` |
| severity | `error` |
| elementId | ID of element with missing input |
| message | `Input "user_id" has no upstream output` |

Clicking an error focuses the problematic element on the canvas.

## File Changes Summary

| File | Change |
|------|--------|
| `config/flowchart_validation.yml` | New - implicit keys config |
| `app/services/flowchart_input_output_validator.rb` | New - server-side validator |
| `app/controllers/flowchart_validation_controller.rb` | New - implicit keys endpoint |
| `app/javascript/flowchart/input_output_validation_service.js` | New - client-side validator |
| `app/controllers/flowcharts_controller.rb` | Modified - add validation to `activate` |
| `app/javascript/controllers/flowchart_canvas_controller.js` | Modified - integrate I/O validation |
| `app/views/flowcharts/_editor.html.erb` | Modified - add auto-validate data attribute |
| `config/routes.rb` | Modified - add implicit_keys route |

## Testing

### Server-Side Tests

- `spec/services/flowchart_input_output_validator_spec.rb`
  - Valid flowchart with all inputs satisfied
  - Invalid flowchart with missing upstream output
  - Implicit keys are excluded from validation
  - Override keys (renamed inputs/outputs) are handled correctly
  - Unreachable elements don't satisfy inputs

### Controller Tests

- `spec/controllers/flowcharts_controller_spec.rb`
  - Activation blocked when validation fails
  - Redirect to edit page with show_validation param
  - Flash contains error details
  - Activation succeeds when validation passes

### JavaScript Tests

- `spec/javascript/flowchart/input_output_validation_service_spec.js`
  - Validates inputs against upstream outputs
  - Handles io_overrides correctly
  - Excludes implicit keys
  - Returns errors in correct format
