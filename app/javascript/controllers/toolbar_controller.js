import { Controller } from "@hotwired/stimulus"

/**
 * Toolbar Controller
 * Manages the flowchart editor toolbar including save, undo/redo, and name editing.
 */
export default class extends Controller {
  static values = {
    readOnly: { type: Boolean, default: false },
    readOnlySaveMessage: { type: String, default: "Cannot save a launched flowchart. Take it offline first." },
    savedMessage: { type: String, default: "Flowchart saved successfully" },
    saveFailedMessage: { type: String, default: "Failed to save flowchart" },
    errorSeparator: { type: String, default: ", " }
  }

  static targets = [
    "saveDot",
    "saveButton",
    "undoButton",
    "redoButton",
    "zoomLevel",
    "overflowMenu",
    "mutatingAction"
  ]

  // ===================
  // Lifecycle
  // ===================

  connect() {
    this._previewLocked = false
    this._findCanvasElement()
    this._bindCanvasEventListeners()

    this.hasUnsavedChanges = false

    this._updateSaveStatus()
    this._updateUndoRedoButtons(false, false)
    this._updateMutabilityState()

    // Listen for zoom changes from canvas
    this._onZoomChanged = (event) => {
      if (this.hasZoomLevelTarget) {
        this.zoomLevelTarget.textContent = `${event.detail.percent}%`
      }
    }
    this.element.closest("[data-controller~='flowchart-canvas']")?.addEventListener("zoomChanged", this._onZoomChanged)
  }

  disconnect() {
    this._unbindCanvasEventListeners()
    this.element.closest("[data-controller~='flowchart-canvas']")?.removeEventListener("zoomChanged", this._onZoomChanged)
    this.closeOverflow()
    this._clearStatusTimer()
  }

  // ===================
  // Canvas Integration
  // ===================

  _findCanvasElement() {
    this.canvasElement = this.element.closest('[data-controller*="flowchart-canvas"]')
  }

  _bindCanvasEventListeners() {
    this._boundHandleFlowchartChanged = this._handleFlowchartChanged.bind(this)
    this._boundHandleFlowchartSaved = this._handleFlowchartSaved.bind(this)
    this._boundHandleFlowchartSaveError = this._handleFlowchartSaveError.bind(this)
    this._boundHandleUndoRedoStateChanged = this._handleUndoRedoStateChanged.bind(this)
    this._boundHandleMutabilityChanged = this._handleMutabilityChanged.bind(this)

    if (this.canvasElement) {
      this.canvasElement.addEventListener("flowchartChanged", this._boundHandleFlowchartChanged)
      this.canvasElement.addEventListener("flowchartSaved", this._boundHandleFlowchartSaved)
      this.canvasElement.addEventListener("flowchartSaveError", this._boundHandleFlowchartSaveError)
      this.canvasElement.addEventListener("undoRedoStateChanged", this._boundHandleUndoRedoStateChanged)
      this.canvasElement.addEventListener("flowchartMutabilityChanged", this._boundHandleMutabilityChanged)
    }
  }

  _unbindCanvasEventListeners() {
    if (this.canvasElement) {
      this.canvasElement.removeEventListener("flowchartChanged", this._boundHandleFlowchartChanged)
      this.canvasElement.removeEventListener("flowchartSaved", this._boundHandleFlowchartSaved)
      this.canvasElement.removeEventListener("flowchartSaveError", this._boundHandleFlowchartSaveError)
      this.canvasElement.removeEventListener("undoRedoStateChanged", this._boundHandleUndoRedoStateChanged)
      this.canvasElement.removeEventListener("flowchartMutabilityChanged", this._boundHandleMutabilityChanged)
    }
  }

  _getCanvasController() {
    if (!this.canvasElement) return null
    return this.application.getControllerForElementAndIdentifier(
      this.canvasElement,
      "flowchart-canvas"
    )
  }

  // ===================
  // Action Handlers
  // ===================

  save(event) {
    event.preventDefault()

    if (this.readOnlyValue) {
      this._showNotification(this.readOnlySaveMessageValue, "error")
      return
    }

    const canvasController = this._getCanvasController()
    if (!canvasController) return

    this._showSaving()
    // Success/failure feedback is driven by the flowchartSaved /
    // flowchartSaveError events the canvas controller dispatches (which carry
    // the server's error messages). Don't also branch on the returned boolean:
    // it double-toasts real failures and shows a spurious error when a
    // re-entrant (double-click) save returns false while the first is in flight.
    canvasController.save()
  }

  undo(event) {
    event.preventDefault()
    const canvasController = this._getCanvasController()
    if (canvasController) canvasController.undo()
  }

  redo(event) {
    event.preventDefault()
    const canvasController = this._getCanvasController()
    if (canvasController) canvasController.redo()
  }

  clear(event) {
    event.preventDefault()
    const canvasController = this._getCanvasController()
    if (canvasController) canvasController.clear()
  }

  zoomIn(event) {
    event.preventDefault()
    const canvasController = this._getCanvasController()
    if (canvasController) canvasController.zoomIn()
  }

  zoomOut(event) {
    event.preventDefault()
    const canvasController = this._getCanvasController()
    if (canvasController) canvasController.zoomOut()
  }

  fitToContent(event) {
    event.preventDefault()
    const canvasController = this._getCanvasController()
    if (canvasController) canvasController.fitToContent()
  }

  exportSVG(event) {
    event.preventDefault()
    const canvasController = this._getCanvasController()
    if (canvasController) canvasController.exportSVG()
  }

  exportPNG(event) {
    event.preventDefault()
    const canvasController = this._getCanvasController()
    if (canvasController) canvasController.exportPNG()
  }

  autoLayout(event) {
    event.preventDefault()
    const canvasController = this._getCanvasController()
    if (canvasController) canvasController.autoLayout()
  }

  cycleConnectionRouting(event) {
    event.preventDefault()
    const canvasController = this._getCanvasController()
    if (canvasController) canvasController.cycleConnectionRouting()
  }

  toggleOverflow(event) {
    event.preventDefault()
    if (!this.hasOverflowMenuTarget) return
    this.overflowMenuTarget.classList.toggle("hidden")

    // Close on click outside
    if (!this.overflowMenuTarget.classList.contains("hidden")) {
      const toggleButton = event.currentTarget
      // Capture the handler in a local so the deferred addEventListener always
      // registers this exact function — reading this._overflowCloseHandler at
      // timer-fire time could see it nulled (by closeOverflow) and register null.
      const handler = (e) => {
        if (!this.overflowMenuTarget.contains(e.target) && !toggleButton.contains(e.target)) {
          this.closeOverflow()
        }
      }
      this._clearOverflowAttachTimer()
      this._overflowCloseHandler = handler
      this._overflowAttachTimer = setTimeout(() => {
        this._overflowAttachTimer = null
        document.addEventListener("click", handler)
      }, 0)
    } else {
      this.closeOverflow()
    }
  }

  closeOverflow() {
    if (this.hasOverflowMenuTarget) {
      this.overflowMenuTarget.classList.add("hidden")
    }
    this._clearOverflowAttachTimer()
    if (this._overflowCloseHandler) {
      document.removeEventListener("click", this._overflowCloseHandler)
      this._overflowCloseHandler = null
    }
  }

  _clearOverflowAttachTimer() {
    if (this._overflowAttachTimer) {
      clearTimeout(this._overflowAttachTimer)
      this._overflowAttachTimer = null
    }
  }

  _clearStatusTimer() {
    if (this._statusTimer) {
      clearTimeout(this._statusTimer)
      this._statusTimer = null
    }
  }

  // ===================
  // Event Handlers
  // ===================

  _handleFlowchartChanged(event) {
    this.hasUnsavedChanges = event.detail?.hasUnsavedChanges ?? true
    this._updateSaveStatus()
  }

  _handleFlowchartSaved(event) {
    this.hasUnsavedChanges = event.detail?.hasUnsavedChanges ?? false
    this._showSaveSuccess()
  }

  // A conflict has its own banner in the editor, so only the dot turns red.
  _handleFlowchartSaveError(event) {
    this._showSaveError(event.detail?.errors || [], { toast: event.detail?.status !== "conflict" })
  }

  _handleUndoRedoStateChanged(event) {
    this._updateUndoRedoButtons(
      event.detail?.canUndo ?? false,
      event.detail?.canRedo ?? false
    )
  }

  _handleMutabilityChanged(event) {
    this._previewLocked = event.detail?.canMutate === false
    this._updateMutabilityState()
  }

  // ===================
  // UI Updates
  // ===================

  _updateMutabilityState() {
    const locked = this.readOnlyValue || this._previewLocked
    if (this.hasSaveButtonTarget) {
      this.saveButtonTarget.classList.toggle("opacity-50", this.readOnlyValue)
      this.saveButtonTarget.classList.toggle("cursor-not-allowed", this.readOnlyValue)
      if (this.readOnlyValue) {
        this.saveButtonTarget.setAttribute("aria-disabled", "true")
      } else {
        this.saveButtonTarget.removeAttribute("aria-disabled")
      }
    }
    this.mutatingActionTargets.forEach((button) => {
      button.disabled = locked
    })
  }

  _updateSaveStatus() {
    if (!this.hasSaveDotTarget) return

    if (this.hasUnsavedChanges) {
      this.saveDotTarget.className = "absolute -top-0.5 -right-0.5 w-2 h-2 rounded-full bg-amber-500"
    } else {
      this.saveDotTarget.classList.add("hidden")
    }
  }

  _updateUndoRedoButtons(canUndo, canRedo) {
    if (this.hasUndoButtonTarget) {
      this.undoButtonTarget.disabled = !canUndo
      this.undoButtonTarget.classList.toggle("opacity-50", !canUndo)
      this.undoButtonTarget.classList.toggle("cursor-not-allowed", !canUndo)
    }

    if (this.hasRedoButtonTarget) {
      this.redoButtonTarget.disabled = !canRedo
      this.redoButtonTarget.classList.toggle("opacity-50", !canRedo)
      this.redoButtonTarget.classList.toggle("cursor-not-allowed", !canRedo)
    }
  }

  _showSaving() {
    if (!this.hasSaveDotTarget) return
    this.saveDotTarget.className = "absolute -top-0.5 -right-0.5 w-2 h-2 rounded-full bg-blue-500 animate-pulse"
  }

  _showSaveSuccess() {
    if (this.hasSaveDotTarget) {
      this.saveDotTarget.className = "absolute -top-0.5 -right-0.5 w-2 h-2 rounded-full bg-green-500"
      this._clearStatusTimer()
      this._statusTimer = setTimeout(() => {
        this._statusTimer = null
        this._updateSaveStatus()
      }, 3000)
    }
    this._showNotification(this.savedMessageValue, "success")
  }

  _showSaveError(errors = [], { toast = true } = {}) {
    if (this.hasSaveDotTarget) {
      this.saveDotTarget.className = "absolute -top-0.5 -right-0.5 w-2 h-2 rounded-full bg-red-500"
      this._clearStatusTimer()
      this._statusTimer = setTimeout(() => {
        this._statusTimer = null
        this._updateSaveStatus()
      }, 5000)
    }
    if (!toast) return

    const errorMessage = errors.length > 0
      ? errors.join(this.errorSeparatorValue)
      : this.saveFailedMessageValue
    this._showNotification(errorMessage, "error")
  }

  _showNotification(message, type = "info") {
    const notification = document.createElement("div")
    const colorClass = this._getNotificationColorClass(type)

    notification.className = `fixed top-4 right-4 z-50 px-4 py-2 rounded-lg shadow-lg transition-all duration-300 border ${colorClass}`
    notification.textContent = message
    document.body.appendChild(notification)

    setTimeout(() => {
      notification.style.transform = "translateX(100%)"
      notification.style.opacity = "0"
      setTimeout(() => notification.remove(), 300)
    }, 5000)
  }

  _getNotificationColorClass(type) {
    const colors = {
      success: "bg-green-100 text-green-800 border-green-200",
      error: "bg-red-100 text-red-800 border-red-200",
      info: "bg-blue-100 text-blue-800 border-blue-200"
    }
    return colors[type] || colors.info
  }

}
