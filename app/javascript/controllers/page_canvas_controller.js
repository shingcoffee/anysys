import { Controller } from "@hotwired/stimulus"
import { getCSRFToken } from "utils"

/**
 * Page Canvas Controller
 * Manages the page builder canvas including field management, drag-drop, and save functionality.
 */
export default class extends Controller {
  static targets = [
    "canvasContainer",
    "dropZone",
    "fieldsContainer",
    "emptyPlaceholder",
    "fieldEditorPanel"
  ]

  static values = {
    id: Number,
    customerId: String,
    configuration: String,
    entityProperties: Array,
    // i18n seam: English defaults byte-identical to the former hardcoded copy.
    // NOTE: this controller currently has no ERB mount in the app (superseded
    // by the page-builder module's own canvas/toolbar) — see notes in the
    // frontend delivery report. The Values keep the seam ready for reuse.
    networkError: { type: String, default: "Network error" },
    fieldPlaceholderFormat: { type: String, default: "Enter {name}" }
  }

  // ===================
  // Lifecycle
  // ===================

  connect() {
    this.fields = []
    this.undoStack = []
    this.redoStack = []
    this.hasUnsavedChanges = false

    this._parseConfiguration()
    this._renderFields()
    this._setupDropZone()
    this._setupFieldListeners()
  }

  disconnect() {
    // Cleanup listeners
  }

  // ===================
  // Configuration Parsing
  // ===================

  _parseConfiguration() {
    try {
      const config = JSON.parse(this.configurationValue || '{"fields":[],"metadata":{}}')
      this.fields = config.fields || []
      this.metadata = config.metadata || {}
    } catch {
      this.fields = []
      this.metadata = {}
    }
  }

  // ===================
  // Field Rendering
  // ===================

  _renderFields() {
    if (!this.hasFieldsContainerTarget) return

    // Show/hide empty placeholder
    if (this.hasEmptyPlaceholderTarget) {
      this.emptyPlaceholderTarget.style.display = this.fields.length === 0 ? "block" : "none"
    }

    // Clear existing rendered fields (but keep placeholder)
    const existingFields = this.fieldsContainerTarget.querySelectorAll('[data-field-id]')
    existingFields.forEach(el => el.remove())

    // Render fields
    this.fields.forEach(field => {
      const fieldElement = this._createFieldElement(field)
      this.fieldsContainerTarget.appendChild(fieldElement)
    })
  }

  _createFieldElement(field) {
    const element = document.createElement("div")
    element.className = this._getFieldWidthClass(field.width) + " field-card bg-white border border-gray-200 rounded-lg p-4 cursor-move hover:border-indigo-300 hover:shadow-sm transition-all"
    element.dataset.fieldId = field.id
    element.draggable = true

    element.innerHTML = `
      <div class="flex items-center justify-between gap-2">
        <div class="flex items-center min-w-0 gap-2">
          <svg class="size-4 flex-shrink-0 text-gray-400 cursor-move" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 8h16M4 16h16" />
          </svg>
          <span class="text-sm font-medium text-gray-700 truncate">${this._escapeHtml(field.label)}</span>
          ${field.required ? '<span class="text-red-500 flex-shrink-0">*</span>' : ''}
          <span class="px-1.5 py-0.5 bg-gray-100 rounded text-xs text-gray-500 flex-shrink-0">${this._escapeHtml(field.property_type)}</span>
        </div>
        <button type="button" class="edit-field-btn p-1 text-gray-400 hover:text-indigo-600 rounded transition-colors flex-shrink-0">
          <svg class="size-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
          </svg>
        </button>
      </div>
      ${field.placeholder ? `<div class="mt-2 text-xs text-gray-400 italic">${this._escapeHtml(field.placeholder)}</div>` : ''}
    `

    // Setup event listeners
    element.addEventListener("dragstart", (e) => this._handleFieldDragStart(e, field))
    element.addEventListener("dragend", () => this._handleFieldDragEnd())
    element.addEventListener("dragover", (e) => this._handleFieldDragOver(e, field))
    element.addEventListener("drop", (e) => this._handleFieldDrop(e, field))

    const editBtn = element.querySelector('.edit-field-btn')
    editBtn.addEventListener("click", () => this._openFieldEditor(field))

    return element
  }

  _getFieldWidthClass(width) {
    switch (width) {
      case "half": return "w-1/2 inline-block align-top pr-2 "
      case "third": return "w-1/3 inline-block align-top pr-2 "
      default: return "w-full "
    }
  }

  _escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }

  // ===================
  // Drop Zone Setup
  // ===================

  _setupDropZone() {
    // Drop zone listeners are set via data-action attributes in HTML
  }

  dragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "copy"
  }

  dragEnter(event) {
    event.preventDefault()
    if (this.hasDropZoneTarget) {
      this.dropZoneTarget.classList.add("border-indigo-400", "bg-indigo-50")
    }
  }

  dragLeave(event) {
    if (!event.currentTarget.contains(event.relatedTarget)) {
      if (this.hasDropZoneTarget) {
        this.dropZoneTarget.classList.remove("border-indigo-400", "bg-indigo-50")
      }
    }
  }

  drop(event) {
    event.preventDefault()
    if (this.hasDropZoneTarget) {
      this.dropZoneTarget.classList.remove("border-indigo-400", "bg-indigo-50")
    }

    try {
      const dragData = JSON.parse(event.dataTransfer.getData("application/json"))
      this._addField(dragData)
    } catch {
      // Invalid drop data
    }
  }

  // ===================
  // Field Management
  // ===================

  _addField(propertyData) {
    const field = {
      id: `field_${this._generateId()}`,
      property_slug: propertyData.propertySlug,
      property_type: propertyData.propertyType,
      label: propertyData.propertyName,
      placeholder: this.fieldPlaceholderFormatValue.replace("{name}", propertyData.propertyName.toLowerCase()),
      required: false,
      width: "full",
      order: this.fields.length
    }

    this._saveState()
    this.fields.push(field)
    this._renderFields()
    this._markChanged()
  }

  addFieldFromPalette(propertyData) {
    this._addField(propertyData)
  }

  updateField(fieldId, updates) {
    this._saveState()
    const fieldIndex = this.fields.findIndex(f => f.id === fieldId)
    if (fieldIndex !== -1) {
      this.fields[fieldIndex] = { ...this.fields[fieldIndex], ...updates }
      this._renderFields()
      this._markChanged()
    }
  }

  removeField(fieldId) {
    this._saveState()
    this.fields = this.fields.filter(f => f.id !== fieldId)
    this._renderFields()
    this._markChanged()
  }

  _reorderFields(fromIndex, toIndex) {
    if (fromIndex === toIndex) return

    this._saveState()
    const [removed] = this.fields.splice(fromIndex, 1)
    this.fields.splice(toIndex, 0, removed)

    // Update order values
    this.fields.forEach((field, index) => {
      field.order = index
    })

    this._renderFields()
    this._markChanged()
  }

  // ===================
  // Field Drag & Drop (Reordering)
  // ===================

  _handleFieldDragStart(event, field) {
    this.draggedField = field
    event.target.style.opacity = "0.5"
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", field.id)
  }

  _handleFieldDragEnd() {
    this.draggedField = null
    const fields = this.fieldsContainerTarget.querySelectorAll('[data-field-id]')
    fields.forEach(el => el.style.opacity = "")
  }

  _handleFieldDragOver(event, field) {
    event.preventDefault()
    if (!this.draggedField || this.draggedField.id === field.id) return

    const rect = event.currentTarget.getBoundingClientRect()
    const midpoint = rect.top + rect.height / 2

    if (event.clientY < midpoint) {
      event.currentTarget.style.borderTop = "2px solid #6366f1"
      event.currentTarget.style.borderBottom = ""
    } else {
      event.currentTarget.style.borderBottom = "2px solid #6366f1"
      event.currentTarget.style.borderTop = ""
    }
  }

  _handleFieldDrop(event, field) {
    event.preventDefault()
    event.currentTarget.style.borderTop = ""
    event.currentTarget.style.borderBottom = ""

    if (!this.draggedField || this.draggedField.id === field.id) return

    const fromIndex = this.fields.findIndex(f => f.id === this.draggedField.id)
    const toIndex = this.fields.findIndex(f => f.id === field.id)

    this._reorderFields(fromIndex, toIndex)
  }

  _setupFieldListeners() {
    // Clear border styling on drop zone leave
    this.element.addEventListener("dragleave", (e) => {
      if (e.target.dataset?.fieldId) {
        e.target.style.borderTop = ""
        e.target.style.borderBottom = ""
      }
    })
  }

  // ===================
  // Field Editor
  // ===================

  _openFieldEditor(field) {
    const event = new CustomEvent("openFieldEditor", {
      detail: { field },
      bubbles: true
    })
    this.element.dispatchEvent(event)
  }

  // ===================
  // Undo/Redo
  // ===================

  _saveState() {
    this.undoStack.push(JSON.stringify(this.fields))
    this.redoStack = []
    this._emitUndoRedoState()
  }

  undo() {
    if (this.undoStack.length === 0) return

    this.redoStack.push(JSON.stringify(this.fields))
    const previousState = this.undoStack.pop()
    this.fields = JSON.parse(previousState)
    this._renderFields()
    this._markChanged()
    this._emitUndoRedoState()
  }

  redo() {
    if (this.redoStack.length === 0) return

    this.undoStack.push(JSON.stringify(this.fields))
    const nextState = this.redoStack.pop()
    this.fields = JSON.parse(nextState)
    this._renderFields()
    this._markChanged()
    this._emitUndoRedoState()
  }

  _emitUndoRedoState() {
    this.element.dispatchEvent(new CustomEvent("undoRedoStateChanged", {
      detail: {
        canUndo: this.undoStack.length > 0,
        canRedo: this.redoStack.length > 0
      }
    }))
  }

  // ===================
  // Save
  // ===================

  async save() {
    const configuration = JSON.stringify({
      fields: this.fields,
      metadata: this.metadata
    })

    try {
      const response = await fetch(`/${this.customerIdValue}/admin/maintenance/pages/${this.idValue}/autosave`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": getCSRFToken(),
          "Accept": "application/json"
        },
        body: JSON.stringify({ page: { configuration } })
      })

      if (response.ok) {
        this.hasUnsavedChanges = false
        this.element.dispatchEvent(new CustomEvent("pageSaved"))
        return true
      } else {
        const data = await response.json()
        this.element.dispatchEvent(new CustomEvent("pageSaveError", {
          detail: { errors: data.errors }
        }))
        return false
      }
    } catch {
      this.element.dispatchEvent(new CustomEvent("pageSaveError", {
        detail: { errors: [this.networkErrorValue] }
      }))
      return false
    }
  }

  // ===================
  // Entity Change
  // ===================

  updateEntity(entityId, entityName, properties) {
    this._saveState()
    this.metadata = {
      ...this.metadata,
      entity_id: entityId,
      entity_name: entityName
    }
    this.entityPropertiesValue = properties
    this._markChanged()
  }

  // ===================
  // Utilities
  // ===================

  _generateId() {
    return Math.random().toString(36).substr(2, 9)
  }

  _markChanged() {
    this.hasUnsavedChanges = true
    this.element.dispatchEvent(new CustomEvent("pageChanged", {
      detail: { hasUnsavedChanges: true }
    }))
  }

  getConfiguration() {
    return {
      fields: this.fields,
      metadata: this.metadata
    }
  }
}
