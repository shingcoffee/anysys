import { Controller } from "@hotwired/stimulus"

/**
 * FlowchartFormController
 *
 * Template selection on the new-flowchart form: one card is selected at a
 * time and its key goes into the hidden template field.
 */
export default class extends Controller {
  static targets = ["templateCard", "templateInput"]

  connect() {
    this.initializeTemplateSelection()
  }

  initializeTemplateSelection() {
    // Select the "blank" template by default
    if (this.hasTemplateInputTarget) {
      const defaultTemplate = this.templateInputTarget.value || "blank"
      this.selectTemplateByValue(defaultTemplate)
    }
  }

  selectTemplate(event) {
    const card = event.currentTarget
    const template = card.dataset.template

    // Update hidden field
    if (this.hasTemplateInputTarget) {
      this.templateInputTarget.value = template
    }

    // Update UI - remove selected state from all cards
    this.templateCardTargets.forEach(card => {
      card.classList.remove("border-indigo-600", "bg-indigo-50")
      card.classList.add("border-gray-300")
      const checkmark = card.querySelector(".template-checkmark")
      if (checkmark) {
        checkmark.classList.add("hidden")
        checkmark.classList.remove("bg-indigo-600", "border-indigo-600")
      }
    })

    // Add selected state to clicked card
    card.classList.remove("border-gray-300")
    card.classList.add("border-indigo-600", "bg-indigo-50")
    const checkmark = card.querySelector(".template-checkmark")
    if (checkmark) {
      checkmark.classList.remove("hidden")
      checkmark.classList.add("bg-indigo-600", "border-indigo-600")
    }
  }

  selectTemplateByValue(templateValue) {
    const card = this.templateCardTargets.find(c => c.dataset.template === templateValue)
    if (card) {
      // Simulate click to trigger selection
      card.click()
    }
  }
}
