/**
 * WidthBreakpointMixin provides toolbar width management and responsive
 * breakpoint switching for the property panel.
 * Apply to a class using Object.assign(YourClass.prototype, WidthBreakpointMixin)
 */
export const WidthBreakpointMixin = {
  setFieldWidth(event) {
    const width = event.currentTarget.dataset.width
    if (!width) return

    // Apply to every selected field so the toolbar width icons work for a
    // multi-selection, not just the single-selected field.
    const selected = this.c.selectionManager.getSelectedFields()
    if (selected.length === 0) return

    // Debounce so rapidly toggling width doesn't push N identical entries
    // onto the undo stack — matches the pattern used in updateFieldProperty.
    if (!this._widthUndoTimer) {
      this.c.undoRedoManager.saveState()
    } else {
      clearTimeout(this._widthUndoTimer)
    }
    this._widthUndoTimer = setTimeout(() => { this._widthUndoTimer = null }, 500)

    const bp = this._activeBreakpoint || "desktop"
    selected.forEach(field => {
      if (bp === "desktop") {
        field.width = width
        field.width_explicit = true
      } else {
        if (!field.responsive_widths) field.responsive_widths = {}
        field.responsive_widths[bp] = width
      }
    })

    this.c.fieldManager.renderFields()
    // Reflect the value actually edited only for a single selection; a
    // multi-selection has no single "active" width to highlight.
    if (selected.length === 1) {
      if (bp === "desktop") {
        this.syncToolbarWidth(selected[0])
      } else {
        this._syncWidthButtonsForBreakpoint(selected[0], width)
      }
    } else {
      this.c.selectionManager.updateVisuals()
    }
    this.c.saveManager.markDirty()
  },

  syncToolbarWidth(field) {
    if (!this.c.hasToolbarWidthGroupTarget) return
    this.c.toolbarWidthGroupTarget.classList.remove("opacity-30", "cursor-not-allowed")

    const activeWidth = field.width || "full"
    this.c.toolbarWidthBtnTargets.forEach(btn => {
      const isActive = btn.dataset.width === activeWidth
      btn.classList.toggle("text-indigo-600", isActive)
      btn.classList.toggle("bg-indigo-50", isActive)
      btn.classList.toggle("text-gray-400", !isActive)
    })
  },

  resetToolbarWidth() {
    if (!this.c.hasToolbarWidthGroupTarget) return
    this.c.toolbarWidthGroupTarget.classList.add("opacity-30", "cursor-not-allowed")

    this.c.toolbarWidthBtnTargets.forEach(btn => {
      btn.classList.remove("text-indigo-600", "bg-indigo-50")
      btn.classList.add("text-gray-400")
    })
  },

  // Multi-selection has no single active width, so enable the toolbar width
  // group (clicking applies to all selected) without highlighting one option.
  enableToolbarWidthForMulti() {
    if (!this.c.hasToolbarWidthGroupTarget) return
    this.c.toolbarWidthGroupTarget.classList.remove("opacity-30", "cursor-not-allowed")
    this.c.toolbarWidthBtnTargets.forEach(btn => {
      btn.classList.remove("text-indigo-600", "bg-indigo-50")
      btn.classList.add("text-gray-400")
    })
  },

  switchBreakpoint(event) {
    const bp = event.currentTarget.dataset.breakpoint
    this._activeBreakpoint = bp

    const selector = this.c.floatingPanelTarget.querySelector("[data-page-builder-target='breakpointSelector']")
    if (selector) {
      selector.querySelectorAll("[data-breakpoint]").forEach(btn => {
        const active = btn.dataset.breakpoint === bp
        btn.classList.toggle("border-indigo-300", active)
        btn.classList.toggle("bg-indigo-50", active)
        btn.classList.toggle("text-indigo-600", active)
        btn.classList.toggle("border-gray-200", !active)
        btn.classList.toggle("text-gray-500", !active)
      })
    }

    const field = this.c.currentPageFields.find(f => f.id === this.c.selectedFieldId)
    if (field) {
      const width = bp === "desktop" ? (field.width || "full") : (field.responsive_widths?.[bp] || null)
      this._syncWidthButtonsForBreakpoint(field, width)

      const resetLink = this.c.floatingPanelTarget.querySelector("[data-page-builder-target='resetBreakpoint']")
      if (resetLink) {
        resetLink.classList.toggle("hidden", bp === "desktop" || !field.responsive_widths?.[bp])
      }
    }
  },

  _syncWidthButtonsForBreakpoint(field, width) {
    const activeWidth = width || this._inheritedWidth(field)
    this.c.toolbarWidthBtnTargets?.forEach(btn => {
      const isActive = btn.dataset.width === activeWidth
      btn.classList.toggle("text-indigo-600", isActive)
      btn.classList.toggle("bg-indigo-50", isActive)
      btn.classList.toggle("text-gray-400", !isActive)
      btn.classList.toggle("bg-transparent", !isActive)
    })

    // Also update width buttons in the layout tab
    const layoutTab = this.c.floatingPanelTarget.querySelector("[data-property-tab-content='layout']")
    if (layoutTab) {
      layoutTab.querySelectorAll("[data-width]").forEach(btn => {
        const isActive = btn.dataset.width === activeWidth
        btn.classList.toggle("border-indigo-500", isActive)
        btn.classList.toggle("text-indigo-600", isActive)
        btn.classList.toggle("bg-indigo-50", isActive)
        btn.classList.toggle("border-gray-200", !isActive)
        btn.classList.toggle("text-gray-500", !isActive)
      })
    }
  },

  _inheritedWidth(field) {
    const bp = this._activeBreakpoint
    if (bp === "mobile" && field.responsive_widths?.tablet) return field.responsive_widths.tablet
    return field.width || "full"
  },

  resetBreakpointWidth(event) {
    event.preventDefault()
    const field = this.c.currentPageFields.find(f => f.id === this.c.selectedFieldId)
    if (!field || !field.responsive_widths) return

    const bp = this._activeBreakpoint
    if (bp === "desktop") return

    this.c.undoRedoManager.saveState()
    delete field.responsive_widths[bp]
    if (Object.keys(field.responsive_widths).length === 0) delete field.responsive_widths
    this.c.fieldManager.renderFields()
    this.c.saveManager.markDirty()
  }
}
