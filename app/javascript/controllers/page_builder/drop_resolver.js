import { BaseManager } from "controllers/page_builder/base_manager"
import { resolveSlot, pickRegion } from "controllers/page_builder/dnd/drop_geometry"

// Reads the rendered canvas into geometric "regions" at drag-start time
// (buildSnapshot) and delegates slot decisions to the pure helpers
// resolveSlot / pickRegion.  No live DOM reads during resolve() — all geometry
// comes from the cached snapshot built by DragEngine._beginDrag (and
// re-built on scroll/resize via DragEngine._rebuildSnapshot).
export class DropResolver extends BaseManager {
  // -------------------------------------------------------------------------
  // Snapshot builder — called once at drag start + on scroll/resize dirty.
  // payload: { kind, data, fieldIds, primaryId, isSection }
  // Returns a snapshot: { topLevel, nested } where nested is Array<NestedEntry>.
  // -------------------------------------------------------------------------
  buildSnapshot(payload) {
    if (!this.c.hasFieldsContainerTarget) return null
    if (payload.kind === "new" && !this._newFieldAllowed(payload.data)) return null

    const topLevel = this._topLevelRegion(payload)
    const nested   = this._mayNest(payload) ? this._allNestedEntries(payload) : []
    return { topLevel, nested }
  }

  // -------------------------------------------------------------------------
  // resolve — pure path: works entirely off the cached snapshot.
  // Called from DragEngine._tick; must not touch the DOM.
  // -------------------------------------------------------------------------
  resolve(pointer, payload, snapshot) {
    if (!snapshot) return null
    const region = pickRegion(snapshot, pointer)

    // DROP-ZONE / SWAP: a single top-level field dragged onto another field's
    // body becomes a swap. This is both the intuitive "drop X onto Y" gesture
    // and the only thing that does something when the two are already adjacent
    // (an insert there would be a no-op and appear to "snap back").
    const swap = this._swapTarget(region, pointer, payload)
    if (swap) return swap

    const slot = resolveSlot(region, pointer)
    if (!slot) return null
    slot.mode = "insert"

    if (slot.containerKey === "page") {
      slot.targetFieldId = this.c.currentPage.fields[slot.index]?.id ?? null
    }
    return slot
  }

  // Returns a swap target when the pointer is over the central body of a
  // top-level field card (not the one being dragged). null otherwise.
  _swapTarget(region, pointer, payload) {
    if (region.containerKey !== "page") return null
    if (payload.kind !== "move" || payload.isSection) return null
    if (!payload.fieldIds || payload.fieldIds.length !== 1) return null
    // The dragged field must itself be a top-level field for a clean swap.
    if (!this.c.currentPage.fields.some(f => f.id === payload.primaryId)) return null

    const moving = new Set(payload.fieldIds)
    for (const row of region.rows) {
      for (const cell of row.cells) {
        if (!cell.id || moving.has(cell.id)) continue
        const padX = (cell.right - cell.left) * 0.12   // outer 12% each side = insert
        if (pointer.x >= cell.left + padX && pointer.x <= cell.right - padX &&
            pointer.y >= cell.top && pointer.y <= cell.bottom) {
          return {
            mode: "swap",
            containerKey: "page",
            swapFieldId: cell.id,
            rect: { left: cell.left, top: cell.top, width: cell.right - cell.left, height: cell.bottom - cell.top }
          }
        }
      }
    }
    return null
  }

  // -------------------------------------------------------------------------
  // Internal helpers — all read live DOM, only called during buildSnapshot.
  // -------------------------------------------------------------------------

  // The page's flat field list (sections are flat markers in data even though
  // their member cards are DOM-nested), excluding the cards being moved.
  _topLevelRegion(payload) {
    const moving = new Set(payload.kind === "move" ? payload.fieldIds : [])
    const fields = this.c.currentPage.fields
    const cells  = []
    fields.forEach((f, index) => {
      if (moving.has(f.id)) return
      const card = this.c.fieldsContainerTarget.querySelector(`[data-field-id="${f.id}"]`)
      if (!card) return
      const rect = card.getBoundingClientRect()
      cells.push({ left: rect.left, right: rect.right, top: rect.top, bottom: rect.bottom, index, id: f.id })
    })
    return { containerKey: "page", rows: this._cellsToRows(cells) }
  }

  // Collect every nestable container present in the DOM at snapshot time.
  // Each entry: { rect, mayNest, region }
  _allNestedEntries(payload) {
    const entries = []

    // Group-field containers
    this.c.fieldsContainerTarget
      .querySelectorAll("[data-group-fields-container]")
      .forEach(el => {
        entries.push(this._buildEntry(el, `group:${el.dataset.groupFieldsContainer}`, payload))
      })

    // Column containers
    this.c.fieldsContainerTarget
      .querySelectorAll("[data-column-index]")
      .forEach(el => {
        entries.push(this._buildEntry(el, `column:${el.dataset.parentFieldId}:${el.dataset.columnIndex}`, payload))
      })

    return entries
  }

  // Only reached when _mayNest(payload) is true (gated by buildSnapshot), so
  // every container entry is nestable — mayNest is always true here. The pure
  // pickRegion still honours mayNest generically.
  _buildEntry(containerEl, containerKey, payload) {
    const domRect = containerEl.getBoundingClientRect()
    const rect    = { left: domRect.left, right: domRect.right, top: domRect.top, bottom: domRect.bottom }
    const region  = this._containerRegion(containerEl, containerKey, payload)
    return { rect, mayNest: true, region }
  }

  // Excludes the cards being moved (mirrors _topLevelRegion); `index` stays the
  // absolute child index so reordering a card already inside this container
  // yields a correct insertion index.
  _containerRegion(containerEl, containerKey, payload) {
    const moving = new Set(payload.kind === "move" ? payload.fieldIds : [])
    const cells  = []
    Array.from(containerEl.children).filter(c => c.classList.contains("field-card")).forEach((card, index) => {
      if (moving.has(card.dataset.fieldId)) return
      const rect = card.getBoundingClientRect()
      cells.push({ left: rect.left, right: rect.right, top: rect.top, bottom: rect.bottom, index, id: card.dataset.fieldId })
    })
    return { containerKey, rows: this._cellsToRows(cells) }
  }

  // Group cells into rows by overlapping vertical bands; sort each row by x.
  _cellsToRows(cells) {
    const rows = []
    let current = null
    cells.forEach(cell => {
      if (current && cell.top < current.bottom - 4) {
        current.cells.push(cell)
        current.bottom = Math.max(current.bottom, cell.bottom)
        current.top    = Math.min(current.top, cell.top)
      } else {
        current = { top: cell.top, bottom: cell.bottom, cells: [cell] }
        rows.push(current)
      }
    })
    rows.forEach(r => r.cells.sort((a, b) => a.left - b.left))
    return rows
  }

  _mayNest(payload) {
    if (payload.isSection) return false
    const type = payload.kind === "new"
      ? payload.data?.type
      : this._typeOf(payload.primaryId)
    return type !== "columns" && type !== "field_group"
  }

  _typeOf(id) {
    const f = this.c.fieldManager.findFieldById(id)
    return f ? (f.type || f.field_type) : null
  }

  _newFieldAllowed(data) {
    if (!data) return false
    if (data.type === "entity" && !data.htmlType) return false
    if (data.propertySlug && this.c.fieldManager.getUsedPropertySlugs().has(data.propertySlug)) return false
    return true
  }
}
