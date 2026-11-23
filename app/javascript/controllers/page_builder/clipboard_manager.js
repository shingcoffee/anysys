import { BaseManager } from "controllers/page_builder/base_manager"

export class ClipboardManager extends BaseManager {
  constructor(controller) {
    super(controller)
    this.clipboard = []
  }

  copy() {
    const selected = this.c.selectionManager.getSelectedFields()
    if (selected.length === 0) return
    this.clipboard = selected.map(f => JSON.parse(JSON.stringify(f)))
  }

  cut() {
    this.copy()
    if (this.clipboard.length === 0) return
    this.c.saveState()
    const ids = new Set(this.clipboard.map(f => f.id))
    this.c.currentPage.fields = this.c.currentPage.fields.filter(f => !ids.has(f.id))
    this.c.selectionManager.deselectAll()
    this.c.fieldManager.renderFields()
    this.c.saveManager.markDirty()
  }

  paste() {
    if (this.clipboard.length === 0) return
    this.c.saveState()
    const newFields = this.clipboard.map((f, i) => {
      const clone = JSON.parse(JSON.stringify(f))
      clone.id = this._newFieldId(i)
      clone.property_slug = this._uniqueSlug(clone.property_slug)
      return clone
    })

    const selectedIds = this.c.selectionManager.getSelectedFieldIds()
    let insertIdx = this.c.currentPageFields.length
    if (selectedIds.length > 0) {
      const lastSelectedId = selectedIds[selectedIds.length - 1]
      const lastIdx = this.c.currentPageFields.findIndex(f => f.id === lastSelectedId)
      if (lastIdx >= 0) insertIdx = lastIdx + 1
    }

    this.c.currentPage.fields.splice(insertIdx, 0, ...newFields)
    this.c.fieldManager.renderFields()
    this.c.saveManager.markDirty()

    this.c.selectionManager.deselectAll()
    newFields.forEach(f => this.c.selectionManager.addToSelection(f.id))
    this.c.selectionManager.updateVisuals()
  }

  duplicateSelected() {
    const selected = this.c.selectionManager.getSelectedFields()
    if (selected.length === 0) return
    this.c.saveState()

    selected.forEach((field, i) => {
      const clone = JSON.parse(JSON.stringify(field))
      clone.id = this._newFieldId(i)
      clone.property_slug = this._uniqueSlug(field.property_slug)
      const idx = this.c.currentPageFields.findIndex(f => f.id === field.id)
      this.c.currentPage.fields.splice(idx + 1, 0, clone)
    })

    this.c.fieldManager.renderFields()
    this.c.saveManager.markDirty()
  }

  // Unique even when many clones are created inside one synchronous loop:
  // Date.now() is identical across the loop, so the index + random suffix is
  // what guarantees no two pasted/duplicated fields share an id.
  _newFieldId(seq = 0) {
    return `field_${Date.now()}_${seq}_${Math.random().toString(36).slice(2, 9)}`
  }

  _uniqueSlug(baseSlug) {
    // Layout elements (section, divider, …) and field groups have no slug;
    // calling .replace on undefined would throw and abort the whole duplicate/
    // paste operation, so pass through unchanged.
    if (!baseSlug) return baseSlug
    const cleanSlug = baseSlug.replace(/_copy(_\d+)?$/, "")
    const allSlugs = new Set(this.c.allFields.map(f => f.property_slug))
    let slug = `${cleanSlug}_copy`
    let counter = 2
    while (allSlugs.has(slug)) {
      slug = `${cleanSlug}_copy_${counter}`
      counter++
    }
    return slug
  }
}
