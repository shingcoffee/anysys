/**
 * Undo/Redo Manager Module
 * Handles undo/redo operations for the Flowchart Canvas.
 *
 * The undo stack holds full graph snapshots; its top is the current state and
 * its bottom the baseline, so each entry's "after" state is the snapshot
 * itself and its "before" state the one beneath it. A commit carrying the same
 * coalesce key as the previous commit (read from `canvas.undoCoalesceKey`,
 * e.g. `<elementId>:<field>` while a property-editor field is focused)
 * replaces the top snapshot instead of pushing a new one.
 */

const MAX_UNDO_ENTRIES = 50
const PERSISTED_ENTRIES = 10

export class UndoRedoManager {
  constructor(controller) {
    this.controller = controller
    const versionId = controller.basedOnVersionIdValue
    this._storageKey = versionId
      ? `flowchart_undo_${controller.idValue}_v${versionId}`
      : `flowchart_undo_${controller.idValue}`
    this.isUndoRedoOperation = false
    this._lastCoalesceKey = null
    this._restoreFromStorage()
  }

  // ===================
  // Public API
  // ===================

  /**
   * Save the initial state when canvas is ready.
   */
  saveInitialState() {
    this._lastCoalesceKey = null
    const state = this.captureCurrentState()
    if (this.undoStack.length > 0) {
      const top = this.undoStack[this.undoStack.length - 1]
      if (state && top === state) {
        this._dispatchUndoRedoUpdate()
        return
      }
      this.undoStack = []
      this.redoStack = []
    }
    if (state) {
      this.undoStack.push(state)
      this._persistToStorage()
      this._dispatchUndoRedoUpdate()
    }
  }

  /**
   * Snapshot the canvas graph in canvas order.
   */
  captureCurrentState() {
    const canvas = this.controller.canvas
    if (!canvas || !canvas.elements) return null

    if (canvas.previewMode && this.controller._collapsedPreviewConfiguration) {
      return this._serializeConfiguration(this.controller._collapsedPreviewConfiguration)
    }

    const elements = canvas.elements.map(el => ({
      id: el.id,
      type: el.type,
      x: Math.round(el.x),
      y: Math.round(el.y),
      width: el.width,
      height: el.height,
      label: el.label || "",
      properties: el.properties ? JSON.parse(JSON.stringify(el.properties)) : {}
    }))

    const connections = (canvas.connections || []).map(c => ({
      id: c.id,
      from: c.from,
      to: c.to,
      fromPort: c.fromPort || null,
      fromPosition: c.fromPosition || null,
      toPort: c.toPort || null,
      toPosition: c.toPosition || null,
      label: c.label || null,
      matchValue: c.matchValue ?? null,
      properties: c.properties ? JSON.parse(JSON.stringify(c.properties)) : {}
    }))

    return JSON.stringify({ elements, connections })
  }

  _serializeConfiguration(config) {
    const elements = (config.elements || []).map(el => ({
      id: el.id,
      type: el.type,
      x: Math.round(el.x),
      y: Math.round(el.y),
      width: el.width,
      height: el.height,
      label: el.label || "",
      properties: el.properties ? JSON.parse(JSON.stringify(el.properties)) : {}
    }))
    const connections = (config.connections || []).map(c => ({
      id: c.id,
      from: c.from,
      to: c.to,
      fromPort: c.fromPort || null,
      fromPosition: c.fromPosition || null,
      toPort: c.toPort || null,
      toPosition: c.toPosition || null,
      label: c.label || null,
      matchValue: c.matchValue ?? null,
      properties: c.properties ? JSON.parse(JSON.stringify(c.properties)) : {}
    }))
    return JSON.stringify({ elements, connections })
  }

  /**
   * Commit the current canvas state to the undo stack.
   * @param {string|null} [coalesceKey] - Consecutive commits with the same
   *   non-null key collapse into one entry. Defaults to `canvas.undoCoalesceKey`.
   */
  commitPendingState(coalesceKey = this.controller.canvas?.undoCoalesceKey ?? null) {
    if (this.isUndoRedoOperation) return

    const currentState = this.captureCurrentState()
    if (!currentState) return

    const topIndex = this.undoStack.length - 1
    if (currentState === this.undoStack[topIndex]) return

    if (coalesceKey && coalesceKey === this._lastCoalesceKey) {
      if (currentState === this.undoStack[topIndex - 1]) {
        // The coalesced edit returned to its "before" state: drop the no-op
        // entry so the next commit pushes instead of overwriting the baseline.
        this.undoStack.pop()
        this._lastCoalesceKey = null
      } else {
        this.undoStack[topIndex] = currentState
      }
    } else {
      this.undoStack.push(currentState)
      this._lastCoalesceKey = coalesceKey
      if (this.undoStack.length > MAX_UNDO_ENTRIES) this.undoStack.shift()
    }
    this.redoStack = []

    this._persistToStorage()
    this._dispatchUndoRedoUpdate()
  }

  /**
   * Undo the last action.
   */
  undo() {
    this.controller._leavePreviewMode?.({ restore: true })
    if (this.controller.canvas?.canMutate?.() === false) return false
    if (this.undoStack.length <= 1) return false

    this.redoStack.push(this.undoStack.pop())
    this._applyRestore(this.undoStack[this.undoStack.length - 1])
    return true
  }

  /**
   * Redo the last undone action.
   */
  redo() {
    this.controller._leavePreviewMode?.({ restore: true })
    if (this.controller.canvas?.canMutate?.() === false) return false
    if (this.redoStack.length === 0) return false

    const nextState = this.redoStack.pop()
    this.undoStack.push(nextState)
    this._applyRestore(nextState)
    return true
  }

  /**
   * Check if undo is available.
   */
  get canUndo() {
    return this.undoStack.length > 1
  }

  /**
   * Check if redo is available.
   */
  get canRedo() {
    return this.redoStack.length > 0
  }

  // ===================
  // Private Methods
  // ===================

  _applyRestore(stateString) {
    this.isUndoRedoOperation = true
    this._lastCoalesceKey = null

    try {
      this._restoreState(stateString)

      this.controller.hasUnsavedChanges = true
      // An undo/redo during an in-flight save must mark the session as dirty
      // so the save-success handler does not clear the unsaved indicator or
      // clobber the restored state via restoreCompleteCanvasState.
      this.controller._editsSinceSaveStart = true
      this.controller._updateUnsavedIndicator()
      this.controller._dispatchConfigurationChange()
      this._persistToStorage()
      this._dispatchUndoRedoUpdate()
    } finally {
      this.isUndoRedoOperation = false
    }
  }

  _restoreState(stateString) {
    const canvas = this.controller.canvas
    if (!canvas) return

    this.controller._leavePreviewMode?.({ restore: false })

    try {
      canvas.restoreGraph(JSON.parse(stateString))
    } catch (_error) {
      // A corrupt stored snapshot leaves the canvas as it is.
    }
  }

  _dispatchUndoRedoUpdate() {
    this.controller.element.dispatchEvent(new CustomEvent("undoRedoStateChanged", {
      detail: { canUndo: this.canUndo, canRedo: this.canRedo },
      bubbles: true
    }))
  }

  _restoreFromStorage() {
    try {
      const stored = sessionStorage.getItem(this._storageKey)
      if (stored) {
        const { undoStack, redoStack } = JSON.parse(stored)
        this.undoStack = undoStack || []
        this.redoStack = redoStack || []
        return
      }
    } catch (_e) {
      // sessionStorage unavailable or corrupt
    }
    this.undoStack = []
    this.redoStack = []
  }

  _persistToStorage() {
    try {
      // sessionStorage has a ~5MB limit and configurations can be large, so
      // only the last few states survive a refresh.
      sessionStorage.setItem(this._storageKey, JSON.stringify({
        undoStack: this.undoStack.slice(-PERSISTED_ENTRIES),
        redoStack: this.redoStack.slice(-PERSISTED_ENTRIES)
      }))
    } catch (_e) {
      // sessionStorage full or unavailable
    }
  }
}

export default UndoRedoManager
