# Flowchart Validate Enrichment + Click-to-Fix Navigation — Design

Date: 2026-06-12
Page: `/:cid/admin/maintenance/flowcharts/:id/edit`

## Problem

The editor's Validate button runs client-side structural + I/O validation and renders a flat
list of text items in the bottom "Problems" tab. Clicking an item only selects/zooms the
element — it does not open the property editor nor point at the offending field. The rule set
also misses problems that only surface at code-generation time (`ActivityGenerator` silently
returns nil / emits TODO markers), plus several authoring mistakes (duplicate labels,
unlabelled decision branch connections, broken/cyclic subflow references).

## Goals

1. Structured problems: every problem carries a stable rule code, severity, target
   (element / connection / flowchart-level), and a navigation pointer (property-editor tab +
   field anchor) plus an optional fix hint.
2. Richer rules: new client-side rules + a server-side check (subflow validity + code-gen
   dry-run) surfaced in the same Problems list.
3. Click-to-fix: clicking a problem selects + zooms the target, opens the property editor on
   the right tab, scrolls to and highlights the offending field. Connection problems select
   the connection and open the connection editor. Flowchart-level problems show an inline note.
4. Problems panel UX: grouped by severity with counts, filterable, and canvas ring badges on
   problem elements.

Non-goals (out of scope): schema changes, auto-fix, validation-on-keystroke, rule muting,
problem export, surfaces outside the editor page, Test Runner changes.

## Architecture

### 1. Problem object schema (shared JS/Ruby shape)

```js
{
  type: "empty_condition",        // stable rule code (existing field name kept: `type`)
  severity: "error" | "warning",
  elementId: "el_x" | null,
  connectionId: "conn_y" | null,  // NEW — for connection-level problems
  message: "Decision \"Check\" has no condition defined",
  fixHint: "Define the condition on the General tab" | undefined,
  meta: { pinKey: "user_id", ... } | undefined   // rule-specific extras for anchoring
}
```

All ~20 existing rule codes are preserved verbatim. Existing emitters in
`validation_service.js` / `input_output_validation_service.js` keep their shape; new fields
are additive.

### 2. Navigation map (new file `app/javascript/flowchart/validation_navigation.js`)

A single declarative lookup `RULE_NAV` keyed by rule code:

```js
export const RULE_NAV = {
  empty_condition:       { tab: "general", anchor: '[name="conditionLeftOperand"], [name="condition"]' },
  decision_branches:     { tab: "steps" },     // "Branches" tab for decisions
  loop_no_collection:    { tab: "advanced", anchor: '[name="collection"]' },
  missing_input:         { tab: "io", anchorFn: (p) => `[data-io-input-key="${p.meta.pinKey}"]` },
  ...
}
```

Each entry: `tab` (general|steps|io|advanced), optional `anchor` (CSS selector resolved
inside the active pane) or `anchorFn(problem)`. Rules with no entry fall back to
select+zoom only (current behavior). The I/O tab rows gain `data-io-input-key` attributes
so `missing_input` can target the exact pin row; if the selector misses, fall back to the
tab top (no scroll). The map also carries default `fixHint` strings per rule.

### 3. New client-side rules (in `validation_service.js`)

- `duplicate_label` (error): two+ elements share a trimmed, case-insensitive label; one
  problem per duplicate element (generated step method names derive from labels, so
  collisions are codegen-relevant).
- `decision_branch_no_label` (error, connection-level): an outgoing connection from a
  decision has neither a branch label nor a branch condition value. Carries
  `connectionId`, `elementId` = the decision (for zoom fallback). Not fired when the
  decision has zero outgoing connections (`decision_branches` covers that).
- `decision_branch_duplicate_label` (warning, connection-level): two outgoing connections
  from one decision share a label.

(Implementer must check the real connection property names — branch label/value — in
`connection_manager.js` before coding the two branch rules.)

### 4. Server-side validation endpoint

- Route: `POST /:customer_id/admin/maintenance/flowcharts/:id/validation` →
  `Admin::Maintenance::Flowcharts::ValidationsController#create` (sibling of the existing
  `implicit_keys_controller.rb`), guarded by the same admin-or-owner before-action and
  tenant scoping used by `FlowchartsController`.
- Request body: `{ configuration: { elements: [...], connections: [...] } }` — the
  in-memory canvas state, stateless, no save side effect.
- Response: `{ problems: [ <problem schema above, snake_case→camelCase normalized client-side> ] }`.
- Service: `app/services/flowchart_server_validator.rb` (naming matches existing
  `flowchart_input_output_validator.rb`). It produces:
  - `subflow_inaccessible` (error): a subflow element references a flowchart that does not
    exist or is not accessible (same-tenant or shared) — same lookup rule as
    `ActivityGenerator`'s subflow loading.
  - `subflow_cycle` (error): DFS over subflow references (including self-reference)
    detects a cycle through the current flowchart.
  - Code-gen dry-run: run `ActivityGenerator` against the submitted configuration inside a
    rescue + `Timeout` guard (10 s):
    - nil return / raised exception → `codegen_failed` (error, flowchart-level unless an
      element is determinable from the generator's structural validation messages).
    - generated code containing TODO markers → `codegen_todo` (error) mapped back to the
      originating element via the generator's `node_element_index`, with a `fixHint`
      naming the unsupported element type / step action.
    - timeout → `codegen_check_timeout` (warning, flowchart-level).
- Client (`flowchart_canvas_controller.js#validate`): fire the POST in parallel with local
  validation; merge returned problems into the same list. On network failure append one
  `server_check_unavailable` warning and proceed with local results.

### 5. Click-to-fix (`focusValidationIssue` rewrite)

Problem items carry `data-element-id`, `data-connection-id`, `data-rule`, `data-severity`.
On click:

1. `connectionId` present and connection exists → clear element selection, select the
   connection (existing selection manager API), then
   `propertyEditor.openConnectionEditor(connection, canvas)`.
2. else `elementId` present and element exists → select + zoom (current behavior), then
   `this._showPropertySidebar(element)` passing nav options; `property_editor_controller.js
   openEditor(element, canvas, { tab, anchor, severity } = {})` gains an optional third
   argument (backward-compatible):
   - after form build + `configureForElementType`, call `tabManager.switchTo(tab)` if the
     tab is visible for the element type;
   - resolve `anchor` inside the active pane, `scrollIntoView({behavior:"smooth",
     block:"center"})`, apply a 2-second highlight: `ring-2 ring-red-400` (error) /
     `ring-2 ring-yellow-400` (warning) + `transition`, removed via timeout.
3. else (flowchart-level, or stale id after deletion) → no exception; show a transient
   inline note in the Problems panel header ("This problem isn't tied to a specific
   element"). Stale-target clicks degrade to this note.

### 6. Problems panel UX (`_showValidationResults` rewrite)

- Badge: keeps total count; red when errors exist, yellow when warnings only (existing
  logic), tooltip/text shows `N errors, M warnings`.
- List: two collapsible groups — **Errors (N)**, **Warnings (M)** — errors first, expanded
  by default. Each item: severity dot, message, optional muted fix-hint line, hover
  affordance. Empty state unchanged.
- Filter: three-state control (All / Errors / Warnings) in the Problems tab header;
  persisted in `sessionStorage` keyed by flowchart id.
- Canvas badges: after each validate run, add an error/warning ring to each problem
  element's SVG group (`[data-element-id]`) — a stroked outline rect/class in the element
  layer; cleared at the start of the next validate run and when the element is deleted.
  Rendered by `element_renderer.js` (a small `setValidationState(elementId, severity)` /
  `clearValidationState()` API) so it survives re-renders and pan/zoom.

All new markup is generated by the existing Stimulus controllers (the editor page is
already a JS-rendered surface); static container changes stay in `_editor.html.erb`.

## Error handling

- Server endpoint: malformed/missing configuration → 422 with `{ problems: [] }` plus a
  client-side warning; oversized payloads bounded by Rails defaults; everything rescued so
  the endpoint never 500s for user-content reasons.
- Client: server check failure never blocks local results; clicking stale problems never
  throws; anchors that don't resolve degrade to tab-switch only; tab not visible for the
  element type degrades to default tab.

## Security

- New route lives under `/:cid/admin/` with `require_admin_or_owner!` (same guard as the
  flowcharts controller) and flowchart lookup scoped to the current tenant (+ shared).
  Cross-tenant `:id` or `:customer_id` → 404/403 as per existing controller conventions.
- Subflow lookup inside the validator uses the same tenant scope as
  `ActivityGenerator#load_subflow_for_current_owner` — no cross-tenant existence leak
  (inaccessible and nonexistent are indistinguishable in the message).
- All problem messages are escaped at render time (existing `escapeHtml` path kept).

## Testing

- **Request spec** `spec/requests/maintenance/flowchart_validations_spec.rb`: auth matrix
  (admin OK, owner OK, member 403/redirect, anonymous redirect, cross-tenant blocked);
  happy path returns structured problems; subflow_inaccessible for cross-tenant reference;
  malformed body → 422.
- **Service spec** `spec/services/flowchart_server_validator_spec.rb`: subflow existence,
  shared-flowchart allowed, self/transitive subflow cycle terminates and reports,
  dry-run nil/exception → codegen_failed, TODO marker mapping via node_element_index,
  empty-elements short-circuit.
- **Editor markup spec** update (`spec/requests/maintenance/flowcharts_editor_spec.rb`):
  Problems tab filter control + grouped-list containers present.
- JS logic (validation rules, nav map, click-to-fix) has no JS test harness in this repo;
  verified via release-engineer smoke test + Playwright browser pass (~/pw-tools).

## Risks

- JS/Ruby validation parity drift — mitigated by the dry-run making `ActivityGenerator`
  itself the source of truth for codegen-blocking problems.
- Anchor selectors depend on `form_builder.js` field names; the nav map centralizes them so
  a rename breaks one file, and unresolved anchors degrade gracefully.
