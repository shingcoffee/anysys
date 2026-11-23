import { BaseManager } from "controllers/page_builder/base_manager"

export class SelectionManager extends BaseManager {
  initialize() {
    this.selectedFieldIds = new Set()
    this.lastSelectedFieldId = null
    this.selectionAnchorId = null
    this._rubberBandActive = false
    this._rubberBandStart = null
  }

  // ---------------------------------------------------------------------------
  // Core Selection
  // ---------------------------------------------------------------------------

  selectField(fieldId, { shift = false, meta = false, showPanel = true } = {}) {
    if (shift && this.selectionAnchorId) {
      this._rangeSelect(fieldId)
    } else if (meta) {
      this._toggleSelect(fieldId)
    } else {
      this._singleSelect(fieldId)
    }

    this.lastSelectedFieldId = fieldId
    this.updateVisuals()
    this.syncScalarState()
    this._updatePanel(showPanel)
  }

  selectAll() {
    const fields = this._currentPageAllFields()
    this.selectedFieldIds.clear()
    fields.forEach(f => this.selectedFieldIds.add(f.id))
    if (fields.length > 0) {
      this.lastSelectedFieldId = fields[fields.length - 1].id
      this.selectionAnchorId = fields[0].id
    }
    this.updateVisuals()
    this.syncScalarState()
    this._updatePanel()
  }

  // Select an explicit set of field ids as one selection (e.g. a whole section).
  selectFields(fieldIds, { showPanel = true } = {}) {
    const ids = (fieldIds || []).filter(Boolean)
    this.selectedFieldIds.clear()
    ids.forEach(id => this.selectedFieldIds.add(id))
    if (ids.length > 0) {
      this.selectionAnchorId = ids[0]
      this.lastSelectedFieldId = ids[ids.length - 1]
    }
    this.updateVisuals()
    this.syncScalarState()
    this._updatePanel(showPanel)
  }

  deselectAll() {
    this.selectedFieldIds.clear()
    this.lastSelectedFieldId = null
    this.selectionAnchorId = null
    this.updateVisuals()
    this.syncScalarState()
    this.c.propertyManager.hideFloatingPanel()
  }

  isSelected(fieldId) {
    return this.selectedFieldIds.has(fieldId)
  }

  get count() {
    return this.selectedFieldIds.size
  }

  get isEmpty() {
    return this.count === 0
  }

  get isSingleSelect() {
    return this.count === 1
  }

  get isMultiSelect() {
    return this.count > 1
  }

  getSelectedFields() {
    const all = this._currentPageAllFields()
    return all.filter(f => this.selectedFieldIds.has(f.id))
  }

  getSelectedFieldIds() {
    return [...this.selectedFieldIds]
  }

  addToSelection(fieldId) {
    this.selectedFieldIds.add(fieldId)
  }

  // ---------------------------------------------------------------------------
  // Visual Updates
  // ---------------------------------------------------------------------------

  updateVisuals() {
    if (!this.c.hasFieldsContainerTarget) return

    this.c.fieldsContainerTarget.querySelectorAll(".field-card").forEach(card => {
      const fieldId = card.dataset.fieldId
      const selected = this.isSelected(fieldId)
      const isMulti = this.isMultiSelect

      card.classList.toggle("selected", selected)
      card.classList.toggle("ring-2", selected)
      card.classList.toggle("ring-offset-1", selected)

      // Single-selected: indigo ring. Multi-selected: blue ring + tint
      card.classList.toggle("ring-indigo-500", selected && !isMulti)
      card.classList.toggle("ring-blue-400", selected && isMulti)
      card.classList.toggle("bg-blue-50/20", selected && isMulti)

      // Multi-select checkbox overlay
      const existing = card.querySelector(".multi-select-check")
      if (isMulti && selected) {
        if (!existing) {
          const check = document.createElement("div")
          check.className = "multi-select-check absolute -top-1 -left-1 w-5 h-5 bg-indigo-500 rounded-full flex items-center justify-center z-10"
          check.innerHTML = '<svg class="w-3 h-3 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M5 13l4 4L19 7"/></svg>'
          card.style.position = "relative"
          card.appendChild(check)
        }
      } else if (existing) {
        existing.remove()
      }
    })
  }

  syncScalarState() {
    if (this.isSingleSelect) {
      const fieldId = [...this.selectedFieldIds][0]
      this.c.selectedFieldId = fieldId
      this.c.selectedFieldValue = fieldId
    } else {
      this.c.selectedFieldId = null
      this.c.selectedFieldValue = null
    }
  }

  // ---------------------------------------------------------------------------
  // Rubber Band Selection
  // ---------------------------------------------------------------------------

  startRubberBand(event) {
    // Only start on canvas background, not on field cards or UI elements
    if (event.target.closest(".field-card") ||
        event.target.closest(".inserter-row") ||
        event.target.closest("button") ||
        event.target.closest("[data-page-builder-target]") && !event.target.closest("[data-page-builder-target='dropZone']") && !event.target.closest("[data-page-builder-target='canvasArea']")) {
      return
    }

    if (event.button !== 0) return // left-click only

    this._rubberBandActive = true
    this._rubberBandStart = { x: event.clientX, y: event.clientY }

    // Create overlay element
    if (!this._rubberBandEl) {
      this._rubberBandEl = document.createElement("div")
      this._rubberBandEl.className = "fixed pointer-events-none z-50 border-2 border-blue-400 bg-blue-100/30 rounded-sm"
      this._rubberBandEl.style.display = "none"
      document.body.appendChild(this._rubberBandEl)
    }
  }

  updateRubberBand(event) {
    if (!this._rubberBandActive || !this._rubberBandStart) return

    const start = this._rubberBandStart
    const x = Math.min(start.x, event.clientX)
    const y = Math.min(start.y, event.clientY)
    const w = Math.abs(event.clientX - start.x)
    const h = Math.abs(event.clientY - start.y)

    // Only show after a minimum drag distance to avoid accidental selection
    if (w < 5 && h < 5) return

    const el = this._rubberBandEl
    el.style.display = "block"
    el.style.left = `${x}px`
    el.style.top = `${y}px`
    el.style.width = `${w}px`
    el.style.height = `${h}px`

    // Highlight intersecting cards
    this._highlightIntersecting({ x, y, w, h })
  }

  endRubberBand(_event) {
    if (!this._rubberBandActive) return
    this._rubberBandActive = false

    if (this._rubberBandEl) {
      const rect = this._rubberBandEl.getBoundingClientRect()
      const hadVisibleBand = this._rubberBandEl.style.display === "block" && rect.width > 5

      this._rubberBandEl.style.display = "none"

      if (hadVisibleBand) {
        this._selectIntersecting({
          x: rect.left,
          y: rect.top,
          w: rect.width,
          h: rect.height
        })
      }
    }

    this._rubberBandStart = null
  }

  cleanupRubberBand() {
    if (this._rubberBandEl) {
      this._rubberBandEl.remove()
      this._rubberBandEl = null
    }
  }

  // ---------------------------------------------------------------------------
  // Move-to-Page Modal
  // ---------------------------------------------------------------------------

  openMoveToPageModal() {
    if (this.isEmpty) return

    const pages = this.c.configuration.pages || []
    const currentPageId = this.c.activePageValue
    const count = this.count

    // Auto-generate a suggested new page name
    const nextPageNumber = pages.length + 1
    const suggestedName = `Page ${nextPageNumber}`

    const pageOptions = pages.map(p => {
      const isCurrent = p.id === currentPageId
      return `
        <label class="flex items-center gap-3 px-3 py-2 rounded-lg ${isCurrent ? "opacity-50 cursor-not-allowed" : "hover:bg-gray-50 cursor-pointer"}">
          <input type="radio" name="move_target_page" value="${p.id}"
                 ${isCurrent ? "disabled" : ""}
                 class="w-4 h-4 text-indigo-600 border-gray-300 focus:ring-indigo-500">
          <span class="text-sm text-gray-700">${this.escapeHtml(p.name)}</span>
          ${isCurrent ? `<span class="text-xs text-gray-400">${this.escapeHtml(this.c.currentPageTagValue)}</span>` : ""}
        </label>
      `
    }).join("")

    const moveFieldsPrompt = (count !== 1 ? this.c.moveFieldsPromptPluralValue : this.c.moveFieldsPromptSingularValue)
      .replace("{count}", count)

    const modalHtml = `
      <div class="fixed inset-0 bg-black/50 z-50 flex items-center justify-center" data-action="click->page-builder#closeMoveToPageModalOnBackdrop">
        <div class="bg-white rounded-xl shadow-2xl w-full max-w-md p-6" data-move-modal-content>
          <h3 class="text-lg font-semibold text-gray-900 mb-1">${this.escapeHtml(this.c.moveToPageModalTitleValue)}</h3>
          <p class="text-sm text-gray-500 mb-4">${this.escapeHtml(moveFieldsPrompt)}</p>

          <div class="space-y-1 mb-4 max-h-48 overflow-y-auto">
            ${pageOptions}
          </div>

          <div class="border-t border-gray-200 pt-4 mb-4">
            <label class="block text-sm font-medium text-gray-700 mb-1">${this.escapeHtml(this.c.orCreateNewPageLabelValue)}</label>
            <input type="text" placeholder="${this.escapeHtml(this.c.newPageNamePlaceholderValue)}"
                   value="${this.escapeHtml(suggestedName)}"
                   data-move-new-page-name
                   class="w-full px-3 py-2 text-sm border border-gray-300 rounded-lg focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500">
          </div>

          <div class="flex justify-end gap-2">
            <button type="button"
                    data-action="click->page-builder#closeMoveToPageModal"
                    class="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50">
              ${this.escapeHtml(this.c.cancelLabelValue)}
            </button>
            <button type="button"
                    data-action="click->page-builder#confirmMoveToPage"
                    class="px-4 py-2 text-sm font-medium text-white bg-indigo-600 rounded-lg hover:bg-indigo-700">
              ${this.escapeHtml(this.c.moveFieldsButtonLabelValue)}
            </button>
          </div>
        </div>
      </div>
    `

    if (this.c.hasMoveToPageModalTarget) {
      this.c.moveToPageModalTarget.innerHTML = modalHtml
    }
  }

  closeMoveToPageModal() {
    if (this.c.hasMoveToPageModalTarget) {
      this.c.moveToPageModalTarget.innerHTML = ""
    }
  }

  closeMoveToPageModalOnBackdrop(event) {
    if (!event.target.closest("[data-move-modal-content]")) {
      this.closeMoveToPageModal()
    }
  }

  confirmMoveToPage() {
    const modal = this.c.moveToPageModalTarget
    if (!modal) return

    this.c.saveState()

    let targetPageId = null

    // Existing page radio takes priority
    const selected = modal.querySelector('input[name="move_target_page"]:checked')
    if (selected) {
      targetPageId = selected.value
    } else {
      // Fall back to creating a new page from the name input
      const newPageInput = modal.querySelector("[data-move-new-page-name]")
      const newPageName = newPageInput?.value?.trim()
      if (!newPageName) return

      const pageId = `page_${Date.now()}`
      const pageNumber = this.c.configuration.pages.length + 1
      this.c.configuration.pages.push({
        id: pageId,
        name: newPageName,
        order: pageNumber,
        fields: []
      })
      targetPageId = pageId
    }

    const fieldIds = this.getSelectedFieldIds()
    this.c.pageManager.moveFieldsToPage(fieldIds, targetPageId)
    this.closeMoveToPageModal()
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  _singleSelect(fieldId) {
    this.selectedFieldIds.clear()
    this.selectedFieldIds.add(fieldId)
    this.selectionAnchorId = fieldId
  }

  _toggleSelect(fieldId) {
    if (this.selectedFieldIds.has(fieldId)) {
      this.selectedFieldIds.delete(fieldId)
    } else {
      this.selectedFieldIds.add(fieldId)
    }
    if (!this.selectionAnchorId) {
      this.selectionAnchorId = fieldId
    }
  }

  _rangeSelect(fieldId) {
    const fields = this._currentPageAllFields()
    const anchorIdx = fields.findIndex(f => f.id === this.selectionAnchorId)
    const targetIdx = fields.findIndex(f => f.id === fieldId)

    if (anchorIdx === -1 || targetIdx === -1) {
      this._singleSelect(fieldId)
      return
    }

    const start = Math.min(anchorIdx, targetIdx)
    const end = Math.max(anchorIdx, targetIdx)

    this.selectedFieldIds.clear()
    for (let i = start; i <= end; i++) {
      this.selectedFieldIds.add(fields[i].id)
    }
  }

  _currentPageAllFields() {
    const topLevel = this.c.currentPageFields || []
    return topLevel.flatMap(f => {
      if (f.field_type === "columns") return [f, ...(f.columns || []).flatMap(c => c.fields || [])]
      if (f.type === "field_group") return [f, ...(f.fields || [])]
      return [f]
    })
  }

  _highlightIntersecting(bandRect) {
    if (!this.c.hasFieldsContainerTarget) return

    this.c.fieldsContainerTarget.querySelectorAll(".field-card").forEach(card => {
      const cardRect = card.getBoundingClientRect()
      const intersects = this._rectsIntersect(bandRect, {
        x: cardRect.left, y: cardRect.top, w: cardRect.width, h: cardRect.height
      })
      card.classList.toggle("ring-2", intersects)
      card.classList.toggle("ring-blue-300", intersects)
    })
  }

  _selectIntersecting(bandRect) {
    if (!this.c.hasFieldsContainerTarget) return

    this.selectedFieldIds.clear()

    this.c.fieldsContainerTarget.querySelectorAll(".field-card").forEach(card => {
      const cardRect = card.getBoundingClientRect()
      const intersects = this._rectsIntersect(bandRect, {
        x: cardRect.left, y: cardRect.top, w: cardRect.width, h: cardRect.height
      })
      if (intersects) {
        this.selectedFieldIds.add(card.dataset.fieldId)
      }
    })

    if (this.count > 0) {
      const ids = [...this.selectedFieldIds]
      this.selectionAnchorId = ids[0]
      this.lastSelectedFieldId = ids[ids.length - 1]
    }

    this.updateVisuals()
    this.syncScalarState()
    this._updatePanel()
  }

  _rectsIntersect(a, b) {
    return !(a.x + a.w < b.x || b.x + b.w < a.x || a.y + a.h < b.y || b.y + b.h < a.y)
  }

  // ---------------------------------------------------------------------------
  // Bulk Operations
  // ---------------------------------------------------------------------------

  bulkSetWidth(event) {
    const width = event.currentTarget.dataset.width
    if (!width) return
    const selected = this.getSelectedFields()
    if (selected.length === 0) return
    this.c.undoRedoManager.saveState()
    selected.forEach(f => { f.width = width; f.width_explicit = true })
    this.c.fieldManager.renderFields()
    this.c.saveManager.markDirty()
    this.updateVisuals()
  }

  bulkDelete() {
    const count = this.count
    if (count === 0) return
    const confirmMsg = (count > 1 ? this.c.bulkDeleteConfirmPluralValue : this.c.bulkDeleteConfirmSingularValue).replace("{count}", count)
    if (!confirm(confirmMsg)) return
    this.c.undoRedoManager.saveState()
    const ids = new Set(this.getSelectedFieldIds())

    // Recurse so fields nested inside `columns` or `field_group` are removed too;
    // earlier this only filtered top-level fields, leaving child selections behind.
    const removeFrom = (list) => {
      return list
        .filter(f => !ids.has(f.id))
        .map(f => {
          if (f.field_type === "columns" && Array.isArray(f.columns)) {
            return { ...f, columns: f.columns.map(col => ({ ...col, fields: removeFrom(col.fields || []) })) }
          }
          if (f.type === "field_group") {
            return { ...f, fields: removeFrom(f.fields || []) }
          }
          return f
        })
    }
    this.c.currentPage.fields = removeFrom(this.c.currentPage.fields)
    this.deselectAll()
    this.c.fieldManager.renderFields()
    this.c.saveManager.markDirty()
  }

  // Move the selected fields into a brand-new section. The new section header
  // is dropped right after the section the selection currently lives in (i.e.
  // immediately before the next section header, or at the end of the page when
  // there is none). Sections are flat markers in the field list — not nested
  // containers — so the selected fields simply follow the new header.
  groupIntoSection() {
    const selected = this.getSelectedFields()
    if (selected.length === 0) return

    const fields = this.c.currentPageFields
    const selectedIds = new Set(selected.map(f => f.id))
    const isSectionHeader = (f) => f && f.property_type === "layout" && f.field_type === "section"

    const firstIdx = fields.findIndex(f => selectedIds.has(f.id))
    if (firstIdx === -1) return

    // End of the current section = the next section header after the selection.
    let boundaryIdx = fields.length
    for (let i = firstIdx + 1; i < fields.length; i++) {
      if (isSectionHeader(fields[i])) { boundaryIdx = i; break }
    }
    // Anchor by id so the insert point survives removing the selected fields.
    const boundaryId = boundaryIdx < fields.length ? fields[boundaryIdx].id : null

    this.c.undoRedoManager.saveState()

    const movedFields = fields.filter(f => selectedIds.has(f.id))   // preserves order
    const remaining = fields.filter(f => !selectedIds.has(f.id))

    const sectionHeader = this.c.fieldManager.createField({ type: "section", label: "New Section" })
    // Leave the grouped section unlabeled — createField applies a default label,
    // so clear it explicitly. The header is auto-selected below for renaming.
    sectionHeader.label = ""

    let insertIdx = remaining.length
    if (boundaryId) {
      const bIdx = remaining.findIndex(f => f.id === boundaryId)
      if (bIdx !== -1) insertIdx = bIdx
    }
    remaining.splice(insertIdx, 0, sectionHeader, ...movedFields)
    remaining.forEach((f, i) => { f.order = i })
    this.c.currentPage.fields = remaining

    this.deselectAll()
    this.c.fieldManager.renderFields()
    this.c.saveManager.markDirty()

    // Select the new section header so it's obvious and immediately renamable.
    this.selectField(sectionHeader.id, { shift: false, meta: false })
  }

  // showPanel=false suppresses the floating property popup (e.g. after a
  // drag-and-drop) while still applying selection highlight + action bar.
  _updatePanel(showPanel = true) {
    if (this.c.hasFloatingActionBarTarget) {
      const bar = this.c.floatingActionBarTarget
      if (this.isMultiSelect) {
        bar.classList.remove("hidden")
        if (this.c.hasSelectionCountTarget) {
          this.c.selectionCountTarget.textContent = this.c.fieldsSelectedLabelValue.replace("{count}", this.count)
        }
        this.c.propertyManager.hideFloatingPanel()
        // Keep the toolbar width icons usable for the whole multi-selection
        // (hideFloatingPanel() disables them).
        this.c.propertyManager.enableToolbarWidthForMulti()
      } else {
        bar.classList.add("hidden")
        if (this.isSingleSelect && showPanel) {
          const field = this.getSelectedFields()[0]
          if (field) this.c.propertyManager.showFloatingPanel(field.id)
        } else {
          this.c.propertyManager.hideFloatingPanel()
        }
      }
    } else if (this.isEmpty) {
      this.c.propertyManager.hideFloatingPanel()
    } else if (this.isSingleSelect && showPanel) {
      const fieldId = [...this.selectedFieldIds][0]
      this.c.propertyManager.showFloatingPanel(fieldId)
    } else if (this.isSingleSelect) {
      this.c.propertyManager.hideFloatingPanel()
    } else {
      this.c.propertyManager.showMultiSelectToolbar(this.count)
    }
  }
}
