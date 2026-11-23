import { BaseManager } from "controllers/page_builder/base_manager"

const MOVE_THRESHOLD  = 5     // px before a mouse/pen drag starts
const LONG_PRESS_MS   = 180   // touch hold before a drag starts
const AUTO_SCROLL_EDGE = 60
const AUTO_SCROLL_MAX  = 20

// Pointer Events drag lifecycle for canvas elements and sidebar fields.
// Unifies mouse + touch + pen.  Hands hit-testing to DropResolver, visuals to
// DragVisuals, and the final mutation to DropMutations.
//
// Architecture — rAF-batched tick loop
// ------------------------------------
// pointermove ONLY stores the latest pointer position and requests a frame;
// it never reads or writes layout.  The single _tick() rAF callback does, in
// strict order:
//   (a) rebuild snapshot if dirty (batched read pass)
//   (b) resolve slot against snapshot  (pure, zero layout reads)
//   (c) WRITE ghost transform + WRITE indicator
//   (d) reschedule itself while dragging
//
// Geometry snapshot is built ONCE at drag-start via DropResolver.buildSnapshot
// and is marked dirty (and lazily rebuilt on the next tick) whenever:
//   • the canvas area or window scrolls
//   • the window is resized
//   • auto-scroll fires
export class DragEngine extends BaseManager {
  // Bound on a draggable element's `pointerdown` (data-action).
  pointerDown(event) {
    if (event.button != null && event.button > 0) return // ignore right/middle
    const source  = event.currentTarget
    const payload = this._buildPayload(source)
    if (!payload) return

    this._source    = source
    this._pointerId = event.pointerId
    this._start     = { x: event.clientX, y: event.clientY }
    this._payload   = payload
    this._armed     = true
    this._dragging  = false
    this._pointer   = { x: event.clientX, y: event.clientY }
    this._lastTarget = null
    this._lastDropPoint = null

    // Capture the grab offset (where within the card the user clicked) AND the
    // card's size. The drop is resolved from the GHOST'S CENTRE (cursor − grab +
    // half-size), not the raw cursor — so a field lands where the visible card
    // is, independent of where it was grabbed.
    if (payload.kind === "move") {
      const r = source.getBoundingClientRect()
      this._grab = { x: event.clientX - r.left, y: event.clientY - r.top }
      this._ghostSize = { w: r.width, h: r.height }
    } else {
      // New field from sidebar — small chip near the cursor; resolve at cursor.
      this._grab = { x: 16, y: 16 }
      this._ghostSize = null
    }

    // rAF state
    this._rafId         = null
    this._snapshot      = null
    this._snapshotDirty = false

    this._onMove   = this._move.bind(this)
    this._onUp     = this._up.bind(this)
    this._onScroll = this._markSnapshotDirty.bind(this)
    this._onResize = this._markSnapshotDirty.bind(this)
    window.addEventListener("pointermove",  this._onMove, { passive: false })
    window.addEventListener("pointerup",    this._onUp)
    window.addEventListener("pointercancel", this._onUp)
    window.addEventListener("resize",       this._onResize, { passive: true })

    if (event.pointerType === "touch") {
      this._longPress = setTimeout(() => {
        if (this._armed) this._beginDrag()
      }, LONG_PRESS_MS)
    }
  }

  _buildPayload(source) {
    const kind = source.dataset.dragKind
    if (kind === "new") {
      const data = this.c.dragDropManager._sidebarData(source)
      return data && data.type ? { kind: "new", data } : null
    }
    if (kind === "move") {
      const fieldId = source.dataset.fieldId
      if (!fieldId) return null
      const sel      = this.c.selectionManager.getSelectedFieldIds()
      const fieldIds = (sel.length > 1 && sel.includes(fieldId)) ? sel.slice() : [fieldId]
      const isSection = !!this.c.fieldManager._sectionIdForDrag(fieldId)
      return { kind: "move", fieldIds, primaryId: fieldId, isSection }
    }
    return null
  }

  // pointermove — ONLY stores pointer + requests frame.  No reads, no writes.
  _move(event) {
    if (!this._armed) return

    if (!this._dragging) {
      const dx = event.clientX - this._start.x
      const dy = event.clientY - this._start.y
      if (Math.hypot(dx, dy) < MOVE_THRESHOLD) return
      this._beginDrag()
    }

    event.preventDefault()
    this._pointer = { x: event.clientX, y: event.clientY }
    this._requestTick()
  }

  _beginDrag() {
    if (this._dragging) return
    clearTimeout(this._longPress)
    this._dragging = true
    try { this._source.setPointerCapture(this._pointerId) } catch (_e) { /* noop */ }
    this._source.style.touchAction = "none"

    // A drag is not an "edit this field" intent — close the property popup so
    // it isn't shown while dragging or after the drop.
    this.c.propertyManager.hideFloatingPanel()

    // Build the initial geometry snapshot (one batched read pass).
    this._rebuildSnapshot()

    // Attach canvas-area scroll listener for snapshot invalidation.
    if (this.c.hasCanvasAreaTarget) {
      this.c.canvasAreaTarget.addEventListener("scroll", this._onScroll, { passive: true })
    }

    const ghostNode = this._payload.kind === "move"
      ? this.c.fieldsContainerTarget.querySelector(`[data-field-id="${this._payload.primaryId}"]`)
      : null
    this.c.dragVisuals.showGhost(ghostNode, this._payload.data?.label, this._grab)
    if (this._payload.kind === "move") this.c.dragVisuals.markSource(this._payload.fieldIds)

    // Kick off the rAF loop.
    this._requestTick()
  }

  // -------------------------------------------------------------------------
  // rAF tick — the ONLY place reads and writes to layout happen during a drag.
  // -------------------------------------------------------------------------
  _tick() {
    this._rafId = null
    if (!this._dragging) return

    const p = this._pointer

    // (a) Auto-scroll first: reads the canvas rect, then writes scrollTop.
    const scrolled = this._autoScroll(p.y)

    // (b) Rebuild the snapshot when stale — AFTER the auto-scroll write, so the
    //     rects reflect the new scroll position. Resolving against pre-scroll
    //     viewport-relative rects would misplace the indicator by the scroll
    //     delta on every edge-scroll frame.
    if (scrolled || this._snapshotDirty || !this._snapshot) {
      this._rebuildSnapshot()
    }

    // (c) Resolve slot from the GHOST'S CENTRE (move) or the cursor (new) —
    //     pure, zero layout reads. Centring decouples the drop from the grab
    //     point so the indicator lands under the visible card.
    const rp = this._ghostSize
      ? { x: p.x - this._grab.x + this._ghostSize.w / 2,
          y: p.y - this._grab.y + this._ghostSize.h / 2 }
      : p
    this._lastTarget = this.c.dropResolver.resolve(rp, this._payload, this._snapshot)

    // (d) WRITE: ghost + indicator + container highlight.
    this.c.dragVisuals.moveGhost(p.x, p.y, this._grab)
    this.c.dragVisuals.showIndicator(this._lastTarget)
    this.c.dragVisuals.highlightContainer(this._lastTarget?.containerKey || null)

    // (e) Reschedule: keep running every frame so auto-scroll continues even
    //     when the pointer is held still at the edge.
    this._requestTick()
  }

  _requestTick() {
    if (!this._dragging || this._rafId !== null) return
    this._rafId = requestAnimationFrame(() => this._tick())
  }

  // -------------------------------------------------------------------------
  // Snapshot lifecycle
  // -------------------------------------------------------------------------
  _rebuildSnapshot() {
    this._snapshot      = this.c.dropResolver.buildSnapshot(this._payload)
    this._snapshotDirty = false
  }

  _markSnapshotDirty() {
    this._snapshotDirty = true
    // Ensure the rAF loop is running so the dirty flag is consumed promptly.
    if (this._dragging) this._requestTick()
  }

  // -------------------------------------------------------------------------
  // Auto-scroll — called inside _tick; returns true if it scrolled.
  // -------------------------------------------------------------------------
  _autoScroll(clientY) {
    if (!this.c.hasCanvasAreaTarget) return false
    const el   = this.c.canvasAreaTarget
    const rect = el.getBoundingClientRect()
    const top    = clientY - rect.top
    const bottom = rect.bottom - clientY
    if (top >= 0 && top < AUTO_SCROLL_EDGE) {
      const delta = Math.round(AUTO_SCROLL_MAX * (1 - top / AUTO_SCROLL_EDGE))
      if (delta > 0) { el.scrollTop -= delta; return true }
    } else if (bottom >= 0 && bottom < AUTO_SCROLL_EDGE) {
      const delta = Math.round(AUTO_SCROLL_MAX * (1 - bottom / AUTO_SCROLL_EDGE))
      if (delta > 0) { el.scrollTop += delta; return true }
    }
    return false
  }

  // -------------------------------------------------------------------------
  // Pointer up / cancel
  // -------------------------------------------------------------------------
  _up(event) {
    clearTimeout(this._longPress)
    window.removeEventListener("pointermove",   this._onMove)
    window.removeEventListener("pointerup",     this._onUp)
    window.removeEventListener("pointercancel", this._onUp)
    window.removeEventListener("resize",        this._onResize)

    const dragging  = this._dragging
    const target    = this._lastTarget
    const payload   = this._payload
    const cancelled = event.type === "pointercancel"

    // Capture final pointer position so FLIP can animate the drop landing.
    if (dragging && this._pointer) {
      this._lastDropPoint = { x: this._pointer.x, y: this._pointer.y }
    }

    this._reset()

    if (dragging && target && !cancelled) {
      this.c.dropMutations.apply(payload, target)
    }
  }

  _reset() {
    // Cancel any pending rAF.
    if (this._rafId !== null) {
      cancelAnimationFrame(this._rafId)
      this._rafId = null
    }

    // Remove canvas-area scroll listener.
    if (this.c.hasCanvasAreaTarget) {
      this.c.canvasAreaTarget.removeEventListener("scroll", this._onScroll)
    }

    if (this._source) this._source.style.touchAction = ""
    this.c.dragVisuals.hideGhost()
    this.c.dragVisuals.hideIndicator()
    this.c.dragVisuals.clearSource()

    this._armed         = false
    this._dragging      = false
    this._source        = null
    this._payload       = null
    this._lastTarget    = null
    this._snapshot      = null
    this._snapshotDirty = false
    this._pointer       = null
    this._grab          = null
    this._ghostSize     = null
    this._onScroll      = null
    this._onResize      = null
    this._onMove        = null
    this._onUp          = null
    // Note: _lastDropPoint is intentionally NOT cleared here — DropMutations
    // reads it synchronously during _afterChange, which happens after _reset.
    // DropMutations is responsible for clearing it after use.
  }
}
