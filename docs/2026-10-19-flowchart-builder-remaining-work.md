# Flowchart builder refactor — remaining work

Last updated: 2026-10-20 07:15 UTC. Supersedes the status in
`docs/2026-10-16-flowchart-builder-remaining-work.md` (that file keeps the history, the original problem
lists and the owner decisions in its §8). Most of Phase 3 was committed in `764a8c19` (by accident, with
other work); the verification and review fixes below sit in the working tree on `main`.

| Phase | Theme | Status |
|---|---|---|
| 1 | Safety and correctness | Complete and verified |
| 2 | Generated activity | Complete and verified |
| 3 | Step-action platform | Complete and verified (§1); two owner decisions open (§1.4) |
| 4 | Element property editor | In progress: waves 1–3 integrated, wave 4 (E2E, docs) running (§3) |
| 5 | Canvas polish | Not started; spec and plan not written (§4) |

Order (owner decision): Phase 3 → Phase 4 → Phase 5, strictly in sequence.

## 1. Phase 3 — summary

Phase 3 design: `docs/superpowers/specs/2026-10-19-flowchart-builder-phase3-design.md` (sections A–J,
open questions Q1–Q14 all taken at their defaults). Ledger and per-task reports:
`.superpowers/sdd/2026-10-19-flowchart-phase3/` (`progress.md`, `*-report.md`). Both folders are
excluded from the Read tool; use `cat`.

### 1.1 What shipped
The `config_schema` DSL and emission helpers; all 78 actions (66 consolidated + 12 new) ported with area
locale files; the server-side `ActionCatalog` embedded in the editor (`export(locale:)`); the runtime
helpers and three new tables; the SSRF guard; the step-form controls (FE-1) and the searchable picker,
always-visible Change/Remove, server field errors, retry toggle and timeout hint, output suggestions
(FE-2); legacy removal and spec consolidation (C1); the AI-assistant schema derived from the catalog (C2);
the I18n guardrails (G3/G4); the developer docs (I). The stored-data migration (H) was later deleted:
existing flowcharts are deleted manually instead (owner decision, 2026-10-20).

### 1.2 Verification (2026-10-20)
- `npm run coverage`: 289 files, 6985 tests, 100% statements, branches, functions and lines.
- Full parallel RSpec: 24,743 examples; only the known reds `session_spec.rb:305` and
  `member/sources/entities_spec.rb:19` (§5). The shell must not export `RAILS_ENV` or `APP_HOST`: the
  first sends RSpec to the development database, the second fails `oauth/server_metadata_spec.rb:10`.
- Playwright builder journey: 15/15 on live sources, including the zh-CN step form (picker search, help
  text, clearing an optional enum, retry on GET / blocked on POST until an idempotency key is typed,
  server field error under the field, translated validation list).
- Dev server smoke: 78 actions in 15 categories with zh-CN labels; one action per category compiles; a
  blocked `api_call` fails with the translated message.
- Reviews: controllers + migration PASS; tech-lead (one I18n finding, fixed); runtime + HTTP (three
  medium findings, fixed and re-reviewed).

### 1.3 Deviations and fixes made during verification
- `FlowchartRuntime::RateLimiter` is a fixed-window counter on `Authentication::Throttle#hit!` (atomic
  in the shared store) instead of a read-then-write bucket; help texts in both locales describe the
  window.
- `OutboundHttp.stream` takes `public_only:` (per-hop guard and IP pin); `FlowchartRuntime::Http` streams
  whenever `max_bytes` is set, so an oversized body aborts mid-transfer and counts as a breaker failure.
- The retry toggle stayed disabled after typing an idempotency key: `canvas_sync` now refreshes the
  capability chrome while typing, and a cleared field no longer falls back to its stored value.
- Server step errors name the step by its box label and the action by its translated label (no raw
  action keys); step conditions take the editor's translated operator labels and value placeholder.
- `spec/rails_helper.rb` resets `Current` after every example (it leaked between specs and made page
  specs order-dependent).
- `bin/rails assets:clobber` was run because precompiled `public/assets` shadowed the importmap sources;
  `app/assets/builds/tailwind.css` was regenerated.

### 1.4 Owner decisions still open
1. **Where a payer lands after checkout** (`request_payment`). The payment handoff passes no
   `exit_target`, so `FeatureModules::ExitResolver` uses the customer's configured payment return URL,
   else `/:cid/admin/dashboard` — an admin URL a public payer cannot use. Page handoffs without an exit
   target behave the same. Options: fall back to the triggering form page after the customer's return URL
   (recommended; module-framework change affecting every handoff), do it for `request_payment` only, or
   keep as is.
2. **CJK font in generated PDFs** (`generate_document`). Today: the system `DroidSansFallbackFull` when
   present, else Helvetica with CJK characters replaced. Option: bundle Noto Sans SC (~8–10 MB) so Chinese
   always renders.

### 1.5 Phase 3 follow-ups (out of scope, documented in the docs)
- `ReferenceSources::*.valid?` is never called: reference fields are only checked for presence when saved
  (runtime helpers still refuse other tenants' records).
- The editor validates step config without the bound entity (`ConfigValidator` empty context), so
  `set_record_fields` `unknown_attribute` appears only at generation.
- `FlowchartRuntime::SmsDelivery.template_vars_code` classifies SMS template errors by message text (works
  in en and zh-CN); needs structured reasons on `Sms::Errors::TemplateVarsInvalid` in the SMS module.
- `generate_document` cannot attach the PDF to a record yet (Q7).
- Read surfaces for `flowchart_audit_events` and `flowchart_notifications` (Q6).
- Key-addressed email templates for shared flowcharts (Q4).
- Approval / wait for a person — separate project.
- I18n fallbacks stay on, so `raise_on_missing_translations` cannot catch keys missing only in zh-CN;
  `action_i18n_keys_spec` covers that for step actions only.
## 2. Deploy checklist (when this ships)
In the same deploy, before serving traffic:
0. `bin/rails db:migrate` — `20261019133000_create_flowchart_runtime_tables` (flowchart_sequences,
   flowchart_audit_events, flowchart_notifications).
1. `DRY_RUN=1 bin/rails flowcharts:regenerate_activities`, then without `DRY_RUN`.

Existing flowcharts are deleted manually before this deploy, so there is no stored-data conversion step.

## 3. Phase 4 — element property editor (done 2026-10-20)

Spec and task waves: `docs/superpowers/specs/2026-10-20-flowchart-builder-phase4-design.md` (written
2026-10-20 from an audit of the current code: 26 of the 28 problems below are still present, 2 partly;
open questions 1–7 taken at their recommended defaults). Ledger:
`.superpowers/sdd/2026-10-20-flowchart-phase4/progress.md`. All four waves are integrated: wave 1
(backend: `ElementCatalog`, Start/End/Subflow, Decision, Loop, `ConditionRules`, mirror removal), wave 2
(editor shell on the embedded catalog), wave 3 (conditions control, Decision branches on connections,
inline validation, Subflow picker, connection form, cleanup) and wave 4 (Playwright E2E and the en + zh-CN
developer docs). The stored-data migration task was dropped: existing flowcharts are deleted manually.

Verification: tech-lead and code-reviewer reviews pass after fixes (client element rules mirror
`ConditionRules` and the Loop generator checks; query-count conditions resolve the entity through
`FlowchartRuntime::EntityResolver` with the tenant; translated labels escaped at every `innerHTML`
insertion; "Notes" moved to `common.labels.notes`). Vitest 286 files / 6,729 tests at 100%; full parallel
RSpec 24,502 examples with only the two pre-existing failures listed in §5; app-backed Playwright 19
passed, self-contained 34 passed. The lists below are the original handoff, kept for reference.

### 3.1 Problems
- Primary settings sit on the Advanced tab (Loop, End, Subflow); empty tabs render; Advanced is a fixed
  two-column grid with no mobile breakpoint; condition builders get half width; 10–11 px type.
- Dead fields: End `http_response` mode (`httpStatus`, `responseBody`); decision branch `description` /
  `branchKey` / `matchValue` copies; `defaultBranchIndex`; loop `accumulatorVariable` on while loops;
  connection `priority`; leftover Start-trigger code and fix hints.
- Confusing fields: three loop types (do_while = "while, checked after"); `iterations` means different
  things per loop type with different defaults; raw-Ruby break condition vs structured main condition;
  implicit decision mode; "true/false/null" options that generate strings; duplicate match values not
  flagged; free-text numeric subflow target.
- Round-trip bugs: cleared numbers display the default while nothing is stored; mode switches lose values;
  legacy keys cannot be removed; zh-CN automatic labels misfire (compared with the English type name).
- No inline validation; removing a branch deletes its target without confirmation.
- Dead code: `app/views/shared/_property_editor_modal.html.erb`, `CanvasBridge`, `_showFieldError`,
  `_validateBeforeSave`, `buildInlineCondition`, `buildSegmentedControl`, `branchFallbackNameFormat`;
  hard-coded English in `branch_manager.js`, `canvas_operations.js`, `renderers.js`,
  `condition_builder.js`, `label_derivation.js`, `form_builder.js`; English validation messages in the
  End/Subflow/Start/Decision generators; assistant seeding defaults ignoring visibility rules
  (`ui_config_schema.rb`).

### 3.2 Design (from the 2026-10-16 handoff, to be confirmed in the Phase 4 spec)
- Editor-wide: General / Steps-or-Branches / I/O / Advanced (only when needed) tabs; one-column layout,
  two columns only from `sm:` for explicit pairs; Notes as a collapsed section; inline errors with
  `aria-invalid` reusing `element_rules.js`; normalization drops non-schema keys except `io_overrides`,
  `steps`, `branches`, `condition`; condition builder with "is true / is false / is empty" operators and
  operands from entity fields, upstream outputs or a ctx path.
- Per element: Start (label, notes); End (Nothing | Return a value); Process (label, steps, notes);
  Decision (Route by Value | Yes/No, branches with match value on the connection, one Otherwise, ≥ 2
  branches, unique match values, remap on mode switch); Loop (Repeat while | For each, "run once before
  checking", max iterations 1–10,000 default 100, advanced stop/skip/index/collect); Subflow (searchable
  picker of accessible launched flowcharts storing the id); Connection (label, notes).
- Element schemas move from `schemas.js` to Ruby (finishes the mirror removal).
- Server: End/Decision/Loop generators and validators with translated messages. (A stored-data
  migration task was planned here and dropped: existing flowcharts are deleted manually.)
- Tasks: editor shell; condition builder; Decision; Loop; End; Subflow picker; cleanup; Playwright per
  editor; docs (en + zh-CN). Vitest stays at 100%.

## 4. Phase 5 — canvas polish (in progress; what is left: §4.2)

Spec, audit result and waves: `docs/superpowers/specs/2026-10-20-flowchart-builder-phase5-design.md`
(written 2026-10-20 from an audit of the code Phase 4 left). Ledger:
`.superpowers/sdd/2026-10-20-flowchart-phase5/progress.md`. The original lists follow. Full lists:
`docs/2026-10-16-flowchart-builder-remaining-work.md` §6. Owner decisions already taken: an expanded
subflow is a read-only preview; the restore confirmation says restoring creates a new head version and the
old head stays in history (no extra snapshot).

- **Placement and layout:** drop exactly where released; no auto-align on load or drag; move only the
  selection; cascading paste offsets; `ResizeObserver` for the viewBox; "+" on edges to insert a box;
  undoable "Tidy layout".
- **Saving:** expected head version id on save → `409 Conflict` with a translated message, client offers
  reload or overwrite; update `based_on_version_id` in version-edit mode; show the server status for
  non-JSON errors; Ctrl+S; fix the restore confirmation text.
- **Undo/redo:** sidebar connection edits through `onBeforeChange`/`onchange`; restore without resetting
  the view; stable snapshot order; coalesce typing into one entry per field focus.
- **Expanded subflows:** read-only preview; reset state in `clear()`; validate the collapsed graph; no
  re-insert of the original element on save.
- **Read-only (launched) flowcharts:** one guard for every mutating command (align, distribute, inline
  label edit, autofix).
- **Validation UX:** de-duplicate problems by element and type; unique default names ("End 2"); correct
  "Add an End" and "Rename branch" autofixes; neutral badge when clean; block Launch on errors.
- **Readability and I18n:** real glyph-width truncation (zh-CN), larger node type, translated toasts /
  dates / Elements tab / tooltips / autofix labels, responsive minimap, clear test-run overlays on edit,
  redraw the whole element after an edit.
- **Shortcuts and selection:** case-insensitive keys; Shift+click, Ctrl+A, arrow nudging; clear connection
  selection on jump; hide resize handles on delete; honour the dragged port for a new decision branch.
- **Cleanup:** leaked listeners (`flowchartStructureChanged`, palette drop zone, overflow menu), uncleared
  debounce timer, ignored parameters (the old property-editor bridge was removed in Phase 4).
- Tasks: one per bullet above, plus Playwright coverage (geometry in Playwright, logic in Vitest at 100%).

### 4.1 Status (2026-10-20 12:36)
All ten build tasks (P5-1 … P5-10) are done. Fixed after them:
- **Decision editor opening on General.** Owner decision: the editor opens on Branches as designed and
  paints the empty-condition error under Condition without switching tabs; a blocked Save and a click on
  the problem in the validation panel still jump to the field (and open a collapsed section). Docs updated
  in en + zh-CN.
- **Retry toggle stored as on.** Clearing the idempotency key on a step that is not otherwise idempotent
  unchecked "Retry on transport error" but could still store it as on (the server then rejects it with
  `retry_not_idempotent`). `_performSync` now refreshes the toggle before reading the form.

Verified: property-editor Vitest 1134/0 with the changed files at 100%; self-contained Playwright 53/0;
full parallel RSpec 24,526 examples, only the two known failures listed in §5. Assets precompiled and the
dev server restarted on port 3000 (the manifest is present: delete `public/assets/.manifest.json` before
the next restart after any JS/CSS change).

### 4.2 Left to do for Phase 5
- [ ] Full `npm run coverage` after the retry-toggle fix (the last full run, before the fix, was 6898/1;
      the one failure was that bug).
- [ ] App-backed Playwright on the isolated port-3001 server (§2.4 commands):
      `flowchart_builder_journey.app.spec.js`, `flowchart_canvas/editor_save.app.spec.js`,
      `flowchart_editors/native_submit.app.spec.js`, `flowchart_editors/toolbar_responsive.app.spec.js`,
      `flowchart_node_drag.app.spec.js`. A run was started and stopped before it reported; stop the
      server through `tmp/pids/e2e-flowchart-builder.pid` and `unset E2E_DATABASE_PATH DATABASE_URL`
      afterwards.
- [ ] Dev smoke in en and zh-CN on port 3000: open, edit, save and validate a flowchart (Decision opens
      on Branches with the condition error under Condition; Save and the validation panel jump to it;
      subflow preview; minimap; Chinese label truncation).
- [ ] Final reviews: tech-lead (AGENTS.md conventions) and code-reviewer (correctness and security) on the
      Phase 5 diff; act on the findings.
- [ ] Record the results in `.superpowers/sdd/2026-10-20-flowchart-phase5/progress.md` and mark
      Phase 5 done here.
- [ ] Optional, found by the Playwright task: a toolbar button keeps keyboard focus after a click, so
      Ctrl/Cmd+Z / Y are ignored until the canvas is clicked.

## 5. Backlog of small follow-ups (not tied to a phase)
- `app/javascript/flowchart/urls.js` resolves server URLs from the first flowchart canvas on the page when
  no controller is passed.
- `entity_selector_controller.js` hard-codes `/admin/maintenance/flowcharts.json`.
- `sync_entity_domain_spec.rb:139` fails only in some test orders.
- `member/sources/entities_spec.rb:19` expects surface keys `entity_course` / `entity_event` but gets
  `entity_<id>` keys (pre-existing, outside the flowchart work).
- `session_spec.rb:305` expects a root `slug` on catalog entities that the entity vocabulary no longer
  returns (pre-existing, outside the flowchart work).
- Clicking a stored Timer box leaves the previous property form visible.
- `IoExtractor` and `ctx.dig(:x)` decision operands: re-check now that steps emit through `read`.
- Decision methods use a ternary; long compound conditions would read better as `if/else`.
- A flowchart's first stored activity lacks the `#<id>` in its header until the next save.
- Mermaid edge labels "success" / "failure" are English.

## 6. How to resume
- Rules: no commits (the owner commits); no `git stash` / `checkout -- <file>` / `reset`; every string in
  en and zh-CN with identical keys and `%{}` variables; JS text via Stimulus values with English defaults
  and server-passed `data-*-value`; no backward-compatibility shims and no stored-data migrations
  (existing flowcharts are deleted manually); every lookup tenant-scoped; TDD, stale specs rewritten, never weakened; `app/javascript/**` at
  100% Vitest; docs in `doc/reference/{en,zh-CN}` change with the code; subagents use the inherited model.
- The test environment now raises on missing translations (`config/environments/test.rb`).
- Isolated RSpec databases: `TEST_ENV_NUMBER=41…49` (`storage/test<n>.sqlite3`). Always
  `unset E2E_DATABASE_PATH DATABASE_URL` first; load a schema with
  `TEST_ENV_NUMBER=<n> RAILS_ENV=test bin/rails db:schema:load`.
- Snapshots to regenerate when the catalog changes: `bin/rails action_catalog:fixture` (JS fixture) and
  `bin/rails ai_assistant:flowchart_schema` (assistant palette); `bin/rails element_catalog:fixture`
  (element-catalog JS fixture, checked by `element_catalog_spec.rb`).
- Playwright and dev-server commands: `docs/2026-10-16-flowchart-builder-remaining-work.md` §2.4.
