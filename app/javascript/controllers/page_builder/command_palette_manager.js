import { BaseManager } from "controllers/page_builder/base_manager"

export const FIELD_COMMANDS = [
  { type: "text", label: "Text Input", category: "Fields", badge: "T" },
  { type: "email", label: "Email", category: "Fields", badge: "E" },
  { type: "select", label: "Select", category: "Fields", badge: "S" },
  { type: "number", label: "Number", category: "Fields", badge: "#" },
  { type: "date", label: "Date", category: "Fields", badge: "D" },
  { type: "file", label: "File Upload", category: "Fields", badge: "F" },
  { type: "textarea", label: "Textarea", category: "Fields", badge: "A" },
  { type: "checkbox", label: "Checkbox", category: "Fields", badge: "C" },
  { type: "radio", label: "Radio", category: "Fields", badge: "R" },
  { type: "switch", label: "Switch", category: "Fields", badge: "W" },
  { type: "currency", label: "Currency", category: "Fields", badge: "$" },
  { type: "rating", label: "Rating", category: "Fields", badge: "*" },
  { type: "password", label: "Password", category: "Fields", badge: "P" },
  { type: "tel", label: "Phone", category: "Fields", badge: "H" },
  { type: "url", label: "URL", category: "Fields", badge: "U" },
  { type: "rich-text", label: "Rich Text", category: "Fields", badge: "X" },
  { type: "signature", label: "Signature", category: "Fields", badge: "G" }
]

export const LAYOUT_COMMANDS = [
  { type: "section", label: "Section", category: "Layout", badge: "S" },
  { type: "heading", label: "Heading", category: "Layout", badge: "H" },
  { type: "paragraph", label: "Paragraph", category: "Layout", badge: "P" },
  { type: "divider", label: "Divider", category: "Layout", badge: "D" },
  { type: "spacer", label: "Spacer", category: "Layout", badge: "V" },
  { type: "columns", label: "Columns", category: "Layout", badge: "C" },
  { type: "card", label: "Card", category: "Layout", badge: "R" },
  { type: "alert", label: "Alert", category: "Layout", badge: "A" },
  { type: "button", label: "Button", category: "Layout", badge: "B" },
  { type: "image", label: "Image", category: "Layout", badge: "I" },
  { type: "video", label: "Video", category: "Layout", badge: "V" },
  { type: "list", label: "List", category: "Layout", badge: "L" },
  { type: "code_block", label: "Code Block", category: "Layout", badge: "<" },
  { type: "progress_bar", label: "Progress Bar", category: "Layout", badge: "%" },
  { type: "quote", label: "Quote", category: "Layout", badge: "Q" },
  { type: "callout", label: "Callout", category: "Layout", badge: "!" }
]

export const ACTION_COMMANDS = [
  { type: "action", action: "duplicate", label: "Duplicate Field", category: "Actions", badge: "D" },
  { type: "action", action: "delete", label: "Delete Field", category: "Actions", badge: "X" },
  { type: "action", action: "copy", label: "Copy Field", category: "Actions", badge: "C" },
  { type: "action", action: "paste", label: "Paste Field", category: "Actions", badge: "V" },
  { type: "action", action: "undo", label: "Undo", category: "Actions", badge: "Z" },
  { type: "action", action: "redo", label: "Redo", category: "Actions", badge: "Y" },
  { type: "action", action: "preview", label: "Preview Form", category: "Actions", badge: "P" },
  { type: "action", action: "save", label: "Save Form", category: "Actions", badge: "S" }
]

const LAYOUT_TYPES = new Set([
  "section", "divider", "heading", "paragraph", "spacer",
  "alert", "image", "callout", "quote", "button", "video",
  "list", "code_block", "card", "progress_bar", "columns"
])

export class CommandPaletteManager extends BaseManager {
  constructor(controller) {
    super(controller)
    this._selectedIndex = 0
    this._results = []
    this._templateCommands = []
  }

  open() {
    if (!this.c.hasCommandPaletteTarget) return

    this.c.commandPaletteTarget.classList.remove("hidden")

    if (this.c.hasCommandPaletteInputTarget) {
      this.c.commandPaletteInputTarget.value = ""
      setTimeout(() => this.c.commandPaletteInputTarget.focus(), 50)
    }

    this._loadTemplates()
    this._selectedIndex = 0
    this._renderResults("")
  }

  close() {
    if (!this.c.hasCommandPaletteTarget) return
    this.c.commandPaletteTarget.classList.add("hidden")
    this._selectedIndex = 0
    this._results = []
  }

  filter(event) {
    const query = event.target.value.trim()
    this._selectedIndex = 0
    this._renderResults(query)
  }

  handleKeydown(event) {
    const { key } = event

    if (key === "ArrowDown") {
      event.preventDefault()
      this._selectedIndex = Math.min(this._selectedIndex + 1, this._results.length - 1)
      this._updateSelection()
      return
    }

    if (key === "ArrowUp") {
      event.preventDefault()
      this._selectedIndex = Math.max(this._selectedIndex - 1, 0)
      this._updateSelection()
      return
    }

    if (key === "Enter") {
      event.preventDefault()
      const cmd = this._results[this._selectedIndex]
      if (cmd) this._execute(cmd)
      return
    }

    if (key === "Escape") {
      event.preventDefault()
      this.close()
      return
    }
  }

  executeFromClick(event) {
    const el = event.currentTarget
    const index = parseInt(el.dataset.resultIndex, 10)
    const cmd = this._results[index]
    if (cmd) this._execute(cmd)
  }

  // --- Private ---

  // Translated display label for a built-in command — templates already carry
  // their (untranslated, tenant-authored) name and action commands are keyed
  // by `action` rather than `type`. Falls back to the command's English
  // default (the FIELD_COMMANDS/LAYOUT_COMMANDS/ACTION_COMMANDS constants).
  _displayLabel(cmd) {
    if (cmd.type === "action") return this.c.actionCommandLabelsValue[cmd.action] || cmd.label
    if (cmd.type === "template") return cmd.label
    const map = LAYOUT_TYPES.has(cmd.type) ? this.c.layoutCommandLabelsValue : this.c.fieldCommandLabelsValue
    return map[cmd.type] || cmd.label
  }

  _categoryLabel(category) {
    return this.c.commandCategoryLabelsValue[category] || category
  }

  _loadTemplates() {
    const customerId = this.c.customerIdValue
    if (!customerId) return

    fetch(`/${customerId}/admin/maintenance/pages/field_templates.json`, {
      headers: { "Accept": "application/json" }
    })
      .then(r => r.ok ? r.json() : [])
      .then(templates => {
        this._templateCommands = (templates || []).map(t => ({
          type: "template",
          label: t.name || this.c.untitledTemplateLabelValue,
          category: "Templates",
          badge: "T",
          template: t
        }))
        // Re-render if palette is still open
        if (this.c.hasCommandPaletteTarget && !this.c.commandPaletteTarget.classList.contains("hidden")) {
          const query = this.c.hasCommandPaletteInputTarget ? this.c.commandPaletteInputTarget.value.trim() : ""
          this._renderResults(query)
        }
      })
      .catch(() => {
        this._templateCommands = []
      })
  }

  _renderResults(query) {
    if (!this.c.hasCommandPaletteResultsTarget) return

    const allCommands = [
      ...FIELD_COMMANDS,
      ...LAYOUT_COMMANDS,
      ...this._templateCommands,
      ...ACTION_COMMANDS
    ]

    const lowerQuery = query.toLowerCase()
    const filtered = query === ""
      ? allCommands
      : allCommands.filter(cmd => this._fuzzyMatch(this._displayLabel(cmd).toLowerCase(), lowerQuery))

    this._results = filtered

    if (filtered.length === 0) {
      this.c.commandPaletteResultsTarget.innerHTML = `
        <div class="py-8 text-center text-sm text-gray-400">${this.escapeHtml(this.c.noResultsFoundLabelValue)}</div>
      `
      return
    }

    // Group by category
    const groups = {}
    const groupOrder = []
    for (const cmd of filtered) {
      if (!groups[cmd.category]) {
        groups[cmd.category] = []
        groupOrder.push(cmd.category)
      }
      groups[cmd.category].push(cmd)
    }

    let globalIndex = 0
    const html = groupOrder.map(category => {
      const items = groups[category].map(cmd => {
        const isSelected = globalIndex === this._selectedIndex
        const idx = globalIndex
        globalIndex++
        return `
          <button type="button"
                  class="w-full flex items-center gap-3 px-3 py-2 rounded-lg text-left transition-colors ${isSelected ? "bg-indigo-50 text-indigo-700" : "text-gray-700 hover:bg-gray-50"}"
                  data-result-index="${idx}"
                  data-action="click->page-builder#executeCommandPaletteResult">
            <span class="flex items-center justify-center w-5 h-5 rounded bg-gray-100 text-[10px] font-bold text-gray-500 flex-shrink-0">${this.escapeHtml(cmd.badge)}</span>
            <span class="text-sm font-medium truncate">${this.escapeHtml(this._displayLabel(cmd))}</span>
          </button>
        `
      }).join("")

      return `
        <div class="mb-2">
          <div class="px-3 py-1 text-[10px] font-bold text-gray-400 uppercase tracking-wider">${this.escapeHtml(this._categoryLabel(category))}</div>
          ${items}
        </div>
      `
    }).join("")

    this.c.commandPaletteResultsTarget.innerHTML = html
  }

  _updateSelection() {
    if (!this.c.hasCommandPaletteResultsTarget) return

    const buttons = this.c.commandPaletteResultsTarget.querySelectorAll("[data-result-index]")
    buttons.forEach((btn, _i) => {
      const idx = parseInt(btn.dataset.resultIndex, 10)
      if (idx === this._selectedIndex) {
        btn.classList.add("bg-indigo-50", "text-indigo-700")
        btn.classList.remove("text-gray-700", "hover:bg-gray-50")
        btn.scrollIntoView({ block: "nearest" })
      } else {
        btn.classList.remove("bg-indigo-50", "text-indigo-700")
        btn.classList.add("text-gray-700", "hover:bg-gray-50")
      }
    })
  }

  _execute(cmd) {
    this.close()

    if (cmd.type === "action") {
      this._executeAction(cmd.action)
      return
    }

    if (cmd.type === "template") {
      this._insertTemplate(cmd.template)
      return
    }

    // Field or Layout insertion
    const isLayout = LAYOUT_TYPES.has(cmd.type)
    const fieldData = {
      type: cmd.type,
      label: cmd.label,
      propertySlug: "",
      propertyType: isLayout ? "layout" : undefined
    }

    const index = this.c.selectedFieldId
      ? this.c.currentPageFields.findIndex(f => f.id === this.c.selectedFieldId) + 1
      : this.c.currentPageFields.length

    this.c.fieldManager.addFieldAtIndex(fieldData, index)
  }

  _executeAction(action) {
    switch (action) {
      case "duplicate":
        this.c.clipboardManager.duplicateSelected()
        break
      case "delete":
        this.c.fieldManager.deleteField()
        break
      case "copy":
        this.c.clipboardManager.copy()
        break
      case "paste":
        this.c.clipboardManager.paste()
        break
      case "undo":
        this.c.undoRedoManager.undo()
        break
      case "redo":
        this.c.undoRedoManager.redo()
        break
      case "preview":
        this.c.saveManager.preview()
        break
      case "save":
        this.c.saveManager.save()
        break
    }
  }

  _insertTemplate(template) {
    if (!template || !template.configuration) return

    const config = JSON.parse(JSON.stringify(template.configuration))

    // Build the base field data from the template configuration...
    const fieldData = {
      type: config.field_type || config.type || "text",
      label: config.label || template.name || this.c.templateFieldFallbackLabelValue,
      propertySlug: "",
      propertyType: config.property_type || undefined,
      htmlType: config.html_type || undefined
    }

    const index = this.c.selectedFieldId
      ? this.c.currentPageFields.findIndex(f => f.id === this.c.selectedFieldId) + 1
      : this.c.currentPageFields.length

    // ...and pass the full saved config as overrides so the preset keeps its
    // validation, options, placeholder, defaults and type-specific settings
    // (previously everything but type/label/html_type was silently dropped).
    this.c.fieldManager.addFieldAtIndex(fieldData, index, config)
  }

  _fuzzyMatch(text, query) {
    if (query === "") return true
    if (text.includes(query)) return true

    let queryIdx = 0
    for (let i = 0; i < text.length && queryIdx < query.length; i++) {
      if (text[i] === query[queryIdx]) queryIdx++
    }
    return queryIdx === query.length
  }
}
