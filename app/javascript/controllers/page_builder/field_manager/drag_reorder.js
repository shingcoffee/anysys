/**
 * DragReorderMixin provides section-level drag/reorder helpers.
 * Apply to a class using Object.assign(YourClass.prototype, DragReorderMixin)
 */
export const DragReorderMixin = {
  // If this drag represents a whole-section move, return the section header id;
  // otherwise null. Triggers when the grabbed card is a section header, or when
  // the active multi-selection contains one.
  _sectionIdForDrag(reorderingId) {
    const fields = this.c.currentPage.fields
    const dragged = fields.find(f => f.id === reorderingId)
    if (dragged && this._isSectionField(dragged)) return reorderingId
    if (Array.isArray(this.c.reorderingFieldIds)) {
      const headerId = this.c.reorderingFieldIds.find(id => {
        const f = fields.find(x => x.id === id)
        return f && this._isSectionField(f)
      })
      if (headerId) return headerId
    }
    return null
  },

  // Move the section block headed by `sectionId` (header + every field up to the
  // next section header) to sit before/after the target's section. Works on a
  // divider-free copy of the list; normalizeSectionDividers() re-adds the lines
  // on the next render. Returns the moved field ids (for re-selection).
  _reorderSection(sectionId, targetId) {
    const list = this.c.currentPage.fields.filter(f => !this._isAutoSectionDivider(f))
    const headerIdxs = []
    list.forEach((f, i) => { if (this._isSectionField(f)) headerIdxs.push(i) })

    const dStart = list.findIndex(f => f.id === sectionId)
    if (dStart < 0) { this.c.currentPage.fields = list; return null }
    const dNextHeader = headerIdxs.find(i => i > dStart)
    const dEnd = dNextHeader === undefined ? list.length : dNextHeader // exclusive
    const draggedBlock = list.slice(dStart, dEnd)
    const draggedIds = new Set(draggedBlock.map(f => f.id))
    const movedIds = draggedBlock.map(f => f.id)

    // Dropping back onto the section's own block is a no-op.
    if (draggedIds.has(targetId)) { this.c.currentPage.fields = list; return movedIds }

    const tAnyIdx = list.findIndex(f => f.id === targetId)
    if (tAnyIdx < 0) { this.c.currentPage.fields = list; return movedIds }

    // Resolve the target section (nearest header at/above the target field).
    let tStart = -1
    for (let i = tAnyIdx; i >= 0; i--) { if (this._isSectionField(list[i])) { tStart = i; break } }

    let beforeId = null
    let afterId = null
    if (tStart === -1) {
      // Target sits in leading content before any section → drop above the page.
      beforeId = list[0]?.id ?? null
    } else {
      const tNextHeader = headerIdxs.find(i => i > tStart)
      const tEnd = tNextHeader === undefined ? list.length : tNextHeader // exclusive
      if (dStart < tStart) {
        afterId = list[tEnd - 1].id    // dragging down → place after target section
      } else {
        beforeId = list[tStart].id     // dragging up → place before target section
      }
    }

    const remaining = list.filter(f => !draggedIds.has(f.id))
    let insertIdx = remaining.length
    if (beforeId != null) {
      const i = remaining.findIndex(f => f.id === beforeId)
      if (i !== -1) insertIdx = i
    } else if (afterId != null) {
      const i = remaining.findIndex(f => f.id === afterId)
      if (i !== -1) insertIdx = i + 1
    }

    remaining.splice(insertIdx, 0, ...draggedBlock)
    remaining.forEach((f, i) => { f.order = i })
    this.c.currentPage.fields = remaining
    return movedIds
  }
}
