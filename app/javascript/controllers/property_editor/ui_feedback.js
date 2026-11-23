/**
 * UiFeedbackMixin — save-button state transitions, field-error display,
 * problem navigation/highlighting, and tab badge updates. Apply with:
 *   Object.assign(PropertyEditorController.prototype, UiFeedbackMixin)
 */
export const UiFeedbackMixin = {
  /**
   * Navigate the freshly-opened editor to a validation problem: switch to the
   * problem's tab, then resolve the anchor selector inside the active pane
   * and highlight it.
   */
  _navigateToProblem({ tab, anchor, severity }) {
    const visibleTabs = this.tabManager.tabBarContainer?.querySelectorAll(`button[data-tab="${tab}"]`)
    if (tab && visibleTabs?.length) this.tabManager.switchTo(tab)
    if (!anchor) return
    let attempts = 0
    const tryResolve = () => {
      const pane = this.tabManager.getPane(this.tabManager.activeTab) || this.formTarget
      const target = pane?.querySelector(anchor)
      if (target) {
        this._revealFieldWrap(target)
        return this._highlightProblemField(target, severity)
      }
      if (++attempts < 15) setTimeout(tryResolve, 100)
    }
    tryResolve()
  },

  _highlightProblemField(target, severity) {
    const ringClasses = severity === "warning"
      ? ["ring-2", "ring-yellow-400", "ring-offset-1"]
      : ["ring-2", "ring-red-400", "ring-offset-1"]
    target.scrollIntoView({ behavior: "smooth", block: "center" })
    clearTimeout(this._problemHighlightTimer)
    if (this._problemHighlightTarget) {
      this._problemHighlightTarget.classList.remove("ring-2", "ring-yellow-400", "ring-red-400", "ring-offset-1")
    }
    this._problemHighlightTarget = target
    target.classList.add(...ringClasses, "transition-shadow", "duration-300", "rounded")
    this._problemHighlightTimer = setTimeout(() => {
      target.classList.remove(...ringClasses)
      if (this._problemHighlightTarget === target) this._problemHighlightTarget = null
    }, 2000)
  },

  /**
   * Paint `data-field-error` + `aria-invalid` under a field by name, and
   * (unless `reveal` is false) reveal the tab / details / disclosure that holds it.
   * @param {string} name
   * @param {string} message
   * @param {{reveal?: boolean}} [options]
   */
  paintFieldError(name, message, { reveal = true } = {}) {
    if (!name || !this.hasFormTarget) return
    const wrap = this._fieldWrap(name)
    if (!wrap) return
    const input = this._fieldInput(wrap, name)
    if (input) input.setAttribute("aria-invalid", "true")
    let err = wrap.querySelector("[data-field-error]")
    if (!err) {
      err = document.createElement("p")
      err.setAttribute("data-field-error", "")
      err.className = "mt-0.5 text-xs text-red-600"
      wrap.appendChild(err)
    }
    err.textContent = message || ""
    if (reveal) this._revealFieldWrap(wrap)
  },

  clearFieldError(name) {
    if (!name || !this.hasFormTarget) return
    const wrap = this._fieldWrap(name)
    if (!wrap) return
    wrap.querySelectorAll("[aria-invalid]").forEach((el) => el.removeAttribute("aria-invalid"))
    wrap.querySelector("[data-field-error]")?.remove()
  },

  _clearElementFieldErrors() {
    if (!this.hasFormTarget) return
    this.formTarget.querySelectorAll("[data-element-field]").forEach((wrap) => {
      wrap.querySelectorAll("[aria-invalid]").forEach((el) => el.removeAttribute("aria-invalid"))
      wrap.querySelector("[data-field-error]")?.remove()
    })
  },

  _fieldWrap(name) {
    return this.formTarget.querySelector(`[data-element-field="${CSS.escape(name)}"]`)
      || this.formTarget.querySelector(`[name="${CSS.escape(name)}"]`)?.closest("[data-element-field], [data-config-field], div")
  },

  _fieldInput(wrap, name) {
    return wrap.querySelector(`[name="${CSS.escape(name)}"]`)
      || wrap.querySelector("[data-config-input], select, textarea, input:not([type='hidden'])")
  },

  _revealFieldWrap(wrap) {
    for (const tab of ["general", "steps", "branches", "io", "advanced"]) {
      if (tab === "branches" && this.currentElement?.type !== "decision") continue
      if (tab === "steps" && this.currentElement?.type === "decision") continue
      const pane = this.getFormFieldsForTab?.(tab)
      if (pane?.contains(wrap) && this.tabManager?.switchTo) {
        this.tabManager.switchTo(tab)
        break
      }
    }
    const details = wrap.closest("details")
    if (details) details.open = true
    let parent = wrap.parentElement
    while (parent && parent !== this.formTarget) {
      if (parent.hasAttribute("data-disclosure-body") && parent.classList.contains("hidden")) {
        const section = parent.closest("[data-disclosure]")
        if (section) this.toggleDisclosure({ preventDefault() {}, currentTarget: section })
      }
      parent = parent.parentElement
    }
  },

  /**
   * Apply `{ field, severity, message }` results. Rows without `field` stay
   * panel-only (ignored here).
   * @param {Array<{field?: string, severity?: string, message?: string}>} results
   * @param {{reveal?: boolean}} [options]
   */
  applyElementFieldProblems(results, options = {}) {
    this._clearElementFieldErrors()
    ;(results || []).forEach((result) => {
      if (!result?.field) return
      this.paintFieldError(result.field, result.message, options)
    })
  },

  _clearFieldErrorOnInput(event) {
    const name = event.target?.name
    if (name) this.clearFieldError(name)
    const wrap = event.target?.closest("[data-element-field]")
    if (wrap?.dataset.elementField) this.clearFieldError(wrap.dataset.elementField)
  },

  _clearSaveButtonTimer() {
    if (this._saveButtonTimer) {
      clearTimeout(this._saveButtonTimer)
      this._saveButtonTimer = null
    }
  },

  _showSaveSuccess() {
    if (!this.hasSaveButtonTarget) return

    this._clearSaveButtonTimer()
    this.saveButtonTarget.innerHTML = `
      <svg class="-ml-1 mr-2 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
      </svg>
      ${this.savedLabelValue}
    `
    this.saveButtonTarget.classList.remove("bg-indigo-600", "hover:bg-indigo-700", "bg-red-600", "hover:bg-red-700")
    this.saveButtonTarget.classList.add("bg-green-600", "hover:bg-green-700")

    this._saveButtonTimer = setTimeout(() => {
      this._saveButtonTimer = null
      this._resetSaveButton()
    }, 1500)
  },

  _showSaveError() {
    if (!this.hasSaveButtonTarget) return

    this._clearSaveButtonTimer()
    this.saveButtonTarget.innerHTML = `
      <svg class="-ml-1 mr-2 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
      </svg>
      ${this.errorLabelValue}
    `
    this.saveButtonTarget.classList.remove("bg-indigo-600", "hover:bg-indigo-700", "bg-green-600", "hover:bg-green-700")
    this.saveButtonTarget.classList.add("bg-red-600", "hover:bg-red-700")

    this._saveButtonTimer = setTimeout(() => {
      this._saveButtonTimer = null
      this._resetSaveButton()
    }, 2000)
  },

  _resetSaveButton() {
    if (!this.hasSaveButtonTarget) return

    this._clearSaveButtonTimer()
    this.saveButtonTarget.innerHTML = `
      <svg class="-ml-1 mr-2 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
      </svg>
      ${this.saveButtonLabelValue}
    `
    this.saveButtonTarget.classList.remove("bg-green-600", "hover:bg-green-700", "bg-red-600", "hover:bg-red-700")
    this.saveButtonTarget.classList.add("bg-indigo-600", "hover:bg-indigo-700")
  },

  _updateTabBadges() {
    if (!this.tabManager) return

    const counts = {}

    if (this.currentElement?.type === "process") {
      const container = this.formTarget?.querySelector("[data-steps-container]")
      counts.steps = container ? container.querySelectorAll("[data-step-item]").length : 0
    }

    if (this.currentElement?.type === "decision") {
      const container = this.formTarget?.querySelector("[data-branches-container]")
      counts.branches = container ? container.querySelectorAll("[data-branch-item]").length : 0
    }

    const pins = this.canvas?.getElementPins?.(this.currentElement?.id) || { inputs: [], outputs: [] }
    counts.inputs = pins.inputs?.length || 0
    counts.outputs = pins.outputs?.length || 0

    this.tabManager.updateBadges(counts)
  }
}
