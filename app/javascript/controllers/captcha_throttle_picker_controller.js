import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["preset", "customFields", "limitCount", "periodMinutes", "choice", "skipped", "display"]

  static values = {
    custom: { type: String, default: "custom" },
    skip: { type: String, default: "skip" }
  }

  connect() {
    this.editing = false
    this.captureSaved()
    this.syncEditor()
  }

  edit() {
    this.editing = true
    this.syncEditor()
    this.openChoice()
  }

  collapse() {
    this.restoreSaved()
    this.editing = false
    this.syncEditor()
  }

  blurChoice() {
    if (!this.editing) return
    if (this.isCustom()) return
    if (this.hasChoiceTarget && this.savedChoice != null && this.choiceTarget.value !== this.savedChoice) return
    this.collapse()
  }

  escape(event) {
    if (!this.editing) return
    if (event) event.preventDefault()
    this.collapse()
  }

  choose() {
    if (!this.hasChoiceTarget || !this.hasPresetTarget) return

    const value = this.choiceTarget.value
    if (!value) return

    this.editing = true

    if (this.isSkipValue(value)) {
      if (this.hasSkippedTarget) this.skippedTarget.value = "true"
      this.syncEditor()
      this.submit()
      return
    }

    const wasSkipped = this.hasSkippedTarget && this.skippedTarget.value === "true"
    if (this.hasSkippedTarget) this.skippedTarget.value = "false"
    const same = this.presetTarget.value === value && !wasSkipped
    this.presetTarget.value = value
    this.syncEditor()
    if (same) {
      this.collapse()
      return
    }
    if (!this.isCustom()) this.submit()
  }

  apply() {
    if (this.isCustom() && this.customComplete()) this.submit()
  }

  guard(event) {
    if (!event) return
    if (this.isCustom() && !this.customComplete()) event.preventDefault()
  }

  isCustom() {
    if (this.hasChoiceTarget && this.isSkipValue(this.choiceTarget.value)) return false
    return this.hasPresetTarget && this.presetTarget.value === this.customValue
  }

  isSkipValue(value) {
    return value === this.skipValue
  }

  syncCustom() {
    if (!this.hasCustomFieldsTarget) return
    this.customFieldsTarget.hidden = !this.shouldShowCustom()
  }

  customComplete() {
    if (!this.hasLimitCountTarget || !this.hasPeriodMinutesTarget) return false
    const limit = Number.parseInt(this.limitCountTarget.value, 10)
    const minutes = Number.parseInt(this.periodMinutesTarget.value, 10)
    return Number.isFinite(limit) && limit > 0 && Number.isFinite(minutes) && minutes > 0
  }

  submit() {
    if (this.element.requestSubmit) {
      this.element.requestSubmit()
      return
    }
    this.element.submit()
  }

  openChoice() {
    if (!this.hasChoiceTarget) return
    this.choiceTarget.focus()
    this.showChoicePicker()
  }

  showChoicePicker() {
    if (!this.hasChoiceTarget) return
    const picker = this.choiceTarget.showPicker
    if (typeof picker !== "function") return
    try {
      picker.call(this.choiceTarget)
    } catch {
      // Native picker can reject when the control is not yet shown.
    }
  }

  shouldShowCustom() {
    if (!this.isCustom()) return false
    if (!this.hasDisplayTarget) return true
    return this.editing === true
  }

  syncEditor() {
    const editing = this.editing === true
    if (this.hasDisplayTarget) {
      this.displayTarget.hidden = editing
      this.displayTarget.setAttribute("aria-expanded", editing ? "true" : "false")
    }
    if (this.hasChoiceTarget && this.hasDisplayTarget) {
      this.choiceTarget.hidden = !editing
    }
    this.syncCustom()
  }

  captureSaved() {
    this.savedChoice = this.hasChoiceTarget ? this.choiceTarget.value : null
    this.savedPreset = this.hasPresetTarget ? this.presetTarget.value : null
    this.savedSkipped = this.hasSkippedTarget ? this.skippedTarget.value : null
  }

  restoreSaved() {
    if (this.hasChoiceTarget && this.savedChoice != null) this.choiceTarget.value = this.savedChoice
    if (this.hasPresetTarget && this.savedPreset != null) this.presetTarget.value = this.savedPreset
    if (this.hasSkippedTarget && this.savedSkipped != null) this.skippedTarget.value = this.savedSkipped
  }
}
