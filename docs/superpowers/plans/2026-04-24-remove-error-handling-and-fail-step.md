# Remove Error Handling and `fail` Step Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove all error-handling scaffolding from generated Trailblazer Activity code. Delete the `error_handler` flowchart element, the `process` element's `errorHandling` / `onStepFailure` advanced fields, and per-action failure-strategy enums from 17 leaf generators. Centralize error handling in `DynamicController#execute_activity`.

**Architecture:** `DynamicController#execute_activity` is the single error boundary — it already wraps activity execution in `rescue StandardError` inside an `ActiveRecord::Base.transaction`. Generated step methods return `true`/`false`; they never `rescue` and never emit `fail :handler` tracks. Exceptions from step bodies propagate untouched to the controller. Elements whose **purpose** is in-flow failure semantics (saga compensations, transactions, signal_wait, resilience primitives) keep their existing failure configuration.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, Trailblazer Activity, Reform, dry-rb, RSpec, StimulusJS, TailwindCSS, ViewComponent.

---

## File Map

**Ruby (created/deleted/modified):**
- Delete: `app/services/code_generators/element_types/error_handler/error_handler_generator.rb`
- Delete: `app/components/flowchart_elements/error_handler_element_component.rb`
- Delete: `spec/services/code_generators/element_types/error_handler/error_handler_generator_spec.rb` (if present)
- Delete: `spec/components/flowchart_elements/error_handler_element_component_spec.rb` (if present)
- Modify: `app/services/activity_generator.rb` (remove `derive_step_type` `error_handler` branch; remove `error_handlers` collection + `build_error_handler_method`; remove `fail :handle_error_in_*` declaration emission; remove `apply_process_scope_options` + caller)
- Modify: `app/components/flowchart_elements/base_element_component.rb` (remove `error_handler_icon` + dispatch)
- Modify: `app/components/admin/code_generators/index_component.rb` (remove `error_handler` icon + color entries)
- Modify: `app/components/admin/code_generators/sidebar_component.rb` (remove `error_handler` color entry)
- Modify: 17 leaf generators under `app/services/code_generators/element_types/process/*/` (strip failure enums + branches; see Phase 3)
- Modify: 17 matching spec files under `spec/services/code_generators/element_types/process/*/` (delete failure-matrix examples; keep happy-path)
- Modify: `spec/services/activity_generator_spec.rb` (delete fail-declaration + begin/rescue examples; add TODO-marker regression example)
- Modify: `spec/controllers/dynamic_controller_spec.rb` (add integration example asserting uncaught exception → 422 + rollback)
- Regenerate: `spec/support/config_schemas.rb` via `rake config_schemas:mirror`

**JavaScript (modified):**
- Modify: `app/javascript/flowchart/constants/elements.js` (remove `error_handler` from `ELEMENT_COLORS` + `DEFAULT_LABELS`)
- Modify: `app/javascript/flowchart/constants/schemas.js` (delete `error_handler` schema block; delete `process.onStepFailure` + `process.errorHandling`)
- Modify: `app/javascript/flowchart/element_renderer.js` (remove `_createErrorHandlerShape` + dispatch)
- Modify: `app/javascript/controllers/property_editor/form_builder.js` (remove `error_handler` icon; remove `error_handling` field-type branch; remove `buildErrorHandlingFieldTemplate` import)
- Modify: `app/javascript/controllers/property_editor/templates.js` (delete `buildErrorHandlingFieldTemplate` export)
- Modify: `app/javascript/controllers/property_editor/tab_manager.js` (remove `error_handler` from 3 elementTypes arrays + default-tab map)
- Modify: `app/javascript/controllers/property_editor_controller.js` (remove `_deriveLabelForErrorHandler`, `handleErrorHandlingModeChange`, `_collectErrorHandling`, `errorHandling[` skipPrefix, `_deriveLabelForErrorHandler` case)
- Modify: `app/javascript/flowchart/constants/action_configs/communication_actions.js` (remove `errorStrategy` from api_call, notify, send_webhook if present)
- Modify: `app/javascript/flowchart/constants/action_configs/file_actions.js` (remove `errorStrategy` from upload_file, download_file, decompress_files, generate_file if present)
- Modify: `app/javascript/flowchart/constants/action_configs/security_actions.js` (remove `onFailure` from authorize, decrypt_data, verify_token; remove `failAction` from authenticate)
- Modify: `app/javascript/flowchart/constants/action_configs/validation_actions.js` (remove `onFailure` from validate_contract; remove `errorStrategy` from build_contract if present)
- Modify: `app/javascript/flowchart/constants/action_configs/caching_actions.js` (remove `fallbackErrorStrategy` residue from cache_fetch)
- Modify: `app/javascript/flowchart/constants/action_configs/concurrency_actions.js` (remove `failAction` from acquire_lock)
- Modify: `app/javascript/flowchart/constants/action_configs/data_actions.js` (remove `onCastFailure` + legacy `onFailure` from type_cast)
- Modify: `app/javascript/flowchart/constants/action_configs/utility_actions.js` (remove `errorStrategy` from i18n_translate if present)

**Unchanged (explicitly kept):**
- `app/services/code_generators/element_types/saga/saga_generator.rb` — `onCompensationFailure`
- `app/services/code_generators/element_types/transaction/transaction_generator.rb` — `errorStrategy`
- `app/services/code_generators/element_types/signal_wait/signal_wait_generator.rb` — `errorStrategy`
- `app/services/code_generators/element_types/process/resilience/*` — retry_with_backoff, circuit_breaker, rate_limiter, idempotency_check
- `app/controllers/dynamic_controller.rb` — already the intended error boundary

---

## Ground Rules

1. **No git commits from the agent.** AGENTS.md forbids auto-commits; each task ends by showing `git status`/`git diff` so the user can review and commit manually.
2. **TDD order.** For each task: write/modify failing test → run it → implement change → run test → verify green.
3. **Run the full scoped suite after each phase.** Target command:
   ```
   bundle exec rspec spec/services/code_generators spec/services/activity_generator_spec.rb spec/components/flowchart_elements spec/controllers/dynamic_controller_spec.rb spec/scripts/audit_generator_ui_spec.rb
   ```
4. **Use dedicated tools.** Prefer Read/Edit/Write over `cat`/`sed`/`echo`.
5. **Preserve all other behavior.** No unrelated refactors. If a spec example also tests an unrelated behavior alongside the error-strategy assertion, split it — don't delete the rest.

---

## Phase 1 — Delete the `error_handler` Element

### Task 1: Baseline the current suite

**Files:** None modified.

- [ ] **Step 1: Run the scoped suite to capture current baseline**

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/services/code_generators spec/services/activity_generator_spec.rb spec/components/flowchart_elements spec/controllers/dynamic_controller_spec.rb spec/scripts/audit_generator_ui_spec.rb 2>&1 | tail -10
```

Expected: a line like `NNNN examples, 0 failures`. Record the number — it's the "before" baseline. All subsequent phases must stay at 0 failures.

- [ ] **Step 2: Confirm git working tree is clean**

Run: `cd /opt/milestone/anysys && git status`
Expected: `nothing to commit, working tree clean`. If not, stop and ask the user.

---

### Task 2: Remove `error_handler` from the JS palette + element constants

**Files:**
- Modify: `app/javascript/flowchart/constants/elements.js`
- Modify: `app/javascript/flowchart/constants/schemas.js` (delete `error_handler:` block at lines ~572–625)

- [ ] **Step 1: Remove `error_handler` from `ELEMENT_COLORS` and `DEFAULT_LABELS`**

In `app/javascript/flowchart/constants/elements.js`, delete these two lines:

```javascript
  error_handler: { fill: "#fff7ed", stroke: "#ea580c" },
```

```javascript
  error_handler: "Error Handler",
```

- [ ] **Step 2: Delete the `error_handler` schema block**

In `app/javascript/flowchart/constants/schemas.js`, delete the entire block starting with `error_handler: {` and ending with its closing `},`. It contains the `label`, `errorTypes`, `fallbackAction`, `customMessage`, `errorClassPattern`, `errorClassPatterns`, `notifyOnError`, `captureBacktrace`, `description` fields.

- [ ] **Step 3: Verify no remaining `error_handler` JS references in these files**

Run:
```
cd /opt/milestone/anysys && grep -n "error_handler" app/javascript/flowchart/constants/elements.js app/javascript/flowchart/constants/schemas.js
```
Expected: no output.

---

### Task 3: Remove `error_handler` shape rendering

**Files:**
- Modify: `app/javascript/flowchart/element_renderer.js`

- [ ] **Step 1: Remove shape dispatch and method**

In `app/javascript/flowchart/element_renderer.js`:
- Delete the line `error_handler: this._createErrorHandlerShape,` (around line 290).
- Delete the `_createErrorHandlerShape(element, colors) { ... }` method (around line 541) and its body, including its closing brace.

- [ ] **Step 2: Verify no remaining references**

Run:
```
cd /opt/milestone/anysys && grep -n "ErrorHandler\|error_handler" app/javascript/flowchart/element_renderer.js
```
Expected: no output.

---

### Task 4: Remove `error_handler` from property editor + tab manager

**Files:**
- Modify: `app/javascript/controllers/property_editor/form_builder.js`
- Modify: `app/javascript/controllers/property_editor/tab_manager.js`
- Modify: `app/javascript/controllers/property_editor_controller.js`

- [ ] **Step 1: Remove `error_handler` from form_builder icon map**

In `app/javascript/controllers/property_editor/form_builder.js` line ~19, delete:

```javascript
  error_handler: "M12 9v2m0 4h.01M5.07 19H19a2 2 0 001.75-2.97L13.75 4a2 2 0 00-3.5 0L3.32 16.03A2 2 0 005.07 19z",
```

- [ ] **Step 2: Remove `error_handler` from tab_manager elementTypes arrays + default-tab map**

In `app/javascript/controllers/property_editor/tab_manager.js`, remove every occurrence of `"error_handler"` from the three `elementTypes:` arrays (lines ~16, ~24, ~28) and delete the `error_handler: "advanced"` line from the default-tab map (line ~70).

- [ ] **Step 3: Remove `_deriveLabelForErrorHandler` and its dispatch**

In `app/javascript/controllers/property_editor_controller.js`:
- Remove the dispatch lines (around line 886):
  ```javascript
        case "error_handler":
          return this._deriveLabelForErrorHandler(properties)
  ```
- Remove the `_deriveLabelForErrorHandler(properties) { ... }` method (around line 966) and its body.

- [ ] **Step 4: Verify**

Run:
```
cd /opt/milestone/anysys && grep -rn "error_handler\|deriveLabelForErrorHandler" app/javascript/controllers/property_editor/ app/javascript/controllers/property_editor_controller.js
```
Expected: no output.

---

### Task 5: Remove `error_handler` Ruby ViewComponent + related admin component entries

**Files:**
- Delete: `app/components/flowchart_elements/error_handler_element_component.rb`
- Delete: `spec/components/flowchart_elements/error_handler_element_component_spec.rb` (if it exists)
- Modify: `app/components/flowchart_elements/base_element_component.rb` (remove `error_handler_icon` method + dispatch)
- Modify: `app/components/admin/code_generators/index_component.rb` (remove `error_handler` icon + color entries)
- Modify: `app/components/admin/code_generators/sidebar_component.rb` (remove `error_handler` color entry)

- [ ] **Step 1: Check for the spec file**

Run:
```
cd /opt/milestone/anysys && ls spec/components/flowchart_elements/error_handler_element_component_spec.rb 2>/dev/null
```

If present, delete: `rm spec/components/flowchart_elements/error_handler_element_component_spec.rb`

- [ ] **Step 2: Delete the ViewComponent**

Run: `rm /opt/milestone/anysys/app/components/flowchart_elements/error_handler_element_component.rb`

- [ ] **Step 3: Remove `error_handler_icon` method and dispatch in base_element_component.rb**

In `app/components/flowchart_elements/base_element_component.rb`:
- Delete the `when 'error_handler' then error_handler_icon` line inside the icon dispatch `case` (around line 188).
- Delete the `def error_handler_icon ... end` method (around line 153).

- [ ] **Step 4: Remove `error_handler` entries from admin code_generators components**

In `app/components/admin/code_generators/index_component.rb`:
- Delete the `error_handler:` icon line (around line 12).
- Delete the `error_handler: { ... }` color line (around line 25).

In `app/components/admin/code_generators/sidebar_component.rb`:
- Delete the `"error_handler" => "bg-rose-500",` entry (around line 11).

- [ ] **Step 5: Verify**

Run:
```
cd /opt/milestone/anysys && grep -rn "error_handler" app/components/
```
Expected: no output.

---

### Task 6: Write failing activity_generator regression spec for unknown element type

**Files:**
- Modify: `spec/services/activity_generator_spec.rb`

- [ ] **Step 1: Find an appropriate location in activity_generator_spec.rb**

Open `spec/services/activity_generator_spec.rb` and scroll to a `describe` or `context` block that exercises `method_body` / `generate_process_body` / unknown-element handling. If none exists, create a new `describe "unknown element types"` block at the end of the top-level `describe` block.

- [ ] **Step 2: Add a failing spec asserting `error_handler` now produces the TODO marker**

Add this example (adapt variable names to match existing patterns in that spec file; the factory helpers used elsewhere in the file are the canonical way to build `flowchart` / `element` fixtures):

```ruby
describe "a persisted error_handler node after removal" do
  it "emits a TODO marker in the generated activity code" do
    # Build a minimal flowchart whose JSON graph contains an error_handler element
    # (use whichever factory/builder pattern the rest of this spec uses to construct fixtures)
    flowchart = build_flowchart_with_elements(
      elements: [
        { "id" => "start-1", "type" => "start", "label" => "Start" },
        { "id" => "eh-1",    "type" => "error_handler", "label" => "Leftover EH" },
        { "id" => "end-1",   "type" => "end",   "label" => "End" }
      ],
      connections: [
        { "from" => "start-1", "to" => "eh-1" },
        { "from" => "eh-1",    "to" => "end-1" }
      ]
    )

    code = described_class.new(flowchart).generate

    expect(code).to include("# TODO: unknown element type 'error_handler'")
  end
end
```

If the existing spec does not have a `build_flowchart_with_elements` helper, use the same fixture pattern already used elsewhere in `activity_generator_spec.rb` (look at another `describe` block for the pattern — typically a `let(:flowchart)` that builds a Flowchart model with a graph hash).

- [ ] **Step 3: Run the new spec — expect it to FAIL (initially)**

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/services/activity_generator_spec.rb -e "persisted error_handler node after removal"
```

It will fail now because the `error_handler` generator still exists and `derive_step_type` still returns `"fail"` for it. That's expected — Task 7 is the removal that makes this pass.

---

### Task 7: Delete the `error_handler` generator and remove activity_generator references

**Files:**
- Delete: `app/services/code_generators/element_types/error_handler/error_handler_generator.rb`
- Delete: `spec/services/code_generators/element_types/error_handler/error_handler_generator_spec.rb` (if present)
- Delete: `app/services/code_generators/element_types/error_handler/` directory (if empty after above deletes)
- Modify: `app/services/activity_generator.rb`

- [ ] **Step 1: Delete the generator file (and its spec, directory)**

Run:
```
cd /opt/milestone/anysys
rm app/services/code_generators/element_types/error_handler/error_handler_generator.rb
rm -f spec/services/code_generators/element_types/error_handler/error_handler_generator_spec.rb
rmdir app/services/code_generators/element_types/error_handler 2>/dev/null
rmdir spec/services/code_generators/element_types/error_handler 2>/dev/null
```

- [ ] **Step 2: Remove the `error_handler` branch in `derive_step_type`**

In `app/services/activity_generator.rb` around line 460–466, change:

```ruby
  def derive_step_type(element)
    case element["type"]
    when "error_handler" then "fail"
    when "fork" then "pass"
    else "step"
    end
  end
```

to:

```ruby
  def derive_step_type(element)
    case element["type"]
    when "fork" then "pass"
    else "step"
    end
  end
```

- [ ] **Step 3: Remove the `fail :handle_error_in_*` declaration append in `step_declarations`**

In `app/services/activity_generator.rb` around lines 440–458, change:

```ruby
  def step_declarations(steps)
    return "# No steps defined" if steps.empty?

    steps.map { |s|
      if s[:subprocess]
        build_subprocess_declaration(s)
      else
        step_type = derive_step_type(s[:element])
        declaration = "#{step_type} :#{s[:method_name]}"

        error_handling = s[:element].dig("properties", "errorHandling")
        if error_handling && error_handling["mode"] == "route_to_error_end"
          declaration += "\nfail :handle_error_in_#{s[:method_name]}"
        end

        declaration
      end
    }.join("\n")
  end
```

to:

```ruby
  def step_declarations(steps)
    return "# No steps defined" if steps.empty?

    steps.map { |s|
      if s[:subprocess]
        build_subprocess_declaration(s)
      else
        "#{derive_step_type(s[:element])} :#{s[:method_name]}"
      end
    }.join("\n")
  end
```

- [ ] **Step 4: Remove `error_handlers` collection and `build_error_handler_method` method**

In `app/services/activity_generator.rb` around lines 509–571, change the `step_methods` method from:

```ruby
  def step_methods(steps)
    return "" if steps.empty?

    regular_steps = steps.reject { |s| s[:subprocess] }
    methods = regular_steps.map { |s| build_method(s) }

    error_handlers = regular_steps
      .select { |s| s[:element].dig("properties", "errorHandling", "mode") == "route_to_error_end" }
      .map { |s| build_error_handler_method(s) }

    (methods + error_handlers).join("\n\n")
  end
```

to:

```ruby
  def step_methods(steps)
    return "" if steps.empty?

    regular_steps = steps.reject { |s| s[:subprocess] }
    regular_steps.map { |s| build_method(s) }.join("\n\n")
  end
```

Then delete the entire `build_error_handler_method(step_info)` method (around lines 560–571):

```ruby
  def build_error_handler_method(step_info)
    method_name = step_info[:method_name]
    error_field = step_info[:element].dig("properties", "errorHandling", "errorOutputField") || "ctx.error"
    field_key = error_field.sub(/^ctx\./, "")

    <<~RUBY.chomp
      # Error handler for #{step_info[:element]['label']}
      def handle_error_in_#{method_name}(ctx, **)
        ctx[:#{field_key}] = ctx["contract.default"]&.errors&.full_messages || ["An error occurred"]
      end
    RUBY
  end
```

— delete all of it.

- [ ] **Step 5: Run the Task 6 regression spec — expect PASS**

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/services/activity_generator_spec.rb -e "persisted error_handler node after removal"
```
Expected: PASS.

- [ ] **Step 6: Run the full scoped suite — expect some failures (to be fixed in subsequent tasks)**

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/services/activity_generator_spec.rb 2>&1 | tail -20
```

Note any examples that reference `fail :handle_error_in_*`, `error_handler`, or `handle_error_in_`. Those will be cleaned up in Task 8.

---

### Task 8: Clean up obsolete `activity_generator_spec` examples for `error_handler` / `handle_error_in_*`

**Files:**
- Modify: `spec/services/activity_generator_spec.rb`

- [ ] **Step 1: Find examples that reference the removed features**

Run:
```
cd /opt/milestone/anysys && grep -n "handle_error_in\|error_handler\|errorHandling\|route_to_error_end" spec/services/activity_generator_spec.rb
```

Note each line. Do NOT touch the Task-6 regression example (which uses `error_handler` legitimately to test the TODO-marker path).

- [ ] **Step 2: Remove obsolete examples**

For each example whose ONLY purpose is to assert `fail :handle_error_in_*` declarations, the emission of `handle_error_in_*` methods, or `errorHandling.mode` branches in process elements, delete the entire `it "..." do ... end` block.

For examples where the obsolete assertion is bundled with other (still-valid) assertions, surgically remove only the obsolete `expect(...)` line(s) so the valid assertions remain.

- [ ] **Step 3: Run — expect PASS**

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/services/activity_generator_spec.rb 2>&1 | tail -10
```
Expected: `N examples, 0 failures`.

- [ ] **Step 4: Stop and show diff to user**

Run: `cd /opt/milestone/anysys && git status && git diff --stat`

Phase 1 complete. User reviews and commits manually.

---

## Phase 2 — Delete `errorHandling` + `onStepFailure` on `process` Element

### Task 9: Delete `onStepFailure` + `errorHandling` from JS schema

**Files:**
- Modify: `app/javascript/flowchart/constants/schemas.js`

- [ ] **Step 1: Remove `onStepFailure` and `errorHandling` from the process schema**

In `app/javascript/flowchart/constants/schemas.js` around lines 340–368, change the `process:` block from:

```javascript
  process: {
    label: COMMON_PROPERTIES.label,
    steps: {
      type: "steps",
      label: "Steps",
      actionOptions: STEP_ACTIONS,
      tab: "steps"
    },
    description: {
      ...COMMON_PROPERTIES.description,
      placeholder: "Describe what this process does..."
    },
    onStepFailure: {
      type: "select",
      label: "On Step Failure",
      options: [
        { value: "halt", label: "Halt" },
        { value: "continue", label: "Continue" },
        { value: "retry", label: "Retry" }
      ],
      default: "halt",
      tab: "advanced"
    },
    errorHandling: {
      type: "error_handling",
      label: "Error Handling",
      tab: "advanced"
    }
  },
```

to:

```javascript
  process: {
    label: COMMON_PROPERTIES.label,
    steps: {
      type: "steps",
      label: "Steps",
      actionOptions: STEP_ACTIONS,
      tab: "steps"
    },
    description: {
      ...COMMON_PROPERTIES.description,
      placeholder: "Describe what this process does..."
    }
  },
```

- [ ] **Step 2: Verify**

Run:
```
cd /opt/milestone/anysys && grep -n "onStepFailure\|errorHandling\|error_handling" app/javascript/flowchart/constants/schemas.js
```
Expected: no output.

---

### Task 10: Delete `error_handling` field type + template + controller wiring

**Files:**
- Modify: `app/javascript/controllers/property_editor/form_builder.js`
- Modify: `app/javascript/controllers/property_editor/templates.js`
- Modify: `app/javascript/controllers/property_editor_controller.js`

- [ ] **Step 1: Remove `error_handling` field-type branch + import in form_builder.js**

In `app/javascript/controllers/property_editor/form_builder.js`:

Remove the import line at the top:
```javascript
import { buildErrorHandlingFieldTemplate } from "controllers/property_editor/templates"
```

Remove the `error_handling` field-type branch (around lines 156–159):
```javascript
    // Handle error_handling field type
    if (fieldSchema.type === "error_handling") {
      return buildErrorHandlingFieldTemplate(fieldName, currentValue)
    }
```

- [ ] **Step 2: Delete `buildErrorHandlingFieldTemplate` from templates.js**

In `app/javascript/controllers/property_editor/templates.js`, delete the entire `// Error Handling Templates` section header, the preceding divider comments, and the full `export function buildErrorHandlingFieldTemplate(fieldName, currentValue) { ... }` function (lines ~874–914).

- [ ] **Step 3: Delete `handleErrorHandlingModeChange`, `_collectErrorHandling`, and all wiring in property_editor_controller.js**

In `app/javascript/controllers/property_editor_controller.js`:

Delete the entire `handleErrorHandlingModeChange(event) { ... }` method (around lines 587–598).

Remove `"errorHandling["` from the `skipPrefixes` array (around line 824):
```javascript
    const skipPrefixes = ["steps[", "branches[", "condition[", "errorHandling["]
```
changes to:
```javascript
    const skipPrefixes = ["steps[", "branches[", "condition["]
```

Delete these two lines (around lines 844–845):
```javascript
    // Collect error handling data (for Process elements)
    const errorHandling = this._collectErrorHandling()
    if (errorHandling !== null) newProperties.errorHandling = errorHandling
```

Delete the `_collectErrorHandling() { ... }` method entirely (around lines 1175–1186).

- [ ] **Step 4: Verify**

Run:
```
cd /opt/milestone/anysys && grep -rn "errorHandling\|error_handling\|buildErrorHandlingFieldTemplate\|handleErrorHandlingModeChange\|_collectErrorHandling" app/javascript/
```
Expected: no output.

---

### Task 11: Remove `apply_process_scope_options` from activity_generator.rb

**Files:**
- Modify: `app/services/activity_generator.rb`

- [ ] **Step 1: Find the caller**

Run:
```
cd /opt/milestone/anysys && grep -n "apply_process_scope_options" app/services/activity_generator.rb
```

Note the definition (~line 795) and caller site(s). There is typically one caller inside `build_method` or `method_body`.

- [ ] **Step 2: Remove the call site**

Find the single caller — it wraps a `body` variable. Replace `apply_process_scope_options(element, body)` with just `body` (passing through unmodified).

- [ ] **Step 3: Delete the method definition**

Delete the entire `apply_process_scope_options(element, body)` method (lines ~791–826) including its preceding doc comment (`# Honours the \`onStepFailure\`...`).

- [ ] **Step 4: Verify**

Run:
```
cd /opt/milestone/anysys && grep -n "apply_process_scope_options\|onStepFailure" app/services/activity_generator.rb
```
Expected: no output.

---

### Task 12: Update activity_generator_spec for deleted `onStepFailure` / `errorHandling` examples

**Files:**
- Modify: `spec/services/activity_generator_spec.rb`

- [ ] **Step 1: Find examples**

Run:
```
cd /opt/milestone/anysys && grep -n "onStepFailure\|apply_process_scope_options\|begin\\\\n.*rescue\|errorHandling" spec/services/activity_generator_spec.rb
```

- [ ] **Step 2: Delete or rewrite**

For examples asserting `onStepFailure: "continue" / "retry"` → `begin/rescue`: delete the entire `it` block.
For examples bundling unrelated assertions: remove only the obsolete `expect(...)` lines.

- [ ] **Step 3: Run — expect PASS**

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/services/activity_generator_spec.rb 2>&1 | tail -10
```
Expected: `N examples, 0 failures`.

- [ ] **Step 4: Stop and show diff to user**

Run: `cd /opt/milestone/anysys && git status && git diff --stat`

Phase 2 complete.

---

## Phase 3a — Strip Failure Enums: Communication + File Operations

> Structural pattern repeated for each generator in this phase: (a) modify generator spec to remove or rewrite failure-strategy examples, (b) delete unused `ERROR_STRATEGIES` constant from generator, (c) remove any `errorStrategy` UI field from `action_configs/*.js`, (d) run the generator's spec green.

### Task 13: `api_call_generator` — remove unused `ERROR_STRATEGIES` constant

**Files:**
- Modify: `app/services/code_generators/element_types/process/communication/api_call_generator.rb`

- [ ] **Step 1: Confirm `ERROR_STRATEGIES` is unused in the generator**

Run:
```
cd /opt/milestone/anysys && grep -n "ERROR_STRATEGIES\|errorStrategy" app/services/code_generators/element_types/process/communication/api_call_generator.rb
```
Expected: only the constant definition on line ~13.

- [ ] **Step 2: Delete the constant**

In `app/services/code_generators/element_types/process/communication/api_call_generator.rb`, delete this line:

```ruby
          ERROR_STRATEGIES  = %w[continue fail_track raise].freeze
```

- [ ] **Step 3: Run the spec — expect PASS**

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/services/code_generators/element_types/process/communication/api_call_generator_spec.rb
```
Expected: all examples pass.

---

### Task 14: `notify_generator` — remove unused `ERROR_STRATEGIES` constant

**Files:**
- Modify: `app/services/code_generators/element_types/process/communication/notify_generator.rb`

- [ ] **Step 1: Confirm unused, delete, run spec**

Run:
```
cd /opt/milestone/anysys && grep -n "ERROR_STRATEGIES\|errorStrategy" app/services/code_generators/element_types/process/communication/notify_generator.rb
```

If only the definition appears, delete it (the `ERROR_STRATEGIES = %w[continue fail_track raise].freeze` line ~12).

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/services/code_generators/element_types/process/communication/notify_generator_spec.rb
```
Expected: PASS.

---

### Task 15: `send_webhook_generator` — remove unused `ERROR_STRATEGIES` constant

**Files:**
- Modify: `app/services/code_generators/element_types/process/communication/send_webhook_generator.rb`

- [ ] **Step 1: Same procedure as Task 14**

Run:
```
cd /opt/milestone/anysys && grep -n "ERROR_STRATEGIES\|errorStrategy" app/services/code_generators/element_types/process/communication/send_webhook_generator.rb
```

If only the definition appears, delete the `ERROR_STRATEGIES = %w[continue fail_track raise].freeze` line ~11.

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/services/code_generators/element_types/process/communication/send_webhook_generator_spec.rb
```
Expected: PASS.

---

### Task 16: Remove `errorStrategy` UI fields (communication + file) from action_configs

**Files:**
- Modify: `app/javascript/flowchart/constants/action_configs/communication_actions.js`
- Modify: `app/javascript/flowchart/constants/action_configs/file_actions.js`

- [ ] **Step 1: Grep each file for `errorStrategy`**

Run:
```
cd /opt/milestone/anysys && grep -n "errorStrategy" app/javascript/flowchart/constants/action_configs/communication_actions.js app/javascript/flowchart/constants/action_configs/file_actions.js
```

For each occurrence:
- Find the enclosing field definition object (`{ key: "errorStrategy", ... }`).
- Delete the whole object, including any trailing comma.
- If the deletion leaves a trailing comma at the end of a `fields: [...]` array, clean that up too.

- [ ] **Step 2: Verify**

Run:
```
cd /opt/milestone/anysys && grep -n "errorStrategy" app/javascript/flowchart/constants/action_configs/
```
Expected: no output.

---

### Task 17: `upload_file_generator` — remove unused `ERROR_STRATEGIES`

**Files:**
- Modify: `app/services/code_generators/element_types/process/file_operations/upload_file_generator.rb`

- [ ] **Step 1: Same procedure**

Run:
```
cd /opt/milestone/anysys && grep -n "ERROR_STRATEGIES\|errorStrategy" app/services/code_generators/element_types/process/file_operations/upload_file_generator.rb
```

If only the definition, delete `ERROR_STRATEGIES = %w[continue fail_track raise].freeze` line ~10.

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/services/code_generators/element_types/process/file_operations/upload_file_generator_spec.rb
```
Expected: PASS.

---

### Task 18: `download_file_generator` — remove unused `ERROR_STRATEGIES`

**Files:**
- Modify: `app/services/code_generators/element_types/process/file_operations/download_file_generator.rb`

- [ ] **Step 1: Same procedure**

Delete the `ERROR_STRATEGIES = %w[continue fail_track raise].freeze` line ~8.

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/services/code_generators/element_types/process/file_operations/download_file_generator_spec.rb
```
Expected: PASS.

---

### Task 19: `decompress_files_generator` — remove unused `ERROR_STRATEGIES`

**Files:**
- Modify: `app/services/code_generators/element_types/process/file_operations/decompress_files_generator.rb`

- [ ] **Step 1: Same procedure**

Delete the `ERROR_STRATEGIES = %w[continue fail_track raise].freeze` line ~8.

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/services/code_generators/element_types/process/file_operations/decompress_files_generator_spec.rb
```
Expected: PASS.

---

### Task 20: `generate_file_generator` — remove unused `ERROR_STRATEGIES`

**Files:**
- Modify: `app/services/code_generators/element_types/process/file_operations/generate_file_generator.rb`

- [ ] **Step 1: Same procedure**

Delete the `ERROR_STRATEGIES = %w[continue fail_track raise].freeze` line ~10.

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/services/code_generators/element_types/process/file_operations/generate_file_generator_spec.rb
```
Expected: PASS.

---

### Task 21: Phase 3a checkpoint

- [ ] **Step 1: Run the scoped suite**

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/services/code_generators/element_types/process/communication spec/services/code_generators/element_types/process/file_operations
```
Expected: `N examples, 0 failures`.

- [ ] **Step 2: Show diff to user**

Run: `cd /opt/milestone/anysys && git status && git diff --stat`

Phase 3a complete.

---

## Phase 3b — Strip Failure Enums: Security + Validation

> These generators actively use their failure enums in generated code — removing them requires removing the generated branches as well as the constants, updating `validate_config`, `sample_input`, and spec examples.

### Task 22: `authorize_generator` — remove `onFailure` + `FAILURE_ACTIONS`

**Files:**
- Modify: `app/services/code_generators/element_types/process/security/authorize_generator.rb`
- Modify: `spec/services/code_generators/element_types/process/security/authorize_generator_spec.rb`
- Modify: `app/javascript/flowchart/constants/action_configs/security_actions.js` (authorize's `onFailure` block)

- [ ] **Step 1: Update `authorize_generator_spec.rb` — remove `onFailure` matrix, keep single happy-path**

Open `spec/services/code_generators/element_types/process/security/authorize_generator_spec.rb`. Find every example that asserts `onFailure: "raise"` → `raise` emission, `onFailure: "return_false"` → `return false` emission, `onFailure: "redirect"` → `ctx[:redirect_to]` emission, or `FAILURE_ACTIONS` validation.

Delete those `it` blocks. Keep examples that test the authorization check itself (role_check, policy_check, etc.).

Add (or keep) a single example asserting the generator still emits a happy-path `true`-returning body on any valid `authType` config.

- [ ] **Step 2: Strip the `onFailure` code paths in the generator**

In `app/services/code_generators/element_types/process/security/authorize_generator.rb`:

Delete the `FAILURE_ACTIONS` constant (line ~12).

Delete the `onFailure` validation branch in `validate_config` (lines ~40–42):
```ruby
            if cfg["onFailure"].present? && !FAILURE_ACTIONS.include?(cfg["onFailure"])
              errors << "Invalid onFailure: #{cfg['onFailure']}. Must be one of: #{FAILURE_ACTIONS.join(', ')}"
            end
```

Change the `generate_body` method (lines ~24–30) from:

```ruby
          def generate_body
            auth_type    = fetch_enum("authType", AUTH_TYPES, default: "role_check")
            user         = condition_operand_to_ruby(config["userExpression"] || "ctx.current_user")
            check        = build_check(auth_type, user)

            on_failure_wrap(check)
          end
```

to:

```ruby
          def generate_body
            auth_type = fetch_enum("authType", AUTH_TYPES, default: "role_check")
            user      = condition_operand_to_ruby(config["userExpression"] || "ctx.current_user")
            check     = build_check(auth_type, user)

            <<~RUBY.chomp
              return false unless #{check}
              true
            RUBY
          end
```

Delete the entire `on_failure_wrap(check)` method (lines ~118–147) including its preceding doc comment.

- [ ] **Step 3: Remove `onFailure` from `security_actions.js` for authorize**

Open `app/javascript/flowchart/constants/action_configs/security_actions.js`. Find the authorize action's field list (around lines ~112–138 — the block before `failureMessage` and `redirectPath`).

Delete:
- The `{ key: "onFailure", ... }` field object (lines ~113–122)
- The `{ key: "failureMessage", ..., visibleWhen: { field: "onFailure", ... } }` field object (lines ~124–130)
- The `{ key: "redirectPath", ..., visibleWhen: { field: "onFailure", ... } }` field object (lines ~131–138)

(These three fields lose their reason to exist once `onFailure` is gone. `failureMessage` was only shown on raise; `redirectPath` was only shown on redirect.)

- [ ] **Step 4: Run the spec — expect PASS**

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/services/code_generators/element_types/process/security/authorize_generator_spec.rb
```
Expected: PASS.

---

### Task 23: `authenticate_generator` — remove `failAction` + `ERROR_STRATEGIES`

**Files:**
- Modify: `app/services/code_generators/element_types/process/security/authenticate_generator.rb`
- Modify: `spec/services/code_generators/element_types/process/security/authenticate_generator_spec.rb`
- Modify: `app/javascript/flowchart/constants/action_configs/security_actions.js` (authenticate's `failAction` block ~288)

- [ ] **Step 1: Update the spec**

Open `spec/services/code_generators/element_types/process/security/authenticate_generator_spec.rb`. Find examples asserting `failAction: "raise"` → `raise "Authentication failed"` emission or `failAction: "fail_track"` → `Railway.fail!` emission. Delete those `it` blocks. Keep examples exercising each `authMethod` branch.

- [ ] **Step 2: Strip the generator**

In `app/services/code_generators/element_types/process/security/authenticate_generator.rb`:

Delete `ERROR_STRATEGIES` constant (line ~11).

Remove `"failAction" => "fail_track",` from `sample_input` (line ~25).

Remove the `fail_action` variable and propagation. The pattern across the generator is:

```ruby
fail_action = config["failAction"] || "fail_track"
# ... used to pick between: raise "Authentication failed"  vs  Railway.fail!
fail_line = fail_action == "raise" ? 'raise "Authentication failed"' : "Railway.fail!"
```

Replace every such `fail_line` / `fail_action` site with a constant string `"return false"` — making the generator emit `return false` on failure (the ActivityTracer interprets `false` as a flow failure, which the controller rescues).

Specifically:

- Delete line ~37: `fail_action = config["failAction"] || "fail_track"`
- Change the call to `prepend_attempt_guards(inner, fail_action)` to `prepend_attempt_guards(inner)`
- In each `generate_*` helper that takes `fail_action`, remove the parameter and change `fail_line = fail_action == "raise" ? 'raise "Authentication failed"' : "Railway.fail!"` to `fail_line = "return false"`
- Same for line ~189 inline ternary (`#{config['failAction'] == 'raise' ? ... : ...}` → `return false`)
- Same for line ~232 `fail_action = config["failAction"] || "fail_track"` inside `generate_jwt`
- Update `prepend_attempt_guards(inner, fail_action)` signature to drop the param; same for the lockout/max-attempts branches (they used `fail_line`)

- [ ] **Step 3: Remove `failAction` from `security_actions.js`**

In `app/javascript/flowchart/constants/action_configs/security_actions.js` around lines ~286–296, delete:

```javascript
      {
        key: "failAction",
        type: "select",
        label: "Fail Action",
        default: "fail_track",
        options: [
          { value: "fail_track", label: "fail_track" },
          { value: "raise", label: "raise" }
        ]
      },
```

(Clean up any trailing comma left behind.)

- [ ] **Step 4: Run spec — expect PASS**

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/services/code_generators/element_types/process/security/authenticate_generator_spec.rb
```
Expected: PASS.

---

### Task 24: `decrypt_data_generator` — remove `onFailure` + `ON_FAILURES` + `ERROR_STRATEGIES`

**Files:**
- Modify: `app/services/code_generators/element_types/process/security/decrypt_data_generator.rb`
- Modify: `spec/services/code_generators/element_types/process/security/decrypt_data_generator_spec.rb`
- Modify: `app/javascript/flowchart/constants/action_configs/security_actions.js` (decrypt's `onFailure` block ~499)

- [ ] **Step 1: Update the spec**

Delete examples asserting `onFailure: "raise"` → `raise` emission, `onFailure: "nil"` → rescue sets target to nil, or `onFailure: "original"` → returns ciphertext unchanged. Keep the happy-path decryption examples.

- [ ] **Step 2: Strip the generator**

In `app/services/code_generators/element_types/process/security/decrypt_data_generator.rb`:

Delete both constants at lines ~12–13:
```ruby
          ON_FAILURES     = %w[raise nil original].freeze
          ERROR_STRATEGIES = %w[continue fail_track raise].freeze
```

Remove `"onFailure" => "raise"` from `sample_input` (line ~33).

Remove the `fetch_enum("onFailure", ...)` call at line ~44 and the `wrap_with_on_failure(inner, on_fail, source, target)` call at line ~70 — replace with a direct `inner` return (or whatever happy-path body `inner` represents).

Delete the `wrap_with_on_failure` method (lines ~159 onward).

Remove the `validate_config` `onFailure` branch at lines ~90–91.

- [ ] **Step 3: Remove `onFailure` from `security_actions.js` for decrypt**

Delete the `{ key: "onFailure", ... }` block around lines ~499–510.

- [ ] **Step 4: Run spec — expect PASS**

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/services/code_generators/element_types/process/security/decrypt_data_generator_spec.rb
```
Expected: PASS.

---

### Task 25: `verify_token_generator` — remove `onFailure` + `ON_FAILURE` + `ERROR_STRATEGIES`

**Files:**
- Modify: `app/services/code_generators/element_types/process/security/verify_token_generator.rb`
- Modify: `spec/services/code_generators/element_types/process/security/verify_token_generator_spec.rb`
- Modify: `app/javascript/flowchart/constants/action_configs/security_actions.js` (verify_token's `onFailure` block ~1002)

- [ ] **Step 1: Update the spec**

Delete examples asserting `onFailure: "raise"` → raise, `onFailure: "false"` → `return false`, `onFailure: "nil"` → sets target to nil. Keep happy-path token-verification examples.

- [ ] **Step 2: Strip the generator**

In `app/services/code_generators/element_types/process/security/verify_token_generator.rb`:

Delete `ERROR_STRATEGIES` and `ON_FAILURE` constants (lines ~9–10).

Remove the `on_failure = ON_FAILURE.include?(...) ? ... : "raise"` lookup (line ~32).

Remove the `failure_handler_line(on_failure, target)` call (line ~69) — replace with a direct `return false` on the failure path, or remove entirely if that branch can just fall through.

Delete the `failure_handler_line(on_failure, target)` method (lines ~120 onward).

Remove the `validate_config` `onFailure` check (lines ~83–85).

- [ ] **Step 3: Remove `onFailure` from `security_actions.js` for verify_token**

Delete the `{ key: "onFailure", ... }` block around lines ~1002–1013.

- [ ] **Step 4: Run spec — expect PASS**

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/services/code_generators/element_types/process/security/verify_token_generator_spec.rb
```
Expected: PASS.

---

### Task 26: `build_contract_generator` — remove unused `ERROR_STRATEGIES`

**Files:**
- Modify: `app/services/code_generators/element_types/process/validation/build_contract_generator.rb`

- [ ] **Step 1: Confirm unused, delete**

Run:
```
cd /opt/milestone/anysys && grep -n "ERROR_STRATEGIES\|errorStrategy" app/services/code_generators/element_types/process/validation/build_contract_generator.rb
```
Expected: only the definition on line ~10. If so, delete the `ERROR_STRATEGIES = %w[continue fail_track raise].freeze` line.

- [ ] **Step 2: Run spec — expect PASS**

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/services/code_generators/element_types/process/validation/build_contract_generator_spec.rb
```
Expected: PASS.

---

### Task 27: `validate_contract_generator` — remove `onFailure` + `ON_FAILURES`

**Files:**
- Modify: `app/services/code_generators/element_types/process/validation/validate_contract_generator.rb`
- Modify: `spec/services/code_generators/element_types/process/validation/validate_contract_generator_spec.rb`
- Modify: `app/javascript/flowchart/constants/action_configs/validation_actions.js` (validate's `onFailure` block ~205)

- [ ] **Step 1: Update the spec**

Delete examples asserting `onFailure: "collect_errors"` → continues-on-invalid emission or `onFailure: "fail_track"` → `return false unless _valid` emission. Keep examples that test the contract-validation and permission-check happy paths.

- [ ] **Step 2: Strip the generator**

In `app/services/code_generators/element_types/process/validation/validate_contract_generator.rb`:

Delete `ON_FAILURES` constant (line 10).

Delete the `validate_config` branch at lines 46–48:
```ruby
            if cfg["onFailure"].present? && !ON_FAILURES.include?(cfg["onFailure"])
              errors << "Invalid onFailure: must be one of #{ON_FAILURES.join(', ')}"
            end
```

In `generate_contract_validation`:
- Delete line 67: `on_failure        = fetch_enum("onFailure", ON_FAILURES, default: "fail_track")`
- Change line 82 from `lines << on_failure_handler(on_failure, error_var)` to `lines << "return false unless _valid"`

Delete the `on_failure_handler(on_failure, error_var)` method entirely (lines 121–128).

- [ ] **Step 3: Remove `onFailure` from `validation_actions.js`**

In `app/javascript/flowchart/constants/action_configs/validation_actions.js` around lines ~204–213, delete:

```javascript
        {
          key: "onFailure",
          type: "select",
          label: "On Failure",
          defaultValue: "fail_track",
          options: [
            { value: "fail_track", label: "fail_track" },
            { value: "collect_errors", label: "collect_errors" }
          ]
        },
```

- [ ] **Step 4: Run spec — expect PASS**

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/services/code_generators/element_types/process/validation/validate_contract_generator_spec.rb
```
Expected: PASS.

---

### Task 28: Phase 3b checkpoint

- [ ] **Step 1: Run the scoped suite**

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/services/code_generators/element_types/process/security spec/services/code_generators/element_types/process/validation
```
Expected: `N examples, 0 failures`.

- [ ] **Step 2: Show diff to user**

Run: `cd /opt/milestone/anysys && git status && git diff --stat`

Phase 3b complete.

---

## Phase 3c — Strip Failure Enums: Caching, Concurrency, Data Operations, Utility

### Task 29: `cache_fetch_generator` — remove `fallbackErrorStrategy` residue

**Files:**
- Modify: `app/services/code_generators/element_types/process/caching/cache_fetch_generator.rb`
- Modify: `spec/services/code_generators/element_types/process/caching/cache_fetch_generator_spec.rb`

- [ ] **Step 1: Inspect generator**

Run:
```
cd /opt/milestone/anysys && grep -n "fallbackErrorStrategy\|FALLBACK_ERROR_STRATEGIES" app/services/code_generators/element_types/process/caching/cache_fetch_generator.rb
```

There are ~3 references (constant def, validate_config usage, body usage). Confirm and list them.

- [ ] **Step 2: Update spec**

Open `spec/services/code_generators/element_types/process/caching/cache_fetch_generator_spec.rb`. Delete examples asserting `fallbackErrorStrategy: "nil" / "default"` behavior. Keep cache-hit / cache-miss happy-path examples.

- [ ] **Step 3: Strip from generator**

Delete:
- `FALLBACK_ERROR_STRATEGIES` constant (line 11)
- `validate_config` branch at lines 48–50
- Any body emission that reads `config["fallbackErrorStrategy"]` — replace with the default-nil path (read the surrounding code to confirm).

- [ ] **Step 4: UI has already been cleaned**

Caching's `fallbackErrorStrategy` was removed in commit `00dd800`. Confirm nothing remains:
```
cd /opt/milestone/anysys && grep -n "fallbackErrorStrategy" app/javascript/flowchart/constants/action_configs/caching_actions.js
```
Expected: no output.

- [ ] **Step 5: Run spec — expect PASS**

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/services/code_generators/element_types/process/caching/cache_fetch_generator_spec.rb
```
Expected: PASS.

---

### Task 30: `acquire_lock_generator` — remove `failAction` + `FAIL_ACTIONS`

**Files:**
- Modify: `app/services/code_generators/element_types/process/concurrency/acquire_lock_generator.rb`
- Modify: `spec/services/code_generators/element_types/process/concurrency/acquire_lock_generator_spec.rb`
- Modify: `app/javascript/flowchart/constants/action_configs/concurrency_actions.js` (line 140 `failAction` block)

- [ ] **Step 1: Update spec**

Delete examples asserting `failAction: "raise"` → raise emission or `failAction: "fail_track"` → `Railway.fail!` emission. Keep lock acquisition/release happy-path examples.

- [ ] **Step 2: Strip generator**

In `app/services/code_generators/element_types/process/concurrency/acquire_lock_generator.rb`:
- Delete `FAIL_ACTIONS` constant (line 10)
- Remove `"failAction" => "fail_track"` from `sample_input` (line 22)
- Delete the `validate_config` branch at lines 46–48
- Replace the `fetch_enum("failAction", FAIL_ACTIONS, default: "fail_track")` call at line 83 — the surrounding code branches on the resolved value. Collapse to the "return false on failure" path.

- [ ] **Step 3: Remove `failAction` UI**

In `app/javascript/flowchart/constants/action_configs/concurrency_actions.js` around line 140, delete the `{ key: "failAction", ... }` field object.

- [ ] **Step 4: Run spec — expect PASS**

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/services/code_generators/element_types/process/concurrency/acquire_lock_generator_spec.rb
```
Expected: PASS.

---

### Task 31: `type_cast_generator` — remove `onCastFailure` + legacy `onFailure`

**Files:**
- Modify: `app/services/code_generators/element_types/process/data_operations/type_cast_generator.rb`
- Modify: `spec/services/code_generators/element_types/process/data_operations/type_cast_generator_spec.rb`
- Modify: `app/javascript/flowchart/constants/action_configs/data_actions.js` (lines 2789 + 2842)

- [ ] **Step 1: Update spec**

Delete examples asserting `onCastFailure: "raise"` → raise emission, `onCastFailure: "default"` → defaultValue emission, or legacy `onFailure` handling. Keep happy-path cast examples for each target type.

- [ ] **Step 2: Strip generator**

In `app/services/code_generators/element_types/process/data_operations/type_cast_generator.rb`:
- Remove the dual-enum handling at lines 61–67 (`failure = cfg["onCastFailure"] || cfg["onFailure"]` and its validation)
- Remove the dual-enum read at lines 73–80 (`config["onCastFailure"]` + `legacy = config["onFailure"]`) — replace with the nil-on-failure default path
- Delete any `ON_CAST_FAILURES` constant if present

- [ ] **Step 3: Remove from `data_actions.js`**

In `app/javascript/flowchart/constants/action_configs/data_actions.js`:
- Delete the `{ key: "onCastFailure", ... }` field object at line ~2789
- Delete the `{ key: "defaultValue", ..., visibleWhen: { field: "onCastFailure", ... } }` object at line ~2805 (it was conditionally visible based on onCastFailure)
- Delete the `{ key: "onFailure", ... }` legacy object at line ~2842

- [ ] **Step 4: Run spec — expect PASS**

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/services/code_generators/element_types/process/data_operations/type_cast_generator_spec.rb
```
Expected: PASS.

---

### Task 32: `i18n_translate_generator` — remove unused `ERROR_STRATEGIES`

**Files:**
- Modify: `app/services/code_generators/element_types/process/utility/i18n_translate_generator.rb`

- [ ] **Step 1: Confirm unused, delete**

Run:
```
cd /opt/milestone/anysys && grep -n "ERROR_STRATEGIES\|errorStrategy" app/services/code_generators/element_types/process/utility/i18n_translate_generator.rb
```
Expected: only definition at line 11. If so, delete the line.

- [ ] **Step 2: Run spec — expect PASS**

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/services/code_generators/element_types/process/utility/i18n_translate_generator_spec.rb
```
Expected: PASS.

---

### Task 33: Phase 3c checkpoint + remaining action_configs sweep

- [ ] **Step 1: Grep for any remaining error-strategy UI fields**

Run:
```
cd /opt/milestone/anysys && grep -n "errorStrategy\|onCastFailure" app/javascript/flowchart/constants/action_configs/
```
Expected: no output.

```
cd /opt/milestone/anysys && grep -n "onFailure\|failAction" app/javascript/flowchart/constants/action_configs/
```
Only `saga`-, `transaction`-, `signal_wait`-, and `resilience`-related fields may remain (those are Category D — kept).

- [ ] **Step 2: Run the scoped suite**

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/services/code_generators
```
Expected: `N examples, 0 failures`.

- [ ] **Step 3: Show diff to user**

Run: `cd /opt/milestone/anysys && git status && git diff --stat`

Phase 3c complete.

---

## Phase 4 — Regenerate Schema Mirror + Run Audit

### Task 34: Regenerate `spec/support/config_schemas.rb`

**Files:**
- Regenerate: `spec/support/config_schemas.rb` (auto-generated from JS schemas)

- [ ] **Step 1: Run the mirror rake task**

Run:
```
cd /opt/milestone/anysys && bundle exec rake config_schemas:mirror
```

- [ ] **Step 2: Inspect the diff**

Run:
```
cd /opt/milestone/anysys && git diff spec/support/config_schemas.rb | head -80
```

Expected changes:
- `error_handler` entry removed entirely from the `ELEMENT_SCHEMAS` hash.
- `process` entry no longer has `:onStepFailure` or `:errorHandling` fields.

If the file didn't change or contains unexpected content, stop and show the output to the user.

- [ ] **Step 3: Run the mirror-backed specs**

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/scripts/audit_generator_ui_spec.rb
```
Expected: PASS.

---

### Task 35: Run the generator↔UI audit script

**Files:** None modified (diagnostic script).

- [ ] **Step 1: Run the audit**

Run:
```
cd /opt/milestone/anysys && ruby scripts/audit_generator_ui.rb 2>&1 | tail -40
```

Expected: no mismatches. Any reported field-drift between generator constants and UI schema must be resolved before proceeding.

- [ ] **Step 2: If mismatches reported, fix**

Typical fix: a leaf generator's `validate_config` still references an enum constant that was deleted from JS, or vice versa. Re-visit the relevant task's generator + action_configs file.

- [ ] **Step 3: Re-run until clean**

Run the script again until it exits clean.

Phase 4 complete.

---

## Phase 5 — Controller Integration Test + Full Suite Sweep

### Task 36: Add `dynamic_controller_spec` integration example for uncaught-exception propagation

**Files:**
- Modify: `spec/controllers/dynamic_controller_spec.rb`

- [ ] **Step 1: Find an appropriate context block**

Open `spec/controllers/dynamic_controller_spec.rb`. Find a `describe "#handle"` or `context` block where an activity is invoked. Read the existing fixtures (flowchart creation, activity-code stubbing) to understand the setup pattern.

- [ ] **Step 2: Add the integration example**

Add this example inside the most relevant `describe`/`context` block, adapting the fixture helpers to match what already exists in the spec:

```ruby
context "when a generated step raises an uncaught exception" do
  it "rescues, rolls back the transaction, and returns 422" do
    # Build a flowchart whose generated activity deliberately raises.
    # Use the same fixture helpers the rest of this spec uses — typically
    # a `let(:flowchart)` with a pre-baked `activity` class body.
    flowchart = build_flowchart_with_activity_code(<<~RUBY)
      class <%= activity_class_name %> < Trailblazer::Activity::Railway
        step :boom

        def boom(ctx, **)
          raise "deliberate failure from generated step"
        end
      end
    RUBY

    # Count of records before — to prove rollback. Choose any model the
    # happy path would create; pick whatever this spec's other examples
    # mutate.
    initial_count = EntityEntry.count

    post :handle, params: { path: "#{flowchart.customer_id}/#{flowchart.uuid}/#{flowchart.entity.id}" }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["error"]).to include("deliberate failure")
    expect(EntityEntry.count).to eq(initial_count) # transaction rolled back
  end
end
```

If `build_flowchart_with_activity_code` does not exist, use whatever fixture-builder pattern the spec already uses. The key requirements: (1) a generated activity that raises, (2) assert 422, (3) assert DB rollback.

- [ ] **Step 3: Run the new example — expect PASS**

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/controllers/dynamic_controller_spec.rb -e "uncaught exception"
```
Expected: PASS. (If it FAILS, it's likely because `dynamic_controller.rb` already handles this correctly — the spec is a regression test, so the controller code should already support it.)

---

### Task 37: Full-suite sweep

**Files:** None modified.

- [ ] **Step 1: Run the full scoped suite**

Run:
```
cd /opt/milestone/anysys && bundle exec rspec spec/services/code_generators spec/services/activity_generator_spec.rb spec/components/flowchart_elements spec/controllers/dynamic_controller_spec.rb spec/scripts/audit_generator_ui_spec.rb spec/services/flowchart_topology_analyzer_spec.rb 2>&1 | tail -15
```

Expected: `N examples, 0 failures`. Example count should be lower than the Task-1 baseline (the reduction reflects deleted failure-matrix examples).

- [ ] **Step 2: Grep for leftover references**

Run each of these to verify no stragglers:

```
cd /opt/milestone/anysys && grep -rn "error_handler" app/ spec/ --include="*.rb" --include="*.js" | grep -v "dynamic_controller\|error_handlers$\|error_handler_icon"
```
Expected: no output (or only matches we explicitly kept — re-read before dismissing).

```
cd /opt/milestone/anysys && grep -rn "errorHandling\|onStepFailure" app/ spec/ --include="*.rb" --include="*.js"
```
Expected: no output.

```
cd /opt/milestone/anysys && grep -rn "handle_error_in_\|apply_process_scope_options\|build_error_handler_method" app/ spec/ --include="*.rb"
```
Expected: no output.

- [ ] **Step 3: Run the full test suite (not just scoped) as a final safety net**

Run:
```
cd /opt/milestone/anysys && bundle exec rspec 2>&1 | tail -15
```
Expected: `N examples, 0 failures`. If there are unexpected failures in untargeted specs, investigate — they may be depending on the removed code paths.

- [ ] **Step 4: Show final diff summary to user**

Run:
```
cd /opt/milestone/anysys && git status && echo "---" && git diff --stat
```

Phase 5 complete. Implementation done. User reviews and commits manually.

---

## Post-Plan Reminders

- The user will commit manually at phase boundaries, per AGENTS.md.
- No DB migration, no data cleanup for existing `error_handler` nodes — they surface as `# TODO: unknown element type 'error_handler'` comments in regenerated activity code.
- The kept categories (saga, transaction, signal_wait, resilience) are intentionally untouched — do not "tidy" them while here.
- If any leaf generator's failure-strategy field turns out to be load-bearing (e.g., a spec example asserts behavior that depends on both the error-strategy branch AND a different code path), split the cleanup — delete only the strategy branch, keep the other code. Don't delete unrelated assertions just to make a broken test pass.
