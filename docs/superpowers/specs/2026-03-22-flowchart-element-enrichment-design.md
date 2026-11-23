# Flowchart Element Property Enrichment & Functional Step Actions — Design Spec

## Overview

Enrich the property schemas for existing flowchart elements and make the currently non-functional step actions (transform, API_call, notify, render_response) fully operational with rich configuration and code generation.

**Priority order:**
1. Enrich existing element properties (Process error handling, Decision context-aware operands, Loop structured condition)
2. Make unused step actions functional with full-featured configuration

---

## Part 1: Enriched Existing Element Properties

### 1.1 Process Element — Error Handling

**Current state:** Process elements have inputs, steps, outputs, and description. No error handling configuration exists. When a step fails in the generated Trailblazer Railway activity, the failure propagates up with no control.

**Design:**

Add a new `errorHandling` property section to the Process element schema, positioned between `steps` and `outputs` (since error handling logically relates to step execution):

```javascript
process: {
  inputs: COMMON_PROPERTIES.inputs,
  steps: { type: "steps", label: "Steps", actionOptions: STEP_ACTIONS },
  errorHandling: { type: "error_handling", label: "Error Handling" },
  outputs: COMMON_PROPERTIES.outputs,
  description: { ...COMMON_PROPERTIES.description }
}
```

**Property structure:**
```json
{
  "errorHandling": {
    "mode": "halt",
    "errorOutputField": "ctx.error"
  }
}
```

**Mode options:**
| Mode | Label | Description | Generated Code |
|------|-------|-------------|----------------|
| `halt` | Halt on Failure | Stop execution immediately on any step failure (default, current behavior) | Standard Railway `fail` track — no additional code |
| `route_to_error_end` | Route to Error End | On failure, write error details to a ctx field and continue to a designated failure output | Generates a `fail` handler that writes to `errorOutputField` and signals `:failure` |

**UI rendering — handled by FormBuilder:**

Add a new case to `FormBuilder._buildFieldHTML()`:
```javascript
if (fieldSchema.type === "error_handling") {
  return this._buildErrorHandlingFieldHTML(fieldName, fieldSchema, currentValue)
}
```

The `_buildErrorHandlingFieldHTML` method (added to `FormBuilder`) renders:
- A collapsible section with a mode dropdown (default: "halt")
- When mode is `route_to_error_end`:
  - Show "Error Output Field" text input (default: `ctx.error`)
  - The canvas renders an additional red connection handle on the element for the failure path
- When mode is `halt`: no additional fields shown

**Code generation in ActivityGenerator:**
- `halt` mode: no change to current generation — Railway's default failure track handles it
- `route_to_error_end` mode: generates a `fail :handle_error` step that captures the error into the configured ctx field and emits a `:failure` signal that can be routed via connections

```ruby
# Generated for route_to_error_end mode:
fail :handle_error_in_<element_label_slug> do |ctx, **|
  ctx[:error] = ctx["contract.default"]&.errors&.full_messages || ["An error occurred"]
end
```

### 1.2 Decision Element — Context-Aware Operands

**Current state:** The Decision condition builder in `BranchManager.buildConditionFieldHTML()` renders:
- **Left operand**: `<select>` with two fixed options: `signal` and `ctx`
- **Operator**: `<select>` with all `BRANCH_OPERATORS`
- **Right operand**: `<select>` with `TRB Activity Success` plus parent output options (from `_availableOutputOptions`)

This is very limited — users can only compare `signal` or `ctx` against a small fixed set of values.

**Design:**

Expand both operand dropdowns with richer, context-aware options. Both remain `<select>` dropdowns (not free-text).

**Left operand sources (expanded from current 2 options):**
1. **Current options** (preserved):
   - `signal` — the signal from the previous step
   - `ctx` — the full context object
2. **New common ctx fields:**
   - `ctx.model` — the current model instance
3. **Bound entity attributes** — all `name_slug` values from the flowchart's bound entity, prefixed with `ctx.model.` (e.g., `ctx.model.email`, `ctx.model.status`). Built from `canvas.entityAttributes` (already available).
4. **Parent element outputs** — dynamically resolved outputs from the parent element (reusing the existing connection traversal pattern from `FormBuilder._applyInheritedInputsFromParent`)

Displayed in the dropdown with `<optgroup>` separators for clarity:
```html
<optgroup label="Signals">
  <option value="signal">signal</option>
</optgroup>
<optgroup label="Context">
  <option value="ctx">ctx</option>
  <option value="ctx.model">ctx.model</option>
</optgroup>
<optgroup label="Entity Fields">
  <option value="ctx.model.email">ctx.model.email</option>
  <option value="ctx.model.status">ctx.model.status</option>
  ...
</optgroup>
<optgroup label="Parent Outputs">
  ...
</optgroup>
```

**Right operand sources (expanded):**
1. **Current options** (preserved): `TRB Activity Success` + parent output options
2. **New:** Same entity attribute options as left operand (for field-to-field comparisons)
3. **New:** A free-text option at the bottom: "Custom value..." — when selected, replaces the `<select>` with a text input so users can type arbitrary comparison values (e.g., `"active"`, `42`, `true`)

**Implementation location:** `BranchManager.buildConditionFieldHTML()` in `branch_manager.js`. Modify `leftOperandOptions` and `rightOperandOptions` arrays. Add a `change` handler on right operand that toggles between select and text input when "Custom value..." is selected.

**No schema change needed** — the condition data structure `{ leftOperand, operator, rightOperand }` remains the same. This is a UI improvement only.

### 1.3 Loop Element — Structured Condition

**Current state:** Loop condition is a free-text `<input type="text">` with placeholder "e.g., while count < 10". Max Iterations is a `<input type="number">`.

**Design:**

Replace the free-text condition with the same structured condition builder used by Decision. Change the schema:

```javascript
loop: {
  inputs: COMMON_PROPERTIES.inputs,
  condition: {
    type: "condition",   // Changed from "text" to "condition"
    label: "Loop Condition"
  },
  iterations: {
    type: "number",
    label: "Max Iterations",
    min: 1,
    placeholder: "10"
  },
  outputs: COMMON_PROPERTIES.outputs,
  description: { ...COMMON_PROPERTIES.description }
}
```

Since the `condition` type is now `"condition"`, `FormBuilder._buildFieldHTML()` already dispatches to `BranchManager.buildConditionFieldHTML()`, which will render the structured builder with the same context-aware operands from section 1.2.

**Condition data structure** (same as Decision):
```json
{
  "condition": {
    "leftOperand": "ctx.retry_count",
    "operator": "<",
    "rightOperand": "3"
  }
}
```

**Code generation in ActivityGenerator:**

The `iterations` property maps to a guard variable `ctx[:_loop_max_iterations]` set at the start of the loop. The structured condition generates a comparison check:

```ruby
step :check_loop_condition_<element_label_slug>

def check_loop_condition_<element_label_slug>(ctx, **)
  # Safety limit from iterations property
  max = 10 # from element properties.iterations
  ctx[:_loop_iteration_count] = (ctx[:_loop_iteration_count] || 0) + 1
  return false if ctx[:_loop_iteration_count] > max

  # Structured condition check
  ctx[:retry_count] < 3
end
```

**Backward compatibility:** If `condition` is a string (legacy free-text format), `BranchManager.buildConditionFieldHTML()` should detect this and render a migration prompt: "This loop uses a legacy text condition. Convert to structured?" with a one-click convert action. Until converted, the free-text value is preserved as-is.

---

## Part 2: Functional Step Actions

### Architecture

Each step action's configuration is rendered as a collapsible config panel inside the existing step modal. The panel appears below the action selector dropdowns when a step is being added or edited.

**Step data structure expansion:**
```json
{
  "action": "API_call",
  "selectionLabels": ["API", "Call"],
  "description": "Fetch user profile from external service",
  "keywordParams": [],
  "config": {
    // Action-specific configuration (new field)
  }
}
```

The `config` field is action-specific. Steps without a `config` field (existing steps, or actions like new_model that don't need config) continue to work unchanged.

**Step config panel lifecycle:**

1. User selects an action in the step modal dropdown (level 0)
2. `StepManager` checks if the action has a `configSchema` in `STEP_ACTIONS`
3. If yes, renders a config panel below the dropdown using a template function from `templates.js`
4. Config fields are standard HTML form inputs within `[data-step-config-panel]`
5. On "Add Step" / "Update Step", `StepManager.addStepFromModal()` collects config values from the panel and stores them in `step.config`
6. When editing an existing step, config panel is pre-populated from `step.config`
7. Repeatable row sections (mappings, headers, etc.) use add/remove buttons with `data-action` handlers on `StepManager`

**Stimulus actions added to StepManager:**
- `addConfigRow(event)` — adds a new repeatable row to a config section
- `removeConfigRow(event)` — removes a repeatable row
- `configFieldChanged(event)` — handles conditional field visibility (e.g., show body only for POST)

### Step Action Config Schemas

Added to each entry in `STEP_ACTIONS` in `schemas.js`:

```javascript
// Transform
{
  value: "transform",
  label: "Transform",
  // ... existing icon, color, description ...
  configSchema: {
    mappings: {
      type: "repeatable_rows",
      label: "Field Mappings",
      fields: {
        source: { type: "ctx_select", label: "Source", placeholder: "Select source field" },
        target: { type: "text", label: "Target", placeholder: "ctx.output_field" },
        transform: {
          type: "select", label: "Transform",
          options: [
            { value: "none", label: "No Transform" },
            { value: "uppercase", label: "Uppercase" },
            { value: "lowercase", label: "Lowercase" },
            { value: "to_integer", label: "To Integer" },
            { value: "to_string", label: "To String" },
            { value: "to_float", label: "To Float" },
            { value: "format_date", label: "Format Date" },
            { value: "split", label: "Split" },
            { value: "join", label: "Join" },
            { value: "strip", label: "Strip Whitespace" },
            { value: "truncate", label: "Truncate" }
          ]
        },
        transformOptions: { type: "dynamic", label: "Options" }
      }
    }
  }
}

// API_call
{
  value: "API_call",
  label: "API Call",
  configSchema: {
    url: { type: "text", label: "URL", placeholder: "https://api.example.com/{{ctx.model.id}}", required: true },
    method: {
      type: "select", label: "HTTP Method",
      options: [
        { value: "GET", label: "GET" },
        { value: "POST", label: "POST" },
        { value: "PUT", label: "PUT" },
        { value: "PATCH", label: "PATCH" },
        { value: "DELETE", label: "DELETE" }
      ]
    },
    headers: {
      type: "repeatable_rows", label: "Headers",
      fields: {
        key: { type: "text", label: "Key", placeholder: "Content-Type" },
        value: { type: "text", label: "Value", placeholder: "application/json" }
      }
    },
    body: { type: "textarea", label: "Request Body", placeholder: '{"name": "{{ctx.model.name}}"}', showWhen: { field: "method", values: ["POST", "PUT", "PATCH"] } },
    auth: {
      type: "group", label: "Authentication", collapsible: true,
      fields: {
        type: {
          type: "select", label: "Auth Type",
          options: [
            { value: "none", label: "None" },
            { value: "bearer", label: "Bearer Token" },
            { value: "basic", label: "Basic Auth" },
            { value: "api_key", label: "API Key" }
          ]
        },
        token: { type: "text", label: "Token", placeholder: "{{ctx.api_token}}", showWhen: { field: "auth.type", values: ["bearer"] } },
        username: { type: "text", label: "Username", showWhen: { field: "auth.type", values: ["basic"] } },
        password: { type: "text", label: "Password", showWhen: { field: "auth.type", values: ["basic"] } },
        keyName: { type: "text", label: "Key Name", showWhen: { field: "auth.type", values: ["api_key"] } },
        keyValue: { type: "text", label: "Key Value", showWhen: { field: "auth.type", values: ["api_key"] } },
        keyLocation: {
          type: "select", label: "Send In",
          options: [{ value: "header", label: "Header" }, { value: "query", label: "Query Param" }],
          showWhen: { field: "auth.type", values: ["api_key"] }
        }
      }
    },
    retry: {
      type: "group", label: "Retry & Timeout", collapsible: true,
      fields: {
        maxRetries: { type: "number", label: "Max Retries", min: 0, placeholder: "0" },
        backoff: {
          type: "select", label: "Backoff Strategy",
          options: [
            { value: "none", label: "None" },
            { value: "linear", label: "Linear" },
            { value: "exponential", label: "Exponential" }
          ]
        },
        retryOnStatusCodes: { type: "text", label: "Retry On Status Codes", placeholder: "500, 502, 503, 504" },
        timeout: { type: "number", label: "Timeout (seconds)", min: 1, placeholder: "30" }
      }
    },
    responseMapping: {
      type: "repeatable_rows", label: "Response Mapping",
      fields: {
        jsonPath: { type: "text", label: "JSON Path", placeholder: "$.data.name" },
        target: { type: "text", label: "Target", placeholder: "ctx.external_name" }
      }
    }
  }
}

// notify
{
  value: "notify",
  label: "Notify",
  configSchema: {
    channel: {
      type: "select", label: "Channel",
      options: [
        { value: "email", label: "Email" },
        { value: "webhook", label: "Webhook" },
        { value: "in_app", label: "In-App" }
      ]
    },
    recipients: {
      type: "group", label: "Recipients",
      fields: {
        type: {
          type: "select", label: "Source",
          options: [
            { value: "static_list", label: "Static List" },
            { value: "ctx_field", label: "Context Field" }
          ]
        },
        staticList: { type: "textarea", label: "Recipients (one per line)", showWhen: { field: "recipients.type", values: ["static_list"] } },
        ctxField: { type: "ctx_select", label: "Field", showWhen: { field: "recipients.type", values: ["ctx_field"] } }
      }
    },
    subject: { type: "text", label: "Subject / Title", placeholder: "Welcome, {{ctx.model.full_name}}!" },
    body: { type: "textarea", label: "Message Body", placeholder: "Your account has been created." },
    webhookConfig: {
      type: "group", label: "Webhook Settings", collapsible: true,
      showWhen: { field: "channel", values: ["webhook"] },
      fields: {
        url: { type: "text", label: "Webhook URL", required: true },
        method: { type: "select", label: "Method", options: [{ value: "POST", label: "POST" }, { value: "PUT", label: "PUT" }] },
        headers: { type: "repeatable_rows", label: "Headers", fields: { key: { type: "text" }, value: { type: "text" } } }
      }
    },
    condition: {
      type: "group", label: "Conditional Delivery", collapsible: true,
      fields: {
        enabled: { type: "checkbox", label: "Only send when condition is met" },
        field: { type: "ctx_select", label: "Field", showWhen: { field: "condition.enabled", values: [true] } },
        operator: { type: "select", label: "Operator", options: "BRANCH_OPERATORS", showWhen: { field: "condition.enabled", values: [true] } },
        value: { type: "text", label: "Value", showWhen: { field: "condition.enabled", values: [true] } }
      }
    },
    priority: {
      type: "select", label: "Priority",
      options: [
        { value: "low", label: "Low" },
        { value: "normal", label: "Normal" },
        { value: "high", label: "High" },
        { value: "urgent", label: "Urgent" }
      ]
    }
  }
}

// render_response
{
  value: "render_response",
  label: "Render Response",
  configSchema: {
    format: {
      type: "select", label: "Response Format",
      options: [
        { value: "html", label: "HTML Template" },
        { value: "json", label: "JSON" },
        { value: "redirect", label: "Redirect" }
      ]
    },
    statusCode: { type: "number", label: "HTTP Status Code", min: 100, max: 599, placeholder: "200" },
    html: {
      type: "group", label: "HTML Settings",
      showWhen: { field: "format", values: ["html"] },
      fields: {
        template: { type: "text", label: "Template Path", placeholder: "e.g., users/show" },
        layout: {
          type: "select", label: "Layout",
          options: [{ value: "application", label: "Application" }, { value: "minimal", label: "Minimal" }, { value: "none", label: "None" }]
        },
        locals: {
          type: "repeatable_rows", label: "Local Variables",
          fields: {
            source: { type: "ctx_select", label: "Source" },
            name: { type: "text", label: "Variable Name" }
          }
        }
      }
    },
    json: {
      type: "group", label: "JSON Settings",
      showWhen: { field: "format", values: ["json"] },
      fields: {
        fields: {
          type: "repeatable_rows", label: "Fields",
          fields: {
            source: { type: "ctx_select", label: "Source" },
            as: { type: "text", label: "Output Key", placeholder: "id" }
          }
        },
        includeMetadata: { type: "checkbox", label: "Include metadata (timestamps, request info)" },
        wrapInEnvelope: { type: "checkbox", label: "Wrap in envelope ({ data: ..., meta: ... })" }
      }
    },
    redirect: {
      type: "group", label: "Redirect Settings",
      showWhen: { field: "format", values: ["redirect"] },
      fields: {
        url: { type: "text", label: "Redirect URL", placeholder: "/{{ctx.model.id}}" },
        flashMessage: { type: "text", label: "Flash Message" },
        flashType: {
          type: "select", label: "Flash Type",
          options: [{ value: "notice", label: "Notice" }, { value: "alert", label: "Alert" }]
        }
      }
    },
    headers: {
      type: "repeatable_rows", label: "Response Headers", collapsible: true,
      fields: {
        key: { type: "text", label: "Key" },
        value: { type: "text", label: "Value" }
      }
    }
  }
}
```

**Note on `ctx_select` type:** This is a new field type for config panels that renders the same context-aware searchable dropdown described in section 1.2 (common ctx fields + entity attributes + parent outputs). It reuses the same option-building logic.

**Note on `showWhen`:** Config panel rendering checks `showWhen` conditions to conditionally show/hide fields. The `configFieldChanged` handler on StepManager toggles visibility when dependent fields change.

**Note on transform functions:** The `custom` expression option from the original proposal is **removed** from scope due to code injection risks. All transform functions are predefined and safe.

### 2.1 Transform — Config & Code Generation

**Config structure:**
```json
{
  "config": {
    "mappings": [
      { "source": "ctx.model.full_name", "target": "ctx.display_name", "transform": "none" },
      { "source": "ctx.model.email", "target": "ctx.normalized_email", "transform": "lowercase" },
      { "source": "ctx.model.birth_date", "target": "ctx.formatted_dob", "transform": "format_date", "transformOptions": { "format": "%Y-%m-%d" } }
    ]
  }
}
```

**Transform function code mapping:**
| Function | Generated Ruby |
|----------|---------------|
| `none` | Direct assignment |
| `uppercase` | `.to_s.upcase` |
| `lowercase` | `.to_s.downcase` |
| `to_integer` | `.to_i` |
| `to_string` | `.to_s` |
| `to_float` | `.to_f` |
| `format_date` | `.strftime(format)` |
| `split` | `.to_s.split(delimiter)` |
| `join` | `.join(delimiter)` |
| `strip` | `.to_s.strip` |
| `truncate` | `.to_s.truncate(length)` |

**Generated code:**
```ruby
step :transform_<element_label_slug>

def transform_<element_label_slug>(ctx, **)
  ctx[:display_name] = ctx.dig(:model, :full_name)
  ctx[:normalized_email] = ctx.dig(:model, :email).to_s.downcase
  ctx[:formatted_dob] = ctx.dig(:model, :birth_date)&.strftime("%Y-%m-%d")
end
```

### 2.2 API Call — Config & Code Generation

**Config structure:**
```json
{
  "config": {
    "url": "https://api.example.com/users/{{ctx.model.external_id}}",
    "method": "GET",
    "headers": [
      { "key": "Content-Type", "value": "application/json" }
    ],
    "body": "",
    "auth": { "type": "bearer", "token": "{{ctx.api_token}}" },
    "retry": { "maxRetries": 3, "backoff": "exponential", "retryOnStatusCodes": "500,502,503,504", "timeout": 30 },
    "responseMapping": [
      { "jsonPath": "$.data.name", "target": "ctx.external_name" }
    ]
  }
}
```

**Generated code:**
```ruby
step :api_call_<element_label_slug>

def api_call_<element_label_slug>(ctx, **)
  url = "https://api.example.com/users/#{ctx.dig(:model, :external_id)}"

  response = ActivitySteps::ApiClient.call(
    url: url,
    method: :get,
    headers: { "Content-Type" => "application/json" },
    auth: { type: :bearer, token: ctx[:api_token] },
    timeout: 30,
    retry_policy: { max_retries: 3, backoff: :exponential, retry_on: [500, 502, 503, 504] }
  )

  return false unless response.success?

  data = response.parsed_body
  ctx[:external_name] = data.dig("data", "name")
  true
end
```

### 2.3 Notify — Config & Code Generation

**Config structure:**
```json
{
  "config": {
    "channel": "email",
    "recipients": { "type": "ctx_field", "value": "ctx.model.email" },
    "subject": "Welcome, {{ctx.model.full_name}}!",
    "body": "Your account has been created.",
    "condition": { "enabled": true, "field": "ctx.model.email", "operator": "is_not_empty" },
    "priority": "normal"
  }
}
```

**Generated code:**
```ruby
step :notify_<element_label_slug>

def notify_<element_label_slug>(ctx, **)
  return true if ctx.dig(:model, :email).blank?

  ActivitySteps::Notifier.call(
    channel: :email,
    recipients: [ctx.dig(:model, :email)],
    subject: "Welcome, #{ctx.dig(:model, :full_name)}!",
    body: "Your account has been created.",
    priority: :normal
  )
end
```

### 2.4 Render Response — Config & Code Generation

**Config structure (JSON example):**
```json
{
  "config": {
    "format": "json",
    "statusCode": 200,
    "json": {
      "fields": [
        { "source": "ctx.model.id", "as": "id" },
        { "source": "ctx.model.full_name", "as": "name" }
      ],
      "includeMetadata": true,
      "wrapInEnvelope": true
    },
    "headers": [
      { "key": "X-Request-Id", "value": "{{ctx.request_id}}" }
    ]
  }
}
```

**Generated code:**
```ruby
step :render_response_<element_label_slug>

def render_response_<element_label_slug>(ctx, **)
  ctx[:render_response] = {
    format: :json,
    status: 200,
    body: {
      id: ctx.dig(:model, :id),
      name: ctx.dig(:model, :full_name)
    },
    headers: { "X-Request-Id" => ctx[:request_id] }
  }
end
```

---

## New Runtime Services

### ActivitySteps::ApiClient

**Location:** `app/services/activity_steps/api_client.rb`

**Class interface:**
```ruby
class ActivitySteps::ApiClient
  Response = Struct.new(:status, :body, :headers, keyword_init: true) do
    def success? = (200..299).cover?(status)
    def parsed_body = JSON.parse(body) rescue {}
    def raw_body = body
  end

  # @param url [String] Request URL
  # @param method [Symbol] :get, :post, :put, :patch, :delete
  # @param headers [Hash] Request headers
  # @param body [String, nil] Request body (for POST/PUT/PATCH)
  # @param auth [Hash, nil] { type: :bearer/:basic/:api_key, ... }
  # @param timeout [Integer] Timeout in seconds (default: 30)
  # @param retry_policy [Hash, nil] { max_retries: 0, backoff: :none, retry_on: [] }
  # @return [Response]
  def self.call(url:, method: :get, headers: {}, body: nil, auth: nil, timeout: 30, retry_policy: nil)
    new(url:, method:, headers:, body:, auth:, timeout:, retry_policy:).call
  end

  def call
    apply_auth!
    execute_with_retry
  end

  private

  def execute_with_retry
    attempts = 0
    max = retry_policy&.dig(:max_retries) || 0
    loop do
      response = execute_request
      return response if response.success? || attempts >= max || !retryable?(response.status)
      attempts += 1
      sleep(backoff_delay(attempts))
    end
  end

  def backoff_delay(attempt)
    case retry_policy&.dig(:backoff)
    when :exponential then 2**attempt
    when :linear then attempt * 2
    else 0
    end
  end
end
```

Uses `Net::HTTP` from stdlib. No new gems needed.

### ActivitySteps::Notifier

**Location:** `app/services/activity_steps/notifier.rb`

**Class interface:**
```ruby
class ActivitySteps::Notifier
  # @param channel [Symbol] :email, :webhook, :in_app
  # @param recipients [Array<String>] Recipient addresses/identifiers
  # @param subject [String] Notification subject/title
  # @param body [String] Notification body/message
  # @param priority [Symbol] :low, :normal, :high, :urgent
  # @param options [Hash] Channel-specific options
  # @return [Boolean] true if sent successfully
  def self.call(channel:, recipients:, subject:, body:, priority: :normal, **options)
    handler = channel_handler(channel)
    handler.call(recipients:, subject:, body:, priority:, **options)
  end

  private

  def self.channel_handler(channel)
    case channel
    when :email   then ActivitySteps::Notifiers::EmailNotifier
    when :webhook then ActivitySteps::Notifiers::WebhookNotifier
    when :in_app  then ActivitySteps::Notifiers::InAppNotifier
    else raise ArgumentError, "Unknown notification channel: #{channel}"
    end
  end
end
```

**Channel handlers** (in `app/services/activity_steps/notifiers/`):
- `EmailNotifier` — uses ActionMailer to send emails
- `WebhookNotifier` — uses `ActivitySteps::ApiClient` to POST to webhook URL
- `InAppNotifier` — creates a record in a notifications table (requires a `Notification` model, which can be added as a feature module later; for now, logs the notification)

**Channel extensibility:** New channels are registered by adding a `when` clause to `channel_handler`. Feature modules that add channels can monkey-patch or use a registry hash. A formal plugin system is deferred — the current `case` approach is sufficient for the three built-in channels.

### DynamicController — Render Response Integration

**Location:** `app/controllers/dynamic_controller.rb`

The `DynamicController` needs a new method to handle `ctx[:render_response]` after activity execution. Add to the files affected list.

**Integration point:** After the activity executes, check for `ctx[:render_response]`:
```ruby
def dispatch_response(ctx)
  if ctx[:render_response].present?
    render_configured_response(ctx[:render_response])
  else
    # existing default response logic
  end
end

def render_configured_response(config)
  case config[:format]
  when :json
    render json: config[:body], status: config[:status] || 200
  when :html
    render template: config[:template], layout: config[:layout], locals: config[:locals] || {}, status: config[:status] || 200
  when :redirect
    redirect_to config[:url], notice: config[:flash_message]
  end
end
```

---

## Template Functions (templates.js)

New template builder functions to add to `app/javascript/controllers/property_editor/templates.js`:

| Function | Parameters | Purpose |
|----------|-----------|---------|
| `buildErrorHandlingFieldTemplate(fieldName, currentValue)` | Field name, current errorHandling config | Renders mode dropdown + conditional error output field |
| `buildStepConfigPanelTemplate(actionValue, configSchema, currentConfig)` | Action name, its configSchema, existing config data | Renders the full config panel for a step action |
| `buildRepeatableRowsTemplate(fieldName, fieldSchema, rows)` | Field name, schema for each row, existing row data | Renders add/remove row UI for mappings, headers, etc. |
| `buildGroupTemplate(fieldName, fieldSchema, currentValue)` | Field name, group schema, current values | Renders collapsible group of fields |
| `buildCtxSelectTemplate(fieldName, options, currentValue)` | Field name, option groups, selected value | Renders the context-aware searchable select dropdown |

Each follows the existing pattern in `templates.js` — returns an HTML string, uses TailwindCSS classes, includes `data-action` attributes for Stimulus.

---

## Files Affected

| File | Change |
|------|--------|
| `app/javascript/flowchart/constants/schemas.js` | Add `errorHandling` to process schema, add `configSchema` to transform/API_call/notify/render_response step actions, change loop condition type from `text` to `condition` |
| `app/javascript/controllers/property_editor/step_manager.js` | Render config panels for step actions, add `addConfigRow`/`removeConfigRow`/`configFieldChanged` methods, collect config on step save |
| `app/javascript/controllers/property_editor/branch_manager.js` | Expand left/right operand options with entity attributes, parent outputs, optgroup separators, custom value toggle for right operand |
| `app/javascript/controllers/property_editor/templates.js` | Add `buildErrorHandlingFieldTemplate`, `buildStepConfigPanelTemplate`, `buildRepeatableRowsTemplate`, `buildGroupTemplate`, `buildCtxSelectTemplate` |
| `app/javascript/controllers/property_editor/form_builder.js` | Add `error_handling` case to `_buildFieldHTML` dispatching to `_buildErrorHandlingFieldHTML` |
| `app/services/activity_generator.rb` | Add handler methods: `generate_transform`, `generate_api_call`, `generate_notify`, `generate_render_response`; add error handling generation for `route_to_error_end` mode |
| `app/controllers/dynamic_controller.rb` | Add `render_configured_response` method to handle `ctx[:render_response]` after activity execution |
| `app/services/activity_steps/api_client.rb` | **New** — HTTP client with retry, auth, timeout |
| `app/services/activity_steps/notifier.rb` | **New** — notification dispatcher |
| `app/services/activity_steps/notifiers/email_notifier.rb` | **New** — email channel via ActionMailer |
| `app/services/activity_steps/notifiers/webhook_notifier.rb` | **New** — webhook channel via ApiClient |
| `app/services/activity_steps/notifiers/in_app_notifier.rb` | **New** — in-app notification (log-based initially) |

---

## Test Plan

### ActivityGenerator Tests (`spec/services/activity_generator_spec.rb`)

**Error handling generation:**
- Process with `halt` mode generates standard Railway code (no additional fail steps)
- Process with `route_to_error_end` generates a `fail :handle_error_in_*` step
- Error output field is correctly interpolated in generated code

**Transform code generation:**
- Single mapping with no transform generates direct assignment
- Mapping with `lowercase` transform generates `.to_s.downcase`
- Mapping with `format_date` and options generates `.strftime(format)`
- Empty mappings array generates no-op step
- Nested source paths (e.g., `ctx.model.address.city`) generate correct `dig` calls

**API_call code generation:**
- GET request with no auth generates basic `ApiClient.call` invocation
- POST request with bearer auth generates correct auth hash
- Response mappings generate correct `data.dig` assignments
- Retry policy config generates correct retry_policy hash
- `{{ctx.field}}` interpolation in URL is converted to Ruby string interpolation

**Notify code generation:**
- Email with ctx_field recipients generates correct `ctx.dig` call
- Conditional delivery generates guard clause
- Static recipients generates literal array
- Priority is passed through correctly

**Render_response code generation:**
- JSON format generates `ctx[:render_response]` with field mappings
- HTML format generates template/layout/locals config
- Redirect format generates URL with interpolation
- Status code override is included

### ApiClient Tests (`spec/services/activity_steps/api_client_spec.rb`)

- Successful GET request returns Response with `success?` true
- Failed request (500) returns Response with `success?` false
- Retry with exponential backoff retries correct number of times
- Retry skips non-retryable status codes
- Timeout raises and is caught gracefully
- Bearer auth adds Authorization header
- Basic auth adds Base64-encoded header
- API key auth adds key to header or query param
- `parsed_body` returns parsed JSON; returns empty hash for non-JSON

### Notifier Tests (`spec/services/activity_steps/notifier_spec.rb`)

- Email channel dispatches to EmailNotifier
- Webhook channel dispatches to WebhookNotifier
- In-app channel dispatches to InAppNotifier
- Unknown channel raises ArgumentError
- Each notifier receives correct parameters

### JavaScript Tests (manual / system specs)

- Process element shows error handling section in property editor
- Switching error handling mode shows/hides error output field
- Decision left operand dropdown shows entity attributes grouped
- Decision right operand "Custom value..." toggles to text input
- Loop condition renders structured builder (not free-text)
- Legacy loop with string condition shows migration prompt
- Step modal shows config panel for transform/API_call/notify/render_response
- Config panel repeatable rows can be added and removed
- Conditional fields show/hide based on dependent values

---

## Migration & Backward Compatibility

- **No database migrations needed** — all new data stored in the existing JSON `configuration` column
- **Existing flowcharts unaffected** — new fields have sensible defaults (errorHandling defaults to `halt`, step configs default to empty/absent)
- **Loop condition backward compat** — if `condition` is a string (legacy), show migration prompt; if it's an object with `leftOperand`, render structured builder
- **Step action backward compat** — steps without `config` field continue to work as before
- **ActivityGenerator backward compat** — unknown step actions (e.g., old `transform` steps with no config) generate a comment placeholder instead of crashing
