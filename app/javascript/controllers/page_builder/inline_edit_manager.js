import { BaseManager } from "controllers/page_builder/base_manager"

export class InlineEditManager extends BaseManager {
  constructor(controller) {
    super(controller)
    this.isEditing = false
    this.editingFieldId = null
    this.editingProperty = null
    this.originalValue = null
  }

  startEdit(event) {
    event.stopPropagation()
    event.preventDefault()

    const card = event.currentTarget.closest("[data-field-id]")
    if (!card) return

    const fieldId = card.dataset.fieldId
    const property = event.currentTarget.dataset.inlineEditProperty || "label"
    const field = this.c.currentPageFields.find(f => f.id === fieldId)
    if (!field) return

    if (this.isEditing) this.cancelEdit()

    this.isEditing = true
    this.editingFieldId = fieldId
    this.editingProperty = property
    this.originalValue = field[property] || ""

    const el = event.currentTarget
    el.setAttribute("contenteditable", "true")
    el.classList.add("outline-none", "ring-1", "ring-indigo-300", "rounded", "px-0.5", "bg-white")
    el.focus()

    // Select all text
    const range = document.createRange()
    range.selectNodeContents(el)
    const sel = window.getSelection()
    sel.removeAllRanges()
    sel.addRange(range)

    // Show heading toolbar if editing a heading
    if (field.field_type === "heading") {
      this._showHeadingToolbar(el, field)
    }

    this._onKeydown = (e) => this._handleKeydown(e, el)
    this._onBlur = () => this._confirmEdit(el)
    el.addEventListener("keydown", this._onKeydown)
    el.addEventListener("blur", this._onBlur)
  }

  _handleKeydown(event, el) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      el.blur()
    } else if (event.key === "Escape") {
      event.preventDefault()
      this._cancelAndRestore(el)
    }
  }

  _confirmEdit(el) {
    if (!this.isEditing) return

    const newValue = el.textContent.trim()
    const field = this.c.currentPageFields.find(f => f.id === this.editingFieldId)

    if (field && newValue !== this.originalValue) {
      this.c.saveState()
      field[this.editingProperty] = newValue
      this.c.saveManager.markDirty()

      if (this.c.selectedFieldId === this.editingFieldId) {
        this.c.propertyManager.populatePropertyPanel(field)
      }
    }

    this._cleanupEditable(el)
  }

  _cancelAndRestore(el) {
    el.textContent = this.originalValue
    el.removeEventListener("blur", this._onBlur)
    this._cleanupEditable(el)
  }

  cancelEdit() {
    if (!this.isEditing) return
    const el = document.querySelector(`[data-field-id="${this.editingFieldId}"] [contenteditable="true"]`)
    if (el) this._cancelAndRestore(el)
    else this._resetState()
  }

  _cleanupEditable(el) {
    this._removeHeadingToolbar()
    el.removeAttribute("contenteditable")
    el.classList.remove("outline-none", "ring-1", "ring-indigo-300", "rounded", "px-0.5", "bg-white")
    el.removeEventListener("keydown", this._onKeydown)
    el.removeEventListener("blur", this._onBlur)
    this._resetState()
  }

  _resetState() {
    this.isEditing = false
    this.editingFieldId = null
    this.editingProperty = null
    this.originalValue = null
  }

  _showHeadingToolbar(el, field) {
    const toolbar = document.createElement("div")
    toolbar.className = "heading-level-toolbar absolute -top-8 left-0 bg-white rounded-lg shadow-lg border border-gray-200 px-1 py-0.5 flex items-center gap-0.5 z-50"

    ;["h2", "h3", "h4"].forEach(level => {
      const btn = document.createElement("button")
      btn.type = "button"
      btn.textContent = level.toUpperCase()
      btn.className = `px-2 py-0.5 text-xs rounded transition-colors ${
        field.heading_level === level
          ? "bg-indigo-100 text-indigo-700 font-semibold"
          : "text-gray-500 hover:bg-gray-100"
      }`
      btn.addEventListener("mousedown", (e) => {
        e.preventDefault()
        this.c.saveState()
        field.heading_level = level
        this.c.saveManager.markDirty()
        toolbar.querySelectorAll("button").forEach(b => {
          b.className = b === btn
            ? "px-2 py-0.5 text-xs rounded bg-indigo-100 text-indigo-700 font-semibold transition-colors"
            : "px-2 py-0.5 text-xs rounded text-gray-500 hover:bg-gray-100 transition-colors"
        })
      })
      toolbar.appendChild(btn)
    })

    el.closest("[data-field-id]").style.position = "relative"
    el.closest("[data-field-id]").appendChild(toolbar)
  }

  _removeHeadingToolbar() {
    document.querySelectorAll(".heading-level-toolbar").forEach(t => t.remove())
  }
}
