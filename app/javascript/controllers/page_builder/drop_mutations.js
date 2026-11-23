import { BaseManager } from "controllers/page_builder/base_manager"
import { moveFields, reorderSectionBlock } from "controllers/page_builder/dnd/field_mutations"

// The single place that applies a resolved drop to the data model. Consolidates
// the four old drop paths. Wraps the pure mutation core + existing helpers, then
// renders, re-selects, animates, and marks dirty.
export class DropMutations extends BaseManager {
  apply(payload, target) {
    if (!target) return
    this.c.undoRedoManager.saveState()

    if (payload.kind === "new") return this._insertNew(payload, target)
    if (target.mode === "swap") return this._swap(payload, target)
    if (payload.isSection) return this._moveSection(payload, target)
    if (target.containerKey.startsWith("column:")) return this._moveIntoColumn(payload, target)
    if (target.containerKey.startsWith("group:")) return this._moveIntoGroup(payload, target)
    return this._moveTopLevel(payload, target)
  }

  _insertNew(payload, target) {
    const field = this.c.fieldManager.createField(payload.data)
    if (target.containerKey.startsWith("column:")) {
      const col = this._column(target.containerKey)
      if (col) col.fields.push(field)
    } else if (target.containerKey.startsWith("group:")) {
      const group = this._group(target.containerKey)
      if (group) group.fields.push(field)
    } else {
      const idx = Math.min(target.index, this.c.currentPage.fields.length)
      this.c.currentPage.fields.splice(idx, 0, field)
    }
    this._afterChange(null, field.id)
  }

  // Swap the dragged field with the drop-zone target field (both top-level).
  _swap(payload, target) {
    const list = this.c.currentPage.fields
    const a = list.findIndex(f => f.id === payload.primaryId)
    const b = list.findIndex(f => f.id === target.swapFieldId)
    if (a < 0 || b < 0 || a === b) { this._afterChange(payload.fieldIds, payload.primaryId); return }
    const tmp = list[a]; list[a] = list[b]; list[b] = tmp
    this._afterChange(payload.fieldIds, payload.primaryId)
  }

  _moveTopLevel(payload, target) {
    this.c.currentPage.fields = moveFields(this.c.currentPage.fields, payload.fieldIds, target.index)
    this._afterChange(payload.fieldIds, payload.primaryId)
  }

  _moveSection(payload, target) {
    const targetId = target.targetFieldId || this._fieldIdAtIndex(target.index)
    if (!targetId) { this._afterChange(payload.fieldIds, payload.primaryId); return }
    const { list } = reorderSectionBlock(this.c.currentPage.fields, payload.primaryId, targetId)
    this.c.currentPage.fields = list
    this._afterChange(payload.fieldIds, payload.primaryId)
  }

  _moveIntoColumn(payload, target) {
    const col = this._column(target.containerKey)
    if (!col) { this._afterChange(payload.fieldIds, payload.primaryId); return }
    this._relocateInto(payload.fieldIds, col.fields)
    this._afterChange(payload.fieldIds, payload.primaryId)
  }

  _moveIntoGroup(payload, target) {
    const group = this._group(target.containerKey)
    if (!group) { this._afterChange(payload.fieldIds, payload.primaryId); return }
    this._relocateInto(payload.fieldIds, group.fields)
    this._afterChange(payload.fieldIds, payload.primaryId)
  }

  // Move existing fields out of wherever they are and into `destFields`.
  _relocateInto(fieldIds, destFields) {
    fieldIds.forEach(id => {
      const field = this.c.fieldManager.findFieldById(id)
      if (!field || field.field_type === "columns" || field.type === "field_group") return
      this.c.fieldManager.removeFieldFromAnyColumn(id)
      const top = this.c.currentPage.fields.findIndex(f => f.id === id)
      if (top !== -1) this.c.currentPage.fields.splice(top, 1)
      if (!destFields.includes(field)) destFields.push(field)
    })
  }

  _afterChange(idsToSelect, primaryId) {
    this.c.fields = this.c.currentPageFields
    this.c.currentPage.fields.forEach((f, i) => { f.order = i })

    // Snapshot card positions BEFORE the DOM re-render so FLIP can compute
    // the delta from old→new layout.
    const prevRects   = this.c.dragDropManager.captureCardRects()
    const dropPoint   = this.c.dragEngine._lastDropPoint
    // Clear the stored drop point now that we've read it.
    this.c.dragEngine._lastDropPoint = null

    this.c.fieldManager.renderFields()

    // Highlight the dropped field(s) but do NOT pop the property panel — a
    // drag-and-drop is not an "edit this field" intent the way a click is.
    if (idsToSelect && idsToSelect.length > 1) {
      this.c.selectionManager.selectFields(idsToSelect, { showPanel: false })
    } else if (primaryId) {
      this.c.fieldManager.selectFieldById(primaryId, { showPanel: false })
    }

    // FLIP settle: glide cards from their old positions to the new layout.
    this.c.dragDropManager.flipFromRects(prevRects, { droppedId: primaryId, dropPoint })

    this.c.saveManager.markDirty()
    if (this.c.tabManager && this.c.tabManager.closeAllTabPanels) this.c.tabManager.closeAllTabPanels()
  }

  _column(containerKey) {
    const [, parentId, colIdx] = containerKey.split(":")
    const parent = this.c.fields.find(f => f.id === parentId)
    return parent && parent.columns ? parent.columns[Number(colIdx)] : null
  }

  _group(containerKey) {
    const [, groupId] = containerKey.split(":")
    const group = this.c.fields.find(f => f.id === groupId && f.type === "field_group")
    if (group && !Array.isArray(group.fields)) group.fields = []
    return group || null
  }

  _fieldIdAtIndex(index) {
    const fields = this.c.currentPage.fields
    if (fields.length === 0) return null
    return fields[Math.min(index, fields.length - 1)]?.id ?? null
  }
}
