import { BaseManager } from "controllers/page_builder/base_manager"

export class KeyboardManager extends BaseManager {
  bindKeyboardShortcuts() {
    this.c.boundHandleKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.c.boundHandleKeydown)
  }

  unbindKeyboardShortcuts() {
    document.removeEventListener("keydown", this.c.boundHandleKeydown)
  }

  bindClickOutside() {
    this.c.boundHandleClickOutside = this.handleClickOutside.bind(this)
    document.addEventListener("click", this.c.boundHandleClickOutside)
  }

  unbindClickOutside() {
    document.removeEventListener("click", this.c.boundHandleClickOutside)
  }

  handleClickOutside(event) {
    // Close inserter popover when clicking outside
    if (this.c.inserterManager?.isPopoverOpen()) {
      const insidePopover = this.c.hasInserterPopoverTarget && this.c.inserterPopoverTarget.contains(event.target)
      const isInserterButton = event.target.closest("[data-action*='openInserterPopover']") ||
                               event.target.closest("[data-action*='openFullCatalog']")
      if (!insidePopover && !isInserterButton) {
        this.c.inserterManager.closePopover()
      }
    }

    // Close tab panels when clicking outside
    const hasActiveTabPanel = this.c.tabPanelTargets.some(panel => !panel.classList.contains("hidden"))
    if (hasActiveTabPanel) {
      if (!event.target.closest('[data-page-builder-target="tabButton"]')) {
        const clickedInsidePanel = this.c.tabPanelTargets.some(panel => {
          return !panel.classList.contains("hidden") && panel.contains(event.target)
        })

        if (!clickedInsidePanel) {
          this.c.tabManager.closeAllTabPanels()
        }
      }
    }

    // Close property panel when clicking outside field cards and the panel itself.
    // The left sidebar is treated as "still inside the editor" — users often grab
    // the next field from the palette and we shouldn't wipe their selection.
    const sm = this.c.selectionManager
    if (!sm.isEmpty && this.c.propertyManager.isFloatingPanelVisible()) {
      const clickedFieldCard = event.target.closest(".field-card")
      const clickedFloatingPanel = this.c.hasFloatingPanelTarget && this.c.floatingPanelTarget.contains(event.target)
      const clickedToolbarWidth = this.c.hasToolbarWidthGroupTarget && this.c.toolbarWidthGroupTarget.contains(event.target)
      const clickedMoveModal = event.target.closest("[data-move-modal-content]")
      const clickedLeftSidebar = this.c.hasLeftSidebarTarget && this.c.leftSidebarTarget.contains(event.target)
      const clickedQuickAdd = this.c.hasQuickAddToolbarTarget && this.c.quickAddToolbarTarget.contains(event.target)

      if (!clickedFieldCard && !clickedFloatingPanel && !clickedToolbarWidth &&
          !clickedMoveModal && !clickedLeftSidebar && !clickedQuickAdd) {
        this.c.fieldManager.deselectField()
      }
    }
  }

  handleKeydown(event) {
    const { key, ctrlKey, metaKey, shiftKey } = event
    const modKey = ctrlKey || metaKey

    // Ctrl/Cmd+S must always work, even when focus is in an input, so that the
    // browser's native "save page" dialog never appears inside the builder.
    if (modKey && key === "s") {
      event.preventDefault()
      this.c.saveManager.save()
      return
    }

    if (this._isInInput(event)) return

    if (modKey && key === "c") {
      event.preventDefault()
      this.c.clipboardManager.copy()
      return
    }

    if (modKey && key === "v") {
      event.preventDefault()
      this.c.clipboardManager.paste()
      return
    }

    if (modKey && key === "x") {
      event.preventDefault()
      this.c.clipboardManager.cut()
      return
    }

    if (modKey && key === "d") {
      event.preventDefault()
      this.c.clipboardManager.duplicateSelected()
      return
    }

    // Ctrl+K — field search on canvas (Ctrl+F left to the browser for native find)
    if (modKey && key === "k") {
      event.preventDefault()
      this.c.zoomManager.openSearch()
      return
    }

    // Ctrl+Plus — zoom in
    if (modKey && (key === "=" || key === "+")) {
      event.preventDefault()
      this.c.zoomManager.zoomIn()
      return
    }

    // Ctrl+Minus — zoom out
    if (modKey && key === "-") {
      event.preventDefault()
      this.c.zoomManager.zoomOut()
      return
    }

    // Ctrl+0 — zoom reset
    if (modKey && key === "0") {
      event.preventDefault()
      this.c.zoomManager.zoomReset()
      return
    }

    if (modKey && key === "z" && !shiftKey) {
      event.preventDefault()
      this.c.undoRedoManager.undo()
      return
    }

    if (modKey && key === "z" && shiftKey) {
      event.preventDefault()
      this.c.undoRedoManager.redo()
      return
    }

    // Ctrl+Y — redo (Windows convention; complements Ctrl+Shift+Z)
    if (modKey && key === "y") {
      event.preventDefault()
      this.c.undoRedoManager.redo()
      return
    }

    // Select all: Ctrl/Cmd + A
    if (modKey && key === "a") {
      event.preventDefault()
      this.c.selectionManager.selectAll()
      return
    }

    if (key === "Delete" || key === "Backspace") {
      if (!this.c.selectionManager.isEmpty) {
        event.preventDefault()
        this.c.fieldManager.deleteField()
      }
      return
    }

    // Arrow key navigation between field cards — only when a field is selected
    // or the canvas is the focused/hovered context. Prevents hijacking scrolls
    // when the user is just browsing the sidebar.
    if (key === "ArrowDown" || key === "ArrowUp") {
      const sm = this.c.selectionManager
      const canvasHasFocus = this.c.hasCanvasAreaTarget && this.c.canvasAreaTarget.contains(document.activeElement)
      if (!sm.isEmpty || canvasHasFocus) {
        event.preventDefault()
        this.navigateFields(key === "ArrowDown" ? 1 : -1)
      }
      return
    }

    if (key === "Escape") {
      // Close context menu first
      if (this.c.hasContextMenuTarget && !this.c.contextMenuTarget.classList.contains("hidden")) {
        this.c.contextMenuManager.close()
        return
      }

      // Close command palette first
      if (this.c.hasCommandPaletteTarget && !this.c.commandPaletteTarget.classList.contains("hidden")) {
        this.c.commandPaletteManager.close()
        return
      }

      // Close move-to-page modal first
      if (this.c.hasMoveToPageModalTarget && this.c.moveToPageModalTarget.innerHTML.trim()) {
        this.c.selectionManager.closeMoveToPageModal()
        return
      }

      // Close inserter popover
      if (this.c.inserterManager?.isPopoverOpen()) {
        this.c.inserterManager.closePopover()
        return
      }

      const hasActivePanel = this.c.tabPanelTargets.some(panel => !panel.classList.contains("hidden"))
      if (hasActivePanel) {
        this.c.tabManager.closeAllTabPanels()
        return
      }

      this.c.fieldManager.deselectField()
      return
    }

    // "/" shortcut opens command palette
    if (key === "/") {
      event.preventDefault()
      this.c.commandPaletteManager.open()
      return
    }

    if (key === "?") {
      event.preventDefault()
      this.showShortcuts()
      return
    }
  }

  navigateFields(direction) {
    const fields = this.c.fields
    if (!fields.length) return

    const sm = this.c.selectionManager

    if (sm.isEmpty) {
      const target = direction > 0 ? fields[0] : fields[fields.length - 1]
      this.c.fieldManager.selectFieldById(target.id)
      return
    }

    // Use last selected field as navigation anchor
    const anchorId = sm.lastSelectedFieldId || [...sm.selectedFieldIds][0]
    const currentIndex = fields.findIndex(f => f.id === anchorId)
    const nextIndex = currentIndex + direction

    if (nextIndex >= 0 && nextIndex < fields.length) {
      // Arrow navigation always clears multi-select and does single select
      this.c.fieldManager.selectFieldById(fields[nextIndex].id)

      const card = this.c.fieldsContainerTarget.querySelector(`[data-field-id="${fields[nextIndex].id}"]`)
      card?.scrollIntoView({ behavior: "smooth", block: "nearest" })
    }
  }

  showShortcuts() {
    if (this.c.hasShortcutsModalTarget) {
      this.c.shortcutsModalTarget.classList.remove("hidden")
    }
  }

  hideShortcuts() {
    if (this.c.hasShortcutsModalTarget) {
      this.c.shortcutsModalTarget.classList.add("hidden")
    }
  }

  _isInInput(event) {
    const tag = event.target.tagName
    return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || event.target.isContentEditable
  }
}
