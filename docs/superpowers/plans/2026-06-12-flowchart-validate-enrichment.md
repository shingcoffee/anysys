# Flowchart Validate Enrichment + Click-to-Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enrich the flowchart editor's Validate feature with structured problems, new rules, a server-side subflow + code-gen dry-run check, and click-to-fix navigation that opens the property editor on the exact tab/field.

**Architecture:** Client-side `ValidationService`/`InputOutputValidationService` keep emitting problems (additive fields: `connectionId`, `meta`); a new declarative `RULE_NAV` map translates rule codes into property-editor navigation; one new stateless admin endpoint (`POST .../flowcharts/:id/validation`) runs `FlowchartServerValidator` (subflow existence/cycle + `ActivityGenerator` dry-run) against the submitted in-memory canvas JSON; `focusValidationIssue` is rewritten to select + zoom + open the editor + switch tab + highlight the field.

**Tech Stack:** Rails 8.1, StimulusJS, TailwindCSS, RSpec. No schema changes. No new JS frameworks.

**Spec:** `docs/superpowers/specs/2026-06-12-flowchart-validate-enrichment-design.md` — read it first.

**Commit policy:** Work directly on `master`, do NOT commit (the user commits manually).

---

## Verified codebase facts (do not re-derive)

- Auth for `/:cid/admin/*` is enforced centrally by the `RouteAuthorization` concern included in `ApplicationController` (see `app/controllers/admin/maintenance/flowcharts/implicit_keys_controller.rb` — it has no explicit guard and is still protected). Request specs must still prove the matrix.
- `Admin::Maintenance::FlowchartsController#find_flowchart` + `guard_shared_write!` define the tenant-scoping pattern; reuse `find_flowchart`'s scoping for the new controller (read it before coding).
- Routes: `config/routes.rb` ~line 214, `resources :flowcharts, controller: "maintenance/flowcharts"` block.
- Connections are plain objects: `{ id, from, to, label, condition, ... }` — `label`/`condition` live on the connection itself (see `app/services/flowchart_topology_analyzer.rb:41-49`, `connection_manager.js:874-943`).
- `ActivityGenerator` (app/services/activity_generator.rb): `generate` returns `nil` when `validate_structure` (private, line 68) finds errors; emits `# TODO: ...` body lines for unknown element types (line 663), unknown step actions (line 827), broken subflow refs (line 640), and generator exceptions (lines 654, 836). `node_element_index` (line 55, public) maps generated method name → canvas element id. `load_subflow_for_current_owner` (line 386) is the tenant-safe subflow lookup. Subflow target id lives at `element.properties.flowchartId` (JS validator also accepts `subflowId` — treat `flowchartId` as primary, `subflowId` as fallback).
- Client fetch pattern: `fetch(`/${this.customerIdValue}/admin/maintenance/flowcharts/...`, { headers: { "X-CSRF-Token": getCSRFToken(), "Content-Type": "application/json" }, ... })` — `getCSRFToken` already imported in `flowchart_canvas_controller.js`.
- Existing problem shape: `{ elementId, type, message }` pushed to `errors`/`warnings` arrays in `app/javascript/flowchart/validation_service.js`. ~22 existing rule codes must keep their `type` strings verbatim.
- Problems list renders in `flowchart_canvas_controller.js#_showValidationResults` (line 755) into `validationListTarget` (a div inside the bottom-panel "Problems" tab in `_editor.html.erb`); items call `focusValidationIssue` (line 804). `openBottomPanel("problems")` opens the tab.
- Property editor: `property_editor_controller.js#openEditor(element, canvas)` (line 122) builds the form, then `tabManager.configureForElementType(element.type)`; `tabManager.switchTo(tabKey)` switches tabs (`tab_manager.js:104`); panes are `tabPaneGeneral|Steps|Io|Advanced` targets. `openConnectionEditor(connection, canvas)` (line 184) exists. Canvas controller opens the sidebar via `_showPropertySidebar(element)` (line 483) and `_handleConnectionSelected(connection)` (line 456).
- I/O tab rows already render `[data-element-io-input][data-pin="<pinKey>"]` (see `element_io/renderers.js`), but the I/O pane renders **asynchronously** (`ElementIoManager#openForElement` awaits fetches) — anchor resolution must retry.
- Form fields render with `name="${fieldName}"` (`form_builder.js`). Before filling `RULE_NAV` anchors, grep `form_builder.js` + `property_editor/templates.js` for the actual `name=` values per element type (e.g. condition, collection, duration, returnValue, requiredCount). Do not guess names; if a field has no stable selector, omit `anchor` (tab-switch only is the defined fallback).
- Canvas elements render as SVG groups `[data-element-id="<id>"]` in `element_renderer.js` (element layer).
- Existing specs: `spec/requests/maintenance/flowcharts_editor_spec.rb` (editor markup + auth), `spec/services/flowchart_input_output_validator_spec.rb`, factory `spec/factories/flowcharts.rb`.

## Shared problem schema (single source of truth)

Server JSON (camelCase, rendered by the controller) and client problems both use:

```js
{
  type: "subflow_inaccessible",      // stable rule code
  severity: "error" | "warning",
  elementId: "el_x" | null,
  connectionId: "conn_y" | null,
  message: "human text",
  fixHint: "one sentence" | null,    // optional
  meta: { pinKey: "user_id" }        // optional, rule-specific (client-side only)
}
```

New rule codes introduced by this plan:
`duplicate_label` (error), `decision_branch_no_label` (error), `decision_branch_duplicate_label` (warning), `subflow_inaccessible` (error), `subflow_cycle` (error), `codegen_failed` (error), `codegen_todo` (error), `codegen_check_timeout` (warning), `server_check_unavailable` (warning, client-side only).

---

### Task 1: `FlowchartServerValidator` service (backend)

**Files:**
- Create: `app/services/flowchart_server_validator.rb`
- Modify: `app/services/activity_generator.rb` (add one public method)
- Test: `spec/services/flowchart_server_validator_spec.rb`

- [ ] **Step 1: Expose structure errors on ActivityGenerator.** Add a public wrapper right below `node_element_index` (keep `validate_structure` private):

```ruby
# Public, read-only access to structural validation messages so callers
# (e.g. FlowchartServerValidator) can report WHY generation would bail
# instead of inferring it from a nil #generate return.
def structure_errors
  validate_structure
end
```

- [ ] **Step 2: Write the failing service spec.** Cover, using the existing flowchart factory (read `spec/factories/flowcharts.rb` first and reuse its configuration shape):
  - subflow element referencing a nonexistent flowchart id → one `subflow_inaccessible` error with that `elementId`
  - subflow referencing another customer's customer_specific flowchart → `subflow_inaccessible` (message must NOT distinguish "exists but other tenant" from "missing")
  - subflow referencing a `shared` flowchart → no subflow problem
  - direct self-reference (subflow → its own flowchart id) and transitive cycle (A → B, B's persisted config has a subflow back to A) → `subflow_cycle`, and the check terminates
  - valid config with an unknown step action (e.g. `action: "no_such_action"`) → `codegen_todo` error whose `elementId` is the process element's id and whose `fixHint` names the action
  - config whose structure is invalid (e.g. element not reachable from start) → `codegen_failed` error(s) carrying the generator's structure messages
  - empty elements array → returns `[]` problems without invoking ActivityGenerator
  - all problems conform to the schema keys `type, severity, element_id, connection_id, message, fix_hint`

- [ ] **Step 3: Run the spec, verify it fails** (`bundle exec rspec spec/services/flowchart_server_validator_spec.rb`).

- [ ] **Step 4: Implement the service.**

```ruby
# frozen_string_literal: true

# Server-side validation for the flowchart editor's Validate button.
# Runs the checks only the server can perform against the SUBMITTED
# (possibly unsaved) canvas configuration:
#   - subflow existence/accessibility (tenant-scoped, no existence leak)
#   - subflow reference cycles (including self-reference)
#   - ActivityGenerator dry-run (structure failures, TODO markers, timeout)
#
# Returns an array of problem hashes:
#   { type:, severity:, element_id:, connection_id:, message:, fix_hint: }
class FlowchartServerValidator
  DRY_RUN_TIMEOUT_SECONDS = 10

  def initialize(flowchart, configuration)
    @flowchart = flowchart
    @configuration = configuration || {}
  end

  def call
    elements = Array(@configuration["elements"])
    return [] if elements.empty?

    # Work on an in-memory copy: same tenant/entity context, submitted config,
    # never saved.
    @flowchart.assign_attributes(configuration: @configuration.to_json)

    problems = []
    problems.concat(subflow_problems(elements))
    problems.concat(codegen_problems)
    problems
  end

  private
  # subflow_problems: for each element type=="subflow" with a present
  #   properties.flowchartId (fallback properties.subflowId):
  #   - resolve via the same rule as ActivityGenerator#load_subflow_for_current_owner
  #     (shared OR same customer_id as @flowchart.customer_id) → else push
  #     subflow_inaccessible error {element_id: el id, fix_hint: "Select a flowchart
  #     that belongs to this customer or is shared"} with a message that does not
  #     reveal whether the id exists.
  #   - cycle check: DFS from @flowchart.id over subflow references; each visited
  #     flowchart's persisted elements contribute edges flowchart_id ->
  #     referenced flowchartId (resolve each through the tenant-scoped lookup;
  #     skip unresolvable). Maintain a visited Set so the walk terminates. If the
  #     walk re-enters @flowchart.id, push subflow_cycle on the originating
  #     subflow element in the SUBMITTED config.
  #
  # codegen_problems:
  #   generator = ActivityGenerator.new(@flowchart)
  #   structure = generator.structure_errors
  #   if structure.any? → map each message to
  #     { type: "codegen_failed", severity: "error", element_id: nil, ... } and return
  #     (generate would nil out anyway).
  #   else run code = Timeout.timeout(DRY_RUN_TIMEOUT_SECONDS) { generator.generate }
  #     rescue Timeout::Error → single codegen_check_timeout warning
  #     rescue StandardError => e → single codegen_failed error (e.class only, not
  #       full message — user content may be embedded)
  #   code.nil? → codegen_failed error ("generator returned no code")
  #   else scan TODO markers: split the generated source on /^  # (.+)\n  def (\w+)/
  #     is brittle — instead, for each "def <name>" method chunk
  #     (code.split(/(?=^  def )/)) containing "# TODO:", look up
  #     generator.node_element_index[name] for element_id and push
  #     { type: "codegen_todo", severity: "error", element_id: that id or nil,
  #       message: the first TODO line text, fix_hint: derived from the TODO text }.
end
```

  Implement the commented logic for real (the comment block above is the spec of each private method; write actual Ruby). Keep each private method small.

- [ ] **Step 5: Run the spec, verify it passes.**

### Task 2: Validation endpoint — route + controller + request spec (security)

**Files:**
- Create: `app/controllers/admin/maintenance/flowcharts/validations_controller.rb`
- Modify: `config/routes.rb` (inside the `resources :flowcharts` block, member scope)
- Test: `spec/requests/maintenance/flowchart_validations_spec.rb`

- [ ] **Step 1: Write the failing request spec.** Mirror the style/helpers of `spec/requests/maintenance/flowcharts_editor_spec.rb` (read it first for sign-in helpers and tenant setup). Cases:
  - admin of the flowchart's customer POSTs a configuration with a bad subflow ref → 200, JSON `problems` array containing `subflow_inaccessible` with camelCase keys (`elementId`, `connectionId`, `fixHint`)
  - clean configuration → 200, `problems: []`
  - admin of ANOTHER customer → 404 (or the app's standard cross-tenant response — match `find_flowchart` behavior)
  - member role → blocked (match the editor spec's expectation for admin URLs)
  - anonymous → redirected to sign-in
  - missing/non-hash `configuration` param → 422 with `problems: []`
- [ ] **Step 2: Run it, verify failure** (`bundle exec rspec spec/requests/maintenance/flowchart_validations_spec.rb`).
- [ ] **Step 3: Add the route** inside the flowcharts resources block (member level, alongside `resource :launch`):

```ruby
resource :validation, only: :create, controller: "maintenance/flowcharts/validations"
```

- [ ] **Step 4: Implement the controller.**

```ruby
# frozen_string_literal: true

module Admin
  module Maintenance
    module Flowcharts
      # Stateless server-side validation for the editor's Validate button.
      # Accepts the in-memory canvas configuration (never persisted) and
      # returns structured problems from FlowchartServerValidator.
      class ValidationsController < ApplicationController
        dashboard_menu_item :maintenance

        def create
          flowchart = find_flowchart_scoped # reuse the exact scoping used by
          # Admin::Maintenance::FlowchartsController#find_flowchart — read that
          # method and copy its lookup (including shared-flowchart visibility);
          # respond 404 when not found, same as the CRUD controller.

          configuration = params.to_unsafe_h["configuration"]
          unless configuration.is_a?(Hash) && configuration["elements"].is_a?(Array)
            return render json: { problems: [] }, status: :unprocessable_entity
          end

          problems = FlowchartServerValidator.new(flowchart, configuration).call
          render json: { problems: problems.map { |p| camelize_problem(p) } }
        rescue StandardError => e
          Rails.logger.error("[FlowchartValidation] #{e.class}: #{e.message}")
          render json: { problems: [] }, status: :unprocessable_entity
        end

        private

        def camelize_problem(p)
          {
            type: p[:type], severity: p[:severity], message: p[:message],
            elementId: p[:element_id], connectionId: p[:connection_id],
            fixHint: p[:fix_hint]
          }
        end
      end
    end
  end
end
```

  Note: `configuration` arrives as raw JSON body — `params.to_unsafe_h` is required because element/connection shapes are arbitrary user content; it is never mass-assigned to a model and never persisted.
- [ ] **Step 5: Run the request spec + the editor spec, verify green:** `bundle exec rspec spec/requests/maintenance/flowchart_validations_spec.rb spec/requests/maintenance/flowcharts_editor_spec.rb`

### Task 3: New client-side rules + problem metadata (frontend)

**Files:**
- Modify: `app/javascript/flowchart/validation_service.js`
- Modify: `app/javascript/flowchart/input_output_validation_service.js`

- [ ] **Step 1: Add `duplicate_label` to `_validateStructure`** (error, one per duplicate element):

```js
const labelGroups = new Map()
for (const el of this.elements) {
  const key = (el.label || "").trim().toLowerCase()
  if (!key) continue
  if (!labelGroups.has(key)) labelGroups.set(key, [])
  labelGroups.get(key).push(el)
}
for (const group of labelGroups.values()) {
  if (group.length < 2) continue
  group.forEach(el => {
    this.errors.push({
      elementId: el.id, type: "duplicate_label",
      message: `${group.length} elements share the label "${this._safe(el.label)}" — generated step names derive from labels, so duplicates are renamed unpredictably`
    })
  })
}
```

- [ ] **Step 2: Add the two decision-branch connection rules to `_validateCompleteness`** inside the existing `el.type === "decision"` block (only when `outgoing.length >= 2`):

```js
const seenLabels = new Map()
outgoing.forEach(conn => {
  const label = (conn.label || "").trim()
  const hasCondition = conn.condition != null && String(conn.condition).trim() !== ""
  if (!label && !hasCondition) {
    this.errors.push({
      elementId: el.id, connectionId: conn.id, type: "decision_branch_no_label",
      message: `A branch of Decision "${this._safe(el.label)}" has neither a label nor a condition — the generated routing cannot identify it`
    })
  }
  if (label) {
    const key = label.toLowerCase()
    if (seenLabels.has(key)) {
      this.warnings.push({
        elementId: el.id, connectionId: conn.id, type: "decision_branch_duplicate_label",
        message: `Decision "${this._safe(el.label)}" has two branches labelled "${label}"`
      })
    }
    seenLabels.set(key, true)
  }
})
```

- [ ] **Step 3: Attach `meta.pinKey` to `missing_input` problems** in `input_output_validation_service.js` — find where the `missing_input` error object is pushed and add `meta: { pinKey: <the input pin name variable in scope> }` (read the function to get the variable name).
- [ ] **Step 4: Build check:** run the asset build (see Task 7 command) or at minimum `node --check` is not applicable to ESM here — verify via the Task 7 build.

### Task 4: `RULE_NAV` navigation map (frontend)

**Files:**
- Create: `app/javascript/flowchart/validation_navigation.js`

- [ ] **Step 1: Grep the real form field names** before writing anchors: `grep -n 'name="' app/javascript/controllers/property_editor/form_builder.js app/javascript/controllers/property_editor/templates.js | head -60` and identify the field names for: decision condition, loop collection / loop condition, subflow target select, end returnValue/responseType, timer duration/waitCondition, join requiredCount, element label. Use only names that actually exist; omit `anchor` where none is stable.
- [ ] **Step 2: Create the map.** Shape (fill EVERY rule code listed; `tab` values: `general|steps|io|advanced`; entries may also be `null` for flowchart-level rules):

```js
/**
 * Maps validation rule codes to property-editor navigation targets.
 * tab: which property-editor tab to activate.
 * anchor: CSS selector resolved INSIDE the editor form; falls back to
 *         tab-switch only when it doesn't resolve.
 * anchorFn(problem): dynamic selector built from problem.meta.
 * fixHint: default hint shown under the problem message.
 */
export const RULE_NAV = {
  duplicate_start:                 { tab: "general", fixHint: "Delete the extra Start element" },
  orphan_start:                    null, // canvas-level: connect it — zoom only
  orphan_end:                      null,
  orphan_element:                  null,
  unreachable:                     null,
  duplicate_label:                 { tab: "general", anchor: '[name="label"]', fixHint: "Rename this element to a unique label" },
  empty_process:                   { tab: "steps", fixHint: "Add at least one step" },
  decision_branches:               null, // needs another outgoing connection on canvas
  empty_condition:                 { tab: "steps", fixHint: "Define the decision's branch conditions" },
  decision_branch_no_label:        { tab: "general", fixHint: "Give the branch connection a label or condition" }, // connection editor
  decision_branch_duplicate_label: { tab: "general", fixHint: "Rename one of the duplicate branch labels" },       // connection editor
  join_branches:                   null,
  join_required_count:             { tab: "advanced", fixHint: "Set Required Count to a positive whole number" },
  join_required_count_exceeds:     { tab: "advanced", fixHint: "Lower Required Count to at most the incoming branch count" },
  loop_no_collection:              { tab: "advanced", fixHint: "Specify the collection to iterate" },
  empty_loop_condition:            { tab: "advanced", fixHint: "Define the loop condition" },
  subflow_no_target:               { tab: "general", fixHint: "Select a target flowchart" },
  subflow_inaccessible:            { tab: "general", fixHint: "Select a flowchart that belongs to this customer or is shared" },
  subflow_cycle:                   { tab: "general", fixHint: "Remove the circular subflow reference" },
  end_no_return_value:             { tab: "advanced", fixHint: "Provide the Return Value expression" },
  timer_no_duration:               { tab: "advanced", fixHint: "Set the timer duration" },
  timer_no_condition:              { tab: "advanced", fixHint: "Set the wait condition" },
  missing_input:                   { tab: "io", anchorFn: (p) => p.meta?.pinKey ? `[data-element-io-input][data-pin="${CSS.escape(p.meta.pinKey)}"]` : null, fixHint: "Pick a producer for this input or add an upstream step that emits it" },
  codegen_todo:                    { tab: "steps", fixHint: "This step/element has no code generator — change the action or element type" },
  // flowchart-level rules (no element): missing_start, missing_end,
  // dangling_connection, duplicate_connection, self_connection, cycle,
  // codegen_failed, codegen_check_timeout, server_check_unavailable → null
}

export function navFor(problem) {
  const entry = RULE_NAV[problem.type]
  if (!entry) return null
  const anchor = entry.anchorFn ? entry.anchorFn(problem) : (entry.anchor || null)
  return { tab: entry.tab || null, anchor, fixHint: problem.fixHint || entry.fixHint || null }
}
```

  ADJUST the `anchor` selectors and `tab` choices to the real form (Step 1 grep + `TabManager.TAB_CONFIG` visibility — e.g. decision uses the `steps` tab labelled "Branches"; loop/timer default tab is `advanced`). Decisions in this snippet about which tab each rule belongs to are final unless the form proves otherwise.

### Task 5: Problems panel rewrite + server merge + canvas rings (frontend)

**Files:**
- Modify: `app/javascript/controllers/flowchart_canvas_controller.js` (`validate`, `_showValidationResults`, `focusValidationIssue`, new helpers)
- Modify: `app/javascript/flowchart/element_renderer.js` (validation ring API)

- [ ] **Step 1: Extend `validate()`** — run the server check concurrently with local validation and merge:

```js
async validate() {
  const structuralValidator = new ValidationService(this.canvas.elements, this.canvas.connections)
  const serverCheckPromise = this._runServerValidation() // fire first, await later
  const { errors: structuralErrors, warnings } = structuralValidator.validate()

  const ioValidator = new InputOutputValidationService(this.canvas)
  await ioValidator.loadImplicitKeys()
  const ioErrors = ioValidator.validate()

  const serverProblems = await serverCheckPromise
  const allErrors = [...structuralErrors, ...ioErrors, ...serverProblems.filter(p => p.severity === "error")]
  const allWarnings = [...warnings, ...serverProblems.filter(p => p.severity === "warning")]
  this._showValidationResults(allErrors, allWarnings)
  return allErrors.length === 0
}

async _runServerValidation() {
  if (!this.idValue || !this.customerIdValue) return []
  try {
    const response = await fetch(`/${this.customerIdValue}/admin/maintenance/flowcharts/${this.idValue}/validation`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": getCSRFToken(), "Accept": "application/json" },
      body: JSON.stringify({ configuration: { elements: this.canvas.elements, connections: this.canvas.connections } })
    })
    if (!response.ok) throw new Error(`HTTP ${response.status}`)
    const data = await response.json()
    return Array.isArray(data.problems) ? data.problems : []
  } catch (e) {
    return [{ type: "server_check_unavailable", severity: "warning", elementId: null, connectionId: null, message: "Server-side checks (subflow validity, code generation) could not run — showing local results only" }]
  }
}
```

- [ ] **Step 2: Rewrite `_showValidationResults(errors, warnings)`.** Keep the badge logic (total count, red if any error else yellow) but set `title` attr to `"${errors.length} errors, ${warnings.length} warnings"`. Store `this._validationProblems = items` (each item: problem + `severity`). Render into `validationListTarget`:
  - A header row (sticky) with: filter pills `All (N) | Errors (E) | Warnings (W)` — buttons with `data-action="click->flowchart-canvas#setValidationFilter"` and `data-filter="all|error|warning"`; active pill styled `bg-slate-200 text-slate-900 rounded-full px-2 py-0.5`, inactive `text-slate-500 hover:text-slate-700`; plus a `data-flowchart-canvas-target="validationNotice"` span (hidden) for the flowchart-level-click notice.
  - Two groups, Errors first then Warnings, each with a collapsible header (`<button data-action="click->flowchart-canvas#toggleValidationGroup" data-group="error">` containing a chevron, the label `Errors (E)`, expanded by default; clicking toggles `hidden` on the group's `<div data-validation-group="error">` body).
  - Items (filtered by `this._validationFilter`): keep current button styling, add per-item data attrs and an optional hint line:

```js
`<button class="w-full text-left px-4 py-2 hover:bg-slate-50 text-sm group"
         data-action="click->flowchart-canvas#focusValidationIssue"
         data-element-id="${escapeHtml(item.elementId || "")}"
         data-connection-id="${escapeHtml(item.connectionId || "")}"
         data-rule="${escapeHtml(item.type || "")}"
         data-severity="${item.severity}"
         data-pin-key="${escapeHtml(item.meta?.pinKey || "")}">
   <span class="flex items-center space-x-2">
     <span class="flex-shrink-0 w-2 h-2 rounded-full ${item.severity === "error" ? "bg-red-500" : "bg-yellow-500"}"></span>
     <span class="${item.severity === "error" ? "text-red-700" : "text-yellow-700"}">${escapeHtml(item.message)}</span>
   </span>
   ${hint ? `<span class="block pl-4 mt-0.5 text-xs text-slate-400">${escapeHtml(hint)}</span>` : ""}
 </button>`
```

  where `hint` comes from `navFor(item)?.fixHint`. Read the filter from `sessionStorage.getItem("flowchartValidationFilter:" + this.idValue) || "all"`; `setValidationFilter` stores it and re-renders from `this._validationProblems`. Add `validationNotice` to the controller's `static targets`.
- [ ] **Step 3: Canvas rings.** In `element_renderer.js` add:

```js
setValidationState(elementId, severity) { /* find `[data-element-id="${elementId}"]` group; add an svg rect outline (or stroke class) — stroke #ef4444 for error, #eab308 for warning, stroke-width 2, dasharray none, rx matching the shape, marked data-validation-ring so re-render preserves/clears it */ }
clearValidationStates() { /* remove all [data-validation-ring] nodes / classes */ }
```

  Read `element_renderer.js` first and implement with whatever primitive the renderer already uses for selection outlines (mirror the selected-state visual approach). Call `clearValidationStates()` at the start of `_showValidationResults` and then `setValidationState` for each problem element (errors win over warnings). Also clear rings for an element when it is deleted (hook the existing element-removal path if trivial; otherwise rings simply vanish on next validate — acceptable).
- [ ] **Step 4: Rewrite `focusValidationIssue(event)`:**

```js
focusValidationIssue(event) {
  const ds = event.currentTarget.dataset
  const problem = { type: ds.rule, severity: ds.severity, elementId: ds.elementId || null, connectionId: ds.connectionId || null, meta: ds.pinKey ? { pinKey: ds.pinKey } : undefined }
  const nav = navFor(problem)

  if (problem.connectionId) {
    const connection = this.canvas.connections.find(c => c.id === problem.connectionId)
    if (connection) {
      this.canvas.selectedElements.forEach(el => this.canvas._setElementSelected(el, false))
      this.canvas.selectedElements = []
      // use the existing connection-selection path so visuals stay consistent
      this._handleConnectionSelected(connection)
      const ends = [problem.elementId, connection.from, connection.to].map(id => this.canvas.elements.find(el => el.id === id)).filter(Boolean)
      if (ends.length) this.canvas.zoomPanManager.fitToContent(ends, 300)
      this._updateZoomDisplay()
      return
    }
  }

  if (problem.elementId) {
    const element = this.canvas.elements.find(el => el.id === problem.elementId)
    if (element) {
      this.canvas.selectedElements.forEach(el => this.canvas._setElementSelected(el, false))
      this.canvas.selectedElements = [element]
      this.canvas._setElementSelected(element, true)
      this.canvas.showConnectionHandles([element])
      this.canvas.zoomPanManager.fitToContent([element], 300)
      this._updateZoomDisplay()
      this._updateAlignmentToolbar()
      this._showPropertySidebar(element, nav ? { tab: nav.tab, anchor: nav.anchor, severity: problem.severity } : undefined)
      return
    }
  }

  this._showValidationNotice("This problem isn't tied to a specific element — fix it on the canvas")
}
```

  `_showValidationNotice(text)`: unhide `validationNoticeTarget`, set text, auto-hide after 4s.
  Update `_showPropertySidebar(element, nav = undefined)` to pass nav through: `propertyEditor.openEditor(element, this.canvas, nav)`.
- [ ] **Step 5: Import `navFor`** at the top of `flowchart_canvas_controller.js`: `import { navFor } from "flowchart/validation_navigation"` (match the existing import style for `flowchart/validation_service`).

### Task 6: Property editor — tab/anchor navigation + highlight (frontend)

**Files:**
- Modify: `app/javascript/controllers/property_editor_controller.js`

- [ ] **Step 1: Extend `openEditor(element, canvas, nav = undefined)`.** After the existing `this.formBuilder._autoDeriveLabelOnOpen()` / before `_showSidebar()` is fine, but tab config must already have run. Append at the end of the method:

```js
if (nav?.tab) this._navigateToProblem(nav)
```

- [ ] **Step 2: Implement `_navigateToProblem({ tab, anchor, severity })`:**

```js
_navigateToProblem({ tab, anchor, severity }) {
  const visibleTabs = this.tabManager.tabBarContainer?.querySelectorAll(`button[data-tab="${tab}"]`)
  if (tab && visibleTabs?.length) this.tabManager.switchTo(tab)
  if (!anchor) return
  // The I/O pane (and some others) render asynchronously — retry resolution.
  let attempts = 0
  const tryResolve = () => {
    const pane = this.tabManager.getPane(this.tabManager.activeTab) || this.formTarget
    const target = pane?.querySelector(anchor)
    if (target) return this._highlightProblemField(target, severity)
    if (++attempts < 15) setTimeout(tryResolve, 100)
  }
  tryResolve()
}

_highlightProblemField(target, severity) {
  const ringClasses = severity === "warning"
    ? ["ring-2", "ring-yellow-400", "ring-offset-1"]
    : ["ring-2", "ring-red-400", "ring-offset-1"]
  target.scrollIntoView({ behavior: "smooth", block: "center" })
  target.classList.add(...ringClasses, "transition-shadow", "duration-300", "rounded")
  clearTimeout(this._problemHighlightTimer)
  this._problemHighlightTimer = setTimeout(() => target.classList.remove(...ringClasses), 2000)
}
```

  Note `switchTo` no-ops when already active — fine. When `tab` isn't visible for the element type (no button), skip switching (default tab stays).
- [ ] **Step 3: Clear the highlight timer in `disconnect()`** (`clearTimeout(this._problemHighlightTimer)`).

### Task 7: Build, targeted specs, smoke test (release)

- [ ] **Step 1: Run targeted backend specs:** `bundle exec rspec spec/services/flowchart_server_validator_spec.rb spec/requests/maintenance/flowchart_validations_spec.rb spec/requests/maintenance/flowcharts_editor_spec.rb spec/services/flowchart_input_output_validator_spec.rb` — all green.
- [ ] **Step 2: Rebuild assets + restart dev server:** `rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000` (kill any existing server on :3000 first). Verify the JS bundle builds without errors (check the build log / `bin/dev` pipeline as the repo dictates — read `Procfile.dev`/`package.json` to find the JS build command and run it once to surface syntax errors).
- [ ] **Step 3: Smoke:** `curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/81721200/admin/maintenance/flowcharts/53/edit` → 200; POST a minimal configuration to `/81721200/admin/maintenance/flowcharts/53/validation` with curl (include CSRF exemption via SKIP_AUTH session or use the JSON + cookie from a logged-in session — if CSRF blocks curl, verify via the browser step instead).
- [ ] **Step 4: Browser verification (Playwright, ~/pw-tools per project memory):** open flowchart 53's editor, click Validate, screenshot the Problems panel (groups + filter + hints), click an element-level problem → property editor opens on the expected tab with a highlighted field (screenshot), click a connection-level problem if present, click a flowchart-level problem → notice appears. Confirm canvas rings render.

### Task 8: Reviews

- [ ] **Step 1:** Dispatch anysys-tech-lead (AGENTS.md conventions) and anysys-code-reviewer (correctness + security: tenant scoping on the new endpoint, no existence leak, XSS-safe rendering of problem messages/hints) on the full diff, in parallel.
- [ ] **Step 2:** Fix any findings; re-run Task 7 Step 1 specs.

---

## Self-review notes

- Spec coverage: structured schema (T3/T5), new client rules (T3), nav map (T4), server endpoint + service (T1/T2), click-to-fix incl. connections + flowchart-level notice + stale targets (T5 falls through to notice when element/connection missing), grouping/filter/badge/rings (T5), property-editor tab+anchor+highlight (T6), error handling (server_check_unavailable T5; 422 paths T2; anchor retry/fallback T6), security (T2 spec matrix), testing (T1/T2/T7).
- Parallelization: T1+T2 (backend/security) are independent of T3–T6 (frontend); T4 depends on T3's `meta.pinKey` shape only nominally (schema fixed here). T5 imports T4. T7 after all; T8 last.
