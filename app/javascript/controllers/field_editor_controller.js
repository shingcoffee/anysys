import { Controller } from "@hotwired/stimulus"

/**
 * Field Editor Controller
 * Manages the field property editing panel.
 */
export default class extends Controller {
  static targets = [
    "panel",
    "form",
    "title",
    "fieldId",
    "labelInput",
    "placeholderInput",
    "widthSelect",
    "requiredCheckbox"
  ]

  // i18n seam: English default byte-identical to the former hardcoded copy.
  // NOTE: this controller currently has no ERB mount in the app (superseded
  // by the page-builder module's own canvas/toolbar) — see notes in the
  // frontend delivery report. The Value keeps the seam ready for reuse.
  static values = {
    editTitleFormat: { type: String, default: "Edit: {label}" }
  }

  // ===================
  // Lifecycle
  // ===================

  connect() {
    this.currentField = null
    this._setupEventListeners()
  }

  disconnect() {
    this._removeEventListeners()
  }

  _setupEventListeners() {
    this._boundOpenFieldEditor = this._handleOpenFieldEditor.bind(this)
    document.addEventListener("openFieldEditor", this._boundOpenFieldEditor)
  }

  _removeEventListeners() {
    document.removeEventListener("openFieldEditor", this._boundOpenFieldEditor)
  }

  // ===================
  // Event Handlers
  // ===================

  _handleOpenFieldEditor(event) {
    const { field } = event.detail
    this.open(field)
  }

  // ===================
  // Panel Controls
  // ===================

  open(field) {
    this.currentField = field

    // Populate form
    if (this.hasFieldIdTarget) this.fieldIdTarget.value = field.id
    if (this.hasLabelInputTarget) this.labelInputTarget.value = field.label
    if (this.hasPlaceholderInputTarget) this.placeholderInputTarget.value = field.placeholder || ""
    if (this.hasWidthSelectTarget) this.widthSelectTarget.value = field.width || "full"
    if (this.hasRequiredCheckboxTarget) this.requiredCheckboxTarget.checked = field.required || false
    if (this.hasTitleTarget) this.titleTarget.textContent = this.editTitleFormatValue.replace("{label}", field.label)

    // Show panel
    if (this.hasPanelTarget) {
      this.panelTarget.classList.remove("translate-x-full")
      this.panelTarget.classList.add("translate-x-0")
    }
  }

  close() {
    this.currentField = null

    // Hide panel
    if (this.hasPanelTarget) {
      this.panelTarget.classList.remove("translate-x-0")
      this.panelTarget.classList.add("translate-x-full")
    }
  }

  // ===================
  // Form Actions
  // ===================

  save(event) {
    event.preventDefault()

    if (!this.currentField) return

    const updates = {
      label: this.hasLabelInputTarget ? this.labelInputTarget.value : this.currentField.label,
      placeholder: this.hasPlaceholderInputTarget ? this.placeholderInputTarget.value : "",
      width: this.hasWidthSelectTarget ? this.widthSelectTarget.value : "full",
      required: this.hasRequiredCheckboxTarget ? this.requiredCheckboxTarget.checked : false
    }

    const canvasController = this._getCanvasController()
    if (canvasController) {
      canvasController.updateField(this.currentField.id, updates)
    }

    this.close()
  }

  removeField() {
    if (!this.currentField) return

    const canvasController = this._getCanvasController()
    if (canvasController) {
      canvasController.removeField(this.currentField.id)
    }

    this.close()
  }

  // ===================
  // Utilities
  // ===================

  _getCanvasController() {
    const canvasElement = document.querySelector('[data-controller*="page-canvas"]')
    if (!canvasElement) return null

    return this.application.getControllerForElementAndIdentifier(
      canvasElement,
      "page-canvas"
    )
  }
}
