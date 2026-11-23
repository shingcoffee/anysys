import { Controller } from "@hotwired/stimulus"

/**
 * Page Toolbar Controller
 * Manages the page builder toolbar including save, undo/redo functionality.
 */
export default class extends Controller {
  static targets = [
    "saveStatus",
    "undoButton",
    "redoButton"
  ]

  // i18n seam: English defaults byte-identical to the former hardcoded copy.
  // NOTE: this controller currently has no ERB mount in the app (superseded
  // by the page-builder module's own canvas/toolbar) — see notes in the
  // frontend delivery report. The Values keep the seam ready for reuse.
  static values = {
    unsavedChanges: { type: String, default: "Unsaved changes" },
    allChangesSaved: { type: String, default: "All changes saved" },
    savingLabel: { type: String, default: "Saving..." },
    savedSuccessfully: { type: String, default: "Saved successfully" },
    saveFailed: { type: String, default: "Save failed" },
    pageSavedNotification: { type: String, default: "Page saved successfully" },
    saveFailedFallback: { type: String, default: "Failed to save page" }
  }

  // ===================
  // Lifecycle
  // ===================

  connect() {
    this._findCanvasElement()
    this._bindCanvasEventListeners()

    this.hasUnsavedChanges = false

    this._updateSaveStatus()
    this._updateUndoRedoButtons(false, false)
  }

  disconnect() {
    this._unbindCanvasEventListeners()
  }

  // ===================
  // Canvas Integration
  // ===================

  _findCanvasElement() {
    this.canvasElement = document.querySelector('[data-controller*="page-canvas"]')
  }

  _bindCanvasEventListeners() {
    this._boundHandlePageChanged = this._handlePageChanged.bind(this)
    this._boundHandlePageSaved = this._handlePageSaved.bind(this)
    this._boundHandlePageSaveError = this._handlePageSaveError.bind(this)
    this._boundHandleUndoRedoStateChanged = this._handleUndoRedoStateChanged.bind(this)

    if (this.canvasElement) {
      this.canvasElement.addEventListener("pageChanged", this._boundHandlePageChanged)
      this.canvasElement.addEventListener("pageSaved", this._boundHandlePageSaved)
      this.canvasElement.addEventListener("pageSaveError", this._boundHandlePageSaveError)
      this.canvasElement.addEventListener("undoRedoStateChanged", this._boundHandleUndoRedoStateChanged)
    }
  }

  _unbindCanvasEventListeners() {
    if (this.canvasElement) {
      this.canvasElement.removeEventListener("pageChanged", this._boundHandlePageChanged)
      this.canvasElement.removeEventListener("pageSaved", this._boundHandlePageSaved)
      this.canvasElement.removeEventListener("pageSaveError", this._boundHandlePageSaveError)
      this.canvasElement.removeEventListener("undoRedoStateChanged", this._boundHandleUndoRedoStateChanged)
    }
  }

  _getCanvasController() {
    if (!this.canvasElement) return null
    return this.application.getControllerForElementAndIdentifier(
      this.canvasElement,
      "page-canvas"
    )
  }

  // ===================
  // Action Handlers
  // ===================

  save(event) {
    event.preventDefault()
    const canvasController = this._getCanvasController()
    if (!canvasController) return

    this._showSaving()
    canvasController.save().then(success => {
      if (!success) this._showSaveError()
    })
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

  // ===================
  // Event Handlers
  // ===================

  _handlePageChanged(event) {
    this.hasUnsavedChanges = event.detail?.hasUnsavedChanges ?? true
    this._updateSaveStatus()
  }

  _handlePageSaved() {
    this.hasUnsavedChanges = false
    this._showSaveSuccess()
  }

  _handlePageSaveError(event) {
    this._showSaveError(event.detail?.errors || [])
  }

  _handleUndoRedoStateChanged(event) {
    this._updateUndoRedoButtons(
      event.detail?.canUndo ?? false,
      event.detail?.canRedo ?? false
    )
  }

  // ===================
  // UI Updates
  // ===================

  _updateSaveStatus() {
    if (!this.hasSaveStatusTarget) return

    if (this.hasUnsavedChanges) {
      this.saveStatusTarget.textContent = this.unsavedChangesValue
      this.saveStatusTarget.className = "text-sm text-amber-600"
    } else {
      this.saveStatusTarget.textContent = this.allChangesSavedValue
      this.saveStatusTarget.className = "text-sm text-green-600"
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
    if (!this.hasSaveStatusTarget) return
    this.saveStatusTarget.textContent = this.savingLabelValue
    this.saveStatusTarget.className = "text-sm text-blue-600"
  }

  _showSaveSuccess() {
    if (this.hasSaveStatusTarget) {
      this.saveStatusTarget.textContent = this.savedSuccessfullyValue
      this.saveStatusTarget.className = "text-sm text-green-600"
      setTimeout(() => this._updateSaveStatus(), 3000)
    }
    this._showNotification(this.pageSavedNotificationValue, "success")
  }

  _showSaveError(errors = []) {
    if (this.hasSaveStatusTarget) {
      this.saveStatusTarget.textContent = this.saveFailedValue
      this.saveStatusTarget.className = "text-sm text-red-600"
      setTimeout(() => this._updateSaveStatus(), 5000)
    }

    const errorMessage = errors.length > 0
      ? errors.join(", ")
      : this.saveFailedFallbackValue
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
