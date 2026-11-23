# Flowchart builder — Phase 5: canvas polish (design)

Date: 2026-10-20. Source lists: `docs/2026-10-16-flowchart-builder-remaining-work.md` §6 and
`docs/2026-10-19-flowchart-builder-remaining-work.md` §4. Written from a read-only audit of the code
Phase 4 left (three audits, 2026-10-20). Ledger: `.superpowers/sdd/2026-10-20-flowchart-phase5/progress.md`.

Owner decisions already taken: an expanded subflow is a read-only preview; the restore confirmation says
restoring creates a new head version and the old head stays in history (no extra snapshot). Existing
flowcharts are deleted manually — no stored-data migration.

Rules: no commits; every user-facing string in en + zh-CN (JS text via Stimulus values with English
defaults and server-passed `data-*-value`); `app/javascript/**` at 100% Vitest lines/branches/functions;
geometry in Playwright; docs in `doc/reference/{en,zh-CN}` change with the code; no backward-compat shims.

## Audit result (what is still broken)

Already fixed (no task): red "0" badge (A5 validation), `STEP_ACTION_LABELS`, "Rename branch" autofix
(removed), `CanvasBridge` (removed in Phase 4), documented-but-ignored `@param`s in canvas files.

## 1. Placement and layout (P5-1)
Problems: `loadConfiguration` (`serialization.js`), multi-drag end and single-drag end
(`drag_handler.js`), `createConnection` (`connection_manager.js`), endpoint retarget (`canvas.js`
`_endConnectionEndpointDrag`) and palette drop (`external_drop.js`) all auto-align; dragging moves the whole
downstream subtree (`_getSubTreeElements`, shared merge points included); external drop shifts other
elements; paste uses a fixed 30 px offset; the palette drop indicator uses SVG coordinates as CSS pixels
and `_scrollToPosition` compares SVG y with `scrollTop`; no `ResizeObserver` (viewBox stale after a
container resize); no edge "+" insert; "Auto layout" is a naive BFS that ignores branch order.
Design:
- Nothing moves except what the user moves. Drop exactly where released (grid snap stays). Drag moves
  only the selection (one element when nothing else is selected). No align on load, drag end, connect,
  retarget or drop. `alignAllElements` and the subtree helpers are deleted unless an explicit command uses
  them.
- Paste cascades: n-th paste of the same clipboard offsets by `30 * n`; `copy()` resets n.
- Drop indicator positioned from client coordinates relative to the container; scroll-into-view uses
  the canvas's own `_scrollToElement`.
- `ZoomPanManager` owns a `ResizeObserver` on the SVG that calls `_updateViewBox()`; disconnected in
  `destroy()`.
- Edge "+": hovering a connection shows a "+" button at its midpoint (hidden when read-only). Clicking it
  opens a small menu of insertable element types — the palette types except Start and End, labelled with
  `elementLabel(type)`. Choosing one inserts the box at the midpoint, rewires A→new→B through the existing
  insert-between path (decision edge data kept on the first leg), selects it and opens its property
  editor. One undo entry.
- "Tidy layout" replaces "Auto layout" (label en "Tidy layout", zh-CN "整理布局"; key renamed): layered
  top-down layout from Start, children ordered by source port index (decision branch order), parents
  centred over their children, loop back-edges ignored for layering, unreachable elements placed in a row
  below. One undo entry; undoable.
- New decision branch honours the dragged port: the new connection is inserted right after the branch of
  the dragged port (index k+1); branches before it keep their port.
Files: `drag_handler.js`, `connection_manager.js` (+ `connection_manager/{alignment,rendering,routing}.js`),
`canvas/serialization.js` (only the load-align removal), `canvas/external_drop.js`, `clipboard_manager.js`,
`zoom_pan_manager.js`, `layout_manager.js`, `dynamic_ports.js`, `canvas.js` (`_endConnectionEndpointDrag`
only), `controllers/element_palette_controller.js`, toolbar label key (`comp_misc.toolbar`).

## 2. Saving, conflicts, launch (P5-2)
Problems: no concurrency check (two tabs overwrite silently); success JSON carries no version id, so
`based_on_version_id` stays stale in version-edit mode (and skips the no-op guard); non-JSON error bodies
throw and show the hard-coded "Network error occurred"; the same in version restore; no Ctrl+S; restore
confirmation promises a snapshot; toolbar toasts are English literals; Launch checks only missing inputs
(structure, config and codegen errors launch anyway; `flash[:validation_errors]` is never read).
Design:
- The editor renders `data-flowchart-canvas-head-version-id-value` =
  `@flowchart.current_line_head_version_id` (the line head, so tenant override heads work). Every save
  sends `expected_head_version_id`. `FlowchartsController#update`: when the param is present and differs
  from `current_line_head_version_id`, answer `409 Conflict` JSON
  `{ status: "conflict", message:, head_version_id: }` (HTML: redirect back with the alert) without
  saving. Success JSON adds `version_id` (new line head). The client stores it in both
  `headVersionIdValue` and, in version-edit mode, `basedOnVersionIdValue`.
- On 409 the editor shows a conflict banner (ViewComponent-free ERB block in `_editor.html.erb`, hidden by
  default, `role="alert"`) with the translated message and two buttons: "Reload" (drops the unsaved guard,
  reloads) and "Overwrite" (resends with `expected_head_version_id` = the returned head).
- Error responses: parse JSON only when `content-type` includes `json`; otherwise show the translated
  "Save failed (HTTP {status})". Network exceptions show a translated network-error message. Same in
  version restore.
- Ctrl/Cmd+S saves (prevents the browser dialog); on a read-only flowchart it shows the read-only toast.
  The key handling lives in `canvas.js` (`onSaveRequested` callback), wired in the controller.
- Restore confirmation (en): "Restore version {number}? This creates a new head version with its
  content; the current head stays in the version history." zh-CN equivalent; JS default updated.
- Toolbar toasts become Stimulus values passed from `toolbar_component.html.erb`.
- Launch: `FlowchartLaunchesController#create` also runs `FlowchartServerValidator` and blocks on any
  `severity == "error"` with a translated alert ("Fix the %{count} problems in the editor before
  launching."); the unused `flash[:validation_errors]` goes.
Files: `app/controllers/admin/maintenance/flowcharts_controller.rb`,
`flowchart_launches_controller.rb`, `_editor.html.erb` (save/conflict attributes and banner),
`flowchart_canvas_controller.js` (save path, conflict banner targets, `onSaveRequested` wiring),
`version_history_mixin.js`, `toolbar_controller.js`, `app/components/flowcharts/toolbar_component.*`,
`canvas.js` (Ctrl+S branch only), locales `maint_core` / `comp_misc`, request specs.

## 3. Undo/redo (P5-3)
Problems: sidebar connection edits bypass `onBeforeChange`/`onchange` (no undo, no unsaved state); undo
restore goes through `loadConfiguration` (resets zoom, wipes metadata, realigns, clears selection);
snapshots sort elements by random id; every 100 ms typing pause is an undo entry (50-entry cap evicted by
one paragraph); `pendingUndoState` unused.
Design:
- `updateConnectionProperties` calls `onBeforeChange`/`onchange` like `updateElementProperties`.
- Undo/redo restore through a silent graph swap (`restoreGraph(data)` in serialization): replaces
  elements/connections, keeps zoom/pan, `_loadedMetadata`, and the selection of elements that still exist;
  no realign; no change hooks.
- Snapshots keep canvas order (no sort).
- Coalescing: a change carries an optional coalesce key; consecutive commits with the same key replace the
  top entry's "after" state instead of pushing. The property editor sets the key to
  `<elementOrConnectionId>:<field>` on `focusin` and clears it on `focusout`, so one focused field = one
  entry. Arrow-key nudging (P5-7) uses key `nudge:<selection ids>`.
Files: `controllers/flowchart_canvas/undo_redo_manager.js`, `canvas/serialization.js` (`restoreGraph`),
`controllers/property_editor/canvas_sync.js` (+ focus hooks in the property editor controller),
`connection_manager.js` (`updateConnectionProperties` only — coordinate with P5-1, same wave: P5-1 owns
the file and adds the two hook calls).

## 4. Expanded subflows = read-only preview, one read-only guard (P5-4)
Problems: expansion mutates the graph outside undo; `clear()`/undo/restore keep `expandedSubflows`, so the
next save re-inserts the original element; edits inside an expansion are dropped silently; validation and
server checks run on the expanded graph (inner Start → `duplicate_start`, autofix could delete it);
pasted inner elements keep `_expandedFromSubflow` and vanish on save. Read-only (launched) flowcharts can
still be changed by align ×6, distribute ×2, inline connection-label edit, autofix (row and Fix all) and
version restore (client); the alignment toolbar shows.
Design:
- Preview mode: while any subflow is expanded the whole canvas is in preview mode. On the first expansion
  the controller stores the collapsed configuration (`getConfiguration()` before expanding). Save,
  validation (client and server) and undo snapshots use that stored collapsed configuration; folding the
  last expansion restores it exactly (positions included) through `restoreGraph`. Expanding/folding adds
  no undo entry and does not mark the flowchart unsaved. A banner/notice explains "Previewing a subflow —
  fold it to edit" (translated). The copy-back code in `_buildSaveConfiguration` and live reads in
  `foldSubflow` are deleted. `clear()`, undo restore and version restore leave preview mode first.
- One guard: `canvas.canMutate()` = `!isReadOnly && !previewMode`. Every mutating entry point checks it:
  drag, resize, connect, retarget, delete, paste, duplicate, inline label edit, align/distribute, tidy,
  routing cycle, palette drop, edge "+", autofix, undo/redo, restore, property-editor save and live sync.
  The alignment toolbar, autofix buttons and edge "+" are hidden when it is false.
Files: `controllers/flowchart_canvas/subflow_manager*`, `flowchart_canvas_controller.js`,
`controllers/flowchart_canvas/validation_mixin.js`, `version_history_mixin.js` (guard only),
`alignment_manager.js`, `connection_manager.js` (`startInlineLabelEdit` guard), `clipboard_manager.js`
(strip the flag), property editor guard (reads `canMutate`).

## 5. Validation UX (P5-5)
Problems: one fault listed up to three times (client rule, server `element_config_invalid`, codegen dry
run `codegen_failed` with no element id); new elements of a type share a default label and get flagged as
duplicates (palette, insert, paste); "Add an End" picks `elements[last]`/first terminal (can be an orphan,
an unreachable island or a Decision; positions under the last array element); `orphan_end` contradicts
its caption.
Design:
- Server: `FlowchartServerValidator` skips the codegen dry run when the subflow or config checks return
  any error (the dry run only means something on an otherwise valid graph).
- Client merge in `validate()`: drop a server problem when a client problem has the same `elementId` and
  `field` (or same `elementId` and type for element-level problems); then de-duplicate by
  `(elementId, type, field)`.
- Unique default labels: shared `uniqueLabel(elements, base)` (new `flowchart/labels.js`, moved from
  `validation_autofix.js`) producing "End 2", "End 3" via a translated `{label} {n}` format; used by
  palette add, insert-next-to, edge "+" insert and paste/duplicate.
- Autofix: `terminalElements` = elements reachable from Start, not Start/End/Decision, with no outgoing
  connection, in traversal order. `missing_end` creates the End below the chosen source (explicit x/y, no
  auto-connect) and connects it; `orphan_end` connects from the last terminal in traversal order. A fix is
  offered only when a source exists.
Files: `flowchart_server_validator.rb`, `validation_mixin.js` (merge only), `validation_autofix.js`,
new `flowchart/labels.js`, `canvas/element_management.js` (label at add/paste),
`canvas/external_drop.js` (label at insert).

## 6. Readability and I18n (P5-6)
Problems: node type 8–9 px; truncation assumes Latin widths (zh-CN overflows) with ASCII "...";
`version_history_mixin` " at " and "v" prefix and browser locale; Elements tab raw type and
"in / out"; minimap hard-codes 200×140 (clipped below `sm`, click offset) and shares z-index with the
bottom panel; test-run overlay stays after edits; only the label is redrawn after an edit (fill, comment
dot, subflow toggle, size stale); English literals: expansion self-reference toast, fold "Subflow" label,
`"{duration} ms"`, `toTimeString()`, inline fallback literals duplicating Stimulus defaults
(`element_management.js`, `external_drop.js`, `serialization.js`, `connection_manager.js` "Label..."),
server validator "Flowchart too large…" / timeout messages; `input_output_validation_service` `_safe`
double-escapes keys.
Design:
- Node text 11 px (decision/steps 10 px). Truncation by a pure width estimator (CJK/full-width = 1 em,
  others 0.6 em; injectable for tests) to the box width, ellipsis "…", full label in `<title>`.
- After an element edit the whole element group is re-rendered (`_rerenderElement`), keeping selection
  and validation rings.
- Version timestamps: `Intl.DateTimeFormat(appLocale, { dateStyle: "medium", timeStyle: "short" })` with
  the app locale from the editor; version label via a `{number}` format value.
- Elements tab: `elementLabel(type)` and a `{incoming} in / {outgoing} out` format value.
- Minimap sizes its SVG from its container (ResizeObserver) and sits above the bottom panel.
- `canvas.onchange` clears the trace overlay.
- Every listed literal becomes a value/locale key; inline fallbacks removed (the values have defaults).
  Server validator messages via `I18n.t`. `_safe` stops escaping (the panel escapes).
Files: `element_renderer.js`, `canvas/element_management.js` (`_updateElementLabel` → rerender),
`bottom_panel_mixin.js`, `version_history_mixin.js` (dates), `minimap_manager.js`, `trace_overlay.js`,
`test_runner_manager.js`, `subflow_manager/{expansion,fold_restore}_mixin.js` (literals),
`canvas/serialization.js` + `canvas/external_drop.js` + `connection_manager.js` (fallback literals),
`input_output_validation_service.js`, `flowchart_server_validator.rb`, `_editor.html.erb`, locales.

## 7. Shortcuts and selection (P5-7)
Problems: key compares are case-sensitive (Caps Lock); multi-select only with Ctrl/Cmd; no Ctrl+A, no
arrow nudging; jumping to a problem leaves a selected connection that Delete removes; resize handles stay
after Delete.
Design: normalise single-character keys to lower case; Shift+click and Shift+marquee add to the selection
(as Ctrl/Cmd do); Ctrl/Cmd+A selects all elements; Arrow keys nudge the selection by the grid size
(Shift = 5 × grid), one undo entry per burst (coalesce key), guarded by `canMutate()`; `_focusElementById`
uses the canvas selection helpers and clears the connection selection, the connection jump calls
`selectConnection`; delete hides resize handles.
Files: `canvas.js` (`_handleKeyDown`, mouse-down modifier), `selection_manager.js`, `element_renderer.js`
(click modifier only), `resize_handler.js`, `validation_mixin.js` (`_focusElementById` and the connection
branch only).

## 8. Cleanup (P5-8)
Leaked listeners: `flowchartStructureChanged` (controller), palette drop-zone listeners on the canvas
container (`element_palette_controller.js`), toolbar overflow handler (toggle-close path and the untracked
`setTimeout`); `_searchDebounceTimer` not cleared on disconnect; untracked timers (sidebar hide, palette
drop indicator, toolbar status); ignored parameters: `getDefaultPropertiesForType(_flowchartType)` and its
callers, `_createPortLabels` (returns null — delete), palette `_calculateOptimalPosition(_container)`,
`_saveConnection(event)`; `createConnection` JSDoc.

## 9. Waves (disjoint files per wave)
- Wave 1 (parallel): P5-1 placement, P5-2 saving/launch, P5-3 undo/redo.
- Wave 2 (parallel): P5-4 preview + guard, P5-7 shortcuts/selection, P5-8 cleanup (palette, toolbar,
  search timer, element_config).
- Wave 3 (parallel): P5-5 validation UX, P5-6 readability/I18n.
- Wave 4 (parallel): Playwright (drop-where-released, drag moves only selection, edge "+", tidy, resize
  drift, conflict banner, Ctrl+S, nudge, preview mode) and docs (`flowchart-builder` en + zh-CN: layout,
  saving and conflicts, undo, subflow preview, shortcuts, validation, launch block).
- Verify: Vitest 100%, targeted RSpec, full parallel RSpec, Playwright app-backed + self-contained, dev
  smoke en + zh-CN, then tech-lead + code-reviewer.

Out of scope: the auto-created decision branch with a blank match value (validation already flags a
second Otherwise); `generate_activity` swallowing generator errors (Launch now runs the dry run first).
