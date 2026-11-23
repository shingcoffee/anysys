import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["entity", "group", "prompt", "checkbox", "submit"]
  static values = { countLabel: { type: String, default: "Selected: {count}" } }

  connect() {
    this.refresh()
  }

  refresh() {
    const selected = this.entityTarget.value
    this.promptTarget.hidden = Boolean(selected)
    this.groupTargets.forEach((group) => {
      group.hidden = group.dataset.entityId !== selected
      group.querySelectorAll("input").forEach((input) => { input.disabled = group.hidden })
    })
    this.updateCount()
  }

  selectAll() {
    this.toggleAll(true)
  }

  clearAll() {
    this.toggleAll(false)
  }

  toggleAll(checked) {
    this.checkboxTargets.filter((box) => !box.disabled).forEach((box) => { box.checked = checked })
    this.updateCount()
  }

  updateCount() {
    this.submitTarget.disabled = !this.checkboxTargets.some((box) => !box.disabled && box.checked)
    this.groupTargets.filter((group) => !group.hidden).forEach((group) => {
      const count = [...group.querySelectorAll('[data-email-template-token-bulk-target="checkbox"]:checked')].length
      group.querySelectorAll('[data-email-template-token-bulk-target="count"]').forEach((node) => {
        node.textContent = this.countLabelValue.replace("{count}", count)
      })
      group.querySelectorAll('input[type="text"]').forEach((input) => {
        input.required = input.closest("div.flex.flex-col").querySelector('input[type="checkbox"]').checked
      })
    })
  }
}
