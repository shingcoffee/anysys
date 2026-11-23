import { BaseManager } from "controllers/page_builder/base_manager"

const MAX_UNDO_BYTES = 5 * 1024 * 1024 // 5 MB total stack budget

export class UndoRedoManager extends BaseManager {
  // Stack entries are JSON strings of { configuration, activePageId } so undo
  // restores not just the document but which page tab the user was on.
  _snapshot() {
    return JSON.stringify({
      configuration: this.c.configuration,
      activePageId: this.c.activePageValue
    })
  }

  saveState() {
    const state = this._snapshot()
    const lastState = this.c.undoStack[this.c.undoStack.length - 1]
    if (state === lastState) return // no-op if identical to top of stack

    this.c.undoStack.push(state)

    // Cap by count
    while (this.c.undoStack.length > this.c.maxHistorySize) {
      this.c.undoStack.shift()
    }

    // Cap by cumulative byte size (drops oldest until under budget)
    let total = this.c.undoStack.reduce((sum, s) => sum + s.length, 0)
    while (total > MAX_UNDO_BYTES && this.c.undoStack.length > 1) {
      total -= this.c.undoStack[0].length
      this.c.undoStack.shift()
    }

    this.c.redoStack = []
    this.updateUndoRedoButtons()
    this.c.saveManager.markDirty()
  }

  saveHistory() {
    this.saveState()
  }

  _restore(serialized) {
    let parsed
    try {
      parsed = JSON.parse(serialized)
    } catch (_e) {
      return
    }

    // Backward-compat: legacy entries were the bare configuration object.
    if (parsed && parsed.configuration && parsed.activePageId !== undefined) {
      this.c.configuration = parsed.configuration
      const stillExists = this.c.configuration.pages?.some(p => p.id === parsed.activePageId)
      this.c.activePageValue = stillExists
        ? parsed.activePageId
        : (this.c.configuration.pages?.[0]?.id || "page_1")
    } else {
      this.c.configuration = parsed
      const stillExists = this.c.configuration.pages?.some(p => p.id === this.c.activePageValue)
      if (!stillExists) {
        this.c.activePageValue = this.c.configuration.pages?.[0]?.id || "page_1"
      }
    }

    this.c.fields = this.c.currentPageFields
  }

  undo() {
    if (this.c.undoStack.length === 0) return

    this.c.redoStack.push(this._snapshot())
    const previousState = this.c.undoStack.pop()
    this._restore(previousState)

    this.c.pageManager.renderPageTabs()
    this.c.fieldManager.renderFields()
    this.c.pageManager.updateFormFooter()
    this.updateUndoRedoButtons()
    this.c.saveManager.markDirty()
    this._refreshSelectionAfterRestore()
  }

  redo() {
    if (this.c.redoStack.length === 0) return

    this.c.undoStack.push(this._snapshot())
    const nextState = this.c.redoStack.pop()
    this._restore(nextState)

    this.c.pageManager.renderPageTabs()
    this.c.fieldManager.renderFields()
    this.c.pageManager.updateFormFooter()
    this.updateUndoRedoButtons()
    this.c.saveManager.markDirty()
    this._refreshSelectionAfterRestore()
  }

  // After restoring a snapshot, check whether the previously selected field
  // still exists and refresh (or close) the property panel accordingly.
  _refreshSelectionAfterRestore() {
    const selectedId = this.c.selectedFieldId
    if (!selectedId) {
      this.c.selectionManager.deselectAll()
      return
    }

    const fieldStillExists = this.c.currentPageFields.some(f => f.id === selectedId) ||
      this.c.currentPageFields.some(f =>
        f.field_type === "columns" && (f.columns || []).some(col =>
          (col.fields || []).some(cf => cf.id === selectedId)
        )
      )

    if (fieldStillExists) {
      // Refresh the property panel with the updated field data
      this.c.propertyManager.showFloatingPanel(selectedId)
    } else {
      // Selected field was removed by the undo/redo — clear selection
      this.c.selectedFieldId = null
      this.c.selectionManager.deselectAll()
      this.c.propertyManager.hideFloatingPanel()
    }
  }

  updateUndoRedoButtons() {
    if (this.c.hasUndoBtnTarget) {
      this.c.undoBtnTarget.disabled = this.c.undoStack.length === 0
    }
    if (this.c.hasRedoBtnTarget) {
      this.c.redoBtnTarget.disabled = this.c.redoStack.length === 0
    }
  }
}
