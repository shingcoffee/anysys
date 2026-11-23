# Test Runner Enhancement — Design

Date: 2026-06-12
Page: `/:cid/admin/maintenance/flowcharts/:id/edit`, bottom-panel "Test Runner" tab.
Companion to: 2026-06-12-flowchart-validate-enrichment-design.md (interaction language reference).

## Problem

Test runs render as a raw Trailblazer trace dump + coarse canvas overlay. No per-step
breakdown, no execution order, captured SQL queries are dropped by the controller, no
timeout (long runs hang), no input validation/persistence, no run history, no request spec
for the traces endpoint, and the test-runner client logic is inlined in the 1150+ line
`flowchart_canvas_controller.js`.

## Decisions (PO open questions resolved)

- Timeout: fixed constant **10s** in `ActivityTracer` (no settings surface).
- Persistence: **localStorage** for last input per flowchart (`flowchartTestInput:<id>`);
  run history is **in-memory** (JS array, last 10) — large traces would blow storage quotas.
- Empty input ≡ `{}`, runnable.
- Panel markup stays in `_editor.html.erb` (editor is deliberately not componentized);
  the refactor target is JS: extract a `TestRunnerManager` module.

## Architecture

### Server

1. `ActivityTracer` (app/services/activity_tracer.rb):
   - Wrap `execute_with_trace` in `Timeout.timeout(10)`; on `Timeout::Error` return an
     error `Result` with `error: "Execution timed out after 10 seconds"` and a new
     `timeout: true` flag (add `:timeout?` member to the Result struct, default false).
   - Best-effort per-step context: in `build_trace_nodes`, attempt to extract a sanitized
     context snapshot per `Snapshot::After` (explore the Trailblazer Developer Snapshot
     API — `snapshot.data`/variable versions; whatever is cheaply available). Sanitize via
     the same `ContextSanitizer`, truncate values > 2000 chars with a `…(truncated)`
     suffix. On any extraction error, omit the key — node shape gains optional
     `ctx_snapshot: {…} | nil`. Never let snapshot extraction fail the run.
2. `FlowchartTracesController#create`: include in the JSON response:
   - `queries: result.queries` (array of `{sql, duration_ms, name}` — already captured),
   - `timeout: result.timeout?`,
   - existing keys unchanged. Sanitize each query's SQL through plain string truncation
     (> 4000 chars) — values are already parameterized SQL text.
3. New request spec `spec/requests/maintenance/flowchart_traces_spec.rb`: auth matrix
   (same-tenant admin OK, owner OK cross-tenant, other-tenant admin 404 own-cid probe,
   member blocked, anonymous redirected), success shape (success/signal/trace/trace_nodes/
   queries/context/error/timeout), timeout path (stub tracer), build-failure path.

### Client

4. New `app/javascript/flowchart/test_runner_manager.js` — owns all test-runner behavior;
   `flowchart_canvas_controller.js` keeps thin delegating actions (`runTest`,
   `clearTraceOverlay`, new `focusTraceStep`, `selectTestHistoryRun`, `loadTestHistoryInput`,
   input listener) and passes itself (targets, canvas, ids) to the manager. Existing
   `_displayTraceResults`/`_displayTestError`/`_setTestStatus` move into the manager.
5. Results rendering (into `testOutput` target, XSS-escaped throughout):
   - Status banner (success/failure/timeout — timeout is its own named state).
   - **Steps**: ordered list from `trace_nodes` — number, status icon (green check / red
     X / gray dot), label; failing step highlighted (`bg-red-50`) with the run `error`
     inline; rows with a resolvable `element_id` are clickable (`focusTraceStep`) and
     select+zoom the canvas element (same pattern as Validate's focus); rows without are
     non-navigable (muted, no pointer). Steps with `ctx_snapshot` get a per-row
     `<details>` "context" disclosure rendering pretty JSON; absent → "not captured".
   - **Queries**: summary line `N queries · X ms total` + collapsible list (`<details>`)
     of each query (duration + SQL in mono); zero queries → "No SQL queries executed".
   - Final context + raw trace keep their current collapsed `<details>` treatment.
   - Empty `trace_nodes` on success → explicit "Run completed without traced steps".
6. Input UX: live JSON validation on `input` events — invalid → red border on textarea,
   inline error line, Run disabled; empty treated as valid (`{}`). Last input saved to
   localStorage per flowchart on each run and restored on connect (try/catch, silent
   degrade). Run button disabled while a run is in flight (re-enabled in finally).
7. History: in-memory array (cap 10, newest first) of `{at, status, label, input, data}`;
   rendered as a compact row of pills/dropdown above the output; selecting an entry
   re-renders its results and re-applies its overlay; a "use input" affordance copies its
   input back into the textarea. Stale element ids degrade exactly like step rows.
8. Canvas overlay (`canvas.js#showTraceOverlay`): add execution-order badges — small
   numbered circle (1-based index of the node in `trace_nodes`) at the top-left of each
   matched element, same overlay layer, cleared with it. Status coloring unchanged.
9. `_editor.html.erb` test tab: add the input-error line element, history container, and
   any needed targets (`testRunButton`, `testInputError`, `testHistory`); keep Tailwind-only
   and responsive.

### Error categories (client)

- JSON parse error (pre-flight, local) — inline at input.
- Save-failed (auto-save before run returns false) — abort with named message.
- Build/execution error (`success: false`, `error` present) — red banner + failing step.
- Timeout (`timeout: true`) — amber/red "Timed out after 10s" banner; steps completed
  before cutoff still render if present; overlay cleared.
- Network/HTTP error — generic error banner. Client `AbortController` timeout at 15s
  backstops the server's 10s.

## Testing

- `spec/requests/maintenance/flowchart_traces_spec.rb` (new) — matrix + shape + timeout.
- `spec/services/activity_tracer_spec.rb` — timeout example, queries passthrough already
  covered, ctx_snapshot best-effort example (present-or-absent tolerant).
- Editor markup spec — new targets present in the test tab.
- JS verified via release smoke + Playwright pass (run a real trace on a flowchart).

## Out of scope

Persisted run history, transactional sandboxing, assertions, streaming progress,
saved scenarios, profiling beyond SQL timings, Validate changes, member/public surfaces.
