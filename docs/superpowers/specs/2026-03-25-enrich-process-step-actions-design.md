# Enrich Process Step Actions

**Date**: 2026-03-25
**Status**: Approved

## Overview

Enrich the flowchart process element's step action system with:
- 24 categorized actions (up from 10) across 9 categories
- Per-action configuration schemas that produce real, runnable Ruby code via the activity generator
- A searchable, categorized dropdown for action selection
- Inline action-specific configuration in expanded step items

The 1-step-per-process-element limit remains unchanged.

## Conventions

### Config Key Naming

All config keys use **camelCase** on the JS side, matching the existing `ELEMENT_SCHEMAS` convention (e.g., `httpMethod`, `triggerType`, `loopType`). These keys are persisted as-is in the JSON `configuration` column. On the Ruby side, generators read config keys as strings from the parsed JSON hash (e.g., `config["httpMethod"]`).

### visibleWhen Syntax

Config field `visibleWhen` follows the same convention as `ELEMENT_SCHEMAS` in `schemas.js`:
- Singular: `visibleWhen: { field: "triggerType", value: "http" }`
- Plural: `visibleWhen: { field: "httpMethod", values: ["POST", "PUT", "PATCH"] }`

Both forms are supported. The existing `FormBuilder._buildFieldHTML` handler (`vw.values || [vw.value]`) is reused for config field visibility.

### Registry Entry Identifier

Registry entries use `value` (not `key`) as the action identifier, matching the existing `STEP_ACTIONS` array format. This ensures `StepManager` code that references `opt.value` works unchanged. The `getAllActions()` helper returns entries with `value`, `label`, `icon`, `color`, `description`, and `subOptions` — identical shape to today's `STEP_ACTIONS` items, plus the new `category`, `singleUse`, and `configSchema` fields.

### subOption Casing

The existing codebase has an inconsistency: JS persists `suboption` (all lowercase) while Ruby tries `subOption` (camelCase) first with a fallback. Per the camelCase convention, this is standardized to `subOption` (camelCase) everywhere. The JS `collectSteps()`, `buildStepItemHTML`, and hidden input names will be updated to use `subOption`. The Ruby generators continue reading `step.dig("subOption")` which now matches.

### SINGLE_USE_ACTIONS Migration

The existing hardcoded `SINGLE_USE_ACTIONS` constant in `step_manager.js` is replaced by `getSingleUseActions()` from the registry. The registry is the single source of truth for which actions are single-use (via the `singleUse: true` flag on each action entry).

### Expression Fields and Security

Several actions accept Ruby expression strings from the user (e.g., `customExpression` in transform/calculate, `guardCondition`, `valueExpression` in assign_value). This is accepted as-is because the generated code runs in a controlled server environment and the flowchart editor is only accessible to authorized users. This is the same trust model as the existing `guardCondition` field.

## Architecture: Action Registry Pattern

A modular Action Registry replaces the flat `STEP_ACTIONS` array. Each action is a self-contained definition with metadata, category, and config schema. On the Ruby side, the monolithic `ActivityGenerator` is decomposed into per-category step generator modules.

### JS File Structure

```
app/javascript/flowchart/constants/
  schemas.js                     # STEP_ACTIONS becomes thin wrapper over registry
  action_registry.js             # Central registry + categories + helper functions
  action_configs/
    model_actions.js             # new_model, find_model, save_model, destroy_model, update_model, query_models
    validation_actions.js        # build_contract, validate
    data_actions.js              # assign_value, transform, calculate, log
    communication_actions.js     # API_call, send_email, send_webhook, notify
    security_actions.js          # authorize
    background_actions.js        # enqueue_job, schedule_job
    file_actions.js              # generate_file, upload_file
    realtime_actions.js          # publish_event, broadcast
    response_actions.js          # render_response
```

### Ruby File Structure

```
app/services/
  activity_generator.rb                # Orchestrator (slimmed down, includes modules)
  activity_generator/
    base_step_helpers.rb               # Shared helpers module (wrap_with_retry, condition_operand_to_ruby, etc.)
    model_steps.rb                     # new_model, find_model, save_model, destroy_model, update_model, query_models
    validation_steps.rb                # build_contract, validate
    data_steps.rb                      # assign_value, transform, calculate, log
    communication_steps.rb             # API_call, send_email, send_webhook, notify
    security_steps.rb                  # authorize
    background_steps.rb                # enqueue_job, schedule_job
    file_steps.rb                      # generate_file, upload_file
    realtime_steps.rb                  # publish_event, broadcast
    response_steps.rb                  # render_response
```

### Registry Entry Shape

Each action in the registry defines:

```javascript
{
  value: "API_call",             // Unique identifier (matches existing STEP_ACTIONS format)
  label: "API Call",             // Display label
  icon: "M3.055 11H5a2...",     // SVG path for icon
  color: "amber",               // Color theme (maps to Tailwind classes)
  category: "communication",    // Category key for grouping
  description: "Make external HTTP request",
  singleUse: false,             // Whether only one instance allowed per process

  configSchema: [               // Fields rendered in expanded step item
    {
      key: "httpMethod",        // Config key stored in step.config (camelCase)
      type: "select",           // Widget type: text, textarea, number, select, key_value_list
      label: "HTTP Method",
      default: "GET",
      required: true,
      options: [
        { value: "GET", label: "GET" },
        { value: "POST", label: "POST" },
        { value: "PUT", label: "PUT" },
        { value: "PATCH", label: "PATCH" },
        { value: "DELETE", label: "DELETE" }
      ]
    },
    {
      key: "bodyTemplate",
      type: "textarea",
      label: "Request Body",
      visibleWhen: { field: "httpMethod", values: ["POST", "PUT", "PATCH"] }
    }
    // ...
  ]
}
```

**Actions with subOptions** (e.g., `validate`) use `configSchemaBySubOption` instead of `configSchema` to scope config fields to a specific sub-option:

```javascript
{
  value: "validate",
  label: "Validate",
  // ...
  subOptions: [
    { value: "contract", label: "Contract" },
    { value: "permission", label: "Permission" }
  ],
  configSchemaBySubOption: {
    contract: [],  // No additional config for contract validation
    permission: [
      { key: "permissionType", type: "select", label: "Permission Type",
        options: [
          { value: "role_check", label: "Role Check" },
          { value: "policy_check", label: "Policy Check" }
        ]
      },
      { key: "roleExpression", type: "text", label: "Role Expression",
        visibleWhen: { field: "permissionType", value: "role_check" } },
      // ...
    ]
  }
}
```

When `buildStepConfigHTML` renders config fields, it checks: if the action has `configSchemaBySubOption`, it uses the schema matching `step.suboption`; otherwise it uses `configSchema`.

### Category Definitions

```javascript
export const ACTION_CATEGORIES = [
  { key: "model",         label: "Model Operations" },
  { key: "validation",    label: "Validation" },
  { key: "data",          label: "Data Operations" },
  { key: "communication", label: "Communication" },
  { key: "security",      label: "Security" },
  { key: "background",    label: "Background & Scheduling" },
  { key: "file",          label: "File Operations" },
  { key: "realtime",      label: "Real-time & Events" },
  { key: "response",      label: "Response" }
]
```

### Registry Helper Functions

```javascript
// Returns array of { category: { key, label }, actions: [actionEntry, ...] }
// Used by searchable dropdown for grouped rendering
export function getActionsByCategory()

// Returns flat array of action entries matching query against label/description/category
export function searchActions(query)

// Returns the full action registry entry for a given action value.
// The caller (e.g., buildStepConfigHTML) reads configSchema or configSchemaBySubOption
// from the returned entry and selects the appropriate schema based on the sub-option.
export function getActionConfig(actionValue)

// Returns array of action value strings where singleUse === true
export function getSingleUseActions()

// Returns flat array of all action entries (backward compat for STEP_ACTIONS)
// Each entry has: value, label, icon, color, description, subOptions (if any)
export function getAllActions()
```

`schemas.js` imports from the registry: `export const STEP_ACTIONS = getAllActions()` -- preserving backward compatibility with existing `StepManager` and `FormBuilder` code.

### Color Assignments

All 24 actions mapped to colors (using existing `STEP_COLOR_CLASSES` in `templates.js`):

| Action | Color | Category |
|---|---|---|
| `new_model` | blue | Model Operations |
| `find_model` | cyan | Model Operations |
| `save_model` | green | Model Operations |
| `destroy_model` | red | Model Operations |
| `update_model` | indigo | Model Operations |
| `query_models` | purple | Model Operations |
| `build_contract` | indigo | Validation |
| `validate` | emerald | Validation |
| `assign_value` | blue | Data Operations |
| `transform` | purple | Data Operations |
| `calculate` | teal | Data Operations |
| `log` | amber | Data Operations |
| `API_call` | amber | Communication |
| `send_email` | pink | Communication |
| `send_webhook` | cyan | Communication |
| `notify` | amber | Communication |
| `authorize` | red | Security |
| `enqueue_job` | indigo | Background & Scheduling |
| `schedule_job` | purple | Background & Scheduling |
| `generate_file` | teal | File Operations |
| `upload_file` | green | File Operations |
| `publish_event` | amber | Real-time & Events |
| `broadcast` | emerald | Real-time & Events |
| `render_response` | teal | Response |

## Full Action Catalog

**Existing actions** (10, gaining config enrichment): `new_model`, `find_model`, `save_model`, `destroy_model`, `build_contract`, `validate`, `transform`, `API_call`, `notify`, `render_response`

**New actions** (14): `update_model`, `query_models`, `assign_value`, `calculate`, `log`, `send_email`, `send_webhook`, `authorize`, `enqueue_job`, `schedule_job`, `generate_file`, `upload_file`, `publish_event`, `broadcast`

All config keys below use camelCase (matching JS convention). Ruby generators read them as `config["camelCaseKey"]`.

### Model Operations (6 actions)

#### `new_model`
- **Description**: Create a new model instance
- **Single-use**: Yes
- **Config**: None (uses bound entity)
- **Generates**: `ctx[:model] = EntityEntry.build_for(ctx[:bound_entity]).new(customer_id: ctx[:customer_id])`

#### `find_model`
- **Description**: Find an existing model
- **Single-use**: Yes
- **Config**:
  - `findStrategy`: select -- `find` (raise on missing), `findBy` (return nil), `where` (collection)
  - `findField`: text -- field to search by (default: `id`); visible when `findBy` or `where`
  - `findValue`: text -- value expression (e.g., `ctx[:email]`); visible when `findBy` or `where`
  - `resultVar`: text -- ctx key to store result (default: `model`)
- **Generates**:
  - `find` -> `ctx[:model] = EntityEntry.build_for(ctx[:bound_entity]).find(ctx[:id])`
  - `findBy` -> `ctx[:model] = EntityEntry.build_for(ctx[:bound_entity]).find_by!(email: ctx[:email])`
  - `where` -> `ctx[:models] = EntityEntry.build_for(ctx[:bound_entity]).where(status: ctx[:status])`

#### `save_model`
- **Description**: Persist model to database
- **Single-use**: Yes
- **Config**:
  - `saveStrategy`: select -- `saveAll` (default, transactional with associations), `saveOnly` (primary model only)
- **Generates**:
  - `saveAll` -> `ActivitySteps::SaveAll.call(ctx)`
  - `saveOnly` -> `ctx[:model].save!`

#### `destroy_model`
- **Description**: Delete model from database
- **Single-use**: Yes
- **Config**:
  - `destroyStrategy`: select -- `destroy` (hard delete), `softDelete` (set status/deleted_at)
- **Generates**:
  - `destroy` -> `ctx[:model].destroy`
  - `softDelete` -> `ctx[:model].update!(status: :deleted, deleted_at: Time.current)`

#### `update_model`
- **Description**: Update specific fields on an existing model
- **Single-use**: No
- **Config**:
  - `fieldMappings`: key_value_list -- array of `{ key: "name", value: "ctx[:new_name]" }`
- **Generates**: `ctx[:model].update!(name: ctx[:new_name], email: ctx[:email])`

#### `query_models`
- **Description**: Complex model queries
- **Single-use**: No
- **Config**:
  - `queryType`: select -- `where`, `scope`, `sql`
  - `conditions`: key_value_list -- field/value pairs; visible when `where`
  - `scopeName`: text -- scope method name; visible when `scope`
  - `scopeArgs`: text -- scope arguments expression; visible when `scope`
  - `sqlExpression`: textarea -- raw SQL; visible when `sql`
  - `orderBy`: text -- e.g., `created_at desc`
  - `limit`: number -- max results
  - `resultVar`: text -- ctx key (default: `models`)
- **Generates**:
  - `where` -> `ctx[:models] = EntityEntry.build_for(ctx[:bound_entity]).where(status: "active").order("created_at desc").limit(10)`
  - `scope` -> `ctx[:models] = EntityEntry.build_for(ctx[:bound_entity]).send(:active_users, ctx[:role])`

### Validation (2 actions)

#### `build_contract`
- **Description**: Build a validation contract
- **Single-use**: Yes
- **Config**: None (uses bound entity)
- **Generates**: `ctx[:contract] = EntityEntryContract.build_for(ctx[:bound_entity]).new(ctx[:model])`

#### `validate`
- **Description**: Validate data or permissions
- **Single-use**: No
- **SubOptions**: `contract`, `permission`
- **Config**: Uses `configSchemaBySubOption` (see Registry Entry Shape section)
- **Config (contract)**: None (existing behavior)
- **Config (permission)**:
  - `permissionType`: select -- `role_check`, `policy_check`
  - `roleExpression`: text -- e.g., `ctx[:current_user].role`; visible when `role_check`
  - `requiredRole`: text -- e.g., `admin`; visible when `role_check`
  - `policyClass`: text; visible when `policy_check`
  - `policyAction`: text; visible when `policy_check`
- **Generates (permission/role_check)**: `ctx[:result] = ctx[:current_user].role == "admin"`
- **Generates (permission/policy_check)**: `ctx[:result] = Pundit.authorize(ctx[:current_user], ctx[:model], :update?)`

### Data Operations (4 actions)

#### `assign_value`
- **Description**: Set a ctx variable
- **Single-use**: No
- **Config**:
  - `targetVar`: text -- ctx key to set (e.g., `total_count`); required
  - `valueType`: select -- `expression`, `string`, `integer`, `boolean`
  - `valueExpression`: text -- Ruby expression; visible when `expression`
  - `stringValue`: text; visible when `string`
  - `integerValue`: number; visible when `integer`
  - `booleanValue`: select (true/false); visible when `boolean`
- **Generates**: `ctx[:total_count] = ctx[:items].count`

#### `transform`
- **Description**: Transform data format
- **Single-use**: No
- **Config**:
  - `transformType`: select -- `mapFields`, `formatDate`, `convertType`, `custom`
  - `sourceField`: text -- source ctx key; required
  - `targetField`: text -- target ctx key; required
  - `fieldMappings`: key_value_list -- old_key to new_key; visible when `mapFields`
  - `dateFormat`: text -- e.g., `%Y-%m-%d`; visible when `formatDate`
  - `convertTo`: select -- `string`, `integer`, `float`, `json`, `array`; visible when `convertType`
  - `customExpression`: textarea -- Ruby expression; visible when `custom`
- **Generates (mapFields)**: `ctx[:target] = ctx[:source].slice(:name, :email).transform_keys({ name: :full_name })`
- **Generates (formatDate)**: `ctx[:formatted_date] = ctx[:raw_date].strftime("%Y-%m-%d")`
- **Generates (convertType)**: `ctx[:count] = ctx[:raw_count].to_i`
- **Generates (custom)**: User-provided expression

#### `calculate`
- **Description**: Compute/aggregate values
- **Single-use**: No
- **Config**:
  - `operation`: select -- `sum`, `count`, `avg`, `min`, `max`, `custom`
  - `collectionExpression`: text -- e.g., `ctx[:orders]`; required (except `custom`)
  - `fieldName`: text -- field to aggregate; visible when `sum`/`avg`/`min`/`max`
  - `customExpression`: textarea; visible when `custom`
  - `resultVar`: text -- ctx key (default: `result`)
- **Generates (sum)**: `ctx[:result] = ctx[:orders].sum { |r| r[:amount] }`
- **Generates (count)**: `ctx[:result] = ctx[:orders].count`

#### `log`
- **Description**: Write to logger or audit trail
- **Single-use**: No
- **Config**:
  - `logLevel`: select -- `debug`, `info`, `warn`, `error`
  - `messageTemplate`: text -- message with interpolation; required
  - `logType`: select -- `rails_logger`, `audit_trail`
  - `auditDataExpression`: textarea; visible when `audit_trail`
- **Generates (rails_logger)**: `Rails.logger.info("User #{ctx[:user_id]} created")`
- **Generates (audit_trail)**: `AuditLog.create!(action: "user_created", data: ctx[:audit_data], customer_id: ctx[:customer_id])`

### Communication (4 actions)

#### `API_call`
- **Description**: External HTTP request
- **Single-use**: No
- **Config**:
  - `httpMethod`: select -- `GET`, `POST`, `PUT`, `PATCH`, `DELETE`
  - `url`: text -- URL with optional interpolation; required
  - `headers`: key_value_list -- header name/value pairs
  - `bodyTemplate`: textarea -- request body; visible when `POST`/`PUT`/`PATCH`
  - `authType`: select -- `none`, `bearer`, `basic`, `apiKey`
  - `authToken`: text -- token expression; visible when `bearer`
  - `authUsername`/`authPassword`: text; visible when `basic`
  - `apiKeyHeader`/`apiKeyValue`: text; visible when `apiKey`
  - `responseVar`: text -- ctx key (default: `api_response`)
- **Generates**: Full `Net::HTTP` code with configured method, URL, headers, auth, body

#### `send_email`
- **Description**: Send email via ActionMailer
- **Single-use**: No
- **Config**:
  - `mailerMethod`: select -- `default` (inline), `custom` (existing mailer)
  - `toExpression`: text -- recipient expression; required
  - `subject`: text -- email subject; required
  - `bodyTemplate`: textarea -- email body; visible when `default`
  - `mailerClass`: text -- e.g., `UserMailer`; visible when `custom`
  - `mailerAction`: text -- e.g., `welcome`; visible when `custom`
- **Generates (default)**: `ActionMailer::Base.mail(to: ctx[:user].email, subject: "Welcome", body: "...").deliver_later`
- **Generates (custom)**: `UserMailer.welcome(ctx[:user]).deliver_later`

#### `send_webhook`
- **Description**: Outbound webhook POST
- **Single-use**: No
- **Config**:
  - `url`: text -- webhook URL; required
  - `payloadExpression`: textarea -- Ruby hash for JSON body; required
  - `headers`: key_value_list -- additional headers
  - `secretExpression`: text -- HMAC signing secret expression (optional)
  - `responseVar`: text -- ctx key (default: `webhook_response`)
- **Generates**: `Net::HTTP.post` with optional HMAC signing

#### `notify`
- **Description**: Generic notification
- **Single-use**: No
- **Config**:
  - `channel`: select -- `email`, `sms`, `push`, `slack`, `in_app`
  - `recipientExpression`: text -- e.g., `ctx[:user]`; required
  - `messageTemplate`: text -- message content; required
  - `metadata`: key_value_list -- extra data (optional)
- **Generates**: Channel-specific notification dispatch code

### Security (1 action)

#### `authorize`
- **Description**: Policy/permission check
- **Single-use**: No
- **Config**:
  - `authType`: select -- `role_check`, `policy_check`, `custom`
  - `userExpression`: text -- default `ctx[:current_user]`
  - `roleName`: text -- required role; visible when `role_check`
  - `policyClass`: text -- e.g., `ArticlePolicy`; visible when `policy_check`
  - `policyAction`: text -- e.g., `update?`; visible when `policy_check`
  - `recordExpression`: text -- e.g., `ctx[:model]`; visible when `policy_check`
  - `customExpression`: textarea; visible when `custom`
  - `failureMessage`: text -- error message on auth failure
- **Generates (role_check)**: `raise "Unauthorized" unless ctx[:current_user].role == "admin"`
- **Generates (policy_check)**: `Pundit.authorize(ctx[:current_user], ctx[:model], :update?)`

### Background & Scheduling (2 actions)

#### `enqueue_job`
- **Description**: Queue a background job
- **Single-use**: No
- **Config**:
  - `jobClass`: text -- e.g., `ProcessOrderJob`; required
  - `jobArgs`: text -- arguments expression
  - `queueName`: select -- `default`, `low`, `high`, `mailers`
  - `priority`: number -- job priority (optional)
- **Generates**: `ProcessOrderJob.set(queue: "high").perform_later(ctx[:order].id, ctx[:user].id)`

#### `schedule_job`
- **Description**: Schedule delayed execution
- **Single-use**: No
- **Config**:
  - `jobClass`: text; required
  - `jobArgs`: text -- arguments expression
  - `delayType`: select -- `duration`, `atTime`
  - `delayValue`: number; visible when `duration`
  - `delayUnit`: select -- `seconds`, `minutes`, `hours`, `days`; visible when `duration`
  - `scheduledAt`: text -- expression; visible when `atTime`
- **Generates**: `ProcessOrderJob.set(wait: 30.minutes).perform_later(ctx[:order].id)`

### File Operations (2 actions)

#### `generate_file`
- **Description**: Generate PDF/CSV/Excel
- **Single-use**: No
- **Config**:
  - `fileType`: select -- `csv`, `pdf`, `excel`
  - `dataExpression`: text -- collection/data source; required
  - `columns`: key_value_list -- column_name to field_expression; visible when `csv`/`excel`
  - `templateName`: text -- PDF template; visible when `pdf`
  - `filenameTemplate`: text -- e.g., `"report_#{Date.today}.csv"`
  - `resultVar`: text -- ctx key (default: `generated_file`)
- **Generates (csv)**: `CSV.generate { |csv| ... }` with column mappings

#### `upload_file`
- **Description**: ActiveStorage file upload
- **Single-use**: No
- **Config**:
  - `attachmentName`: text -- e.g., `avatar`; required
  - `sourceExpression`: text -- file source; required
  - `recordExpression`: text -- model to attach to (default: `ctx[:model]`)
- **Generates**: `ctx[:model].avatar.attach(ctx[:params][:file])`

### Real-time & Events (2 actions)

#### `publish_event`
- **Description**: Publish a domain event
- **Single-use**: No
- **Config**:
  - `eventName`: text -- e.g., `order.completed`; required
  - `payloadExpression`: textarea -- Ruby hash for event payload; required
  - `channel`: text -- event bus/channel (optional)
- **Generates**: `ActiveSupport::Notifications.instrument("order.completed", ctx[:order].attributes)`

#### `broadcast`
- **Description**: Turbo Stream / ActionCable broadcast
- **Single-use**: No
- **Config**:
  - `broadcastType`: select -- `turbo_stream`, `action_cable`
  - `streamName`: text -- e.g., `"orders"` or `ctx[:user]`; required
  - `action`: select -- `append`, `prepend`, `replace`, `remove`, `update`; visible when `turbo_stream`
  - `target`: text -- DOM target ID; visible when `turbo_stream`
  - `partialName`: text -- e.g., `orders/order`; visible when `turbo_stream`
  - `localsExpression`: text -- locals hash; visible when `turbo_stream`
  - `dataExpression`: textarea -- payload; visible when `action_cable`
- **Generates (turbo_stream)**: `Turbo::StreamsChannel.broadcast_append_to("orders", target: "orders", partial: "orders/order", locals: { order: ctx[:model] })`

### Response (1 action)

#### `render_response`
- **Description**: Render response to client
- **Single-use**: No
- **Config**:
  - `responseFormat`: select -- `json`, `html`, `redirect`
  - `statusCode`: number -- HTTP status (default: 200); visible when `json`/`html`
  - `jsonBody`: textarea -- Ruby hash expression; visible when `json`
  - `templateName`: text -- view template; visible when `html`
  - `redirectUrl`: text -- URL/path expression; visible when `redirect`
  - `flashType`: select -- `notice`, `alert`, `none`; visible when `redirect`
  - `flashMessage`: text; visible when flashType is `notice` or `alert` (i.e., `visibleWhen: { field: "flashType", values: ["notice", "alert"] }`)
- **Generates (json)**: `ctx[:response] = { success: true, data: ctx[:model].attributes }; ctx[:http_status] = 200`
- **Generates (redirect)**: `ctx[:redirect_url] = "/orders/#{ctx[:model].id}"; ctx[:flash] = { notice: "Created!" }`

## Searchable Category Dropdown UI

The action dropdown (level 0) in the step modal is replaced with a searchable grouped dropdown. Sub-option dropdowns (level 1+) remain standard `<select>` elements.

### Implementation

- **Extend existing Stimulus controller**: `searchable_select_controller.js` already supports grouped options with collapsible headers. It will be extended with: disabled item support (for single-use actions already used), SVG icon rendering per item, and description tooltip. The existing group rendering pattern is preserved.
- **Trigger**: Looks like the current dropdown in closed state -- shows placeholder or selected action label
- **Open panel**:
  - Search input at top, auto-focused
  - Category headers (non-selectable, styled gray/uppercase)
  - Action items below each category with icon + label
  - Max height with scroll
- **Search**: Filters actions by matching against label, description, and category name. Categories with no matches are hidden.
- **Keyboard**: Arrow keys to navigate, Enter to select, Escape to close
- **Single-use actions**: Already used actions shown as disabled/grayed out with "(already used)" note
- **Integration**: Emits standard `change` event with selected value -- `StepManager.handleDropdownChange` works unchanged
- **Rendering**: `StepManager._renderDropdownLevel()` uses searchable component for level 0; standard `<select>` for level 1+

### Data Format

`getActionsByCategory()` returns:
```javascript
[
  {
    category: { key: "model", label: "Model Operations" },
    actions: [
      { value: "new_model", label: "New Model", icon: "...", color: "blue", ... },
      { value: "find_model", label: "Find Model", icon: "...", color: "cyan", ... },
      // ...
    ]
  },
  {
    category: { key: "validation", label: "Validation" },
    actions: [ ... ]
  },
  // ...
]
```

The searchable select controller transforms this into its internal rendering format.

## Expanded Step Item Configuration

Per-action configuration fields are rendered inside the expanded step item in the property editor sidebar.

### Behavior

1. **Collapsed** (default): Same compact row as today -- drag handle, icon, action label, badges, remove button
2. **Expanded** (click to toggle): Reveals action-specific config fields, then shared fields (description, keyword params), then collapsible Advanced section
3. **Auto-save**: Config field changes trigger `_dispatchEvent("stepChanged")` for auto-sync to canvas. For text/textarea fields, events fire on `change` (blur), not `input` (every keystroke), to avoid excessive updates with intermediate expression states. Select and number fields fire on `change`.
4. **Defaults**: Config starts with default values from `configSchema` when step is first added
5. **Existing flowcharts**: When a user opens an existing flowchart with a step that has no `config`, expanding the step item renders config fields pre-filled with schema defaults. Saving the flowchart persists the `config` hash (forward migration on save).

### Config Field Types

| Schema Type | Widget | Use Case |
|---|---|---|
| `text` | Text input | URLs, field names, expressions |
| `textarea` | Multi-line textarea | Request bodies, custom expressions |
| `number` | Number input with min/max | Status codes, limits, delays |
| `select` | Standard dropdown | HTTP method, file type, log level |
| `key_value_list` | Dynamic key-value pair rows with +/- buttons | Headers, field mappings, columns |

### key_value_list Widget

This is new UI work (no existing implementation). Structure:

```html
<div data-key-value-list>
  <div data-kv-row class="flex items-center gap-2">
    <input data-kv-key placeholder="Key" class="flex-1 ...">
    <input data-kv-value placeholder="Value" class="flex-1 ...">
    <button data-action="click->..." title="Remove">-</button>
  </div>
  <!-- more rows -->
  <button data-action="click->..." title="Add row">+ Add</button>
</div>
```

Data format: serialized as JSON array of `{ key: "Content-Type", value: "application/json" }` objects in the `config` hash. Follows the same +/- row pattern as existing keyword params in `StepManager`.

### Conditional Visibility

Config fields support `visibleWhen` -- same pattern as `ELEMENT_SCHEMAS`:
```javascript
{ key: "bodyTemplate", type: "textarea", visibleWhen: { field: "httpMethod", values: ["POST", "PUT", "PATCH"] } }
```

When a controlling field changes, dependent fields show/hide with transition.

### Data Persistence

Config values stored in `step.config` hash within `element.properties.steps[0]`:

```json
{
  "action": "API_call",
  "config": {
    "httpMethod": "POST",
    "url": "https://api.example.com/users",
    "authType": "bearer",
    "authToken": "ctx[:api_token]",
    "responseVar": "api_response"
  },
  "description": "",
  "selectionLabels": ["API Call"]
}
```

### Implementation

- `StepManager.buildStepConfigHTML(actionValue, currentConfig, suboption)` -- reads configSchema (or configSchemaBySubOption[suboption]) from registry, renders fields with current values
- `StepManager.collectStepConfig(stepItem)` -- extracts config values from expanded item's config inputs into a hash
- `StepManager.collectSteps()` -- updated to call `collectStepConfig(item)` for each step item and include the result as `stepData.config` in the returned step object
- `buildStepItemTemplate` in `templates.js` gains `configFieldsHTML` section inside `[data-step-details]`

## Activity Generator Integration

### Module Architecture

The monolithic `ActivityGenerator` is decomposed. Step code generators move into per-category modules:

```ruby
class ActivityGenerator
  include ActivityGenerator::BaseStepHelpers
  include ActivityGenerator::ModelSteps
  include ActivityGenerator::ValidationSteps
  include ActivityGenerator::DataSteps
  include ActivityGenerator::CommunicationSteps
  include ActivityGenerator::SecuritySteps
  include ActivityGenerator::BackgroundSteps
  include ActivityGenerator::FileSteps
  include ActivityGenerator::RealtimeSteps
  include ActivityGenerator::ResponseSteps

  STEP_ACTIONS = {
    "new_model"          => :generate_new_model,
    "find_model"         => :generate_find_model,
    "save_model"         => :generate_save_model,
    "destroy_model"      => :generate_destroy_model,
    "update_model"       => :generate_update_model,
    "query_models"       => :generate_query_models,
    "build_contract"     => :generate_build_contract,
    "validate"           => :generate_validate_contract,
    "validate_contract"  => :generate_validate_contract,
    "assign_value"       => :generate_assign_value,
    "transform"          => :generate_transform,
    "calculate"          => :generate_calculate,
    "log"                => :generate_log,
    "API_call"           => :generate_api_call,
    "send_email"         => :generate_send_email,
    "send_webhook"       => :generate_send_webhook,
    "notify"             => :generate_notify,
    "authorize"          => :generate_authorize,
    "enqueue_job"        => :generate_enqueue_job,
    "schedule_job"       => :generate_schedule_job,
    "generate_file"      => :generate_file_action,
    "upload_file"        => :generate_upload_file,
    "publish_event"      => :generate_publish_event,
    "broadcast"          => :generate_broadcast,
    "render_response"    => :generate_render_response
  }.freeze

  # Existing orchestration stays: dfs_collect_steps, generate_step_code,
  # step_declarations, step_methods, method_body, generate_process_body
end
```

Note: `"validate_contract"` alias retained for backward compatibility with existing saved flowcharts.

### Base Step Helpers

`ActivityGenerator::BaseStepHelpers` is a module (not a class) extracting shared helpers from the current `ActivityGenerator`:
- `wrap_with_retry(code, step)` -- retry logic with backoff
- `wrap_with_timeout(code, step)` -- timeout wrapping
- `wrap_with_guard(code, step)` -- guard condition wrapping
- `condition_operand_to_ruby(operand)` -- expression resolver
- `build_headers_code(headers, auth_type, config)` -- shared HTTP helper for API_call and send_webhook

### Config-Aware Generation

Every generator reads `step["config"]` with graceful defaults. Config keys are camelCase strings from JSON:

```ruby
def generate_find_model(step, _ctx)
  config = step["config"] || {}
  strategy = config["findStrategy"] || "find"
  result_var = config["resultVar"] || "model"

  case strategy
  when "find"
    <<~RUBY.chomp
      ctx[:#{result_var}] = EntityEntry.build_for(ctx[:bound_entity]).find(ctx[:id])
      true
    RUBY
  when "findBy"
    field = config["findField"] || "id"
    value = config["findValue"] || "ctx[:id]"
    <<~RUBY.chomp
      ctx[:#{result_var}] = EntityEntry.build_for(ctx[:bound_entity]).find_by!(#{field}: #{value})
      true
    RUBY
  when "where"
    field = config["findField"] || "id"
    value = config["findValue"] || "ctx[:id]"
    <<~RUBY.chomp
      ctx[:#{result_var}] = EntityEntry.build_for(ctx[:bound_entity]).where(#{field}: #{value})
      true
    RUBY
  end
end
```

### Backward Compatibility

Existing flowcharts with steps that have no `config` hash continue to work unchanged. Every generator defaults gracefully when `config` is nil or empty, producing the same output as today's generators.

## Step Presets

The existing `STEP_PRESETS` constant in `step_manager.js` (CRUD Create, Read, Update, Delete) is retained and updated:

- Preset step objects now include a `config` hash with appropriate defaults:
  ```javascript
  crud_read: {
    label: "CRUD Read",
    steps: [
      { action: "find_model", selectionLabels: ["Find Model"], config: { findStrategy: "find" } }
    ]
  }
  ```
- The preset dropdown UI in `buildStepsFieldHTML` remains unchanged.
- The `applyPreset` method passes config through to `buildStepItemHTML` and stored step data.

Note: The existing `applyPreset` method adds all preset steps to the container regardless of the 1-step limit (the limit is only enforced in `addStepFromModal`). This is existing behavior and presets remain exempt from the limit -- they represent a complete workflow pattern applied to a process element. No changes to preset behavior.

## End-to-End Data Flow

```
User clicks "Add Step"
  -> Step Modal opens with searchable category dropdown
  -> action_registry.js getActionsByCategory() provides grouped actions

User searches/selects action (e.g., "API Call")
  -> searchable_select_controller emits change event
  -> StepManager.handleDropdownChange() captures selection
  -> If action has subOptions, renders level 1 dropdown (unchanged)

User clicks "Add Step" button
  -> StepManager.addStepFromModal()
  -> Creates step: { action: "API_call", config: {defaults from configSchema}, selectionLabels: ["API Call"] }
  -> Renders collapsed step item
  -> Dispatches "stepAdded" -> auto-sync to canvas

User clicks step item to expand
  -> Reveals action-specific config fields (from configSchema)
  -> Fields pre-filled with defaults (or existing config values)

User configures fields
  -> Each change (on blur for text, on change for select) dispatches "stepChanged" -> auto-sync to canvas

Save (update/autosave)
  -> StepManager.collectSteps() reads action + config from DOM via collectStepConfig()
  -> Returns [{ action: "API_call", config: { httpMethod: "POST", ... } }]
  -> Canvas stores in element.properties.steps
  -> Persisted to flowcharts.configuration JSON column

Activity generation
  -> ActivityGenerator.new(flowchart).generate
  -> DFS traversal hits process element
  -> Reads steps[0], looks up STEP_ACTIONS["API_call"] -> :generate_api_call
  -> CommunicationSteps#generate_api_call reads step["config"]
  -> Reads config["httpMethod"], config["url"], config["authType"], etc.
  -> Builds parameterized Net::HTTP code
  -> Wraps with retry/timeout/guard if configured
  -> Returns real, runnable Ruby code
```

## Testing Strategy

### JavaScript Tests
- Action registry: category grouping, search filtering, single-use detection, getAllActions backward compat
- Searchable select controller: open/close, search, keyboard navigation, selection events, disabled items
- StepManager: config field rendering per action, config collection, visibility toggling, configSchemaBySubOption
- Templates: config field HTML generation for each field type including key_value_list
- Presets: config defaults applied correctly

### Ruby Tests (RSpec)
- Per-category step generator modules: each action with various config combinations
- Backward compatibility: steps without config produce same output as before
- `validate_contract` alias produces same output as `validate`
- Integration: full flowchart generation with configured steps end-to-end
- Edge cases: missing config fields, nil values, empty config hash

### Coverage
- Every action's code generator tested with all config variations
- Searchable dropdown tested for all 24 actions across 9 categories
- Config field visibility rules tested for each `visibleWhen` condition
- key_value_list widget: add row, remove row, collect values, empty state
