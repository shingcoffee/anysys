/**
 * FieldVisibilityMixin — handles conditional field visibility (visibleWhen)
 * and step-card disclosure open/close toggling. Apply with:
 *   Object.assign(PropertyEditorController.prototype, FieldVisibilityMixin)
 */
import { matchesWhen } from "controllers/property_editor/controls/field_renderer"

export const FieldVisibilityMixin = {
  // Native constraint validation runs before submit. Reveal invalid controls
  // inside inactive tabs/collapsed cards so the browser can focus and explain
  // the failure instead of reporting an unfocusable control and trapping Save.
  _revealInvalidField(event) {
    const input = event.target
    for (const tab of ["general", "steps", "branches", "io", "advanced"]) {
      const pane = this.getFormFieldsForTab(tab)
      if (!pane?.contains(input)) continue
      if (tab === "branches" && this.currentElement?.type !== "decision") continue
      if (tab === "steps" && this.currentElement?.type === "decision") continue
      this.tabManager.switchTo(tab)
    }
    const step = input.closest("[data-step-item]")
    if (step) this.stepManager._setStepExpanded(step, true)
    const details = input.closest("details")
    if (details && !details.open) details.open = true
    let parent = input.parentElement
    while (parent && parent !== this.formTarget) {
      if (parent.hasAttribute("data-disclosure-body") && parent.classList.contains("hidden")) {
        const section = parent.closest("[data-disclosure]")
        this.toggleDisclosure({ preventDefault() {}, currentTarget: section })
      }
      parent = parent.parentElement
    }
  },

  /**
   * Single change handler for every control that drives visibleWhen fields.
   * Fields are CSS-hidden, never removed, so hidden values survive type switches.
   */
  handleVisibilityFieldChange(event) {
    const fieldName = event.target.name
    if (!fieldName || !this.hasFormTarget) return

    this._applyFieldVisibility()
    this._syncChangesToCanvas()
  },

  _visibilityValueBag() {
    const bag = {}
    this.formTarget.querySelectorAll("[name]").forEach((el) => {
      if (!el.name || el.name.includes("[")) return
      if (el.type === "checkbox") bag[el.name] = el.checked
      else bag[el.name] = el.value
    })
    return bag
  },

  _isVisibleFromDataset(field, bag) {
    const raw = field.dataset.visibleWhen
    if (!raw) return true
    if (raw.trim().startsWith("{")) {
      try { return matchesWhen(JSON.parse(raw), bag) } catch { return true }
    }
    const visibleValues = (field.dataset.visibleValues || "").split(",")
    return visibleValues.includes(String(bag[raw] ?? ""))
  },

  _applyFieldVisibility(fieldName, selectedValue) {
    const bag = this._visibilityValueBag()
    if (fieldName && selectedValue !== undefined) bag[fieldName] = selectedValue
    this.formTarget.querySelectorAll("[data-visible-when]").forEach((field) => {
      const visible = this._isVisibleFromDataset(field, bag)
      field.classList.toggle("hidden", !visible)
      field.querySelectorAll("[data-conditionally-required]").forEach((input) => {
        input.required = visible && !this._controlIsHiddenInside(field, input)
      })
      if (field.hasAttribute("data-conditionally-required")) {
        field.querySelectorAll("input, textarea, select").forEach((input) => {
          if (input.type === "checkbox" || input.type === "hidden") return
          input.required = visible && !this._controlIsHiddenInside(field, input)
        })
      }
    })
  },

  _controlIsHiddenInside(field, input) {
    let node = input
    while (node !== field) {
      if (node.classList.contains("hidden")) return true
      node = node.parentElement
    }
    return false
  },

  toggleDisclosure(event) {
    event.preventDefault()
    const section = event.currentTarget.closest("[data-disclosure]")
    if (!section) return
    const body = section.querySelector("[data-disclosure-body]")
    const chevron = section.querySelector("[data-disclosure-chevron]")
    if (body) body.classList.toggle("hidden")
    if (chevron) chevron.classList.toggle("rotate-180")
    this._recordDisclosureState(section, body)
  },

  _recordDisclosureState(section, body) {
    if (!body || !this.disclosureState) return
    const stepId = section.closest("[data-step-item]")?.dataset.stepId
    if (!stepId) return
    const disclosureId = section.dataset.disclosureId || ""
    const kind = disclosureId.startsWith("step-more") ? "more" : null
    if (!kind) return
    this.disclosureState.set(`${stepId}:${kind}`, !body.classList.contains("hidden"))
  }
}
