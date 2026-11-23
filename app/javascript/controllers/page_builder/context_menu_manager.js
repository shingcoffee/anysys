import { BaseManager } from "controllers/page_builder/base_manager"

export class ContextMenuManager extends BaseManager {
  constructor(controller) {
    super(controller)
    this._onClickOutside = (e) => {
      if (!e.target.closest("[data-page-builder-target='contextMenu']")) this.close()
    }
    this._currentItems = []
  }

  openForField(event) {
    event.preventDefault()
    event.stopPropagation()

    const card = event.currentTarget.closest("[data-field-id]")
    if (!card) return

    const fieldId = card.dataset.fieldId
    const field = this.c.allFields.find(f => f.id === fieldId)
    if (!field) return

    // Select the field if not already selected
    if (!this.c.selectionManager.isSelected(fieldId)) {
      this.c.selectionManager.selectField(fieldId, { shift: false, meta: false })
    }

    const items = this._fieldMenuItems(field)
    this._show(event.clientX, event.clientY, items)
  }

  openForCanvas(event) {
    event.preventDefault()
    if (event.target.closest("[data-field-id]")) return

    const hasClipboard = this.c.clipboardManager.clipboard.length > 0
    const pasteLabel = this.c.pasteActionTitleValue
    const items = [
      hasClipboard
        ? { label: pasteLabel, shortcut: "Ctrl+V", action: () => this.c.clipboardManager.paste() }
        : { label: pasteLabel, shortcut: "Ctrl+V", disabled: true },
      { type: "divider" },
      { label: this.c.addFieldActionTitleValue, action: () => this.c.commandPaletteManager.open() },
      { label: this.c.selectAllActionTitleValue, shortcut: "Ctrl+A", action: () => this.c.selectionManager.selectAll() }
    ]
    this._show(event.clientX, event.clientY, items)
  }

  close() {
    if (this.c.hasContextMenuTarget) {
      this.c.contextMenuTarget.classList.add("hidden")
    }
    document.removeEventListener("click", this._onClickOutside)
    document.removeEventListener("contextmenu", this._onClickOutside)
    this._currentItems = []
  }

  _fieldMenuItems(field) {
    const isGroup = field.type === "field_group"
    const hasClipboard = this.c.clipboardManager.clipboard.length > 0
    const pasteAfterLabel = this.c.pasteAfterActionTitleValue

    const items = [
      { label: this.c.editLabelActionTitleValue, action: () => this._triggerInlineEdit(field) },
      { label: this.c.actionDuplicateTitleValue, shortcut: "Ctrl+D", action: () => this.c.clipboardManager.duplicateSelected() },
      { label: this.c.copyActionTitleValue, shortcut: "Ctrl+C", action: () => this.c.clipboardManager.copy() },
      { label: this.c.cutActionTitleValue, shortcut: "Ctrl+X", action: () => this.c.clipboardManager.cut() },
      hasClipboard
        ? { label: pasteAfterLabel, shortcut: "Ctrl+V", action: () => this.c.clipboardManager.paste() }
        : { label: pasteAfterLabel, shortcut: "Ctrl+V", disabled: true },
      { type: "divider" },
      { label: this.c.widthMenuTitleValue, submenu: [
        { label: this.c.widthFullLabelValue, action: () => this._setWidth(field, "full") },
        { label: "3/4", action: () => this._setWidth(field, "three_quarters") },
        { label: "2/3", action: () => this._setWidth(field, "two_thirds") },
        { label: this.c.widthHalfLabelValue, action: () => this._setWidth(field, "half") },
        { label: "1/3", action: () => this._setWidth(field, "third") },
        { label: "1/4", action: () => this._setWidth(field, "quarter") }
      ]},
      { type: "divider" },
      { label: this.c.saveAsTemplateLabelValue, action: () => this.c.fieldManager.saveFieldAsTemplate({ currentTarget: { dataset: { fieldId: field.id } }, stopPropagation: () => {} }) },
      { type: "divider" },
      { label: this.c.actionDeleteTitleValue, shortcut: "Del", danger: true, action: () => this.c.fieldManager.deleteField() }
    ]

    if (isGroup) {
      // Insert "Ungroup" before the last divider+delete
      items.splice(items.length - 2, 0, {
        label: this.c.ungroupLabelValue, action: () => this.c.fieldManager.ungroupFields({
          currentTarget: { dataset: { groupId: field.id } }, stopPropagation: () => {}
        })
      })
    }

    return items
  }

  _show(x, y, items) {
    if (!this.c.hasContextMenuTarget || !this.c.hasContextMenuContentTarget) return

    this._currentItems = items
    const menu = this.c.contextMenuTarget
    const content = this.c.contextMenuContentTarget

    content.innerHTML = items.map((item, idx) => {
      if (item.type === "divider") return '<hr class="my-1 border-gray-100">'
      if (item.disabled) {
        return `<div class="px-3 py-1.5 text-gray-300 cursor-not-allowed flex justify-between">
          <span>${item.label}</span>${item.shortcut ? `<span class="text-[10px]">${item.shortcut}</span>` : ""}
        </div>`
      }
      if (item.submenu) {
        return `<div class="relative group/sub">
          <div class="px-3 py-1.5 text-gray-700 hover:bg-gray-50 flex justify-between cursor-pointer">
            <span>${item.label}</span>
            <svg class="w-3 h-3 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/></svg>
          </div>
          <div class="hidden group-hover/sub:block absolute left-full top-0 bg-white rounded-lg shadow-xl border border-gray-200 py-1 w-32">
            ${item.submenu.map((sub, si) =>
              `<button type="button" class="w-full px-3 py-1.5 text-left text-gray-700 hover:bg-gray-50" data-context-action="${idx}_${si}">${sub.label}</button>`
            ).join("")}
          </div>
        </div>`
      }
      const cls = item.danger ? "text-red-600 hover:bg-red-50" : "text-gray-700 hover:bg-gray-50"
      return `<button type="button" class="w-full px-3 py-1.5 text-left ${cls} flex justify-between" data-context-action="${idx}">
        <span>${item.label}</span>${item.shortcut ? `<span class="text-[10px] text-gray-400">${item.shortcut}</span>` : ""}
      </button>`
    }).join("")

    // Attach click handlers
    content.querySelectorAll("[data-context-action]").forEach(btn => {
      btn.addEventListener("click", () => {
        const parts = btn.dataset.contextAction.split("_")
        const item = this._currentItems[parseInt(parts[0])]
        if (parts.length === 2 && item.submenu) {
          item.submenu[parseInt(parts[1])].action?.()
        } else {
          item.action?.()
        }
        this.close()
      })
    })

    // Position within viewport
    menu.style.left = `${Math.min(x, window.innerWidth - 200)}px`
    menu.style.top = `${Math.min(y, window.innerHeight - 300)}px`
    menu.classList.remove("hidden")

    setTimeout(() => {
      document.addEventListener("click", this._onClickOutside)
      document.addEventListener("contextmenu", this._onClickOutside)
    }, 0)
  }

  _setWidth(field, width) {
    this.c.saveState()
    // Match the resize handle: on a non-desktop viewport write the per-breakpoint
    // override instead of clobbering the desktop width.
    const viewport = this.c.viewportValue || "desktop"
    if (viewport === "desktop") {
      field.width = width
      field.width_explicit = true
    } else {
      if (!field.responsive_widths) field.responsive_widths = {}
      field.responsive_widths[viewport] = width
    }
    this.c.fieldManager.renderFields()
    this.c.saveManager.markDirty()
    this.close()
  }

  _triggerInlineEdit(field) {
    this.close()
    const card = this.c.fieldsContainerTarget.querySelector(`[data-field-id="${field.id}"]`)
    const editable = card?.querySelector("[data-inline-edit-property]")
    if (editable) editable.dispatchEvent(new MouseEvent("dblclick", { bubbles: true }))
  }
}
