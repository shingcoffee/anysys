# Test Runner Enhancement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Structured per-step test results with click-to-locate, SQL query surfacing, server timeout, input validation/persistence, run history, execution-order overlay badges, and extraction of test-runner JS into a focused module.

**Architecture:** See `docs/superpowers/specs/2026-06-12-test-runner-enhancement-design.md` — read it first; it is the contract. Server: `ActivityTracer` gains a 10s timeout + best-effort per-step ctx snapshots; `FlowchartTracesController` returns `queries` + `timeout`. Client: new `app/javascript/flowchart/test_runner_manager.js` owns all behavior; the canvas controller delegates.

**Tech Stack:** Rails 8.1, StimulusJS (importmap — `pin_all_from "app/javascript/flowchart"` auto-pins new files), TailwindCSS, RSpec. No schema changes. No commits (user commits manually).

---

## Verified codebase facts

- Test tab markup: `app/views/admin/maintenance/flowcharts/_editor.html.erb:408-445` (targets `testInput`, `testOutput`, `testStatus`; actions `runTest`, `clearTraceOverlay`).
- Client logic: `flowchart_canvas_controller.js:1012-1157` (`runTest` auto-saves via `await this.save()` which returns false on failure; `_displayTraceResults`, `_displayTestError`, `_setTestStatus`, `clearTraceOverlay`). `escapeHtml` + `getCSRFToken` already imported. The Validate feature's `focusValidationIssue` (same file) is the precedent for select+zoom: clear selection, push element, `_setElementSelected`, `showConnectionHandles`, `zoomPanManager.fitToContent([element], 300)`, `_updateZoomDisplay()`, `_updateAlignmentToolbar()`.
- Server: `app/controllers/admin/maintenance/flowchart_traces_controller.rb` (uses `Flowchart.accessible.find`, permissive `input: {}` param); `app/services/activity_tracer.rb` — `Result = Struct.new(:success?, :signal, :ctx, :trace, :trace_nodes, :error, :queries, keyword_init: true)`; `execute_with_trace` wraps `Trailblazer::Developer::Wtf.invoke` in `FlowchartRuntime::QueryLogger.capture` (queries = `{sql, duration_ms, name}` hashes); `build_trace_nodes` iterates `Trailblazer::Developer::Trace::Snapshot::After` snapshots; `ContextSanitizer.sanitize` exists.
- Existing service spec: `spec/services/activity_tracer_spec.rb` (143 lines). NO request spec for traces exists.
- Request-spec conventions: `spec/requests/maintenance/flowchart_validations_spec.rb` (newest, full auth matrix incl. owner cross-tenant, member, anonymous, 404 own-cid probe) — mirror it.
- Canvas overlay: `app/javascript/flowchart/canvas.js:1997-2098` `showTraceOverlay(traceNodes)` builds `idStatusMap`/`labelStatusMap`, draws status rects + icons into `_traceOverlayLayer`; `clearTraceOverlay()` removes the layer.
- Auth for `/:cid/admin/*` is central (`RouteAuthorization` on ApplicationController) — no per-controller guard; specs prove the matrix.

---

### Task A (backend): timeout + queries + ctx snapshots + traces request spec

**Files:**
- Modify: `app/services/activity_tracer.rb`
- Modify: `app/controllers/admin/maintenance/flowchart_traces_controller.rb`
- Create: `spec/requests/maintenance/flowchart_traces_spec.rb`
- Modify: `spec/services/activity_tracer_spec.rb`

- [ ] **Step 1 (TDD): extend `spec/services/activity_tracer_spec.rb`** (read it first; reuse its flowchart/factory setup):
  - timeout: stub `Trailblazer::Developer::Wtf` (or the tracer's internal execute) to sleep past a shrunk timeout (use `stub_const("ActivityTracer::EXECUTION_TIMEOUT_SECONDS", 0.1)`) → result has `success?: false`, `timeout?: true`, `error` mentioning "timed out", `trace_nodes: []`.
  - ctx snapshot tolerance: for a successful run, every trace_node either has no `:ctx_snapshot` key or a Hash value — assert the run never raises and nodes keep `{id, element_id, label, status, signal}`.
- [ ] **Step 2: implement in `activity_tracer.rb`:**
  - `EXECUTION_TIMEOUT_SECONDS = 10`; add `:timeout?` to the Result struct (default false in the success/error builders).
  - Wrap the body of `execute_with_trace` (the QueryLogger.capture + invoke) in `Timeout.timeout(EXECUTION_TIMEOUT_SECONDS)`; rescue `Timeout::Error` → `Result(success?: false, timeout?: true, error: "Execution timed out after #{EXECUTION_TIMEOUT_SECONDS} seconds", trace_nodes: [], queries: [], trace: nil, ctx: nil, signal: nil)`.
  - Per-step ctx snapshots in `build_trace_nodes`: inside the snapshot loop, `begin ... rescue StandardError => nil` an extraction: inspect the Snapshot::After API at runtime (`snapshot` responds to data/variable versions — explore `Trailblazer::Developer::Trace::Snapshot` source in the installed gem under `bundle show trailblazer-developer`); if a ctx-like hash is reachable, `ContextSanitizer.sanitize` it, then truncate every String value > 2000 chars to `value[0,2000] + "…(truncated)"` (recursively, small helper), and set `node[:ctx_snapshot]`. If the API gives nothing usable, leave the key absent — the feature is best-effort BY DESIGN; do not contort. Cap: skip snapshot extraction entirely once 50 nodes have snapshots.
- [ ] **Step 3: controller** — add to the rendered JSON: `queries: truncated_queries(result.queries), timeout: result.timeout?`. `truncated_queries` maps each `{sql:, duration_ms:, name:}` truncating sql > 4000 chars. Keep everything else unchanged.
- [ ] **Step 4 (TDD): create `spec/requests/maintenance/flowchart_traces_spec.rb`** mirroring `flowchart_validations_spec.rb` helpers/style:
  - same-tenant admin POST with a simple runnable flowchart (reuse whatever minimal launched/generated-activity setup `activity_tracer_spec.rb` uses; if running a real activity in a request spec is heavy, stub `ActivityTracer#call` to return a canned Result) → 200, body has keys success, signal, trace, trace_nodes, queries, context, error, timeout.
  - queries appear in the body when the Result carries them (canned Result with one query hash).
  - timeout Result (canned `timeout?: true`) → 200 with `timeout: true` and `success: false`.
  - platform owner (customer 81721200, lingercoffee@gmail.com) cross-tenant → allowed.
  - other-tenant admin probing the flowchart id under their OWN cid → 404; member → 403; anonymous → redirect. (Match `flowchart_validations_spec.rb` exactly.)
- [ ] **Step 5: run** `bundle exec rspec spec/services/activity_tracer_spec.rb spec/requests/maintenance/flowchart_traces_spec.rb` → green.

### Task B (frontend-manager): `TestRunnerManager` + panel rendering + history + input UX

**Files:**
- Create: `app/javascript/flowchart/test_runner_manager.js`
- Modify: `app/javascript/controllers/flowchart_canvas_controller.js` (test/debug section only — lines ~1012-1157; do NOT touch validation code)

- [ ] **Step 1: create the manager.** `export class TestRunnerManager { constructor(controller) { this.controller = controller; this.history = []; } }` — move `runTest`, `_displayTraceResults`, `_displayTestError`, `_setTestStatus` logic in (access targets via `this.controller.testInputTarget` etc., canvas via `this.controller.canvas`). Public API: `run()`, `clear()`, `focusStep(elementId)`, `selectHistory(index)`, `useHistoryInput(index)`, `validateInput()`, `restoreSavedInput()`.
- [ ] **Step 2: input UX.** `validateInput()` on textarea `input` events: empty → valid (`{}`); `JSON.parse` failure → add `border-red-400` to the textarea, show message in the new `testInputError` target, disable the Run button (`testRunButton` target, `disabled` + `opacity-50`); valid → clear all. `restoreSavedInput()` (called from controller `connect`/first panel open): `localStorage.getItem("flowchartTestInput:" + id)` in try/catch. On each run: save input back. Run button also disabled while a run is in flight (`finally` re-enables, re-running `validateInput` to respect current text).
- [ ] **Step 3: `run()`** — keep auto-save first (`const saved = await this.controller.save()`; on `false` → named error "Save failed — run aborted; fix validation/save errors first" and return). Fetch with `AbortController` + 15s `setTimeout` backstop; on abort → named timeout error. Push `{at: new Date(), status, input, data}` into `this.history` (unshift, cap 10) on every completed response, then render.
- [ ] **Step 4: rendering** (all dynamic text through `escapeHtml`; import it like the controller does):
  - banner: success green / failure red / `data.timeout` amber "Timed out after 10 seconds — execution aborted" (timeout also clears overlay and skips applying a new one unless trace_nodes present, in which case render them and apply overlay anyway, banner stays timeout).
  - steps list from `data.trace_nodes`: `<ol>` rows — index badge, icon (✓ green / ✕ red / ◦ gray by `status`), label, per-row `<details>` ctx snapshot when `node.ctx_snapshot` (pretty `JSON.stringify(…, null, 2)` in a `<pre>`) else a muted "context not captured" line inside the details; failing row gets `bg-red-50` + the run `error` inline and `scrollIntoView` after render. Rows whose `element_id` resolves to a current canvas element get `cursor-pointer hover:bg-slate-50` + `data-action="click->flowchart-canvas#focusTraceStep"` + `data-element-id`; others muted.
  - queries: `data.queries?.length ? summary + <details> list (duration_ms ms + mono sql)` : explicit "No SQL queries executed" line; summary = `${n} queries · ${total} ms total` (sum duration_ms, 1 decimal).
  - history strip: compact pills (`HH:MM:SS ✓/✕/⏱`) above output; active pill highlighted; each pill `data-action="click->flowchart-canvas#selectTestHistoryRun" data-history-index`; a small "use input" link per pill → `loadTestHistoryInput`. `selectHistory(i)` re-renders that run's data + re-applies `showTraceOverlay(data.trace_nodes)`.
  - keep final context + raw trace `<details>` blocks as today (move the existing markup-building code).
  - empty trace_nodes on success → "Run completed without traced steps".
- [ ] **Step 5: slim the controller.** Replace the bodies of the test section methods with delegations: `runTest() { this._testRunner.run() }`, `clearTraceOverlay() { this._testRunner.clear() }`, new actions `focusTraceStep(event)` (reads `data-element-id`, then the exact select+zoom sequence used by `focusValidationIssue`'s element branch — reuse/extract a tiny `_focusElementById(id)` private used by both), `selectTestHistoryRun(event)`, `loadTestHistoryInput(event)`, `validateTestInput()`. Instantiate `this._testRunner = new TestRunnerManager(this)` in `connect()`; import from `"flowchart/test_runner_manager"`. Add `testRunButton`, `testInputError`, `testHistory` to static targets.
- [ ] **Step 6: verify** `node --check --input-type=module` on both files.

### Task C (frontend-markup): ERB targets + overlay order badges + editor spec

**Files:**
- Modify: `app/views/admin/maintenance/flowcharts/_editor.html.erb` (test tab block, lines ~408-445 only)
- Modify: `app/javascript/flowchart/canvas.js` (`showTraceOverlay` area only, ~1997-2098)
- Modify: `spec/requests/maintenance/flowcharts_editor_spec.rb` (additive examples)

- [ ] **Step 1: ERB.** In the Test Runner tab block add, Tailwind-only and responsive: an inline error line under the textarea `<p data-flowchart-canvas-target="testInputError" class="hidden text-xs text-red-600 mt-1"></p>`; give the Run button `data-flowchart-canvas-target="testRunButton"` and add `data-action="input->flowchart-canvas#validateTestInput"` to the textarea; a history container `<div data-flowchart-canvas-target="testHistory" class="flex flex-wrap items-center gap-1 px-1 pb-1 empty:hidden"></div>` between input and output sections. Do not restructure the rest.
- [ ] **Step 2: overlay order badges in `canvas.js#showTraceOverlay`.** Build `orderMap`: first index (1-based) of each element_id in `traceNodes` (fall back to normalized label like the status maps). When drawing each matched element's overlay, also draw a small circle (r≈9, fill `#1e293b`, fill-opacity 0.85) at the element's top-LEFT corner with white 10px text of the order number, into the same `_traceOverlayLayer` (so `clearTraceOverlay` removes it). Skip the badge when the element has no order (not executed).
- [ ] **Step 3: editor spec.** Add examples asserting the new targets exist in the edit page HTML (`testRunButton`, `testInputError`, `testHistory`, the `validateTestInput` action). Run `bundle exec rspec spec/requests/maintenance/flowcharts_editor_spec.rb` → green.
- [ ] **Step 4: verify** `node --check --input-type=module` on canvas.js.

### Task D: release + browser verify + reviews

- [ ] Targeted specs: `bundle exec rspec spec/services/activity_tracer_spec.rb spec/requests/maintenance/flowchart_traces_spec.rb spec/requests/maintenance/flowcharts_editor_spec.rb` green.
- [ ] Restart server per AGENTS.md; smoke `GET /81721200/admin/maintenance/flowcharts/53/edit` → 200; new JS file served via importmap.
- [ ] Playwright (~/pw-tools): run a test on a runnable flowchart — steps list renders with order badges on canvas, click a step → element focused, queries section, invalid JSON disables Run, history pill re-view works, console clean. Don't persist canvas changes.
- [ ] anysys-tech-lead + anysys-code-reviewer parallel review of the diff; fix findings.

## Self-review notes

- Coverage vs spec: timeout (A), queries (A+B), ctx snapshots best-effort (A+B), steps + click-to-locate + failing-step prominence (B), input UX + persistence (B+C), history (B+C), order badges (C), refactor extraction (B), request spec matrix (A), editor spec (C), error categories incl. save-failed and client 15s backstop (B).
- Parallelization: A, B, C touch disjoint files and can run concurrently (B's `focusTraceStep` markup contract with C: action names fixed here; C's targets consumed by B as named here). D last.
