# Canvas Drag-and-Drop Engine — Design Spec

Date: 2026-06-04
Area: Page Builder canvas editor (`app/javascript/controllers/page_builder/*`)

## 1. Problem

The page-builder canvas uses native HTML5 drag-and-drop. It has four issues:

1. **Inaccurate drop position.** Insertion is computed purely from vertical
   `clientY` against each card's midpoint over a flat `.field-card` list. In a
   12-column row with side-by-side fields you cannot target the slot *between*
   two adjacent fields, and the indicator only ever spans a single card.
2. **Fragile index math.** `getDropIndex` counts every `.field-card` — including
   nested column/group children — so the DOM index drifts from the
   `currentPage.fields` array index.
3. **Duplicated, divergent drop logic.** Four overlapping paths (main drop zone,
   row drop zones, column zones, field-card reorder) re-implement insert/move
   and have already drifted (the section-aware reorder lives only in one path).
4. **No touch support.** Native HTML5 DnD does not fire on touch, so reordering
   is impossible on tablet/phone — which violates the responsive requirement in
   `AGENTS.md`.
5. **Ghost/indicator jank.** A custom preview chases the cursor via a separate
   `mousemove` listener that desyncs from the native drag image.

## 2. Goals

- Precise insertion anywhere, including **between side-by-side fields** in a row,
  with a single clear indicator that shows exactly where the element will land.
- Smooth, controlled visuals (ghost + indicator) with no desync.
- Full **mouse + touch + pen** support via the Pointer Events API.
- One unified drag engine so behavior (grid, columns, groups, sections,
  dividers) is consistent across every drop location.

## 3. Non-goals

- The **resize handle** keeps its existing `mousedown` flow (separate concern);
  pointer-event migration can follow later.
- No redesign of the rendered card / section / column markup beyond optional
  `data-drop-*` hints.
- No third-party drag library (rejected: conflicts with the Stimulus-only
  guideline in `AGENTS.md`, and generic sortables do not model the 12-col grid /
  nested columns / groups / sections).

## 4. Principle

Native HTML5 DnD is replaced by a custom **Pointer Events** engine. The existing
**data-mutation logic is reused** — only input capture, hit-testing, and visuals
are rewritten. *What happens on drop* (insert, reorder, move into column, move
section, divider normalization) stays; *how a drag is captured and where it
lands* is rebuilt. This bounds regression risk.

## 5. Modules

Each module has one purpose, a defined interface, and is testable on its own.

### 5.1 `DragEngine` (new manager)
Owns the drag-session lifecycle.

- Arms on `pointerdown` on any element carrying a draggable descriptor
  (sidebar items, canvas field cards, section headers).
- Starts a drag only after a **movement threshold (~5px)** OR a **touch
  long-press (~180ms)**. Below that, the gesture remains a tap/click (select) or
  a scroll — preserving existing tap-to-select and touch scrolling.
- Builds a `DragPayload`:
  - `{ kind: "new", data }` — from a sidebar element (data = field descriptor).
  - `{ kind: "move", fieldIds, primaryId, isSection }` — from canvas; `fieldIds`
    is the current selection if the grabbed card is selected, else just itself.
- Calls `setPointerCapture(pointerId)` and applies `touch-action: none` to the
  source for the duration of the drag, so events keep flowing and touch does not
  scroll mid-drag.
- `pointermove` → position ghost, run `DropResolver`, update indicator,
  auto-scroll.
- `pointerup` / `pointercancel` → resolve the final `DropTarget` and hand to
  `DropMutations`, or cancel and restore.

Interface (conceptual):
```
start(pointerEvent, source)   // arm + build payload + show ghost
move(pointerEvent)            // visuals + hit-test + autoscroll
finish(pointerEvent)          // resolve + apply, or cancel
cancel()                      // restore, no mutation
```

### 5.2 `DropResolver` (new)
Pure-ish hit-testing. Given pointer `(x, y)` and the live DOM, returns a
normalized `DropTarget` or `null`.

- Builds candidate regions from rendered geometry:
  - top-level **row gaps** (between rows) → horizontal insertion;
  - **slots within a row** between side-by-side cards, decided by each card's
    mid-**x** → vertical insertion;
  - **column cells** (`[data-column-index]`);
  - **group containers** (`[data-group-fields-container]`);
  - page top / bottom.
- Returns:
  ```
  {
    container: "page" | "column" | "group",
    containerRef,            // parentFieldId / columnIndex when nested
    index,                   // insertion index within that container's field list
    orientation: "vertical" | "horizontal",
    rect                     // where to draw the indicator
  }
  ```
- **Section-aware:** when the payload `isSection` is true, snaps `index` to a
  section boundary (reuses the `_reorderSection` boundary logic).
- Enforces nesting constraints: a `columns` or `field_group` may not drop into a
  group container; `columns` may not nest in a column; an `entity` field with no
  `html_type` is rejected; a duplicate `property_slug` is rejected.

### 5.3 `DragVisuals` (new)
One controlled ghost + one reusable indicator.

- **Ghost:** a snapshot (cloned node or labeled chip for new fields) positioned
  with `transform: translate(x, y)` on `pointermove` — GPU-cheap, no separate
  `mousemove` listener, so no desync.
- **Indicator:** a single element rendered as a **vertical bar** for in-row slots
  or a **horizontal bar** between rows, placed from `DropTarget.rect`.
- **Source placeholder:** the dragged card(s) are dimmed / hold their space.
- Cleans up fully on finish/cancel.

### 5.4 `DropMutations` (consolidated; wraps existing logic)
The single place that applies a resolved drop to the data model. Collapses the
four old drop paths into:

- `insertNewField(payload, target)` — `createField` + slug guard, then splice at
  `target.index` into page / column / group.
- `moveFields(payload, target)` — relocate one or more existing fields (preserve
  document order), with index adjustment.
- `moveSection(payload, target)` — whole-section block move (delegates to the
  existing `_reorderSection`).
- `moveIntoColumn(payload, target)` — remove from origin, push into the target
  column.

Each ends with: `undoRedoManager.saveState()` (before mutation),
`fieldManager.renderFields()` (which runs `normalizeSectionDividers`),
re-select moved/created field(s), animate, `saveManager.markDirty()`.

### 5.5 Glue
- `page_builder_controller` exposes a `dragPointerDown(event)` action delegating
  to `DragEngine`.
- Sidebar items, field cards, and section headers get
  `data-action="pointerdown->page-builder#dragPointerDown"` plus a small
  descriptor (`data-drag-kind`, existing `data-field-*` / `data-field-id`).
- Native `draggable="true"` and all `dragstart/dragover/drop`-style
  `data-action`s are removed.

## 6. Data flow

```
pointerdown
  → (threshold / long-press) DragEngine.start: build payload + ghost
  → pointermove: DropResolver.resolve(x,y)
       → DragVisuals.showIndicator(target) + autoScroll
  → pointerup: DropMutations.apply(payload, target)
       → fieldManager.renderFields() → normalizeSectionDividers()
       → re-select + animate + markDirty
```

## 7. Touch & accessibility

- Long-press-or-move start preserves tap-to-select and touch scrolling; only
  while a drag is active is `touch-action: none` applied to the source.
- Edge auto-scroll reuses the existing distance/speed math.
- Background rubber-band selection is unaffected (engine only arms on draggable
  elements; background `pointerdown` still drives rubber-band).
- Keyboard selection / shortcuts unchanged.

## 8. Reuse vs. replace

**Reuse (unchanged):** `createField`, `getUsedPropertySlugs`,
`removeFieldFromAnyColumn`, `_reorderSection`, `normalizeSectionDividers`,
selection manager, undo/redo, save manager, `_colsToWidth`, auto-scroll math.

**Replace / delete:** in `DragDropManager` — `dragStart`, `dragEnd`, `dragOver`,
`dragEnter`, `dragLeave`, `drop`, `getDropIndex`, `updateDropIndicator`,
`showDragPreview` / `hideDragPreview` / `_moveDragPreview`, `rowDropZone*`,
`column*`, placeholder helpers (re-homed into `DragVisuals`). In `FieldManager` —
`fieldDragStart`, `fieldDragEnd`, `fieldDragOver`, `fieldDrop`, and the native
`draggable`/dnd `data-action`s emitted in card/section rendering.

## 9. Testing

- **`DropMutations` + section/divider logic:** unit tests over synthetic field
  arrays (same style as the standalone simulations already validated for section
  reorder and divider normalization).
- **`DropResolver`:** unit tests feeding synthetic element rects → assert chosen
  container/index/orientation, including the side-by-side in-row slot case and
  nesting-constraint rejections.
- **Manual smoke (mouse + touch emulation):** add from sidebar; reorder
  top-level; insert between side-by-side fields; move into a column; whole
  section move; divider correctness after each.

## 10. Risks & mitigations

- **Regression in a working feature.** Mitigation: reuse the mutation layer; build
  the engine alongside, switch `data-action`s over, then delete native handlers
  in one pass; keep rendered markup stable.
- **Touch gesture ambiguity (drag vs scroll vs tap).** Mitigation: explicit
  long-press/threshold start; `touch-action` toggled only during an active drag.
- **Hit-test edge cases at row/column/group boundaries.** Mitigation: unit tests
  with synthetic rects; deterministic region ordering.

## 11. Rollout

Single coordinated change set (build engine → repoint actions → delete native
handlers). No schema or server changes. No feature flag needed; the canvas is an
internal admin tool and the change is all client-side.
