# Canvas Drag-and-Drop Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the page-builder canvas's native HTML5 drag-and-drop with a custom Pointer Events engine that supports mouse + touch + pen, drops precisely (including between side-by-side fields in a 12-column row), and unifies the four duplicated drop paths into one.

**Architecture:** Split the drag layer into pure, node-testable core modules (geometry + mutation index math) and thin DOM/pointer manager wrappers. Reuse the existing, sound data-mutation helpers (`createField`, `_reorderSection`, `normalizeSectionDividers`, etc.). Input capture, hit-testing, and visuals are rewritten; *what happens on drop* is reused.

**Tech Stack:** Stimulus controllers/managers (ES modules via importmap, bare-specifier `controllers/page_builder/*`), Pointer Events API, TailwindCSS. No bundler, no JS test runner — pure logic is tested with standalone `node --test`-free `assert` scripts; DOM/pointer layers verified by manual smoke.

**Testing note (read first):** This repo has **no JS test runner and no Capybara JS driver** (JS system specs are skipped). Therefore:
- Pure logic (Tasks 1–2) lives in dependency-free modules and is tested with `node` scripts under `test/js/` using `node:assert`.
- DOM/pointer layers (Tasks 3–8) have no automated harness; each has an explicit **manual smoke** verification run against `SKIP_AUTH=1` dev server on an **active** page (e.g. `/81721200/admin/maintenance/pages/41/edit`).
- Do not add npm/jest/a bundler — that conflicts with project conventions.

**Commit policy:** The user works on `master` and commits themselves. Do **not** run `git commit` (no auto-commit on master). "Commit" steps below are replaced by "stop and report; leave changes staged-free for the user." If executed inside a git worktree branch, auto-commit is fine.

---

## File Structure

Create (all under `app/javascript/controllers/page_builder/` unless noted):

- `dnd/drop_geometry.js` — **pure**. Given region rects + pointer, returns the chosen insertion slot `{containerKey, index, orientation, rect}`. No imports. Node-testable.
- `dnd/field_mutations.js` — **pure**. Index math over plain field arrays: `insertAt`, `moveFields`, `reorderSectionBlock`, `moveIntoColumn`. No imports. Node-testable. (Section/divider helpers re-expressed as pure functions; `field_manager` keeps thin wrappers that call these.)
- `drag_engine.js` — manager. Pointer lifecycle, payload, threshold/long-press, capture, autoscroll. Imports `BaseManager`, `drop_geometry`.
- `drop_resolver.js` — manager. Reads the live DOM into region descriptors, calls `drop_geometry`, applies nesting constraints. Imports `BaseManager`, `drop_geometry`.
- `drag_visuals.js` — manager. Ghost + single insertion indicator + source placeholder. Imports `BaseManager`.
- `drop_mutations.js` — manager. Applies a resolved drop using `field_mutations` core + existing helpers, then render/undo/select/markDirty. Imports `BaseManager`, `field_mutations`.

Modify:
- `app/javascript/controllers/page_builder_controller.js` — register new managers; add `dragPointerDown` action; remove native dnd action delegations.
- `app/javascript/controllers/page_builder/field_manager.js` — card/section render: swap native `draggable`+dnd `data-action`s for `pointerdown->page-builder#dragPointerDown` + descriptors; delete `fieldDragStart/End/Over/Drop`; keep `_reorderSection`/`normalizeSectionDividers` but route their pure math through `field_mutations`.
- `app/javascript/controllers/page_builder/drag_drop_manager.js` — delete native handlers (`dragStart/End/Over/Enter/Leave/drop`, `getDropIndex`, `updateDropIndicator`, `showDragPreview/hideDragPreview/_moveDragPreview`, `rowDropZone*`, `column*`, placeholder helpers). Keep `_colsToWidth` + `_autoScroll` (move to `drag_engine`/`drop_resolver` or keep as shared util).
- Sidebar field item partial `app/views/admin/maintenance/pages/_field_sidebar_item.html.erb` — swap native `draggable`/`dragstart` for `pointerdown->page-builder#dragPointerDown` + `data-drag-kind="new"`.

Test files:
- `test/js/drop_geometry_test.mjs`
- `test/js/field_mutations_test.mjs`
- `test/js/run.sh` — runs both with `node`.

---

## Task 1: Pure drop-geometry core

**Files:**
- Create: `app/javascript/controllers/page_builder/dnd/drop_geometry.js`
- Test: `test/js/drop_geometry_test.mjs`

The core operates on plain "regions". A **region** describes one container's children as rows of cells:
```
Region = {
  containerKey: string,                 // "page" | "column:<id>:<idx>" | "group:<id>"
  rows: Array<{ top, bottom, cells: Array<{ left, right, index }> }>
  // `index` is the insertion index in the container's field array for the slot
  // BEFORE that cell. The slot AFTER the last cell in a row uses cell.index+1.
}
```
`resolveSlot(region, pointer)` returns `{ containerKey, index, orientation, rect }`:
- Find the row whose `[top,bottom]` contains `pointer.y` (else nearest row; if pointer below all rows → after last row).
- Within that row, find the cell whose `[left,right]` contains `pointer.x`; insert **before** it if `pointer.x < midX`, else **after**. Orientation `"vertical"`, rect = a thin vertical bar at the chosen cell edge spanning the row height.
- If pointer.y is between rows (not inside any cell row) → orientation `"horizontal"`, rect = thin horizontal bar at the gap, index = first cell index of the row below (or after-last).

- [ ] **Step 1: Write the failing test**

```js
// test/js/drop_geometry_test.mjs
import assert from "node:assert/strict"
import { resolveSlot } from "../../app/javascript/controllers/page_builder/dnd/drop_geometry.js"

// One row with two side-by-side cells (each 100px wide, row y 0..40)
const region = {
  containerKey: "page",
  rows: [
    { top: 0, bottom: 40, cells: [
      { left: 0,   right: 100, index: 0 },
      { left: 100, right: 200, index: 1 }
    ] }
  ]
}

// Pointer over left half of first cell → insert before index 0, vertical
let r = resolveSlot(region, { x: 20, y: 20 })
assert.equal(r.index, 0); assert.equal(r.orientation, "vertical")

// Pointer over right half of first cell → insert before second cell (index 1)
r = resolveSlot(region, { x: 80, y: 20 })
assert.equal(r.index, 1); assert.equal(r.orientation, "vertical")

// Pointer over right half of last cell → after last (index 2)
r = resolveSlot(region, { x: 180, y: 20 })
assert.equal(r.index, 2); assert.equal(r.orientation, "vertical")

// Pointer below all rows → after last cell
r = resolveSlot(region, { x: 50, y: 80 })
assert.equal(r.index, 2)

console.log("drop_geometry: all assertions passed")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node test/js/drop_geometry_test.mjs`
Expected: FAIL — `Cannot find module .../drop_geometry.js` (file not yet created).

- [ ] **Step 3: Write minimal implementation**

```js
// app/javascript/controllers/page_builder/dnd/drop_geometry.js
// Pure geometry: no DOM, no imports. Given a region (rows of cells) and a
// pointer, return the insertion slot. Unit-tested under test/js/.

export function resolveSlot(region, pointer) {
  const rows = region.rows || []
  if (rows.length === 0) {
    return { containerKey: region.containerKey, index: 0, orientation: "horizontal", rect: null }
  }

  // Locate the row the pointer is vertically within.
  let rowIdx = rows.findIndex(r => pointer.y >= r.top && pointer.y <= r.bottom)

  if (rowIdx === -1) {
    // Between/above/below rows → horizontal insertion.
    if (pointer.y < rows[0].top) {
      return horizontalSlot(region, rows[0], "before")
    }
    for (let i = 0; i < rows.length - 1; i++) {
      if (pointer.y > rows[i].bottom && pointer.y < rows[i + 1].top) {
        return horizontalSlot(region, rows[i + 1], "before")
      }
    }
    return horizontalSlot(region, rows[rows.length - 1], "after")
  }

  // Inside a row → vertical slot between cells by mid-x.
  const row = rows[rowIdx]
  const cells = row.cells
  for (const cell of cells) {
    if (pointer.x < (cell.left + cell.right) / 2) {
      return verticalSlot(region, row, cell.left, cell.index)
    }
  }
  const last = cells[cells.length - 1]
  return verticalSlot(region, row, last.right, last.index + 1)
}

function verticalSlot(region, row, x, index) {
  return {
    containerKey: region.containerKey,
    index,
    orientation: "vertical",
    rect: { left: x, top: row.top, width: 2, height: row.bottom - row.top }
  }
}

function horizontalSlot(region, row, edge) {
  const cells = row.cells
  const left = cells.length ? cells[0].left : 0
  const right = cells.length ? cells[cells.length - 1].right : 0
  const index = edge === "before"
    ? (cells.length ? cells[0].index : 0)
    : (cells.length ? cells[cells.length - 1].index + 1 : 0)
  const y = edge === "before" ? row.top : row.bottom
  return {
    containerKey: region.containerKey,
    index,
    orientation: "horizontal",
    rect: { left, top: y, width: right - left, height: 2 }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node test/js/drop_geometry_test.mjs`
Expected: `drop_geometry: all assertions passed`

- [ ] **Step 5: Checkpoint**

Stop and report. (No commit on master — leave for the user.)

---

## Task 2: Pure field-mutation core

**Files:**
- Create: `app/javascript/controllers/page_builder/dnd/field_mutations.js`
- Test: `test/js/field_mutations_test.mjs`

Pure functions over plain field arrays (objects with `id`, optional `type`/`field_type`/`property_type`). They return **new arrays**; callers assign back and re-number `order`.

Functions:
- `isSection(f)` → `f.property_type === "layout" && f.field_type === "section"`.
- `moveFields(list, movingIds, targetIndex)` — remove `movingIds` (preserve their relative order), insert them at the index they map to after removal (target expressed as an index into the *original* list; adjust for removed-before-target).
- `reorderSectionBlock(list, sectionId, targetId)` — the algorithm already validated in the section-reorder work: move the whole section block before/after the target's section. Returns `{ list, movedIds }`.

- [ ] **Step 1: Write the failing test**

```js
// test/js/field_mutations_test.mjs
import assert from "node:assert/strict"
import { moveFields, reorderSectionBlock, isSection }
  from "../../app/javascript/controllers/page_builder/dnd/field_mutations.js"

const S = id => ({ id, property_type: "layout", field_type: "section" })
const F = id => ({ id })

// moveFields: move f1 to the end
let list = [F("f1"), F("f2"), F("f3")]
let out = moveFields(list, ["f1"], 3)  // target index 3 = after f3 (original length)
assert.deepEqual(out.map(f => f.id), ["f2", "f3", "f1"])

// moveFields: move f3 before f1
out = moveFields(list, ["f3"], 0)
assert.deepEqual(out.map(f => f.id), ["f3", "f1", "f2"])

// reorderSectionBlock: drag SA down onto SC
list = [S("SA"), F("a1"), S("SB"), F("b1"), S("SC"), F("c1")]
let res = reorderSectionBlock(list, "SA", "SC")
assert.deepEqual(res.list.map(f => f.id), ["SB", "b1", "SC", "c1", "SA", "a1"])
assert.deepEqual(res.movedIds, ["SA", "a1"])

// reorderSectionBlock: dropping a section onto a field inside another section
// snaps after that whole section (no mid-section landing)
res = reorderSectionBlock(list, "SA", "b1")
assert.deepEqual(res.list.map(f => f.id), ["SB", "b1", "SA", "a1", "SC", "c1"])

assert.equal(isSection(S("x")), true)
assert.equal(isSection(F("y")), false)
console.log("field_mutations: all assertions passed")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node test/js/field_mutations_test.mjs`
Expected: FAIL — module not found.

- [ ] **Step 3: Write minimal implementation**

```js
// app/javascript/controllers/page_builder/dnd/field_mutations.js
// Pure list math for drag-drop. No DOM, no imports. Unit-tested under test/js/.

export function isSection(f) {
  return !!f && f.property_type === "layout" && f.field_type === "section"
}

// Move `movingIds` (kept in their current relative order) so they land at
// `targetIndex` expressed against the ORIGINAL list. Returns a new array.
export function moveFields(list, movingIds, targetIndex) {
  const ids = new Set(movingIds)
  const moving = list.filter(f => ids.has(f.id))
  const remaining = list.filter(f => !ids.has(f.id))
  const removedBefore = list.slice(0, targetIndex).filter(f => ids.has(f.id)).length
  const insertAt = Math.max(0, Math.min(targetIndex - removedBefore, remaining.length))
  remaining.splice(insertAt, 0, ...moving)
  return remaining
}

// Move the whole section block headed by `sectionId` (header + fields up to the
// next section header) before/after the target's section. Returns { list, movedIds }.
export function reorderSectionBlock(list, sectionId, targetId) {
  const headerIdxs = []
  list.forEach((f, i) => { if (isSection(f)) headerIdxs.push(i) })

  const dStart = list.findIndex(f => f.id === sectionId)
  if (dStart < 0) return { list, movedIds: [] }
  const dNext = headerIdxs.find(i => i > dStart)
  const dEnd = dNext === undefined ? list.length : dNext
  const block = list.slice(dStart, dEnd)
  const ids = new Set(block.map(f => f.id))
  const movedIds = block.map(f => f.id)

  if (ids.has(targetId)) return { list: list.slice(), movedIds }
  const tAny = list.findIndex(f => f.id === targetId)
  if (tAny < 0) return { list: list.slice(), movedIds }

  let tStart = -1
  for (let i = tAny; i >= 0; i--) { if (isSection(list[i])) { tStart = i; break } }

  let beforeId = null, afterId = null
  if (tStart === -1) {
    beforeId = list[0] ? list[0].id : null
  } else {
    const tNext = headerIdxs.find(i => i > tStart)
    const tEnd = tNext === undefined ? list.length : tNext
    if (dStart < tStart) afterId = list[tEnd - 1].id
    else beforeId = list[tStart].id
  }

  const remaining = list.filter(f => !ids.has(f.id))
  let insertIdx = remaining.length
  if (beforeId != null) {
    const i = remaining.findIndex(f => f.id === beforeId)
    if (i !== -1) insertIdx = i
  } else if (afterId != null) {
    const i = remaining.findIndex(f => f.id === afterId)
    if (i !== -1) insertIdx = i + 1
  }
  remaining.splice(insertIdx, 0, ...block)
  return { list: remaining, movedIds }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node test/js/field_mutations_test.mjs`
Expected: `field_mutations: all assertions passed`

- [ ] **Step 5: Add the runner script**

```bash
# test/js/run.sh
#!/usr/bin/env bash
set -e
node test/js/drop_geometry_test.mjs
node test/js/field_mutations_test.mjs
```
Run: `bash test/js/run.sh` → both pass.

- [ ] **Step 6: Checkpoint** — stop and report (no commit on master).

---

## Task 3: `DragVisuals` manager (ghost + indicator)

**Files:**
- Create: `app/javascript/controllers/page_builder/drag_visuals.js`
- Modify: `app/javascript/controllers/page_builder_controller.js` (register manager; reuse existing `dragPreview`/`dropIndicator` targets)

No automated test (DOM). Manual smoke at end.

- [ ] **Step 1: Implement**

```js
// app/javascript/controllers/page_builder/drag_visuals.js
import { BaseManager } from "controllers/page_builder/base_manager"

export class DragVisuals extends BaseManager {
  // Show a floating ghost. `node` is an HTMLElement to snapshot, or null for a
  // labeled chip (new field from sidebar).
  showGhost(node, label) {
    if (!this.c.hasDragPreviewTarget) return
    const ghost = this.c.dragPreviewTarget
    if (node) {
      ghost.innerHTML = ""
      const clone = node.cloneNode(true)
      clone.style.width = `${node.getBoundingClientRect().width}px`
      ghost.appendChild(clone)
    } else {
      ghost.innerHTML = `<div class="px-4 py-2 bg-white rounded-lg shadow-lg border border-indigo-200 text-sm font-medium text-indigo-700">${label || "Field"}</div>`
    }
    ghost.classList.remove("opacity-0")
    ghost.classList.add("opacity-90", "shadow-xl", "scale-105")
  }

  moveGhost(x, y) {
    if (!this.c.hasDragPreviewTarget) return
    // translate; offset so the cursor sits just inside the top-left.
    this.c.dragPreviewTarget.style.transform = `translate(${x + 8}px, ${y + 8}px)`
  }

  hideGhost() {
    if (!this.c.hasDragPreviewTarget) return
    this.c.dragPreviewTarget.classList.add("opacity-0")
    this.c.dragPreviewTarget.classList.remove("opacity-90", "shadow-xl", "scale-105")
    this.c.dragPreviewTarget.innerHTML = ""
    this.c.dragPreviewTarget.style.transform = ""
  }

  // target = { orientation, rect:{left,top,width,height} } in viewport coords.
  showIndicator(target) {
    if (!this.c.hasDropIndicatorTarget || !target || !target.rect) { this.hideIndicator(); return }
    const ind = this.c.dropIndicatorTarget
    const r = target.rect
    ind.style.left = `${r.left}px`
    ind.style.top = `${r.top}px`
    ind.style.width = `${r.width}px`
    ind.style.height = `${r.height}px`
    ind.classList.remove("opacity-0")
    ind.classList.add("opacity-100")
  }

  hideIndicator() {
    if (!this.c.hasDropIndicatorTarget) return
    this.c.dropIndicatorTarget.classList.remove("opacity-100")
    this.c.dropIndicatorTarget.classList.add("opacity-0")
  }

  markSource(ids) {
    ids.forEach(id => {
      const card = this.c.fieldsContainerTarget?.querySelector(`[data-field-id="${id}"]`)
      if (card) card.classList.add("opacity-40")
    })
  }

  clearSource() {
    this.c.fieldsContainerTarget?.querySelectorAll(".opacity-40").forEach(el => el.classList.remove("opacity-40"))
  }
}
```

- [ ] **Step 2: Register** in `page_builder_controller.js` `connect()` manager init block (follow existing `initManager` pattern):
```js
this.dragVisuals = initManager("DragVisuals", () => new DragVisuals(this))
```
and add the import at top:
```js
import { DragVisuals } from "controllers/page_builder/drag_visuals"
```

- [ ] **Step 3: Adjust the `dropIndicator` markup** in `app/views/admin/maintenance/pages/_editor.html.erb` so a single element can render either orientation — replace the two-child indicator with one bar styled by inline size:
```erb
<div class="drop-indicator fixed pointer-events-none z-50 bg-indigo-500 rounded-full opacity-0 transition-opacity"
     data-page-builder-target="dropIndicator"></div>
```
(Width/height are set by `showIndicator`.)

- [ ] **Step 4: Checkpoint** — stop and report.

---

## Task 4: `DropResolver` manager (DOM → regions → slot)

**Files:**
- Create: `app/javascript/controllers/page_builder/drop_resolver.js`

Reads the rendered canvas into `Region`s and calls `drop_geometry.resolveSlot`, then applies nesting constraints. Returns a `DropTarget` enriched with container references and the data-array index, or `null` if not droppable.

- [ ] **Step 1: Implement**

```js
// app/javascript/controllers/page_builder/drop_resolver.js
import { BaseManager } from "controllers/page_builder/base_manager"
import { resolveSlot } from "controllers/page_builder/dnd/drop_geometry"

export class DropResolver extends BaseManager {
  // payload: { kind, data, fieldIds, primaryId, isSection }
  // Returns { containerKey, container, containerRef, index, orientation, rect } | null
  resolve(pointer, payload) {
    const region = this._topLevelRegion(payload)
    // Prefer a column/group region if the pointer is over one and the payload is allowed there.
    const nested = this._nestedRegionAt(pointer, payload)
    const slot = resolveSlot(nested || region, pointer)
    if (!slot) return null
    return this._decorate(slot, payload)
  }

  _topLevelRegion(payload) {
    const container = this.c.fieldsContainerTarget
    const movingIds = new Set(payload.kind === "move" ? payload.fieldIds : [])
    // Build rows from top-level .field-card and .field-group elements that are
    // direct visual children (skip ones being moved so geometry ignores them).
    const cards = Array.from(container.querySelectorAll(":scope .field-card, :scope .field-group, :scope .section-group"))
      .filter(el => !movingIds.has(el.dataset.fieldId))
    return { containerKey: "page", rows: this._rowsFromCards(cards) }
  }

  _rowsFromCards(cards) {
    // Group cards into rows by overlapping vertical bands; assign data indices
    // from each card's position in currentPageFields.
    const fields = this.c.currentPageFields
    const indexOf = id => fields.findIndex(f => f.id === id)
    const rows = []
    let current = null
    cards.forEach(el => {
      const rect = el.getBoundingClientRect()
      const idx = indexOf(el.dataset.fieldId)
      const cell = { left: rect.left, right: rect.right, index: idx < 0 ? fields.length : idx }
      if (current && rect.top < current.bottom - 4) {
        current.cells.push(cell)
        current.bottom = Math.max(current.bottom, rect.bottom)
      } else {
        current = { top: rect.top, bottom: rect.bottom, cells: [cell] }
        rows.push(current)
      }
    })
    rows.forEach(r => r.cells.sort((a, b) => a.left - b.left))
    return rows
  }

  _nestedRegionAt(pointer, payload) {
    // Columns/groups: only if pointer is inside one and the payload may nest there.
    const el = document.elementFromPoint(pointer.x, pointer.y)
    if (!el) return null
    const col = el.closest("[data-column-index]")
    const group = el.closest("[data-group-fields-container]")
    if (group && this._mayNest(payload)) {
      return this._regionFromContainer(group, `group:${group.dataset.groupFieldsContainer}`)
    }
    if (col && this._mayNest(payload)) {
      return this._regionFromContainer(col, `column:${col.dataset.parentFieldId}:${col.dataset.columnIndex}`)
    }
    return null
  }

  _mayNest(payload) {
    const type = payload.kind === "new" ? payload.data?.type : this._typeOf(payload.primaryId)
    return type !== "columns" && type !== "field_group" && !payload.isSection
  }

  _typeOf(id) {
    const f = this.c.fieldManager.findFieldById(id)
    return f ? (f.type || f.field_type) : null
  }

  _regionFromContainer(containerEl, containerKey) {
    const cards = Array.from(containerEl.querySelectorAll(":scope > .field-card"))
    return { containerKey, rows: this._rowsFromCards(cards) }
  }

  _decorate(slot, payload) {
    // Reject obvious non-drops: duplicate slug for a new entity field, etc.
    if (payload.kind === "new") {
      const d = payload.data
      if (d?.type === "entity" && !d.htmlType) return null
      if (d?.propertySlug && this.c.fieldManager.getUsedPropertySlugs().has(d.propertySlug)) return null
    }
    return slot
  }
}
```

- [ ] **Step 2: Register** in controller (`import { DropResolver }` + `this.dropResolver = initManager("DropResolver", () => new DropResolver(this))`).

- [ ] **Step 3: Manual sanity** — add a temporary `console.log(this.dropResolver.resolve(...))` is unnecessary; verified via Task 7 smoke. Checkpoint — stop and report.

---

## Task 5: `DragEngine` manager (pointer lifecycle)

**Files:**
- Create: `app/javascript/controllers/page_builder/drag_engine.js`
- Modify: `page_builder_controller.js` (register + `dragPointerDown` action)

- [ ] **Step 1: Implement**

```js
// app/javascript/controllers/page_builder/drag_engine.js
import { BaseManager } from "controllers/page_builder/base_manager"

const MOVE_THRESHOLD = 5      // px before a mouse drag starts
const LONG_PRESS_MS = 180     // touch hold before a drag starts
const AUTO_SCROLL_EDGE = 60
const AUTO_SCROLL_MAX = 20

export class DragEngine extends BaseManager {
  // Bound on a draggable element's pointerdown (data-action).
  pointerDown(event) {
    if (event.button != null && event.button !== 0) return
    const source = event.currentTarget
    this._start = { x: event.clientX, y: event.clientY }
    this._source = source
    this._pointerId = event.pointerId
    this._payload = this._buildPayload(source)
    if (!this._payload) return
    this._armed = true
    this._dragging = false

    this._onMove = this._move.bind(this)
    this._onUp = this._up.bind(this)
    window.addEventListener("pointermove", this._onMove, { passive: false })
    window.addEventListener("pointerup", this._onUp)
    window.addEventListener("pointercancel", this._onUp)

    if (event.pointerType === "touch") {
      this._longPressTimer = setTimeout(() => this._beginDrag(event), LONG_PRESS_MS)
    }
  }

  _buildPayload(source) {
    const kind = source.dataset.dragKind
    if (kind === "new") {
      return { kind: "new", data: this.c.dragDropManager._sidebarData(source) }
    }
    const fieldId = source.dataset.fieldId
    if (!fieldId) return null
    const sel = this.c.selectionManager.getSelectedFieldIds()
    const fieldIds = (sel.length > 1 && sel.includes(fieldId)) ? sel : [fieldId]
    const isSection = !!this.c.fieldManager._sectionIdForDrag(fieldId)
    return { kind: "move", fieldIds, primaryId: fieldId, isSection }
  }

  _move(event) {
    if (!this._armed) return
    if (!this._dragging) {
      const dx = event.clientX - this._start.x
      const dy = event.clientY - this._start.y
      if (Math.hypot(dx, dy) >= MOVE_THRESHOLD) this._beginDrag(event)
      else return
    }
    event.preventDefault()
    const p = { x: event.clientX, y: event.clientY }
    this.c.dragVisuals.moveGhost(p.x, p.y)
    const target = this.c.dropResolver.resolve(p, this._payload)
    this._lastTarget = target
    this.c.dragVisuals.showIndicator(target)
    this._autoScroll(p.y)
  }

  _beginDrag(event) {
    if (this._dragging) return
    clearTimeout(this._longPressTimer)
    this._dragging = true
    try { this._source.setPointerCapture(this._pointerId) } catch (_e) {}
    this._source.style.touchAction = "none"
    const ghostNode = this._payload.kind === "move"
      ? this.c.fieldsContainerTarget.querySelector(`[data-field-id="${this._payload.primaryId}"]`)
      : null
    this.c.dragVisuals.showGhost(ghostNode, this._payload.data?.label)
    if (this._payload.kind === "move") this.c.dragVisuals.markSource(this._payload.fieldIds)
  }

  _up(event) {
    clearTimeout(this._longPressTimer)
    window.removeEventListener("pointermove", this._onMove)
    window.removeEventListener("pointerup", this._onUp)
    window.removeEventListener("pointercancel", this._onUp)

    const wasDragging = this._dragging
    const target = this._lastTarget
    const payload = this._payload
    this._cleanup()

    if (wasDragging && target && event.type !== "pointercancel") {
      this.c.dropMutations.apply(payload, target)
    }
  }

  _cleanup() {
    if (this._source) this._source.style.touchAction = ""
    this.c.dragVisuals.hideGhost()
    this.c.dragVisuals.hideIndicator()
    this.c.dragVisuals.clearSource()
    this._armed = false
    this._dragging = false
    this._source = null
    this._payload = null
    this._lastTarget = null
  }

  _autoScroll(clientY) {
    if (!this.c.hasCanvasAreaTarget) return
    const el = this.c.canvasAreaTarget
    const rect = el.getBoundingClientRect()
    const top = clientY - rect.top
    const bottom = rect.bottom - clientY
    if (top < AUTO_SCROLL_EDGE && top >= 0) el.scrollTop -= Math.round(AUTO_SCROLL_MAX * (1 - top / AUTO_SCROLL_EDGE))
    else if (bottom < AUTO_SCROLL_EDGE && bottom >= 0) el.scrollTop += Math.round(AUTO_SCROLL_MAX * (1 - bottom / AUTO_SCROLL_EDGE))
  }
}
```

- [ ] **Step 2:** Add `_sidebarData(source)` to `drag_drop_manager.js` (extract from the old `dragStart`):
```js
_sidebarData(element) {
  return {
    type: element.dataset.fieldType,
    label: element.dataset.fieldLabel || element.dataset.propertyName,
    propertySlug: element.dataset.propertySlug,
    propertyType: element.dataset.propertyType,
    htmlType: element.dataset.propertyHtmlType,
    source: element.dataset.source || null,
    sourceSection: element.dataset.sourceSection || null,
    options: element.dataset.fieldOptions ? JSON.parse(element.dataset.fieldOptions) : null,
    dynamicOptions: element.dataset.dynamicOptions ? JSON.parse(element.dataset.dynamicOptions) : null
  }
}
```

- [ ] **Step 3: Register + action** in `page_builder_controller.js`:
```js
import { DragEngine } from "controllers/page_builder/drag_engine"
// in connect(): this.dragEngine = initManager("DragEngine", () => new DragEngine(this))
// add delegated action:
dragPointerDown(event) { this.dragEngine.pointerDown(event) }
```

- [ ] **Step 4: Checkpoint** — stop and report.

---

## Task 6: `DropMutations` manager

**Files:**
- Create: `app/javascript/controllers/page_builder/drop_mutations.js`

- [ ] **Step 1: Implement**

```js
// app/javascript/controllers/page_builder/drop_mutations.js
import { BaseManager } from "controllers/page_builder/base_manager"
import { moveFields, reorderSectionBlock } from "controllers/page_builder/dnd/field_mutations"

export class DropMutations extends BaseManager {
  apply(payload, target) {
    this.c.undoRedoManager.saveState()
    if (payload.kind === "new") return this._insertNew(payload, target)
    if (payload.isSection) return this._moveSection(payload, target)
    if (target.containerKey.startsWith("column:")) return this._moveIntoColumn(payload, target)
    return this._moveTopLevel(payload, target)
  }

  _afterChange(idsToSelect, primaryId) {
    this.c.fields = this.c.currentPageFields
    this.c.currentPage.fields.forEach((f, i) => { f.order = i })
    this.c.fieldManager.renderFields()
    if (idsToSelect && idsToSelect.length > 1) this.c.selectionManager.selectFields(idsToSelect)
    else if (primaryId) this.c.fieldManager.selectFieldById(primaryId)
    if (primaryId) this.c.dragDropManager._animateDroppedField(primaryId)
    this.c.saveManager.markDirty()
    this.c.tabManager.closeAllTabPanels()
  }

  _insertNew(payload, target) {
    const field = this.c.fieldManager.createField(payload.data)
    if (target.containerKey.startsWith("column:")) {
      const [, parentId, colIdx] = target.containerKey.split(":")
      const cols = this.c.fields.find(f => f.id === parentId)?.columns
      if (cols && cols[colIdx]) cols[colIdx].fields.push(field)
    } else {
      this.c.currentPage.fields.splice(target.index, 0, field)
    }
    this._afterChange(null, field.id)
  }

  _moveTopLevel(payload, target) {
    this.c.currentPage.fields = moveFields(this.c.currentPage.fields, payload.fieldIds, target.index)
    this._afterChange(payload.fieldIds, payload.primaryId)
  }

  _moveSection(payload, target) {
    // Resolve the target field id nearest the drop slot to reuse the validated
    // section-block algorithm.
    const targetId = this._fieldIdAtIndex(target.index)
    const { list } = reorderSectionBlock(this.c.currentPage.fields, payload.primaryId, targetId)
    this.c.currentPage.fields = list
    this._afterChange(payload.fieldIds, payload.primaryId)
  }

  _moveIntoColumn(payload, target) {
    const [, parentId, colIdx] = target.containerKey.split(":")
    const cols = this.c.fields.find(f => f.id === parentId)?.columns
    if (!cols || !cols[colIdx]) { this._afterChange(payload.fieldIds, payload.primaryId); return }
    payload.fieldIds.forEach(id => {
      const field = this.c.fieldManager.findFieldById(id)
      if (!field || field.field_type === "columns") return
      this.c.fieldManager.removeFieldFromAnyColumn(id)
      const top = this.c.currentPage.fields.findIndex(f => f.id === id)
      if (top !== -1) this.c.currentPage.fields.splice(top, 1)
      cols[colIdx].fields.push(field)
    })
    this._afterChange(payload.fieldIds, payload.primaryId)
  }

  _fieldIdAtIndex(index) {
    const fields = this.c.currentPage.fields
    return fields[Math.min(index, fields.length - 1)]?.id
  }
}
```

- [ ] **Step 2: Register** in controller (`import { DropMutations }` + `this.dropMutations = initManager(...)`).

- [ ] **Step 3: Checkpoint** — stop and report.

---

## Task 7: Wire rendering to the new engine

**Files:**
- Modify: `app/javascript/controllers/page_builder/field_manager.js` (`createFieldCard` ~line 800, `_renderSectionGroup`, `_renderFieldGroup`)
- Modify: `app/views/admin/maintenance/pages/_field_sidebar_item.html.erb`

- [ ] **Step 1:** In `createFieldCard`, replace the native dnd block. Change:
```js
div.draggable = true
div.dataset.action = [
  "click->page-builder#selectField",
  "dragstart->page-builder#fieldDragStart",
  "dragend->page-builder#fieldDragEnd",
  "dragover->page-builder#fieldDragOver",
  "drop->page-builder#fieldDrop",
  "contextmenu->page-builder#openFieldContextMenu"
].join(" ")
```
to:
```js
div.dataset.dragKind = "move"
div.dataset.action = [
  "click->page-builder#selectField",
  "pointerdown->page-builder#dragPointerDown",
  "contextmenu->page-builder#openFieldContextMenu"
].join(" ")
```
(Remove `div.draggable = true`.)

- [ ] **Step 2:** In `_renderSectionGroup`, the header card's `dataset.action` is rebuilt — ensure it keeps `pointerdown->page-builder#dragPointerDown` (it inherits from `createFieldCard`) plus the existing `dblclick->page-builder#selectSection`. Confirm `headerCard.dataset.dragKind` stays `"move"`.

- [ ] **Step 3:** In the sidebar item partial, replace native drag attributes. Change the draggable element's `draggable="true"` + `data-action="dragstart->page-builder#dragStart dragend->page-builder#dragEnd"` to:
```erb
data-action="pointerdown->page-builder#dragPointerDown"
data-drag-kind="new"
```
(Keep all existing `data-field-*`, `data-property-*`, `data-source*`, `data-field-options`, `data-dynamic-options` attributes — `_sidebarData` reads them.)

- [ ] **Step 4: Manual smoke** — `rm -f public/assets/.manifest.json && RAILS_ENV=development bundle exec rails assets:precompile`, restart server, open `/81721200/admin/maintenance/pages/41/edit`. Verify with **mouse**:
  - Drag a sidebar field onto the canvas → inserts at the indicated slot.
  - Drag a card between two side-by-side fields → vertical indicator appears at the gap; drops into that slot.
  - Drag a card between rows → horizontal indicator; drops there.
  - Double-click a section header → whole section selected → drag → section reorders, dividers correct.
  - Drag a field into a `columns` cell → lands in the column.
  Then with **touch emulation** (DevTools): long-press a card → drag → drops; page still scrolls when not dragging.

- [ ] **Step 5: Checkpoint** — stop and report.

---

## Task 8: Delete obsolete native handlers

**Files:**
- Modify: `app/javascript/controllers/page_builder/drag_drop_manager.js`
- Modify: `app/javascript/controllers/page_builder/field_manager.js`
- Modify: `app/javascript/controllers/page_builder_controller.js`

- [ ] **Step 1:** From `drag_drop_manager.js` delete: `dragStart`, `dragEnd`, `cleanupDrag`, `dragOver`, `dragEnter`, `dragLeave`, `drop`, `getDropIndex`, `showDragPreview`, `hideDragPreview`, `updateDropIndicator`, `hideDropIndicator`, `rowDropZoneDragOver/Enter/Leave/Drop`, `columnDragOver/Enter/Leave`, `columnDrop`, `_createPlaceholder`, `_removePlaceholder`. **Keep:** `_sidebarData`, `_animateDroppedField`, `_colsToWidth`, `_autoScroll` (still referenced).

- [ ] **Step 2:** From `field_manager.js` delete: `fieldDragStart`, `fieldDragEnd`, `fieldDragOver`, `fieldDrop`. **Keep:** `_reorderSection`, `_sectionIdForDrag`, `normalizeSectionDividers`, `selectSection`, `removeFieldFromAnyColumn`, `findFieldById`.

- [ ] **Step 3:** From `page_builder_controller.js` delete the now-unused delegations: `dragStart`, `dragEnd`, `dragOver`, `dragEnter`, `dragLeave`, `drop`, `fieldDragStart`, `fieldDragEnd`, `fieldDragOver`, `fieldDrop`, `rowDropZone*`, `columnDrag*`, `columnDrop`. Remove any matching `data-action`s still present in editor markup (row drop zones / column zones now route through the engine; update `_createRowDropZone` and column rendering to use `pointerdown` only if they remain interactive — otherwise the engine's `_nestedRegionAt` + top-level region already covers them, so their native `data-action`s can be dropped).

- [ ] **Step 4:** Grep for leftovers:
```bash
grep -rn "fieldDragStart\|dragStart\|rowDropZone\|columnDrop\|getDropIndex\|draggable" app/javascript app/views/admin/maintenance/pages
```
Expected: no references except the new `pointerdown->page-builder#dragPointerDown` wiring.

- [ ] **Step 5: Re-run pure tests + smoke** — `bash test/js/run.sh` passes; repeat Task 7 Step 4 smoke matrix. Checkpoint — stop and report.

---

## Task 9: Regression pass

- [ ] **Step 1:** Targeted RSpec for any touched server views/components (the page editor render path):
```bash
bundle exec rspec spec/system/page_builder 2>/dev/null || bundle exec rspec spec/components/page_builder
```
Expected: existing passing specs still pass (JS-driver system specs remain skipped — that is pre-existing).

- [ ] **Step 2:** Manual regression: undo/redo after each drag op; save + reload page → order/columns/sections/dividers persist; preview reflects layout.

- [ ] **Step 3: Final report** — summarize what changed, the smoke results (mouse + touch), and that pure-logic tests pass.

---

## Self-Review

**Spec coverage:**
- Accurate drop incl. side-by-side → Task 1 (`drop_geometry`) + Task 4 (`DropResolver._rowsFromCards` builds in-row cells). ✓
- Smooth visuals (no desync) → Task 3 (`DragVisuals` transform-based ghost, single indicator). ✓
- Touch/pen → Task 5 (`DragEngine` Pointer Events, long-press, `setPointerCapture`, `touch-action`). ✓
- Unify four paths → Task 6 (`DropMutations`) + Task 8 (delete duplicates). ✓
- Section-aware + dividers → Task 2 (`reorderSectionBlock`) + reuse of `normalizeSectionDividers` via `renderFields`. ✓
- Nesting constraints → Task 4 (`_mayNest`, `_decorate`). ✓
- Out-of-scope (resize) untouched → no task modifies `resize_manager`. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code. ✓

**Type/name consistency:** `resolveSlot`, `moveFields`, `reorderSectionBlock`, `isSection`, payload shape `{kind,data,fieldIds,primaryId,isSection}`, target shape `{containerKey,index,orientation,rect}` used consistently across Tasks 1–6. Manager names (`DragEngine`, `DropResolver`, `DragVisuals`, `DropMutations`) and controller delegation `dragPointerDown` consistent across Tasks 3–8. ✓

**Risk note:** Tasks 3–8 lack automated coverage (no JS DOM harness in repo); mitigated by the explicit manual smoke matrix and by isolating all index/section logic into the node-tested pure cores.
